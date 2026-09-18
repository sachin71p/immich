import SwiftUI
import UIKit

// MARK: - key-asset photo (Years/Months cards)

// Loads one bucket key photo through the production path: fixture assets resolve
// to their deterministic generated art, real assets through `pipeline.load` at the
// thumbnail tier. Only key thumbnails ever load — never full timelines.
//
// Layout discipline (see WP2 report): the art's intrinsic pixel size must never
// reach layout — a bare `Image` reports its ideal size outward and warps the
// card (480-wide cards, 544-tall rows; verified by removing the image: every
// card snaps to its frames). So the art is cropped to the display aspect up
// front (UIKit aspect-fill draw) and shown with a plain stretch into EXPLICIT
// concrete frames — no `aspectRatio` anywhere, nothing left to negotiate.

struct KeyAssetPhoto: View {
  @EnvironmentObject var session: AppSession
  var assetId: String

  var body: some View {
    Rectangle()
      .fill(Color.secondary.opacity(0.15))
      .overlay {
        // Environment flows through overlay + GeometryReader on its own.
        GeometryReader { geo in
          CroppedKeyArt(assetId: assetId, size: geo.size)
        }
      }
      .clipped()
  }
}

/// Loads one art bitmap and crops it to `size` (points, aspect-fill center crop
/// at 3x). Separate view so the crop key (id + rounded size) owns its `.task`.
private struct CroppedKeyArt: View {
  @EnvironmentObject var session: AppSession
  var assetId: String
  var size: CGSize

  @State private var image: UIImage?

  private static var cropCache = NSCache<NSString, UIImage>()

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
      } else {
        ProgressView().controlSize(.small)
      }
    }
    .frame(width: size.width, height: size.height)
    .task(id: "\(assetId)-\(Int(size.width))x\(Int(size.height))") { await load() }
  }

  private func load() async {
    guard size.width > 1, size.height > 1,
      let store = session.store,
      let asset = try? await store.asset(id: assetId)
    else { return }
    if Task.isCancelled { return }
    let key = "\(assetId)-\(Int(size.width))x\(Int(size.height))" as NSString
    if let cached = Self.cropCache.object(forKey: key) {
      image = cached
      return
    }
    let art: UIImage?
    if let fixture = FixtureArtwork.image(for: asset) {
      art = fixture
    } else if let pipeline = session.pipeline,
      let loaded = try? await pipeline.load(asset: asset, tier: .thumbnail)
    {
      switch loaded.content {
      case .placeholder(let img): art = img
      case .tier(_, let img, _): art = img
      }
    } else {
      art = nil
    }
    guard let art, !Task.isCancelled else { return }
    let target = CGSize(width: size.width * 3, height: size.height * 3)
    let cropped = await Task.detached(priority: .utility) { art.croppedToFill(target) }.value
    guard !Task.isCancelled else { return }
    Self.cropCache.setObject(cropped, forKey: key)
    image = cropped
  }
}

extension UIImage {
  /// Aspect-fill center crop to an exact pixel size (renderer scale 1: `target`
  /// is already pixels). Displayed with a plain stretch it cannot distort.
  fileprivate func croppedToFill(_ target: CGSize) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      let scale = max(target.width / size.width, target.height / size.height)
      let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
      let origin = CGPoint(
        x: (target.width - drawSize.width) / 2,
        y: (target.height - drawSize.height) / 2)
      draw(in: CGRect(origin: origin, size: drawSize))
    }
  }
}
