import CoreImage
import Foundation

/// Style presets with OUR OWN color science: each style is a parameterised Core Image chain
/// built from primitive filters (`CIColorControls`, `CIToneCurve`, `CISepiaTone`,
/// `CIVignette`, `CIExposureAdjust`). No Apple LUT files are copied or embedded, and no
/// `CIPhotoEffect*` presets are used — the look is dialed in from the parameter tables below.
/// Only the style *names* follow the Photos-like vocabulary the brief asks for.
public enum EditStyle: String, Sendable, Codable, CaseIterable {
  case none = "None"
  case vivid = "Vivid"
  case vividWarm = "Vivid Warm"
  case vividCool = "Vivid Cool"
  case dramatic = "Dramatic"
  case dramaticWarm = "Dramatic Warm"
  case dramaticCool = "Dramatic Cool"
  case mono = "Mono"
  case silvertone = "Silvertone"
  case noir = "Noir"

  public var displayName: String { rawValue }

  /// Applies the style at full strength; callers blend toward the source for intensity < 100
  /// via `EditStyles.blend`.
  func applyFull(to image: CIImage) -> CIImage {
    switch self {
    case .none:
      return image
    case .vivid:
      return image
        .controlled(saturation: 1.35, contrast: 1.08, brightness: 0.01)
        .toned(black: 0.04, white: 0.98)
    case .vividWarm:
      return image
        .controlled(saturation: 1.32, contrast: 1.06)
        .warmed(temperature: 0.10)
    case .vividCool:
      return image
        .controlled(saturation: 1.32, contrast: 1.06)
        .warmed(temperature: -0.10)
    case .dramatic:
      return image
        .controlled(saturation: 1.12, contrast: 1.28, brightness: -0.03)
        .toned(black: 0.10, white: 0.94)
        .vignetted(radius: 1.6, intensity: 0.55)
    case .dramaticWarm:
      return image
        .controlled(saturation: 1.10, contrast: 1.25, brightness: -0.02)
        .toned(black: 0.10, white: 0.94)
        .warmed(temperature: 0.12)
        .vignetted(radius: 1.6, intensity: 0.55)
    case .dramaticCool:
      return image
        .controlled(saturation: 1.10, contrast: 1.25, brightness: -0.02)
        .toned(black: 0.10, white: 0.94)
        .warmed(temperature: -0.12)
        .vignetted(radius: 1.6, intensity: 0.55)
    case .mono:
      return image.controlled(saturation: 0, contrast: 1.10)
    case .silvertone:
      return image
        .controlled(saturation: 0, contrast: 1.05, brightness: 0.04)
        .sepia(intensity: 0.28)
    case .noir:
      return image
        .controlled(saturation: 0, contrast: 1.45, brightness: -0.04)
        .toned(black: 0.14, white: 0.96)
        .vignetted(radius: 1.4, intensity: 0.8)
    }
  }
}

public enum EditStyles {
  /// Applies `style` at `intensity` (`0...100`) by dissolving the full-strength result over
  /// the source — intensity 0 returns the source unchanged.
  public static func apply(_ style: EditStyle, intensity: Int, to image: CIImage) -> CIImage {
    let t = min(1, max(0, Double(intensity) / 100.0))
    guard t > 0, style != .none else { return image }
    let full = style.applyFull(to: image)
    guard t < 1 else { return full }
    return blend(foreground: full, background: image, amount: t)
  }

  private static func blend(foreground: CIImage, background: CIImage, amount: Double) -> CIImage {
    // Exact cross-dissolve: source-over with scaled alpha.
    let alpha = CIFilter(name: "CIColorMatrix")
    alpha?.setValue(foreground, forKey: kCIInputImageKey)
    alpha?.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount)), forKey: "inputAVector")
    guard let faded = alpha?.outputImage else { return foreground }
    let over = CIFilter(name: "CISourceOverCompositing")
    over?.setValue(faded, forKey: kCIInputImageKey)
    over?.setValue(background, forKey: kCIInputBackgroundImageKey)
    return over?.outputImage ?? foreground
  }
}

// MARK: - Private filter helpers (own parameter tables, primitive filters only)

private extension CIImage {
  func controlled(saturation: Double, contrast: Double = 1, brightness: Double = 0) -> CIImage {
    let f = CIFilter(name: "CIColorControls")
    f?.setValue(self, forKey: kCIInputImageKey)
    f?.setValue(saturation, forKey: kCIInputSaturationKey)
    f?.setValue(contrast, forKey: kCIInputContrastKey)
    f?.setValue(brightness, forKey: kCIInputBrightnessKey)
    return f?.outputImage ?? self
  }

  /// Lifts blacks / rolls off whites with an S-tone curve through (0,black) and (1,white).
  func toned(black: Double, white: Double) -> CIImage {
    let f = CIFilter(name: "CIToneCurve")
    f?.setValue(self, forKey: kCIInputImageKey)
    f?.setValue(CIVector(x: 0, y: black), forKey: "inputPoint0")
    f?.setValue(CIVector(x: 0.25, y: 0.25 + (black * 0.4)), forKey: "inputPoint1")
    f?.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
    f?.setValue(CIVector(x: 0.75, y: 0.75 - ((1 - white) * 0.4)), forKey: "inputPoint3")
    f?.setValue(CIVector(x: 1, y: white), forKey: "inputPoint4")
    return f?.outputImage ?? self
  }

  /// Positive temperature warms (red/yellow), negative cools (blue).
  func warmed(temperature: Double) -> CIImage {
    let f = CIFilter(name: "CITemperatureAndTint")
    f?.setValue(self, forKey: kCIInputImageKey)
    f?.setValue(CIVector(x: 6500 + temperature * 2500, y: 0), forKey: "inputNeutral")
    f?.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
    return f?.outputImage ?? self
  }

  func vignetted(radius: Double, intensity: Double) -> CIImage {
    let f = CIFilter(name: "CIVignette")
    f?.setValue(self, forKey: kCIInputImageKey)
    f?.setValue(intensity, forKey: kCIInputIntensityKey)
    f?.setValue(radius, forKey: kCIInputRadiusKey)
    return f?.outputImage ?? self
  }

  func sepia(intensity: Double) -> CIImage {
    let f = CIFilter(name: "CISepiaTone")
    f?.setValue(self, forKey: kCIInputImageKey)
    f?.setValue(intensity, forKey: kCIInputIntensityKey)
    return f?.outputImage ?? self
  }
}
