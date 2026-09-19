import CoreGraphics
import Foundation

/// WP-F F5: the ≤ 64 px micro tier for mosaic zoom (13- and 21-column levels).
///
/// Micro images are derived, never fetched: downsampled off-main from the cached
/// thumbnail via CoreGraphics and memory-cached under `.micro`. Prefetch is
/// velocity-aware — cells that will pass through the viewport within 100 ms are
/// skipped, so a fast fling never queues decodes nobody will see.
///
/// The API surface lives here (not in grid files) for WP-G to consume.
public enum MicroThumbnail: Sendable {
  /// Max pixel dimension of the micro tier.
  public static let maxPixelSize = 64
  /// Cells crossing the viewport sooner than this are skipped by prefetch.
  public static let passThroughWindow: TimeInterval = 0.1
  /// Column counts that render micro thumbnails (mosaic zoom levels).
  public static let mosaicColumnCounts = [13, 21]

  /// Whether `columnCount` renders the micro tier.
  public static func usesMicroTier(columnCount: Int) -> Bool {
    mosaicColumnCounts.contains(columnCount)
  }

  /// Whether to decode/prefetch a cell `distance` points from the viewport edge
  /// while scrolling at `velocity` points/second. A cell already visible
  /// (`distance <= 0`) or a stationary list always decodes; a cell that arrives
  /// within `passThroughWindow` is skipped.
  public static func shouldDecode(
    distanceToViewportPts distance: Double, velocityPtsPerSec velocity: Double
  ) -> Bool {
    guard distance > 0, velocity > 0 else { return true }
    return distance / velocity >= passThroughWindow
  }

  /// Downsamples `image` to fit `maxPixelSize`, preserving aspect ratio. Images
  /// already at or below the cap are returned as-is (no pointless re-encode).
  /// Pure CoreGraphics (no ImageIO session): safe to call off-main; see
  /// `downsampleOffMain` for the detached wrapper the pipeline uses.
  public static func downsample(_ image: CGImage, maxPixelSize: Int = maxPixelSize) -> CGImage? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }
    guard max(width, height) > maxPixelSize else { return image }
    let scale = Double(maxPixelSize) / Double(max(width, height))
    let targetWidth = max(1, Int((Double(width) * scale).rounded()))
    let targetHeight = max(1, Int((Double(height) * scale).rounded()))
    guard
      let context = CGContext(
        data: nil, width: targetWidth, height: targetHeight, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    return context.makeImage()
  }

  /// Off-main downsample for the pipeline path (never blocks cell configuration).
  public static func downsampleOffMain(
    _ image: CGImage, maxPixelSize: Int = maxPixelSize
  ) async -> CGImage? {
    await Task.detached(priority: .userInitiated) {
      downsample(image, maxPixelSize: maxPixelSize)
    }.value
  }
}
