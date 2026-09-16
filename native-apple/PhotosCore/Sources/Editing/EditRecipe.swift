import CoreGraphics
import CoreModel
import Foundation

/// The metadata-KV key holding the fork's edit recipe. The stored value is always a JSON
/// object (`PUT /assets/:id/metadata` requires object values — server/src/dtos/asset.dto.ts
/// `AssetMetadataUpsertItemSchema`):
/// `{ "format": "fork.editRecipe.v1", "sourceAssetId": ..., "savedAt": ...,
///    "recipe": {...}, "renderedAssetId": ...? }` — see `EditPersistencePayload`.
public enum EditRecipeKey {
  public static let current = "fork.editRecipe.v1"
}

/// A full non-destructive edit description. The original bytes are never modified: operations
/// upstream supports (crop rectangle, quarter-turn rotation, flips) are ALSO sent to
/// `PUT /assets/:id/edits`, while this recipe is the source of truth for everything else and
/// for the client-side full-resolution render that is uploaded as a NEW asset.
public struct EditRecipe: Sendable, Codable, Equatable {
  public static let schemaVersion = 1

  public var adjust: AdjustRecipe
  public var style: StyleRecipe?
  public var crop: CropRecipe?
  public var portrait: PortraitRecipe?
  public var markup: MarkupRecipe?
  public var video: VideoRecipe?

  public init(
    adjust: AdjustRecipe = .init(),
    style: StyleRecipe? = nil,
    crop: CropRecipe? = nil,
    portrait: PortraitRecipe? = nil,
    markup: MarkupRecipe? = nil,
    video: VideoRecipe? = nil
  ) {
    self.adjust = adjust
    self.style = style
    self.crop = crop
    self.portrait = portrait
    self.markup = markup
    self.video = video
  }

  /// True when every section is at its neutral value — nothing to persist, render, or upload.
  public var isEmpty: Bool {
    adjust.isEmpty && style == nil && crop == nil && portrait == nil && markup == nil && video == nil
  }

  /// True when the recipe contains anything upstream edits cannot express (anything beyond a
  /// crop rectangle, quarter-turn rotation, and flips). Such recipes REQUIRE the recipe-KV +
  /// rendered-upload path; upstream-only recipes may persist through `/edits` alone, though the
  /// recipe is still saved so other clients can show "edited in Heirloom".
  public var requiresClientRender: Bool {
    if !(style?.isNeutral ?? true) { return true }
    if !adjust.isEmpty { return true }
    if let crop, !crop.isUpstreamExpressible { return true }
    if portrait != nil { return true }
    if markup != nil { return true }
    if video != nil { return true }
    return false
  }
}

/// All `-100...100` adjust sliders. Values are clamped on set; neutral is `0`.
public struct AdjustRecipe: Sendable, Codable, Equatable {
  public var exposure: Int
  public var brilliance: Int
  public var highlights: Int
  public var shadows: Int
  public var contrast: Int
  public var brightness: Int
  public var blackPoint: Int
  public var saturation: Int
  public var vibrance: Int
  public var warmth: Int
  public var tint: Int
  public var sharpness: Int
  public var definition: Int
  public var noiseReduction: Int
  public var vignette: Int
  public var autoEnhance: Bool

  public init(
    exposure: Int = 0, brilliance: Int = 0, highlights: Int = 0, shadows: Int = 0,
    contrast: Int = 0, brightness: Int = 0, blackPoint: Int = 0, saturation: Int = 0,
    vibrance: Int = 0, warmth: Int = 0, tint: Int = 0, sharpness: Int = 0,
    definition: Int = 0, noiseReduction: Int = 0, vignette: Int = 0, autoEnhance: Bool = false
  ) {
    self.exposure = Self.clamp(exposure)
    self.brilliance = Self.clamp(brilliance)
    self.highlights = Self.clamp(highlights)
    self.shadows = Self.clamp(shadows)
    self.contrast = Self.clamp(contrast)
    self.brightness = Self.clamp(brightness)
    self.blackPoint = Self.clamp(blackPoint)
    self.saturation = Self.clamp(saturation)
    self.vibrance = Self.clamp(vibrance)
    self.warmth = Self.clamp(warmth)
    self.tint = Self.clamp(tint)
    self.sharpness = Self.clamp(sharpness)
    self.definition = Self.clamp(definition)
    self.noiseReduction = Self.clamp(noiseReduction)
    self.vignette = Self.clamp(vignette)
    self.autoEnhance = autoEnhance
  }

  public static func clamp(_ v: Int) -> Int { min(100, max(-100, v)) }

  public var isEmpty: Bool { self == AdjustRecipe() }

  /// Slider value -> unit float in `-1...1`.
  public func unit(_ v: Int) -> Double { Double(v) / 100.0 }
}

/// A named style preset plus intensity `0...100`. Style color science is our own
/// (parameterised Core Image chains — see `EditStyles`); only the *names* follow the
/// Photos-like vocabulary the brief asks for. Never an Apple LUT copy.
public struct StyleRecipe: Sendable, Codable, Equatable {
  public var style: EditStyle
  public var intensity: Int

  public init(style: EditStyle, intensity: Int = 100) {
    self.style = style
    self.intensity = min(100, max(0, intensity))
  }

  public var isNeutral: Bool { intensity == 0 || style == .none }
}

/// Crop/straighten/perspective. Only a plain rect + quarter turns + flips are
/// upstream-expressible; any straighten angle or perspective amount forces the
/// client-render path (see `isUpstreamExpressible`).
public struct CropRecipe: Sendable, Codable, Equatable {
  /// Normalized crop rectangle, origin upper-left, `0...1`. `nil` means full frame.
  public var rect: NormalizedRect?
  /// Free rotation in degrees (`-45...45`); quarter turns live in `quarterTurns`.
  public var straightenDegrees: Double
  /// Perspective correction `-100...100` (vertical / horizontal keystone).
  public var perspectiveVertical: Int
  public var perspectiveHorizontal: Int
  /// Clockwise quarter turns `0...3` — maps to upstream `rotate` (`angle = quarterTurns * 90`).
  public var quarterTurns: Int
  public var flipHorizontal: Bool
  public var flipVertical: Bool
  /// Aspect preset the rect was composed under (bookkeeping for the UI; `nil` = free).
  public var aspect: CropAspect?

  public init(
    rect: NormalizedRect? = nil,
    straightenDegrees: Double = 0,
    perspectiveVertical: Int = 0,
    perspectiveHorizontal: Int = 0,
    quarterTurns: Int = 0,
    flipHorizontal: Bool = false,
    flipVertical: Bool = false,
    aspect: CropAspect? = nil
  ) {
    self.rect = rect
    self.straightenDegrees = straightenDegrees
    self.perspectiveVertical = perspectiveVertical
    self.perspectiveHorizontal = perspectiveHorizontal
    self.quarterTurns = ((quarterTurns % 4) + 4) % 4
    self.flipHorizontal = flipHorizontal
    self.flipVertical = flipVertical
    self.aspect = aspect
  }

  public var isUpstreamExpressible: Bool {
    straightenDegrees == 0 && perspectiveVertical == 0 && perspectiveHorizontal == 0
  }
}

public struct NormalizedRect: Sendable, Codable, Equatable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  /// Pixel rectangle for upstream `crop` params (origin top-left), clamped into `imageSize`.
  public func pixels(in imageSize: CGSize) -> CGRect {
    let r = CGRect(
      x: x * imageSize.width, y: y * imageSize.height,
      width: width * imageSize.width, height: height * imageSize.height)
    return r.intersection(CGRect(origin: .zero, size: imageSize))
  }
}

public enum CropAspect: String, Sendable, Codable, CaseIterable {
  case free, square = "1:1", threeTwo = "3:2", fourThree = "4:3", sixteenNine = "16:9", nineSixteen = "9:16"

  public var ratio: Double? {
    switch self {
    case .free: return nil
    case .square: return 1
    case .threeTwo: return 3.0 / 2.0
    case .fourThree: return 4.0 / 3.0
    case .sixteenNine: return 16.0 / 9.0
    case .nineSixteen: return 9.0 / 16.0
    }
  }
}

/// Portrait depth effect. Requires depth/disparity data in the source file; the
/// renderer reports unavailability and the UIs disable the tab (brief section 4).
public struct PortraitRecipe: Sendable, Codable, Equatable {
  /// Aperture f-stop `1.4...16`; larger values = less blur.
  public var aperture: Double
  /// Focus point, normalized to the source image (`0...1`, origin upper-left).
  public var focus: NormalizedPoint

  public init(aperture: Double = 2.8, focus: NormalizedPoint = .init(x: 0.5, y: 0.5)) {
    self.aperture = min(16, max(1.4, aperture))
    self.focus = focus
  }
}

public struct NormalizedPoint: Sendable, Codable, Equatable {
  public var x: Double
  public var y: Double
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// Markup marker. The vector ink itself is platform-owned: on iOS PencilKit strokes live in
/// the session and are flattened into the rendered upload; on macOS the vector elements ARE
/// serializable (`MacMarkupElement`) and round-trip through the recipe. Either way the
/// original asset bytes are never touched.
public struct MarkupRecipe: Sendable, Codable, Equatable {
  /// macOS vector elements (nil on iOS — see `hasFlattenedInk`).
  public var elements: [MacMarkupElement]?
  /// True when iOS PencilKit ink was flattened into the rendered upload.
  public var hasFlattenedInk: Bool

  public init(elements: [MacMarkupElement]? = nil, hasFlattenedInk: Bool = false) {
    self.elements = elements
    self.hasFlattenedInk = hasFlattenedInk
  }
}

/// Trim/mute/rotate for videos; mute + motion-trim + key-frame for Live Photos.
public struct VideoRecipe: Sendable, Codable, Equatable {
  /// Trim range in seconds from the start of the timeline; `nil` = full length.
  public var trimStart: Double?
  public var trimEnd: Double?
  public var muted: Bool
  /// Clockwise quarter turns applied at export.
  public var quarterTurns: Int
  /// Live Photo only: key-frame time in seconds (still image choice).
  public var livePhotoKeyFrame: Double?

  public init(
    trimStart: Double? = nil, trimEnd: Double? = nil, muted: Bool = false,
    quarterTurns: Int = 0, livePhotoKeyFrame: Double? = nil
  ) {
    self.trimStart = trimStart
    self.trimEnd = trimEnd
    self.muted = muted
    self.quarterTurns = ((quarterTurns % 4) + 4) % 4
    self.livePhotoKeyFrame = livePhotoKeyFrame
  }

  public var isEmpty: Bool {
    trimStart == nil && trimEnd == nil && !muted && quarterTurns == 0 && livePhotoKeyFrame == nil
  }
}
