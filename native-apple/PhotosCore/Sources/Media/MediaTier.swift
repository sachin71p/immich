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

  /// Quality rank, low → high. The disk cache serves the highest cached tier (brief task 4);
  /// the network tries the requested tier first, then each lower tier.
  var rank: Int {
    switch self {
    case .thumbnail: 0
    case .preview: 1
    case .fullsize: 2
    case .original: 3
    }
  }

  static var orderedHighToLow: [MediaTier] { [.original, .fullsize, .preview, .thumbnail] }

  /// Tiers to try in order for a request: the tier itself, then each lower tier.
  public static func fallbackOrder(from requested: MediaTier) -> [MediaTier] {
    orderedHighToLow.filter { $0.rank <= requested.rank }
  }

  /// The `size` query value for `viewAsset`; `nil` for `.original` (served by `downloadAsset`).
  var viewSize: String? {
    switch self {
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
    case .thumbnail: 512
    case .preview: 2048
    case .fullsize: nil
    case .original: nil
    }
  }
}
