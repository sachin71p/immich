import CoreModel
import Foundation

/// WP-F F3: the last Library snapshot's compact columns persisted to
/// `Caches/…/timeline-<scope>.bin` after each successful build, shown immediately on
/// launch (thumbhash placeholders, then disk-cached thumbnails), then revalidated.
///
/// Only id/ratio/thumbhash/kind/dates/counts are stored — enough for the grid's first
/// paint and the footer's cached counts. The on-launch snapshot rebuilds as one flat
/// section (grouping re-applies on revalidation); `photoCount`/`videoCount` are exact.
/// A version mismatch (or corrupt/missing file) loads as nil so the caller rebuilds.
public struct TimelineDiskSnapshot: Codable, Sendable {
  public static let version = 1
  public static let filePrefix = "timeline-"
  public static let fileExtension = "bin"

  public struct DiskRow: Codable, Sendable {
    public var id: String
    public var thumbhash: String?
    public var aspectRatio: Double
    public var mediaKind: TimelineMediaKind
    public var isFavorite: Bool
    public var localEpochSeconds: Double?

    public init(
      id: String, thumbhash: String?, aspectRatio: Double, mediaKind: TimelineMediaKind,
      isFavorite: Bool, localEpochSeconds: Double?
    ) {
      self.id = id
      self.thumbhash = thumbhash
      self.aspectRatio = aspectRatio
      self.mediaKind = mediaKind
      self.isFavorite = isFavorite
      self.localEpochSeconds = localEpochSeconds
    }
  }

  public var version: Int
  public var scopeID: String
  public var savedAt: Date
  public var photoCount: Int
  public var videoCount: Int
  public var rows: [DiskRow]

  public init(
    scopeID: String, photoCount: Int, videoCount: Int, rows: [DiskRow],
    savedAt: Date = Date()
  ) {
    self.version = Self.version
    self.scopeID = scopeID
    self.savedAt = savedAt
    self.photoCount = photoCount
    self.videoCount = videoCount
    self.rows = rows
  }

  public init(snapshot: TimelineGridSnapshot, scopeID: String) {
    self.init(
      scopeID: scopeID, photoCount: snapshot.photoCount, videoCount: snapshot.videoCount,
      rows: snapshot.rows.map {
        DiskRow(
          id: $0.id, thumbhash: $0.thumbhash, aspectRatio: $0.aspectRatio,
          mediaKind: $0.mediaKind, isFavorite: $0.isFavorite,
          localEpochSeconds: $0.localDateTime?.timeIntervalSince1970)
      })
  }

  /// Rebuilds a flat grid snapshot for first paint (grouping re-applies on revalidate).
  public func snapshot() -> TimelineGridSnapshot {
    let rows = rows.map { disk in
      TimelineRow(
        id: disk.id, thumbhash: disk.thumbhash, aspectRatio: disk.aspectRatio,
        mediaKind: disk.mediaKind, isFavorite: disk.isFavorite, isTrashed: false,
        isArchived: false,
        localDateTime: disk.localEpochSeconds.map { Date(timeIntervalSince1970: $0) })
    }
    return TimelineGridSnapshot.build(
      sections: [TimelineSourceSection(kind: .none, rows: rows)],
      order: .newestFirst, include: { _ in true }, generation: 0)
  }

  /// `timeline-<scope>.bin` with the scope sanitized to filename-safe characters.
  public static func fileURL(scopeID: String, directory: URL) -> URL {
    let safe = scopeID.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
    return directory.appendingPathComponent("\(filePrefix)\(String(safe)).\(fileExtension)")
  }

  public func save(scopeID: String, directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(self)
    try data.write(to: Self.fileURL(scopeID: scopeID, directory: directory), options: .atomic)
  }

  /// Nil on missing file, decode failure, version mismatch, or scope mismatch.
  public static func load(scopeID: String, directory: URL) -> TimelineDiskSnapshot? {
    guard
      let data = try? Data(contentsOf: fileURL(scopeID: scopeID, directory: directory)),
      let decoded = try? JSONDecoder().decode(TimelineDiskSnapshot.self, from: data),
      decoded.version == version, decoded.scopeID == scopeID
    else { return nil }
    return decoded
  }
}
