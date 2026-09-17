import CoreModel
import Foundation
import GRDB
import Rules

/// Brief task 4: "Timeline queries on LocalStore" — month/day buckets, bucket pages, favorites, recents,
/// media-type filters, trash, and per-container (space/library/album) timelines (the last three are all
/// just a `ContainerScope` produced by `Rules.TimelineScope`, so one set of queries covers every case).
/// Every query returns `TimelineRow`, never a full `Asset` — A0 Architecture: grid scrolling never waits
/// on more than id/thumbhash/ratio/type/flags.
extension PhotosLocalStore {
  public enum Granularity: String, Sendable, Hashable {
    case year
    case month
    case day

    var strftimeFormat: String {
      switch self {
      case .year: return "%Y"
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
  /// The media-kind classifier, shared by the row projection and the SQL kind filter in
  /// `assets(scope:mediaKind:)` — kept as one string so the two can never drift (a Photos
  /// destination must not pull 102k rows to keep 57k).
  static let mediaKindCaseSQL = """
    CASE
      WHEN asset.livePhotoVideoId IS NOT NULL THEN 'livePhoto'
      WHEN asset.projectionType = 'equirectangular' THEN 'panorama'
      WHEN asset.type = 'VIDEO' THEN 'video'
      WHEN asset.originalFileName LIKE 'Screenshot%' OR asset.originalFileName LIKE 'screenshot%' THEN 'screenshot'
      ELSE 'photo'
    END
    """

  /// WP-F F2: no `assetExif` join — the only exif field the grid consumes
  /// (`projectionType`, for the panorama arm above) is denormalized onto `asset`
  /// (v5 migration backfill + `.assetExif` apply mirroring). Map pins and search
  /// keep their own explicit exif joins; they are not on the grid hot path.
  static let rowSelectSQL = """
    SELECT asset.id AS id, asset.thumbhash AS thumbhash, asset.width AS width, asset.height AS height,
      asset.isFavorite AS isFavorite,
      asset.deletedAt IS NOT NULL AS deletedAt, asset.visibility = 'archive' AS visibility,
      julianday(asset.localDateTime) AS localDateTime,
      asset.ownerId AS ownerId, asset.isEdited AS isEdited, asset.durationSeconds AS durationSeconds,
      asset.originalFileName AS originalFileName,
      \(mediaKindCaseSQL) AS mediaKind
    FROM asset
    JOIN (
      SELECT id FROM asset
      WHERE id NOT IN (SELECT livePhotoVideoId FROM asset WHERE livePhotoVideoId IS NOT NULL)
    ) AS visibleAsset ON visibleAsset.id = asset.id
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
    // Decode-light projection (WP1 perf: 102k rows must load in ≤400ms Release): flags
    // arrive as booleans and the timestamp as a Julian-day double, so no per-row string
    // date parsing or string comparison runs in Swift. `julianday` parses the stored
    // wall-time-as-UTC text in C and round-trips to ~0.1ms; NULL stays NULL.
    let trashed: Bool = row["deletedAt"]
    let archived: Bool = row["visibility"]
    let julianDay: Double? = row["localDateTime"]
    let duration: Int? = row["durationSeconds"]
    let fileName: String? = row["originalFileName"]
    return TimelineRow(
      id: row["id"],
      thumbhash: row["thumbhash"],
      aspectRatio: ratio,
      mediaKind: TimelineMediaKind(rawValue: row["mediaKind"]) ?? .photo,
      isFavorite: row["isFavorite"],
      isTrashed: trashed,
      isArchived: archived,
      localDateTime: julianDay.map { Date(timeIntervalSince1970: ($0 - 2_440_587.5) * 86_400) },
      ownerId: row["ownerId"],
      isEdited: row["isEdited"],
      durationSeconds: duration,
      originalFileName: fileName ?? ""
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
    return try await HeirloomSignpost.interval(HeirloomSignpost.timelineQuery) {
      try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs([bucketKey], args, [limit, offset])).map(Self.row)
      }
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
    return try await HeirloomSignpost.interval(HeirloomSignpost.timelineQuery) {
      try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args, [limit, offset])).map(Self.row)
      }
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
    return try await HeirloomSignpost.interval(HeirloomSignpost.timelineQuery) {
      try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args, [limit, offset])).map(Self.row)
      }
    }
  }

  /// Media-type destination (Photos/Videos) — the kind filter runs in SQL via the same
  /// `mediaKindCaseSQL` the projection uses, so the query never materializes rows it drops.
  public func assets(
    scope: ContainerScope,
    mediaKind: TimelineMediaKind,
    limit: Int = 200,
    offset: Int = 0
  ) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND \(Self.mediaKindCaseSQL) = ? AND \(whereSQL)
      ORDER BY asset.localDateTime DESC
      LIMIT ? OFFSET ?
      """
    return try await HeirloomSignpost.interval(HeirloomSignpost.timelineQuery) {
      try await dbQueue.read { db in
        try Row.fetchAll(
          db, sql: sql, arguments: Self.sqlArgs([mediaKind.rawValue], args, [limit, offset])
        ).map(Self.row)
      }
    }
  }

  /// A whole timeline in **one** read transaction — replaces the app's per-bucket
  /// `timelineAssets` loop (one `dbQueue.read` per month bucket). Optionally restricted to
  /// `bucketKeys`; otherwise returns every visible row in the scope, newest first.
  public func timelineRows(
    scope: ContainerScope,
    bucketKeys: [String]? = nil,
    granularity: Granularity = .month
  ) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    // `let`, not `var`: the dbQueue closure below is `@Sendable`, so captured state must
    // be immutable (Swift 6 rejects captured `var`s in concurrently-executing code).
    let bucketSQL: String
    let bucketArgs: [String]
    if let bucketKeys {
      guard !bucketKeys.isEmpty else { return [] }
      bucketSQL =
        "AND strftime('\(granularity.strftimeFormat)', asset.localDateTime) IN (\(bucketKeys.map { _ in "?" }.joined(separator: ",")))"
      bucketArgs = bucketKeys
    } else {
      bucketSQL = ""
      bucketArgs = []
    }
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked' \(bucketSQL) AND \(whereSQL)
      ORDER BY asset.localDateTime DESC
      """
    return try await HeirloomSignpost.interval(HeirloomSignpost.timelineQuery) {
      try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(bucketArgs, args)).map(Self.row)
      }
    }
  }

  /// Asset ids in any album the user can see — one query replacing the app's per-album loop
  /// (R8: mutations did one SQL query per album).
  public func assetIdsInAnyAlbum(userId: String) async throws -> Set<String> {
    try await dbQueue.read { db in
      Set(
        try String.fetchAll(
          db,
          sql: """
            SELECT DISTINCT assetId FROM albumAsset
            WHERE albumId IN (SELECT albumId FROM albumUser WHERE userId = ?)
            """,
          arguments: [userId]
        ))
    }
  }

  /// Every located pin in `scope` with its capture time — the full-library Places map.
  /// No limit (WP6 clusters client-side); `locatedAssets(limit:)` remains for the side list.
  public func locatedAssetPoints(scope: ContainerScope) async throws -> [LocatedPoint] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      SELECT asset.id AS id, assetExif.latitude AS latitude, assetExif.longitude AS longitude,
        asset.localDateTime AS localDateTime
      FROM asset
      JOIN assetExif ON assetExif.assetId = asset.id
      WHERE asset.deletedAt IS NULL AND assetExif.latitude IS NOT NULL
        AND assetExif.longitude IS NOT NULL AND \(whereSQL)
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args)).compactMap { row in
        guard let latitude: Double = row["latitude"], let longitude: Double = row["longitude"] else {
          return nil
        }
        let id: String = row["id"]
        let localDateTime: Date? = row["localDateTime"]
        return LocatedPoint(
          id: id, latitude: latitude, longitude: longitude, localDateTime: localDateTime)
      }
    }
  }

  /// People summaries for WP6's People grid — one query (person + visible-face count on
  /// non-trashed assets), named persons first, then by count descending. The asset↔person
  /// link is the `face` table (`face.personId` → `face.assetId`).
  public func peopleSummaries(userId: String) async throws -> [PersonSummary] {
    try await dbQueue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT person.id AS id, person.name AS name, person.isHidden AS isHidden,
            person.birthDate AS birthDate,
            COUNT(DISTINCT CASE WHEN face.isVisible = 1 AND face.deletedAt IS NULL
              AND asset.id IS NOT NULL THEN face.assetId END) AS assetCount
          FROM person
          LEFT JOIN face ON face.personId = person.id
          LEFT JOIN asset ON asset.id = face.assetId AND asset.deletedAt IS NULL
          WHERE person.ownerId = ?
          GROUP BY person.id
          ORDER BY (person.name != '') DESC, assetCount DESC, person.name ASC
          """,
        arguments: [userId]
      ).map { row in
        let count: Int = row["assetCount"]
        return PersonSummary(
          id: row["id"], name: row["name"], isHidden: row["isHidden"], assetCount: count,
          birthDate: row["birthDate"])
      }
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
    return try await HeirloomSignpost.interval(HeirloomSignpost.timelineQuery) {
      try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args, [limit, offset])).map(Self.row)
      }
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
    return try await HeirloomSignpost.interval(HeirloomSignpost.timelineQuery) {
      try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs([currentUserId], [limit, offset])).map(Self.row)
      }
    }
  }
}
