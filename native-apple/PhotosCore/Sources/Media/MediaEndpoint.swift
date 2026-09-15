import CoreModel
import Foundation

/// Builds media URLs against the server routes in `open-api/immich-openapi-specs.json`
/// (`viewAsset`, `downloadAsset`, `playAssetVideo`) — brief task 1: thumbnail (`size=thumbnail`),
/// preview, fullsize/original, video playback, live-photo motion (`livePhotoVideoId`), and
/// edited vs original variants (`edited=true`, accepted by both `viewAsset` and `downloadAsset`).
///
/// Auth (`Authorization: Bearer`) is attached by `MediaPipeline` at send time, never baked into
/// the URL, so rotation/logout can't leak a token through a cached URL.
public struct MediaEndpoint: Sendable {
  public var serverURL: URL
  public var assetID: String

  public init(serverURL: URL, assetID: String) {
    self.serverURL = serverURL
    self.assetID = assetID
  }

  public func url(for tier: MediaTier, edited: Bool = false) -> URL {
    switch tier {
    case .original:
      return originalURL(edited: edited)
    default:
      return viewURL(size: tier.viewSize, edited: edited)
    }
  }

  public func thumbnailURL(edited: Bool = false) -> URL {
    viewURL(size: MediaTier.thumbnail.viewSize, edited: edited)
  }

  public func previewURL(edited: Bool = false) -> URL {
    viewURL(size: MediaTier.preview.viewSize, edited: edited)
  }

  public func fullsizeURL(edited: Bool = false) -> URL {
    viewURL(size: MediaTier.fullsize.viewSize, edited: edited)
  }

  /// Verbatim original bytes — task 5 (HEIC/RAW/ProRAW/HDR keep original bytes).
  public func originalURL(edited: Bool = false) -> URL {
    renditionURL(path: "original", query: editedQuery(edited: edited))
  }

  /// Transcoded video stream for a video asset.
  public func videoPlaybackURL() -> URL {
    serverURL
      .appendingPathComponent("assets")
      .appendingPathComponent(assetID)
      .appendingPathComponent("video")
      .appendingPathComponent("playback")
  }

  /// Playback URL for a live photo's motion part — `Asset.livePhotoVideoId` is the motion
  /// asset's id, served through that asset's own playback route.
  public func livePhotoMotionURL(motionAssetID: String) -> URL {
    MediaEndpoint(serverURL: serverURL, assetID: motionAssetID).videoPlaybackURL()
  }

  // MARK: - private

  private func viewURL(size: String?, edited: Bool) -> URL {
    var query: [URLQueryItem] = []
    if let size { query.append(URLQueryItem(name: "size", value: size)) }
    query += editedQuery(edited: edited)
    return renditionURL(path: "thumbnail", query: query)
  }

  private func editedQuery(edited: Bool) -> [URLQueryItem] {
    edited ? [URLQueryItem(name: "edited", value: "true")] : []
  }

  private func renditionURL(path: String, query: [URLQueryItem]) -> URL {
    let base =
      serverURL
      .appendingPathComponent("assets")
      .appendingPathComponent(assetID)
      .appendingPathComponent(path)
    guard !query.isEmpty else { return base }
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
    components?.queryItems = query
    return components?.url ?? base
  }
}
