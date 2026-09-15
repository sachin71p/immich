import CoreModel
import Foundation
import GRDB
import Rules

/// Read-only sidebar/destination listings for the app shells (A3 iOS + A4 macOS share these).
/// Everything here mirrors DECISIONS §4 (membership) and §10 (scope); no mutation, no network.
extension PhotosLocalStore {
  /// Spaces the user belongs to, with their role — DECISIONS §4. Ordered by name for the sidebar.
  public func memberSpaces(for userId: String) async throws -> [(space: Space, role: SharedSpaceRoleKind)] {
    try await dbQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT space.id AS id, space.name AS name, space.description AS description,
                 space.createdAt AS createdAt, space.updatedAt AS updatedAt,
                 spaceMember.role AS role
          FROM space
          JOIN spaceMember ON spaceMember.spaceId = space.id
          WHERE spaceMember.userId = ?
          ORDER BY space.name COLLATE NOCASE
          """,
        arguments: [userId]
      )
      return rows.map { row in
        let roleString: String = row["role"]
        return (
          space: Space(
            id: row["id"], name: row["name"], description: row["description"],
            createdAt: row["createdAt"], updatedAt: row["updatedAt"]
          ),
          role: SharedSpaceRoleKind(rawValue: roleString) ?? .contributor
        )
      }
    }
  }

  /// External libraries the user owns or is a member of — DECISIONS §4 "external library sharing".
  public func accessibleLibraries(for userId: String) async throws -> [(library: Library, isOwner: Bool)] {
    try await dbQueue.read { db in
      let owned = try LibraryRecord
        .filter(sql: "ownerId = ?", arguments: [userId])
        .fetchAll(db)
      let memberIds = try Set(
        String.fetchAll(db, sql: "SELECT libraryId FROM libraryMember WHERE userId = ?", arguments: [userId])
      )
      let member: [LibraryRecord]
      if memberIds.isEmpty {
        member = []
      } else {
        member = try LibraryRecord
          .filter(
            sql: "id IN (\(Self.placeholdersList(memberIds.count))) AND ownerId != ?",
            arguments: StatementArguments(Array(memberIds) + [userId])
          )
          .fetchAll(db)
      }
      var result = owned.map { ($0.model, true) } + member.map { ($0.model, false) }
      result.sort { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
      return result
    }
  }

  /// Albums the user is a member of — DECISIONS §4 (R11). Ordered by most recently updated.
  public func memberAlbums(for userId: String) async throws -> [Album] {
    try await dbQueue.read { db in
      try AlbumRecord
        .filter(sql: "id IN (SELECT albumId FROM albumUser WHERE userId = ?)", arguments: [userId])
        .order(Column("updatedAt").desc)
        .fetchAll(db)
        .map(\.model)
    }
  }

  /// Members of one space, for the manage sheet — DECISIONS §4.
  public func spaceMembers(spaceId: String) async throws -> [SpaceMember] {
    try await dbQueue.read { db in
      try SpaceMemberRecord
        .filter(sql: "spaceId = ?", arguments: [spaceId])
        .fetchAll(db)
        .map(\.model)
    }
  }

  /// Members of one album, for the share sheet — DECISIONS §4 (R11).
  public func albumMembers(albumId: String) async throws -> [AlbumMember] {
    try await dbQueue.read { db in
      try AlbumUserRecord
        .filter(sql: "albumId = ?", arguments: [albumId])
        .fetchAll(db)
        .map(\.model)
    }
  }

  /// Asset count for a sidebar badge / move-sheet subtitle.
  public func albumAssetCount(albumId: String) async throws -> Int {
    try await dbQueue.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM albumAsset WHERE albumId = ?", arguments: [albumId]) ?? 0
    }
  }

  /// People for the sidebar People section (per-owner clustering — DECISIONS §11).
  public func people(forOwner ownerId: String) async throws -> [Person] {
    try await dbQueue.read { db in
      try PersonRecord
        .filter(sql: "ownerId = ?", arguments: [ownerId])
        .order(Column("name"))
        .fetchAll(db)
        .map(\.model)
    }
  }

  /// Saved memories for the sidebar Memories section.
  public func savedMemories(forOwner ownerId: String) async throws -> [Memory] {
    try await dbQueue.read { db in
      try MemoryRecord
        .filter(sql: "ownerId = ? AND isSaved = 1 AND deletedAt IS NULL", arguments: [ownerId])
        .order(Column("memoryAt").desc)
        .fetchAll(db)
        .map(\.model)
    }
  }

  /// Asset ids in one album, newest first (joins capture time for ordering).
  public func assetIds(inAlbum albumId: String, limit: Int = 2000) async throws -> [String] {
    try await dbQueue.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT albumAsset.assetId FROM albumAsset
          LEFT JOIN asset ON asset.id = albumAsset.assetId
          WHERE albumAsset.albumId = ?
          ORDER BY asset.localDateTime DESC
          LIMIT ?
          """,
        arguments: Self.sqlArgs([albumId], [limit])
      )
    }
  }

  /// Archived assets in scope — Utilities · Archive (DECISIONS §10 `manage` purpose scope).
  public func archivedAssets(scope: ContainerScope, limit: Int = 500) async throws -> [Asset] {
    let (whereSQL, args) = Self.scopeWhereValues(scope)
    return try await dbQueue.read { db in
      let records = try AssetRecord
        .filter(sql: "deletedAt IS NULL AND visibility = 'archive' AND \(whereSQL)", arguments: Self.sqlArgs(args))
        .order(Column("localDateTime").desc)
        .limit(limit)
        .fetchAll(db)
      return records.map(\.model)
    }
  }

  /// Hidden (but not locked) assets in scope — Utilities · Hidden.
  public func hiddenAssets(scope: ContainerScope, limit: Int = 500) async throws -> [Asset] {
    let (whereSQL, args) = Self.scopeWhereValues(scope)
    return try await dbQueue.read { db in
      let records = try AssetRecord
        .filter(sql: "deletedAt IS NULL AND visibility = 'hidden' AND \(whereSQL)", arguments: Self.sqlArgs(args))
        .order(Column("localDateTime").desc)
        .limit(limit)
        .fetchAll(db)
      return records.map(\.model)
    }
  }

  /// Geotagged assets in scope — sidebar Map (DECISIONS §10 `timeline` purpose scope).
  public func mapPoints(scope: ContainerScope, limit: Int = 2000) async throws -> [MapPoint] {
    let (whereSQL, args) = Self.scopeWhereValues(scope)
    return try await dbQueue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT asset.id AS id, assetExif.latitude AS latitude, assetExif.longitude AS longitude
          FROM asset
          JOIN assetExif ON assetExif.assetId = asset.id
          WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked'
            AND assetExif.latitude IS NOT NULL AND assetExif.longitude IS NOT NULL
            AND \(whereSQL)
          LIMIT ?
          """,
        arguments: Self.sqlArgs(args, [limit])
      ).map { row in
        MapPoint(id: row["id"], latitude: row["latitude"], longitude: row["longitude"])
      }
    }
  }

  static func scopeWhereValues(_ scope: ContainerScope) -> (sql: String, arguments: [String]) {
    var clauses: [String] = []
    var args: [String] = []
    if !scope.personalUserIds.isEmpty {
      let ids = Array(scope.personalUserIds)
      clauses.append(
        "(asset.spaceId IS NULL AND asset.libraryId IS NULL AND asset.ownerId IN (\(placeholdersList(ids.count))))"
      )
      args += ids
    }
    if !scope.spaceIds.isEmpty {
      let ids = Array(scope.spaceIds)
      clauses.append("asset.spaceId IN (\(placeholdersList(ids.count)))")
      args += ids
    }
    if !scope.libraryIds.isEmpty {
      let ids = Array(scope.libraryIds)
      clauses.append("asset.libraryId IN (\(placeholdersList(ids.count)))")
      args += ids
    }
    guard !clauses.isEmpty else { return ("0", []) }
    return ("(" + clauses.joined(separator: " OR ") + ")", args)
  }
}

/// One geotagged asset for the sidebar Map — DECISIONS §10 `timeline` scope.
public struct MapPoint: Sendable, Hashable {
  public var id: String
  public var latitude: Double
  public var longitude: Double

  public init(id: String, latitude: Double, longitude: Double) {
    self.id = id
    self.latitude = latitude
    self.longitude = longitude
  }
}
