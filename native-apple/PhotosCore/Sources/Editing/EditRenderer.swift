import CoreImage
import Foundation
import ImageIO
import Metal
import Vision

/// UI-free Core Image renderer (brief: "Metal-backed CIContext"). Preview renders run at a
/// caller-chosen downscale for 60 fps slider scrubbing; export renders run full-resolution.
/// `CIContext` is thread-safe; the class is `@unchecked Sendable` so slider callbacks can
/// render off the main thread.
public final class EditRenderer: @unchecked Sendable {
  public static let shared = EditRenderer()

  private let context: CIContext

  public init() {
    if let device = MTLCreateSystemDefaultDevice() {
      self.context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
    } else {
      self.context = CIContext(options: [.cacheIntermediates: false])
    }
  }

  // MARK: - Pipeline

  /// Applies `recipe` to `source`. `previewMaxPixel` downscales the working image first
  /// (pass ~1080 for live slider rendering, nil for full-resolution export).
  public func render(source: CIImage, recipe: EditRecipe, previewMaxPixel: Int? = nil) -> CIImage {
    var image = source
    if let maxPx = previewMaxPixel {
      image = Self.downscale(image, maxPixel: maxPx)
    }
    if recipe.adjust.autoEnhance {
      image = Self.autoAdjusted(image)
    }
    image = applyAdjust(recipe.adjust, to: image)
    if let style = recipe.style, !style.isNeutral {
      image = EditStyles.apply(style.style, intensity: style.intensity, to: image)
    }
    if let portrait = recipe.portrait, Self.portraitAvailable(source: source) {
      image = applyPortrait(portrait, to: image, fullSource: source)
    }
    if let crop = recipe.crop {
      image = applyGeometry(crop, to: image)
    }
    return image
  }

  /// Renders to a `CGImage` (preview or export).
  public func cgImage(source: CIImage, recipe: EditRecipe, previewMaxPixel: Int? = nil) -> CGImage? {
    let out = render(source: source, recipe: recipe, previewMaxPixel: previewMaxPixel)
    return context.createCGImage(out, from: out.extent)
  }

  /// Deterministic pixel hash of a small render — used by tests to prove render
  /// determinism without golden files (same recipe + same pixels = same hash).
  /// Returns `nil` when the device cannot render at all (no GPU + blocked software
  /// fallback, e.g. a sandboxed builder) so tests can skip instead of false-failing.
  public func pixelHash(source: CIImage, recipe: EditRecipe, size: Int = 16) -> UInt64? {
    let small = Self.downscale(source, maxPixel: size)
    let out = render(source: small, recipe: recipe)
    guard let cg = context.createCGImage(out, from: out.extent) else { return nil }
    guard let data = cg.dataProvider?.data as Data? else { return nil }
    var h: UInt64 = 0xcbf29ce484222325
    for byte in data {
      h ^= UInt64(byte)
      h &*= 0x100000001b3
    }
    // Mix in extent so a degenerate empty render can never equal a real one by accident.
    h ^= UInt64(cg.width) &* 0x9e3779b97f4a7c15 ^ UInt64(cg.height)
    return h
  }

  // MARK: - Export

  public enum ExportFormat: Sendable {
    case jpeg(quality: Double)
    /// HEIC when the source UTType supports it; callers fall back to JPEG on failure.
    case heic(quality: Double)
  }

  /// Encodes the full-resolution render, carrying the source file's metadata dictionary
  /// (EXIF/TIFF/GPS) into the destination. HDR gain-map preservation is best-effort: when
  /// the source has HDR content the JPEG path keeps the base image + metadata; true
  /// ISO-21496 gain-map muxing is out of scope for A8 and noted in the returned report.
  public func export(
    sourceData: Data, recipe: EditRecipe, format: ExportFormat,
    markupOverlay: CGImage? = nil
  ) throws -> ExportReport {
    guard let src = CGImageSourceCreateWithData(sourceData as CFData, nil),
      let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { throw EditRenderError.undecodableSource }
    var ci = CIImage(cgImage: cg)
    ci = render(source: ci, recipe: recipe)
    if let overlay = markupOverlay {
      ci = flattenMarkup(CIImage(cgImage: overlay), onto: ci)
    }
    guard let rendered = context.createCGImage(ci, from: ci.extent) else {
      throw EditRenderError.renderFailed
    }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
    let data = NSMutableData()
    let uti: CFString =
      switch format {
      case .jpeg: "public.jpeg" as CFString
      case .heic: "public.heic" as CFString
      }
    guard let dest = CGImageDestinationCreateWithData(data, uti, 1, nil) else {
      throw EditRenderError.encoderUnavailable
    }
    let quality: Double =
      switch format {
      case .jpeg(let q), .heic(let q): q
      }
    CGImageDestinationAddImage(dest, rendered, props as CFDictionary)
    CGImageDestinationSetProperties(
      dest, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw EditRenderError.encoderUnavailable }
    // String lookup (not the `kCGImagePropertyHasHDRContent` symbol) so this compiles on
    // older SDKs too; absent key simply means "not HDR".
    let isHDR = (props["HasHDRContent" as CFString] as? Bool) ?? false
    return ExportReport(data: data as Data, pixelSize: ci.extent.size, carriedHDRGainMap: false, sourceWasHDR: isHDR)
  }

  // MARK: - Adjust

  private func applyAdjust(_ a: AdjustRecipe, to image: CIImage) -> CIImage {
    var img = image
    if a.exposure != 0 {
      img = filtered("CIExposureAdjust", img, ["inputEV": a.unit(a.exposure) * 2.0])
    }
    if a.brilliance != 0 {
      // Brilliance approximation: tone-curve lift of midtones + mild local contrast.
      img = toneCurve(img, black: -a.unit(a.brilliance) * 0.06, white: a.unit(a.brilliance) * 0.03)
      img = filtered("CIUnsharpMask", img, ["inputIntensity": abs(a.unit(a.brilliance)) * 0.6, "inputRadius": 8.0])
    }
    if a.highlights != 0 {
      img = filtered(
        "CIHighlightShadowAdjust", img,
        ["inputHighlightAmount": 1.0 + a.unit(a.highlights), "inputShadowAmount": 0.0])
    }
    if a.shadows != 0 {
      img = filtered(
        "CIHighlightShadowAdjust", img,
        ["inputHighlightAmount": 1.0, "inputShadowAmount": a.unit(a.shadows)])
    }
    if a.contrast != 0 || a.saturation != 0 || a.brightness != 0 {
      img = filtered(
        "CIColorControls", img,
        [
          kCIInputContrastKey as String: 1.0 + a.unit(a.contrast) * 0.6,
          kCIInputSaturationKey as String: 1.0 + a.unit(a.saturation),
          kCIInputBrightnessKey as String: a.unit(a.brightness) * 0.3,
        ])
    }
    if a.blackPoint != 0 {
      img = toneCurve(img, black: a.unit(a.blackPoint) * 0.25, white: 0)
    }
    if a.levelsInBlack != 0 || a.levelsInWhite != 100 || a.levelsOutBlack != 0
      || a.levelsOutWhite != 100
    {
      img = levels(
        img, inBlack: Double(a.levelsInBlack) / 100, inWhite: Double(a.levelsInWhite) / 100,
        outBlack: Double(a.levelsOutBlack) / 100, outWhite: Double(a.levelsOutWhite) / 100)
    }
    if a.vibrance != 0 {
      img = filtered("CIVibrance", img, ["inputAmount": a.unit(a.vibrance)])
    }
    if a.warmth != 0 || a.tint != 0 {
      img = filtered(
        "CITemperatureAndTint", img,
        [
          "inputNeutral": CIVector(x: 6500 + Double(a.warmth) * 25, y: 0),
          "inputTargetNeutral": CIVector(x: 6500, y: CGFloat(a.tint) * 4),
        ])
    }
    if a.sharpness != 0 {
      img = filtered(
        "CISharpenLuminance", img, ["inputSharpness": max(0, a.unit(a.sharpness)) * 2.0])
    }
    if a.definition != 0 {
      // Definition approximation: local contrast via unsharp with a wide radius.
      img = filtered(
        "CIUnsharpMask", img,
        ["inputIntensity": abs(a.unit(a.definition)) * 0.9, "inputRadius": 2.5])
    }
    if a.noiseReduction != 0 {
      img = filtered(
        "CINoiseReduction", img,
        ["inputNoiseLevel": 0.02, "inputSharpness": max(0, 1.0 - a.unit(a.noiseReduction))])
    }
    if a.vignette != 0 {
      let v = a.unit(a.vignette)
      img = filtered(
        "CIVignette", img,
        ["inputIntensity": v > 0 ? v * 1.5 : v, "inputRadius": v > 0 ? 1.6 : 2.2])
    }
    // MARK: WP-E section keys
    if a.cast != 0 {
      // Color > Cast: extra color shift after the legacy warmth/tint pair.
      img = filtered(
        "CITemperatureAndTint", img,
        [
          "inputNeutral": CIVector(x: 6500 + Double(a.cast) * 12, y: 0),
          "inputTargetNeutral": CIVector(x: 6500, y: CGFloat(a.cast) * 2),
        ])
    }
    if a.wbTemperature != 0 || a.wbTint != 0 {
      // White Balance section: finer Temperature-Tint control.
      img = filtered(
        "CITemperatureAndTint", img,
        [
          "inputNeutral": CIVector(x: 6500 + Double(a.wbTemperature) * 25, y: 0),
          "inputTargetNeutral": CIVector(x: 6500, y: CGFloat(a.wbTint) * 4),
        ])
    }
    if a.bwIntensity != 0 {
      // B&W Intensity: dissolve toward monochrome with a touch of contrast.
      let t = min(1, max(0, abs(a.unit(a.bwIntensity))))
      let mono = filtered("CIColorControls", img, ["inputSaturation": 0.0])
      img = dissolve(foreground: mono, background: img, amount: a.bwIntensity > 0 ? t : 0)
      if a.bwIntensity < 0 {
        img = filtered("CIColorControls", img, ["inputSaturation": 1.0 + t * 0.5])
      } else {
        img = filtered("CIColorControls", img, ["inputContrast": 1.0 + t * 0.12])
      }
    }
    if a.bwNeutrals != 0 {
      // B&W Neutrals: midtone lift/cut on the (possibly desaturated) image.
      img = toneCurve(img, black: -a.unit(a.bwNeutrals) * 0.05, white: a.unit(a.bwNeutrals) * 0.05)
    }
    if a.bwTone != 0 {
      // B&W Tone: warm/cool split-tone push.
      img = filtered(
        "CITemperatureAndTint", img,
        [
          "inputNeutral": CIVector(x: 6500 + Double(a.bwTone) * 15, y: 0),
          "inputTargetNeutral": CIVector(x: 6500, y: 0),
        ])
    }
    if a.grain != 0 {
      // Grain: deterministic high-frequency luminance texture (a fixed checkerboard
      // dissolved over the image — same input always renders the same output,
      // unlike CIRandomGenerator). Positive grain adds texture; negative smooths
      // via the existing noise-reduction path.
      let t = a.unit(a.grain)
      if t > 0 {
        img = grained(img, amount: t)
      } else {
        img = filtered(
          "CINoiseReduction", img,
          ["inputNoiseLevel": 0.02, "inputSharpness": max(0, 1.0 + t)])
      }
    }
    if a.sharpenEdges != 0 || a.sharpenFalloff != 0 {
      // Sharpen section: edge intensity + falloff (radius) around the legacy sharpness.
      let edge = max(0, a.unit(a.sharpenEdges))
      let falloff = a.unit(a.sharpenFalloff)
      img = filtered("CISharpenLuminance", img, ["inputSharpness": edge * 2.0])
      img = filtered(
        "CIUnsharpMask", img,
        ["inputIntensity": edge * 0.6, "inputRadius": max(0.5, 2.5 + falloff * 4.0)])
    }
    if a.vignetteStrength != 0 || a.vignetteRadius != 0 || a.vignetteSoftness != 0 {
      // Vignette section detail: strength/radius/softness (softness widens the
      // transition by lowering the effective intensity at a larger radius).
      let s = a.unit(a.vignetteStrength)
      let r = 1.0 + a.unit(a.vignetteRadius) * 1.5
      let soft = a.unit(a.vignetteSoftness)
      img = filtered(
        "CIVignette", img,
        ["inputIntensity": s * (1.0 - abs(soft) * 0.4), "inputRadius": max(0.3, r + soft)])
    }
    return img
  }

  private static func autoAdjusted(_ image: CIImage) -> CIImage {
    // No options: the `[.enhance: true]` variant crashes inside CoreImage's cached
    // auto-adjust context on some OS builds (verified by oracle harness 2026-09-15).
    let filters = image.autoAdjustmentFilters()
    return filters.reduce(image) { partial, filter in
      filter.setValue(partial, forKey: kCIInputImageKey)
      return filter.outputImage ?? partial
    }
  }

  // MARK: - Portrait

  /// True when the source carries auxiliary depth/disparity data AND the device supports
  /// `CIDepthBlurEffect`. UIs disable the Portrait tab otherwise (brief section 4).
  public static func portraitAvailable(source: CIImage) -> Bool {
    guard CIFilter(name: "CIDepthBlurEffect") != nil else { return false }
    let keys = source.properties.keys.map { $0.lowercased() }
    return keys.contains(where: {
      $0.contains("disparity") || $0.contains("depth") || $0.contains("portrait")
        || $0.contains("auxiliary")
    })
  }

  private func applyPortrait(_ p: PortraitRecipe, to image: CIImage, fullSource: CIImage) -> CIImage {
    let f = CIFilter(name: "CIDepthBlurEffect")
    f?.setValue(image, forKey: kCIInputImageKey)
    // Disparity comes from the same auxiliary-backed source when present.
    f?.setValue(fullSource, forKey: "inputDisparityImage")
    f?.setValue(p.aperture, forKey: "inputAperture")
    let size = image.extent.size
    let focus = CIVector(
      x: CGFloat(p.focus.x) * size.width, y: (1.0 - CGFloat(p.focus.y)) * size.height)
    f?.setValue(focus, forKey: "inputFocusRect")
    return f?.outputImage ?? image
  }

  // MARK: - Geometry (crop / straighten / perspective / rotate / flip)

  private func applyGeometry(_ crop: CropRecipe, to image: CIImage) -> CIImage {
    var img = image
    if crop.perspectiveVertical != 0 || crop.perspectiveHorizontal != 0 {
      img = perspectiveCorrected(
        img, vertical: Double(crop.perspectiveVertical) / 100.0,
        horizontal: Double(crop.perspectiveHorizontal) / 100.0)
    }
    if crop.straightenDegrees != 0 {
      img = img.transformed(
        by: CGAffineTransform(rotationAngle: CGFloat(crop.straightenDegrees * .pi / 180.0)))
    }
    let turns = crop.quarterTurns % 4
    if turns != 0 {
      // Clockwise quarter turns about the image center.
      let angle = -CGFloat(turns) * .pi / 2.0
      img = img.transformed(by: CGAffineTransform(rotationAngle: angle))
    }
    if crop.flipHorizontal || crop.flipVertical {
      var t = CGAffineTransform.identity
      let e = img.extent
      if crop.flipHorizontal { t = t.translatedBy(x: e.width, y: 0).scaledBy(x: -1, y: 1) }
      if crop.flipVertical { t = t.translatedBy(x: 0, y: e.height).scaledBy(x: 1, y: -1) }
      img = img.transformed(by: t)
    }
    if let rect = crop.rect {
      // Normalized rect is origin-upper-left; CIImage extent is origin-lower-left.
      let e = img.extent
      let px = CGRect(
        x: e.minX + CGFloat(rect.x) * e.width,
        y: e.minY + (1.0 - CGFloat(rect.y + rect.height)) * e.height,
        width: CGFloat(rect.width) * e.width,
        height: CGFloat(rect.height) * e.height)
      img = img.cropped(to: px.intersection(e))
    }
    return img
  }

  private func perspectiveCorrected(_ image: CIImage, vertical: Double, horizontal: Double) -> CIImage {
    let e = image.extent
    // Vertical keystone (tilted up/down): narrow the top edge. Horizontal keystone
    // (panned left/right): shear the side edges vertically.
    let dx = CGFloat(vertical) * e.width * 0.15
    let dy = CGFloat(horizontal) * e.height * 0.15
    let f = CIFilter(name: "CIPerspectiveCorrection")
    f?.setValue(image, forKey: kCIInputImageKey)
    f?.setValue(CIVector(x: e.minX + dx, y: e.maxY + dy), forKey: "inputTopLeft")
    f?.setValue(CIVector(x: e.maxX - dx, y: e.maxY - dy), forKey: "inputTopRight")
    f?.setValue(CIVector(x: e.maxX - dx, y: e.minY - dy), forKey: "inputBottomRight")
    f?.setValue(CIVector(x: e.minX + dx, y: e.minY + dy), forKey: "inputBottomLeft")
    return f?.outputImage ?? image
  }

  // MARK: - Auto-straighten (Vision horizon)

  /// Suggests a straighten angle in degrees via the Vision horizon detector. Throws
  /// `EditRenderError.noHorizonFound` for flat/abstract scenes.
  public func suggestedStraightenAngle(for cgImage: CGImage) async throws -> Double {
    let request = VNDetectHorizonRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([request])
    guard let horizon = request.results?.first else { throw EditRenderError.noHorizonFound }
    // `VNHorizonObservation.angle` is radians from level (0 = level horizon).
    return -horizon.angle * 180.0 / .pi
  }

  // MARK: - Helpers

  private static func downscale(_ image: CIImage, maxPixel: Int) -> CIImage {
    let e = image.extent
    let longest = max(e.width, e.height)
    guard longest > CGFloat(maxPixel), longest > 0 else { return image }
    let s = CGFloat(maxPixel) / longest
    return image.transformed(by: CGAffineTransform(scaleX: s, y: s))
  }

  private func filtered(_ name: String, _ image: CIImage, _ values: [String: Any]) -> CIImage {
    let f = CIFilter(name: name)
    f?.setValue(image, forKey: kCIInputImageKey)
    for (k, v) in values { f?.setValue(v, forKey: k) }
    return f?.outputImage ?? image
  }

  /// Cross-dissolve of `foreground` over `background` (exact blend for B&W intensity).
  private func dissolve(foreground: CIImage, background: CIImage, amount: Double) -> CIImage {
    guard amount > 0 else { return background }
    guard amount < 1 else { return foreground }
    let alpha = CIFilter(name: "CIColorMatrix")
    alpha?.setValue(foreground, forKey: kCIInputImageKey)
    alpha?.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount)), forKey: "inputAVector")
    guard let faded = alpha?.outputImage else { return foreground }
    let over = CIFilter(name: "CISourceOverCompositing")
    over?.setValue(faded, forKey: kCIInputImageKey)
    over?.setValue(background, forKey: kCIInputBackgroundImageKey)
    return over?.outputImage ?? foreground
  }

  /// Deterministic grain: a fixed high-frequency checkerboard dissolved over the
  /// image at low alpha. A fixed pattern (not `CIRandomGenerator`) keeps renders
  /// deterministic for tests and export stability.
  private func grained(_ image: CIImage, amount: Double) -> CIImage {
    let checker = CIFilter(name: "CICheckerboardGenerator")
    checker?.setValue(CIVector(x: 0, y: 0, z: 1.5, w: 0), forKey: "inputCenter")
    checker?.setValue(CIColor(red: 0.5, green: 0.5, blue: 0.5), forKey: "inputColor0")
    checker?.setValue(CIColor(red: 0.62, green: 0.62, blue: 0.62), forKey: "inputColor1")
    checker?.setValue(1.5, forKey: "inputWidth")
    checker?.setValue(0.0, forKey: "inputSharpness")
    guard var pattern = checker?.outputImage else { return image }
    let e = image.extent
    pattern = pattern.cropped(to: CGRect(x: e.minX, y: e.minY, width: max(e.width, 2), height: max(e.height, 2)))
    return dissolve(foreground: pattern, background: image, amount: min(0.35, amount * 0.25))
      .cropped(to: e)
  }

  /// True levels transform (D3): input remap [inBlack, inWhite] -> [0, 1] via
  /// CIToneCurve, then output range scale to [outBlack, outWhite] via
  /// CIColorMatrix. Degenerate input ranges fall back to identity.
  private func levels(
    _ image: CIImage, inBlack: Double, inWhite: Double, outBlack: Double, outWhite: Double
  ) -> CIImage {
    let lo = min(1, max(0, min(inBlack, inWhite)))
    let hi = min(1, max(0, max(inBlack, inWhite)))
    var img = image
    if hi - lo > 1e-3 && (lo > 0 || hi < 1) {
      let f = CIFilter(name: "CIToneCurve")
      f?.setValue(img, forKey: kCIInputImageKey)
      f?.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
      f?.setValue(CIVector(x: lo, y: 0), forKey: "inputPoint1")
      f?.setValue(CIVector(x: (lo + hi) / 2, y: (lo + hi) / 2), forKey: "inputPoint2")
      f?.setValue(CIVector(x: hi, y: 1), forKey: "inputPoint3")
      f?.setValue(CIVector(x: 1, y: 1), forKey: "inputPoint4")
      img = f?.outputImage ?? img
    }
    let scale = outWhite - outBlack
    if scale != 1 || outBlack != 0 {
      let m = CIFilter(name: "CIColorMatrix")
      m?.setValue(img, forKey: kCIInputImageKey)
      m?.setValue(CIVector(x: scale, y: 0, z: 0, w: 0), forKey: "inputRVector")
      m?.setValue(CIVector(x: 0, y: scale, z: 0, w: 0), forKey: "inputGVector")
      m?.setValue(CIVector(x: 0, y: 0, z: scale, w: 0), forKey: "inputBVector")
      m?.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
      m?.setValue(
        CIVector(x: outBlack, y: outBlack, z: outBlack, w: 0), forKey: "inputBiasVector")
      img = m?.outputImage ?? img
    }
    return img
  }

  private func toneCurve(_ image: CIImage, black: Double, white: Double) -> CIImage {
    let f = CIFilter(name: "CIToneCurve")
    f?.setValue(image, forKey: kCIInputImageKey)
    f?.setValue(CIVector(x: 0, y: black), forKey: "inputPoint0")
    f?.setValue(CIVector(x: 0.25, y: 0.25), forKey: "inputPoint1")
    f?.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
    f?.setValue(CIVector(x: 0.75, y: 0.75), forKey: "inputPoint3")
    f?.setValue(CIVector(x: 1, y: 1 + white), forKey: "inputPoint4")
    return f?.outputImage ?? image
  }
}

public struct ExportReport: Sendable {
  public var data: Data
  public var pixelSize: CGSize
  public var carriedHDRGainMap: Bool
  public var sourceWasHDR: Bool
  public init(data: Data, pixelSize: CGSize, carriedHDRGainMap: Bool, sourceWasHDR: Bool) {
    self.data = data
    self.pixelSize = pixelSize
    self.carriedHDRGainMap = carriedHDRGainMap
    self.sourceWasHDR = sourceWasHDR
  }
}

public enum EditRenderError: Error, Sendable, Equatable {
  case undecodableSource
  case renderFailed
  case encoderUnavailable
  case noHorizonFound
  case depthUnavailable
}

