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
  /// Owning user — lets cells and menus resolve the container without hydrating `Asset`.
  public var ownerId: String
  /// Whether the server holds an edited rendition (viewer offers edited vs original).
  public var isEdited: Bool
  /// Video duration in seconds; nil for stills (viewer progress + duration badges).
  public var durationSeconds: Int?

  public init(
    id: String,
    thumbhash: String?,
    aspectRatio: Double,
    mediaKind: TimelineMediaKind,
    isFavorite: Bool,
    isTrashed: Bool,
    isArchived: Bool,
    localDateTime: Date?,
    ownerId: String = "",
    isEdited: Bool = false,
    durationSeconds: Int? = nil
  ) {
    self.id = id
    self.thumbhash = thumbhash
    self.aspectRatio = aspectRatio
    self.mediaKind = mediaKind
    self.isFavorite = isFavorite
    self.isTrashed = isTrashed
    self.isArchived = isArchived
    self.localDateTime = localDateTime
    self.ownerId = ownerId
    self.isEdited = isEdited
    self.durationSeconds = durationSeconds
  }
}

extension TimelineRow {
  /// Client-side projection for utility and album queries that intentionally hydrate `Asset`
  /// records rather than using the timeline SQL projection.
  public init(asset: Asset) {
    let ratio: Double
    if let w = asset.width, let h = asset.height, h > 0 { ratio = Double(w) / Double(h) } else { ratio = 1 }
    let kind: TimelineMediaKind
    if asset.livePhotoVideoId != nil { kind = .livePhoto }
    else if asset.type == .video { kind = .video }
    else if asset.originalFileName.lowercased().hasPrefix("screenshot") { kind = .screenshot }
    else { kind = .photo }
    self.init(
      id: asset.id, thumbhash: asset.thumbhash, aspectRatio: ratio, mediaKind: kind,
      isFavorite: asset.isFavorite, isTrashed: asset.deletedAt != nil,
      isArchived: asset.visibility == .archive, localDateTime: asset.localDateTime,
      ownerId: asset.ownerId, isEdited: asset.isEdited, durationSeconds: asset.durationSeconds)
  }
}

/// A map pin for the full-library Places map — like `LocatedAsset` but carrying the capture
/// time so pins can be clustered/filtered by date. No limit is applied by the query (WP6 renders
/// all pins); the bounded `locatedAssets(limit:)` remains for the side list.
public struct LocatedPoint: Sendable, Hashable, Identifiable {
  public var id: String
  public var latitude: Double
  public var longitude: Double
  public var localDateTime: Date?

  public init(id: String, latitude: Double, longitude: Double, localDateTime: Date? = nil) {
    self.id = id
    self.latitude = latitude
    self.longitude = longitude
    self.localDateTime = localDateTime
  }
}

/// An asset carrying GPS — the Places map's pin set (backed by `assetExif` lat/lng).
public struct LocatedAsset: Sendable, Hashable, Identifiable {
  public var id: String
  public var latitude: Double
  public var longitude: Double

  public init(id: String, latitude: Double, longitude: Double) {
    self.id = id
    self.latitude = latitude
    self.longitude = longitude
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
