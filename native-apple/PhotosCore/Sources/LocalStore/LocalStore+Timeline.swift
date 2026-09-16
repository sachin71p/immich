import CoreModel
import GRDB
import Rules

/// Brief task 4: "Timeline queries on LocalStore" — month/day buckets, bucket pages, favorites, recents,
/// media-type filters, trash, and per-container (space/library/album) timelines (the last three are all
/// just a `ContainerScope` produced by `Rules.TimelineScope`, so one set of queries covers every case).
/// Every query returns `TimelineRow`, never a full `Asset` — A0 Architecture: grid scrolling never waits
/// on more than id/thumbhash/ratio/type/flags.
extension PhotosLocalStore {
  public enum Granularity: String, Sendable {
    case month
    case day

    var strftimeFormat: String {
      switch self {
      case .month: return "%Y-%m"
      case .day: return "%Y-%m-%d"
      }
    }
  }

  /// The row projection shared by every query below — kept in one place so the `mediaKind` heuristics
  /// (live/panorama/video from data we already have; screenshot is a best-effort filename heuristic,
  /// no DECISIONS section defines one) never drift between call sites.
  /// A Live Photo's motion-video half is synced as its own `asset` row (type VIDEO) so it can be
  /// played, but Immich (and every other client) treats it as an internal component of the still
  /// photo that owns it, never a standalone timeline item — otherwise every Live Photo would count
  /// and appear as one photo plus one extra "video". The `visibleAsset` join enforces that by
  /// dropping any row that some other asset's `livePhotoVideoId` points at.
  static let rowSelectSQL = """
    SELECT asset.id AS id, asset.thumbhash AS thumbhash, asset.width AS width, asset.height AS height,
      asset.isFavorite AS isFavorite, asset.deletedAt AS deletedAt, asset.visibility AS visibility,
      asset.localDateTime AS localDateTime,
      CASE
        WHEN asset.livePhotoVideoId IS NOT NULL THEN 'livePhoto'
        WHEN assetExif.projectionType = 'equirectangular' THEN 'panorama'
        WHEN asset.type = 'VIDEO' THEN 'video'
        WHEN asset.originalFileName LIKE 'Screenshot%' OR asset.originalFileName LIKE 'screenshot%' THEN 'screenshot'
        ELSE 'photo'
      END AS mediaKind
    FROM asset
    JOIN (
      SELECT id FROM asset
      WHERE id NOT IN (SELECT livePhotoVideoId FROM asset WHERE livePhotoVideoId IS NOT NULL)
    ) AS visibleAsset ON visibleAsset.id = asset.id
    LEFT JOIN assetExif ON assetExif.assetId = asset.id
    """

  static func row(from row: Row) -> TimelineRow {
    let width: Int? = row["width"]
    let height: Int? = row["height"]
    let ratio: Double
    if let width, let height, height > 0 {
      ratio = Double(width) / Double(height)
    } else {
      ratio = 1
    }
    return TimelineRow(
      id: row["id"],
      thumbhash: row["thumbhash"],
      aspectRatio: ratio,
      mediaKind: TimelineMediaKind(rawValue: row["mediaKind"]) ?? .photo,
      isFavorite: row["isFavorite"],
      isTrashed: (row["deletedAt"] as String?) != nil,
      isArchived: (row["visibility"] as String) == "archive",
      localDateTime: row["localDateTime"]
    )
  }

  static func scopeWhere(_ scope: ContainerScope) -> (sql: String, arguments: [String]) {
    var clauses: [String] = []
    var args: [String] = []
    if !scope.personalUserIds.isEmpty {
      let ids = Array(scope.personalUserIds)
      clauses.append(
        "(asset.spaceId IS NULL AND asset.libraryId IS NULL AND asset.ownerId IN (\(placeholders(ids.count))))"
      )
      args += ids
    }
    if !scope.spaceIds.isEmpty {
      let ids = Array(scope.spaceIds)
      clauses.append("asset.spaceId IN (\(placeholders(ids.count)))")
      args += ids
    }
    if !scope.libraryIds.isEmpty {
      let ids = Array(scope.libraryIds)
      clauses.append("asset.libraryId IN (\(placeholders(ids.count)))")
      args += ids
    }
    guard !clauses.isEmpty else { return ("0", []) }
    return ("(" + clauses.joined(separator: " OR ") + ")", args)
  }

  private static func placeholders(_ count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ",")
  }

  /// Bucket headers with counts, most recent first. Excludes trashed and locked assets — DECISIONS §10
  /// "Locked view: personal = [me] only" is its own screen (`lockedAssets`), not part of the main grid.
  public func timelineBuckets(scope: ContainerScope, granularity: Granularity = .month) async throws -> [TimelineBucket] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      SELECT strftime('\(granularity.strftimeFormat)', asset.localDateTime) AS bucketKey, COUNT(*) AS count
      FROM asset
      WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked' AND asset.localDateTime IS NOT NULL AND \(whereSQL)
        AND asset.id NOT IN (SELECT livePhotoVideoId FROM asset WHERE livePhotoVideoId IS NOT NULL)
      GROUP BY bucketKey
      ORDER BY bucketKey DESC
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args)).map {
        TimelineBucket(key: $0["bucketKey"], count: $0["count"])
      }
    }
  }

  /// One bucket's page of rows, newest first.
  public func timelineAssets(
    scope: ContainerScope,
    bucketKey: String,
    granularity: Granularity = .month,
    limit: Int = 200,
    offset: Int = 0
  ) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked'
        AND strftime('\(granularity.strftimeFormat)', asset.localDateTime) = ? AND \(whereSQL)
      ORDER BY asset.localDateTime DESC
      LIMIT ? OFFSET ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs([bucketKey], args, [limit, offset])).map(Self.row)
    }
  }

  public func favoriteAssets(scope: ContainerScope, limit: Int = 200, offset: Int = 0) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND asset.isFavorite = 1 AND \(whereSQL)
      ORDER BY asset.localDateTime DESC
      LIMIT ? OFFSET ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args, [limit, offset])).map(Self.row)
    }
  }

  /// Recents — ordered by upload time (`createdAt`) rather than capture time (`localDateTime`).
  public func recentAssets(scope: ContainerScope, limit: Int = 200, offset: Int = 0) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked' AND \(whereSQL)
      ORDER BY asset.createdAt DESC
      LIMIT ? OFFSET ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args, [limit, offset])).map(Self.row)
    }
  }

  public func assets(
    scope: ContainerScope,
    mediaKind: TimelineMediaKind,
    limit: Int = 200,
    offset: Int = 0
  ) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND \(whereSQL)
      ORDER BY asset.localDateTime DESC
      LIMIT ? OFFSET ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args, [limit, offset]))
        .map(Self.row)
        .filter { $0.mediaKind == mediaKind }
    }
  }

  /// Trash — DECISIONS §10 `manage` purpose; callers pass a `manage`-resolved scope.
  public func trashedAssets(scope: ContainerScope, limit: Int = 200, offset: Int = 0) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NOT NULL AND \(whereSQL)
      ORDER BY asset.deletedAt DESC
      LIMIT ? OFFSET ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args, [limit, offset])).map(Self.row)
    }
  }

  /// Locked view — DECISIONS §10 "Locked view: personal = [me] only"; ignores whatever scope the caller
  /// resolved for other purposes and always restricts to the signed-in user's own assets.
  public func lockedAssets(currentUserId: String, limit: Int = 200, offset: Int = 0) async throws -> [TimelineRow] {
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND asset.visibility = 'locked' AND asset.spaceId IS NULL
        AND asset.libraryId IS NULL AND asset.ownerId = ?
      ORDER BY asset.localDateTime DESC
      LIMIT ? OFFSET ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs([currentUserId], [limit, offset])).map(Self.row)
    }
  }
}
