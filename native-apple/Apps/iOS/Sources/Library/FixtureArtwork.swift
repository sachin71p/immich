import CoreModel
import UIKit

/// Deterministic generated artwork for `-useFixtureStore` assets (WP0 step 2).
///
/// Every fixture asset id starts with `"fx"`. For such ids this type vends:
/// - a solid-hue image with a large index number, drawn with `UIGraphicsImageRenderer` and
///   memoized in a small lock-guarded cache;
/// - a thumbhash string (one of PhotosCore's golden vectors, picked by hue family) so the
///   pipeline's placeholder stage renders a matching colour.
///
/// The grid cell paints the generated image directly *and* warms the pipeline memory cache at
/// every tier, so album covers and the viewer — which only ever call `pipeline.load` — render
/// the same art through the production path (no fixture branch outside the grid cell).
enum FixtureArtwork {
  static let idPrefix = "fx"

  static func isFixtureAsset(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

  // MARK: - thumbhashes

  /// PhotosCore's golden vectors (`PhotosCore/Tests/Fixtures/thumbhash-vectors.json`): real,
  /// decodable hashes in four hue families. Index by hue family so placeholder and full art agree.
  private static let thumbhashes = [
    "1fsDBYBKeI97iIh4eIiIdweIdIBI",  // red landscape
    "4AcKPR5wh3CIeIh4iHh4h3BwB/eH",  // teal gradient portrait
    "FQCCBQAIT22KiHbnd/GRCwAAeHgYB4eHcA==",  // blue checker
    "HvgBFIJyWGIkYGAxdiZfs2uvow==",  // olive mixed landscape
  ]

  /// Base hue per thumbhash family, matching the vector's dominant colour.
  private static let familyHues: [CGFloat] = [0.0, 0.48, 0.6, 0.13]

  static func thumbhash(index: Int) -> String {
    thumbhashes[index % thumbhashes.count]
  }

  static func thumbhash(id: String) -> String {
    thumbhashes[family(of: id) % thumbhashes.count]
  }

  // MARK: - generated images

  /// Stable hue for an asset id: its thumbhash family's base hue plus a small id-hash jitter.
  static func hue(id: String) -> CGFloat {
    let base = familyHues[family(of: id) % familyHues.count]
    let jitter = CGFloat(stableHash(id) % 100) / 100 * 0.06 - 0.03
    let h = base + jitter
    return h < 0 ? h + 1 : (h >= 1 ? h - 1 : h)
  }

  /// Large index label: the trailing digit run of the id (`fx000123` → `123`).
  static func label(id: String) -> String {
    let digits = id.reversed().prefix(while: { $0.isNumber }).reversed()
    let label = String(digits).replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
    if !label.isEmpty { return label }
    return String(stableHash(id) % 9000 + 1000)
  }

  /// Rendered art at the asset's own aspect ratio (long edge 512), memoized.
  static func image(for asset: Asset) -> UIImage? {
    guard isFixtureAsset(asset.id) else { return nil }
    let key = asset.id
    if let hit = ArtCache.shared.get(key) { return hit }
    let w = CGFloat(asset.width ?? 0), h = CGFloat(asset.height ?? 0)
    let longEdge: CGFloat = 512
    let size: CGSize
    if w > 0, h > 0 {
      let scale = longEdge / max(w, h)
      size = CGSize(width: max(1, (w * scale).rounded()), height: max(1, (h * scale).rounded()))
    } else {
      size = CGSize(width: longEdge, height: longEdge)
    }
    let color = UIColor(hue: hue(id: asset.id), saturation: 0.55, brightness: 0.85, alpha: 1)
    let text = label(id: asset.id) as NSString
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { ctx in
      color.setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
      let fontSize = min(size.width, size.height) * 0.32
      let font = UIFont.boldSystemFont(ofSize: fontSize)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: UIColor.white.withAlphaComponent(0.92),
      ]
      let textSize = text.size(withAttributes: attrs)
      let rect = CGRect(
        x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2,
        width: textSize.width, height: textSize.height)
      text.draw(in: rect, withAttributes: attrs)
    }
    ArtCache.shared.set(image, key: key)
    return image
  }

  // MARK: - helpers

  private static func family(of id: String) -> Int {
    Int(stableHash(id) % 4)
  }

  /// djb2 — deterministic across launches (unlike `String.hashValue`).
  private static func stableHash(_ s: String) -> UInt {
    var h: UInt = 5381
    for b in s.utf8 { h = h &* 33 &+ UInt(b) }
    return h
  }
}

/// Tiny lock-guarded image memo (NSCache is not `Sendable` under Swift 6 strict concurrency).
private final class ArtCache: @unchecked Sendable {
  static let shared = ArtCache()
  private let lock = NSLock()
  private var images: [String: UIImage] = [:]
  private var order: [String] = []
  private let cap = 200

  func get(_ key: String) -> UIImage? {
    lock.withLock { images[key] }
  }

  func set(_ image: UIImage, key: String) {
    lock.withLock {
      if images[key] == nil {
        order.append(key)
        while order.count > cap, !order.isEmpty {
          images.removeValue(forKey: order.removeFirst())
        }
      }
      images[key] = image
    }
  }
}
