import Media
import UIKit

// MARK: - off-main thumbhash image cache (WP1 §6, P4)

/// Decoded thumbhash placeholders keyed by asset id. Decode runs off-main in the
/// caller's task; the cell sets its image synchronously only on a cache hit, so
/// `configure` never pays the 23–34% main-thread decode cost from the baseline trace.
///
/// Threading: `NSCache` is thread-safe; all access goes through it, no actor needed.
final class ThumbhashCache: @unchecked Sendable {
  static let shared = ThumbhashCache()

  private let cache = NSCache<NSString, UIImage>()

  init() {
    // Placeholders are tiny (~32x32 upscaled by the GPU); 100k entries would still only
    // be tens of MB, but the visible window plus prefetch never needs that many.
    cache.countLimit = 20_000
  }

  /// A decoded placeholder when already cached — the only path the cell takes synchronously.
  func image(for id: String) -> UIImage? {
    cache.object(forKey: id as NSString)
  }

  /// Decodes `thumbhash` off the caller's thread and caches it under `id`. Returns nil
  /// for missing/invalid hashes (the cell keeps its neutral fill).
  func decode(id: String, thumbhash: String?) async -> UIImage? {
    if let hit = cache.object(forKey: id as NSString) { return hit }
    guard let thumbhash, !thumbhash.isEmpty else { return nil }
    guard let decoded = try? ThumbHash.decode(base64: thumbhash) else { return nil }
    // `makeCGImage` is pure CPU work; `await` a detached hop so even a caller on the
    // main actor decodes off-main.
    let image = await Task.detached(priority: .userInitiated) {
      decoded.makeCGImage().map { UIImage(cgImage: $0) }
    }.value
    guard let image else { return nil }
    cache.setObject(image, forKey: id as NSString)
    return image
  }

  func remove(id: String) {
    cache.removeObject(forKey: id as NSString)
  }
}
