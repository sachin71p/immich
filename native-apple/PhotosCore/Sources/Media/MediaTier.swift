import Foundation

/// Still-image quality tiers — brief task 1. `thumbnail`/`preview`/`fullsize` are served by
/// `GET /assets/{id}/thumbnail?size=…` (`viewAsset`); `original` by `GET /assets/{id}/original`
/// (`downloadAsset`, verbatim bytes — task 5). Video playback and live-photo motion stream via
/// `MediaEndpoint.videoPlaybackURL`, not through these disk tiers.
public enum MediaTier: String, Sendable, Hashable, CaseIterable, Codable {
  case thumbnail
  case preview
  case fullsize
  case original
  /// WP-F F5: mosaic-zoom tier (≤ 64 px), downsampled locally from the cached
  /// thumbnail off-main and memory-cached. Never fetched from the server as its own
  /// rendition and never a fallback source for higher tiers.
  case micro

  /// Quality rank, low → high. The disk cache serves the highest cached tier (brief task 4);
  /// the network tries the requested tier first, then each lower tier.
  var rank: Int {
    switch self {
    case .micro: -1
    case .thumbnail: 0
    case .preview: 1
    case .fullsize: 2
    case .original: 3
    }
  }

  static var orderedHighToLow: [MediaTier] { [.original, .fullsize, .preview, .thumbnail] }

  /// Tiers to try in order for a request: the tier itself, then each lower tier.
  /// `.micro` stands alone (falling back to it would serve 64 px for a 512 px slot).
  public static func fallbackOrder(from requested: MediaTier) -> [MediaTier] {
    guard requested != .micro else { return [.micro] }
    return orderedHighToLow.filter { $0.rank <= requested.rank }
  }

  /// The `size` query value for `viewAsset`; `nil` for `.original` (served by `downloadAsset`).
  /// `.micro` fetches `thumbnail` bytes and downsamples locally (see `MicroThumbnail`).
  var viewSize: String? {
    switch self {
    case .micro: "thumbnail"
    case .thumbnail: "thumbnail"
    case .preview: "preview"
    case .fullsize: "fullsize"
    case .original: nil
    }
  }

  /// Default downsampling target (max pixel dimension) for display decoding — task 2.
  /// `nil` means full resolution (zoom / explicit original).
  public var defaultPixelSize: Int? {
    switch self {
    case .micro: 64
    case .thumbnail: 512
    case .preview: 2048
    case .fullsize: nil
    case .original: nil
    }
  }
}
