import CoreModel
import Foundation
import GRDB
import Rules

/// WP1 §1: the grid's data index — one compact SQL query feeding the collection view.
///
/// Why an index instead of hydrated rows: the loader used to fan out `timelineAssets` per
/// bucket plus a full `assets(ids:)` for badges (N+1 reads, full `Asset` decode), which blew
/// the 1.5 s first-paint budget on a 102k library. The index carries only what the grid
/// needs per cell — id, capture date, badge flags, video duration — in a single ordered
/// query; thumbhashes and full rows arrive later per visible page via `assetsLite(ids:)`.
extension PhotosLocalStore {
  /// Badge flags for one timeline entry. Computed in SQL (integers), decoded as `Bool`s —
  /// no per-row string work in Swift.
  struct TimelineIndexFlags: OptionSet, Sendable, Hashable {
    let rawValue: Int

    static let video = TimelineIndexFlags(rawValue: 1 << 0)
    static let livePhoto = TimelineIndexFlags(rawValue: 1 << 1)
    static let favorite = TimelineIndexFlags(rawValue: 1 << 2)
    /// Space or external-library container (the `person.2.fill` top-right badge).
    static let sharedContainer = TimelineIndexFlags(rawValue: 1 << 3)
    static let screenshot = TimelineIndexFlags(rawValue: 1 << 4)
    static let edited = TimelineIndexFlags(rawValue: 1 << 5)
  }

  /// One compact timeline entry: id, capture date, badge flags, video duration.
  struct TimelineIndexEntry: Sendable, Hashable {
    var id: String
    var localDateTime: Date?
    var flags: TimelineIndexFlags
    /// Video duration in seconds (nil for stills).
    var durationSeconds: Int?
  }

  /// The whole visible timeline in display order (newest first), plus an id lookup.
  /// A struct of arrays-in-one: `entries` is the order, `indexById` the random access.
  struct TimelineIndex: Sendable {
    var entries: [TimelineIndexEntry]
    var indexById: [String: Int]

    static let empty = TimelineIndex(entries: [], indexById: [:])
  }

  /// One bucket header for Years/Months views: key, count, key asset and date range.
  /// The key asset prefers a favorite, else the most recent asset in the bucket.
  struct TimelineBucketSummary: Sendable, Hashable {
    /// `yyyy` for year buckets, `yyyy-MM` for month buckets, `yyyy-MM-dd` for day buckets.
    var key: String
    var count: Int
    var keyAssetId: String
    var startDate: Date?
    var endDate: Date?
  }

  /// Shared visibility filter with the other timeline queries: drops trashed/locked assets
  /// and live-photo video halves (internal playback components, never standalone items).
  /// Undated assets are excluded, matching `timelineBuckets` (a NULL date has no bucket).
  static let indexWhereSQL = """
    asset.deletedAt IS NULL AND asset.visibility != 'locked' AND asset.localDateTime IS NOT NULL
      AND asset.id NOT IN (SELECT livePhotoVideoId FROM asset WHERE livePhotoVideoId IS NOT NULL)
    """

  /// The compact index: one SQL query ordered by date desc. Flags arrive as integers so
  /// Swift decodes 100k+ rows without per-row string parsing (julianday parses the stored
  /// wall-time-as-UTC text in C, same trick as the row projection).
  func timelineIndex(scope: ContainerScope) async throws -> TimelineIndex {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      SELECT asset.id AS id, julianday(asset.localDateTime) AS localDateTime,
        (asset.type = 'VIDEO') AS isVideo,
        (asset.livePhotoVideoId IS NOT NULL) AS isLive,
        asset.isFavorite AS isFavorite,
        (asset.spaceId IS NOT NULL OR asset.libraryId IS NOT NULL) AS isShared,
        (asset.originalFileName LIKE 'Screenshot%' OR asset.originalFileName LIKE 'screenshot%') AS isScreenshot,
        asset.isEdited AS isEdited,
        asset.durationSeconds AS durationSeconds
      FROM asset
      WHERE \(Self.indexWhereSQL) AND \(whereSQL)
      ORDER BY asset.localDateTime DESC
      """
    let entries: [TimelineIndexEntry] = try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args)).map(Self.indexEntry(from:))
    }
    var indexById: [String: Int] = [:]
    indexById.reserveCapacity(entries.count)
    for (offset, entry) in entries.enumerated() { indexById[entry.id] = offset }
    return TimelineIndex(entries: entries, indexById: indexById)
  }

  /// Bucket headers with counts, key assets and date ranges — one SQL query using window
  /// functions (`ROW_NUMBER() ... ORDER BY isFavorite DESC, localDateTime DESC` picks the
  /// key asset: favorite first, else most recent). Most recent bucket first.
  func bucketSummaries(scope: ContainerScope, granularity: Granularity = .month) async throws
    -> [TimelineBucketSummary]
  {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let format = granularity.strftimeFormat
    let sql = """
      SELECT bucketKey, keyAssetId, cnt AS count, minDate, maxDate FROM (
        SELECT strftime('\(format)', asset.localDateTime) AS bucketKey,
          asset.id AS keyAssetId,
          COUNT(*) OVER (PARTITION BY strftime('\(format)', asset.localDateTime)) AS cnt,
          MIN(julianday(asset.localDateTime)) OVER (PARTITION BY strftime('\(format)', asset.localDateTime)) AS minDate,
          MAX(julianday(asset.localDateTime)) OVER (PARTITION BY strftime('\(format)', asset.localDateTime)) AS maxDate,
          ROW_NUMBER() OVER (
            PARTITION BY strftime('\(format)', asset.localDateTime)
            ORDER BY asset.isFavorite DESC, asset.localDateTime DESC) AS rn
        FROM asset
        WHERE \(Self.indexWhereSQL) AND \(whereSQL)
      ) WHERE rn = 1 ORDER BY bucketKey DESC
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args)).map(Self.bucketSummary(from:))
    }
  }

  /// Full `TimelineRow`s for the given ids (thumbhash included), in input order, missing ids
  /// dropped. Callers page the visible window through this; chunks keep each read small.
  func assetsLite(ids: [String]) async throws -> [TimelineRow] {
    guard !ids.isEmpty else { return [] }
    var byId: [String: TimelineRow] = [:]
    byId.reserveCapacity(ids.count)
    for chunk in ids.chunked(into: 500) {
      let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
      let sql = "\(Self.rowSelectSQL) WHERE asset.id IN (\(placeholders))"
      let rows: [TimelineRow] = try await dbQueue.read { db in
        try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(chunk)).map(Self.row)
      }
      for row in rows { byId[row.id] = row }
    }
    return ids.compactMap { byId[$0] }
  }

  // MARK: - row decoders

  static func indexEntry(from row: Row) -> TimelineIndexEntry {
    var flags = TimelineIndexFlags()
    let isVideo: Bool = row["isVideo"]
    let isLive: Bool = row["isLive"]
    let isFavorite: Bool = row["isFavorite"]
    let isShared: Bool = row["isShared"]
    let isScreenshot: Bool = row["isScreenshot"]
    let isEdited: Bool = row["isEdited"]
    if isVideo { flags.insert(.video) }
    if isLive { flags.insert(.livePhoto) }
    if isFavorite { flags.insert(.favorite) }
    if isShared { flags.insert(.sharedContainer) }
    if isScreenshot { flags.insert(.screenshot) }
    if isEdited { flags.insert(.edited) }
    let julianDay: Double? = row["localDateTime"]
    let duration: Int? = row["durationSeconds"]
    return TimelineIndexEntry(
      id: row["id"],
      localDateTime: julianDay.map { Date(timeIntervalSince1970: ($0 - 2_440_587.5) * 86_400) },
      flags: flags,
      durationSeconds: duration
    )
  }

  static func bucketSummary(from row: Row) -> TimelineBucketSummary {
    let minDay: Double? = row["minDate"]
    let maxDay: Double? = row["maxDate"]
    return TimelineBucketSummary(
      key: row["bucketKey"],
      count: row["count"],
      keyAssetId: row["keyAssetId"],
      startDate: minDay.map { Date(timeIntervalSince1970: ($0 - 2_440_587.5) * 86_400) },
      endDate: maxDay.map { Date(timeIntervalSince1970: ($0 - 2_440_587.5) * 86_400) }
    )
  }
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    guard size > 0 else { return [self] }
    var chunks: [[Element]] = []
    chunks.reserveCapacity((count + size - 1) / size)
    var offset = 0
    while offset < count {
      chunks.append(Array(self[offset..<Swift.min(offset + size, count)]))
      offset += size
    }
    return chunks
  }
}
