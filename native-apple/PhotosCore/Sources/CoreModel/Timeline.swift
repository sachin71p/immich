import Foundation

/// A lightweight timeline media type, cheap to compute from `Asset` + `AssetExif` for grid rendering.
/// Mirrors the classification the brief's `LocalStore` timeline queries need (video/live/panorama/screenshot).
public enum TimelineMediaKind: String, Sendable, Codable {
  case photo
  case video
  case livePhoto
  case panorama
  case screenshot
}

/// One row of a timeline grid — deliberately minimal so scroll performance never waits on network
/// or full asset hydration (A0 Architecture: "UI never blocks on network for grid scrolling").
public struct TimelineRow: Sendable, Hashable, Identifiable {
  public var id: String
  public var thumbhash: String?
  /// width / height, used to lay out the grid without decoding the image.
  public var aspectRatio: Double
  public var mediaKind: TimelineMediaKind
  public var isFavorite: Bool
  public var isTrashed: Bool
  public var isArchived: Bool
  public var localDateTime: Date?

  public init(
    id: String,
    thumbhash: String?,
    aspectRatio: Double,
    mediaKind: TimelineMediaKind,
    isFavorite: Bool,
    isTrashed: Bool,
    isArchived: Bool,
    localDateTime: Date?
  ) {
    self.id = id
    self.thumbhash = thumbhash
    self.aspectRatio = aspectRatio
    self.mediaKind = mediaKind
    self.isFavorite = isFavorite
    self.isTrashed = isTrashed
    self.isArchived = isArchived
    self.localDateTime = localDateTime
  }
}

/// One month or day bucket header with its asset count — the unit the grid paginates by.
public struct TimelineBucket: Sendable, Hashable {
  /// `yyyy-MM` for month buckets, `yyyy-MM-dd` for day buckets.
  public var key: String
  public var count: Int

  public init(key: String, count: Int) {
    self.key = key
    self.count = count
  }
}
