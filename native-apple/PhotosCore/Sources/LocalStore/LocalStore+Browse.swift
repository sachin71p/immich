import CoreModel
import GRDB
import Rules

/// Read-only browse queries for the app layer (A3 iOS, shared with A4 macOS): container listings,
/// membership, album contents, people, map points, and single-row fetches the timeline queries in
/// `LocalStore+Timeline` don't cover. All reads run against the local mirror only (A0 Architecture:
/// "The local DB is the UI's only data source"); writes stay in `LocalStore+Mutations`.
extension PhotosLocalStore {
  // MARK: - spaces (DECISIONS §4)

  /// Spaces the user is a member of (owner or contributor), ordered by name.
  public func spacesForUser(_ userId: String) async throws -> [Space] {
    try await dbQueue.read { db in
      try SpaceRecord
        .filter(sql: "id IN (SELECT spaceId FROM spaceMember WHERE userId = ?)", arguments: [userId])
        .order(Column("name"))
        .fetchAll(db)
        .map(\.model)
    }
  }

  public func space(id: String) async throws -> Space? {
    try await dbQueue.read { db in try SpaceRecord.fetchOne(db, key: id)?.model }
  }

  public func user(id: String) async throws -> User? {
    try await dbQueue.read { db in try UserRecord.fetchOne(db, key: id)?.model }
  }

  public func spaceRole(spaceId: String, userId: String) async throws -> SharedSpaceRoleKind? {
    try await dbQueue.read { db in
      try SpaceMemberRecord
        .filter(sql: "spaceId = ? AND userId = ?", arguments: [spaceId, userId])
        .fetchOne(db)
        .map(\.model.role)
    }
  }

  public func membersOfSpace(_ spaceId: String) async throws -> [SpaceMember] {
    try await dbQueue.read { db in
      try SpaceMemberRecord
        .filter(sql: "spaceId = ?", arguments: [spaceId])
        .fetchAll(db)
        .map(\.model)
    }
  }

  // MARK: - external libraries (DECISIONS §4 "external library sharing")

  /// Libraries the user owns or is a member of, ordered by name.
  public func librariesForUser(_ userId: String) async throws -> [Library] {
    try await dbQueue.read { db in
      try LibraryRecord
        .filter(
          sql: "ownerId = ? OR id IN (SELECT libraryId FROM libraryMember WHERE userId = ?)",
          arguments: [userId, userId]
        )
        .order(Column("name"))
        .fetchAll(db)
        .map(\.model)
    }
  }

  public func library(id: String) async throws -> Library? {
    try await dbQueue.read { db in try LibraryRecord.fetchOne(db, key: id)?.model }
  }

  // MARK: - albums (DECISIONS §4 R11)

  /// Albums the user is a member of, most recently updated first.
  public func albumsForUser(_ userId: String) async throws -> [Album] {
    try await dbQueue.read { db in
      try AlbumRecord
        .filter(sql: "id IN (SELECT albumId FROM albumUser WHERE userId = ?)", arguments: [userId])
        .order(Column("updatedAt").desc)
        .fetchAll(db)
        .map(\.model)
    }
  }

  public func album(id: String) async throws -> Album? {
    try await dbQueue.read { db in try AlbumRecord.fetchOne(db, key: id)?.model }
  }

  public func albumMemberRole(albumId: String, userId: String) async throws -> AlbumUserRoleKind? {
    try await dbQueue.read { db in
      try AlbumUserRecord
        .filter(sql: "albumId = ? AND userId = ?", arguments: [albumId, userId])
        .fetchOne(db)
        .map(\.model.role)
    }
  }

  public func membersOfAlbum(_ albumId: String) async throws -> [AlbumMember] {
    try await dbQueue.read { db in
      try AlbumUserRecord
        .filter(sql: "albumId = ?", arguments: [albumId])
        .fetchAll(db)
        .map(\.model)
    }
  }

  /// Album timeline: the same `TimelineRow` projection as every other grid (see `rowSelectSQL` in
  /// `LocalStore+Timeline`), restricted to the album's assets, newest first.
  public func albumAssets(albumId: String, limit: Int = 200, offset: Int = 0) async throws -> [TimelineRow] {
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NULL
        AND asset.id IN (SELECT assetId FROM albumAsset WHERE albumId = ?)
      ORDER BY asset.localDateTime DESC
      LIMIT ? OFFSET ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs([albumId], [limit, offset])).map(Self.row)
    }
  }

  public func albumAssetCount(_ albumId: String) async throws -> Int {
    try await dbQueue.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM albumAsset WHERE albumId = ?", arguments: [albumId]
      ) ?? 0
    }
  }

  // MARK: - asset details for the viewer

  public func exif(for assetId: String) async throws -> AssetExif? {
    try await dbQueue.read { db in try AssetExifRecord.fetchOne(db, key: assetId)?.domainModel }
  }

  /// Assets carrying GPS inside `scope` — the Places map's pin set (DECISIONS §10 `timeline` purpose).
  public func locatedAssets(scope: ContainerScope, limit: Int = 2000) async throws -> [LocatedAsset] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      SELECT asset.id AS id, assetExif.latitude AS latitude, assetExif.longitude AS longitude
      FROM asset
      JOIN assetExif ON assetExif.assetId = asset.id
      WHERE asset.deletedAt IS NULL AND assetExif.latitude IS NOT NULL
        AND assetExif.longitude IS NOT NULL AND \(whereSQL)
      LIMIT ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args, [limit])).compactMap { row in
        guard let latitude: Double = row["latitude"], let longitude: Double = row["longitude"] else {
          return nil
        }
        let id: String = row["id"]
        return LocatedAsset(id: id, latitude: latitude, longitude: longitude)
      }
    }
  }

  /// Non-trashed assets with a given visibility inside `scope` — backs the Archive/Hidden utility
  /// views (DECISIONS §10 `manage` purpose; callers pass a `manage`-resolved scope).
  public func visibilityAssets(
    _ visibility: AssetVisibilityKind, scope: ContainerScope, limit: Int = 200, offset: Int = 0
  ) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND asset.visibility = ? AND \(whereSQL)
      ORDER BY asset.localDateTime DESC
      LIMIT ? OFFSET ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs([visibility.rawValue], args, [limit, offset]))
        .map(Self.row)
    }
  }

  /// Native Photos-style media utility collections that can be derived from the metadata mirrored
  /// by Immich today. A missing server-side classification simply yields an empty collection rather
  /// than leaking unrelated media into the category.
  public func mediaAssets(
    scope: ContainerScope, collection: NativeMediaCollection, limit: Int = 500
  ) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let predicate: String
    switch collection {
    case .videos: predicate = "asset.type = 'VIDEO'"
    case .selfies: predicate = "lower(asset.originalFileName) LIKE '%selfie%'"
    case .livePhotos: predicate = "asset.livePhotoVideoId IS NOT NULL"
    case .portraits: predicate = "lower(asset.originalFileName) LIKE '%portrait%'"
    case .screenshots: predicate = "lower(asset.originalFileName) LIKE 'screenshot%'"
    case .screenRecordings:
      predicate = "asset.type = 'VIDEO' AND (lower(asset.originalFileName) LIKE 'screen recording%' OR lower(asset.originalFileName) LIKE 'screenrecording%')"
    }
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked' AND \(predicate) AND \(whereSQL)
      ORDER BY asset.localDateTime DESC
      LIMIT ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args, [limit])).map(Self.row)
    }
  }

  // MARK: - people (DECISIONS §11: per-owner)

  /// People owned by `ownerId`, ordered by name — faces in a space asset cluster under the
  /// contributor's People, so the viewer filters to the signed-in user's (or the asset owner's) set.
  public func peopleForOwner(_ ownerId: String) async throws -> [Person] {
    try await dbQueue.read { db in
      try PersonRecord
        .filter(sql: "ownerId = ?", arguments: [ownerId])
        .order(Column("name"))
        .fetchAll(db)
        .map(\.model)
    }
  }

  /// Visible faces of `personId` on non-trashed assets — the person timeline's asset ids.
  public func assetIds(forPerson personId: String, limit: Int = 500) async throws -> [String] {
    try await dbQueue.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT face.assetId FROM face
          JOIN asset ON asset.id = face.assetId
          WHERE face.personId = ? AND face.isVisible = 1 AND face.deletedAt IS NULL
            AND asset.deletedAt IS NULL
          LIMIT ?
          """,
        arguments: [personId, limit]
      )
    }
  }
}

public enum NativeMediaCollection: String, Sendable, Hashable, CaseIterable {
  case videos, selfies, livePhotos, portraits, screenshots, screenRecordings

  public var title: String {
    switch self {
    case .videos: return "Videos"
    case .selfies: return "Selfies"
    case .livePhotos: return "Live Photos"
    case .portraits: return "Portrait"
    case .screenshots: return "Screenshots"
    case .screenRecordings: return "Screen Recordings"
    }
  }

  public var systemImage: String {
    switch self {
    case .videos: return "video"
    case .selfies: return "person.crop.rectangle"
    case .livePhotos: return "livephoto"
    case .portraits: return "f.cursive"
    case .screenshots: return "camera.viewfinder"
    case .screenRecordings: return "record.circle"
    }
  }
}
