import CoreGraphics
import Foundation

/// Reference box so decoded `CGImage`s can live in `NSCache` (which needs `AnyObject` values).
final class CGImageBox {
  let image: CGImage

  init(_ image: CGImage) {
    self.image = image
  }
}

/// Synchronous in-memory store for decoded grid images — the fix for R9's "no synchronous
/// memory-cache hit when a cell is configured": cells hit `cachedImage` on the main thread
/// without suspending.
///
/// `@unchecked Sendable` is safe because every mutable state lives inside `NSCache`,
/// which is documented thread-safe; the limits are set once at `init` and never mutated.
public final class MediaMemoryCache: @unchecked Sendable {
  private let images: NSCache<NSString, CGImageBox>
  private let placeholders: NSCache<NSString, CGImageBox>

  /// - Parameter costLimit: byte budget for decoded images
  ///   (`MediaPipeline.memoryCacheCostLimit()`); placeholders get a fixed count limit.
  public init(costLimit: Int) {
    images = NSCache()
    images.totalCostLimit = costLimit
    placeholders = NSCache()
    // Thumbhash bitmaps are tiny (~32px); a count cap is the right shape, sized for a
    // 100k library's visible window plus prefetch headroom.
    placeholders.countLimit = 5000
  }

  /// Main-thread hit for cell configuration — never suspends.
  public func cached(id: String, tier: MediaTier, edited: Bool) -> CGImage? {
    images.object(forKey: Self.key(id: id, tier: tier, edited: edited) as NSString)?.image
  }

  public func store(_ image: CGImage, id: String, tier: MediaTier, edited: Bool) {
    images.setObject(
      CGImageBox(image), forKey: Self.key(id: id, tier: tier, edited: edited) as NSString,
      cost: (image.bytesPerRow * image.height))
  }

  public func remove(id: String, tier: MediaTier, edited: Bool) {
    images.removeObject(forKey: Self.key(id: id, tier: tier, edited: edited) as NSString)
  }

  /// Synchronous thumbhash-placeholder hit for cell configuration.
  public func cachedPlaceholder(id: String) -> CGImage? {
    placeholders.object(forKey: id as NSString)?.image
  }

  public func storePlaceholder(_ image: CGImage, id: String) {
    placeholders.setObject(CGImageBox(image), forKey: id as NSString)
  }

  static func key(id: String, tier: MediaTier, edited: Bool) -> String {
    "\(id)|\(tier.rawValue)|\(edited)"
  }
}
