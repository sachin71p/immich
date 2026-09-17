import CoreGraphics
import Foundation

/// Pure crop-rectangle math for the WP-E E6 crop overlay (unit-tested in
/// `EditModeParityTests`; the AppKit/SwiftUI overlay in `MacEditModeView` is a
/// thin projection of these functions).
public enum CropMath {
  /// Clamps a handle-dragged rect into the `0...1` image bounds, preserving a
  /// non-degenerate size (min 1% per side).
  public static func clamped(_ rect: NormalizedRect) -> NormalizedRect {
    let x0 = min(1, max(0, rect.x))
    let y0 = min(1, max(0, rect.y))
    let x1 = min(1, max(0, rect.x + rect.width))
    let y1 = min(1, max(0, rect.y + rect.height))
    let w = max(0.01, x1 - x0)
    let h = max(0.01, y1 - y0)
    return NormalizedRect(x: min(x0, 1 - w), y: min(y0, 1 - h), width: w, height: h)
  }

  /// Centered 90%-frame rect for `aspect` under `orientation`. Unconstrained
  /// aspects (free/custom) and source-defined (original) return the full frame.
  public static func rect(
    for aspect: CropAspect, orientation: CropOrientation = .landscape
  ) -> NormalizedRect {
    guard let ratio = aspect.ratio(orientation: orientation) else {
      return NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    }
    let w: Double
    let h: Double
    if ratio >= 1 {
      w = 0.9
      h = 0.9 / ratio
    } else {
      h = 0.9
      w = 0.9 * ratio
    }
    return NormalizedRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
  }

  /// Auto-scale factor applied after straightening by `degrees` so the rotated
  /// frame covers the viewport with no empty corners. `1 / cos(θ)` is the
  /// conservative cover scale for small angles; 0° is exactly 1.
  public static func straightenScale(degrees: Double) -> Double {
    guard degrees != 0 else { return 1.0 }
    let clamped = min(45, max(-45, degrees))
    return 1.0 / cos(clamped * .pi / 180.0)
  }
}
