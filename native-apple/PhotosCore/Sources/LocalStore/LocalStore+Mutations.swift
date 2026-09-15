import CoreModel
import Foundation
import GRDB

/// Local optimistic writes — brief task 5: "Mutations through API then local optimistic update". These
/// only touch the local mirror; `SyncEngine`'s mutation calls apply the matching server request first and
/// call these on success (or roll them back to the pre-mutation value on failure — see `SyncEngine`).
extension PhotosLocalStore {
  public func asset(id: String) async throws -> Asset? {
    try await dbQueue.read { db in try AssetRecord.fetchOne(db, key: id)?.model }
  }

  public func assets(ids: [String]) async throws -> [Asset] {
    guard !ids.isEmpty else { return [] }
    return try await dbQueue.read { db in try AssetRecord.fetchAll(db, keys: ids).map(\.model) }
  }

  /// Assets sharing a stack with `stackId`, and — separately — a live photo's video-pair id, so callers
  /// can expand a move/trash selection per DECISIONS §6 rule 5 before calling `Rules.MoveTargets`.
  public func stackMembers(stackId: String) async throws -> [Asset] {
    try await dbQueue.read { db in
      try AssetRecord.filter(sql: "stackId = ?", arguments: [stackId]).fetchAll(db).map(\.model)
    }
  }

  public func setFavorite(ids: [String], isFavorite: Bool) async throws {
    guard !ids.isEmpty else { return }
    try await dbQueue.write { db in
      try db.execute(
        sql: "UPDATE asset SET isFavorite = ? WHERE id IN (\(Self.placeholdersList(ids.count)))",
        arguments: Self.sqlArgs([isFavorite], ids)
      )
    }
  }

  public func setVisibility(ids: [String], visibility: AssetVisibilityKind) async throws {
    guard !ids.isEmpty else { return }
    try await dbQueue.write { db in
      try db.execute(
        sql: "UPDATE asset SET visibility = ? WHERE id IN (\(Self.placeholdersList(ids.count)))",
        arguments: Self.sqlArgs([visibility.rawValue], ids)
      )
    }
  }

  /// Trash (soft delete): stamps `deletedAt`. Restore clears it. Permanent delete removes the row —
  /// callers only reach that after the server's `force: true` delete succeeds.
  public func trash(ids: [String], at date: Date = Date()) async throws {
    guard !ids.isEmpty else { return }
    try await dbQueue.write { db in
      try db.execute(
        sql: "UPDATE asset SET deletedAt = ? WHERE id IN (\(Self.placeholdersList(ids.count)))",
        arguments: Self.sqlArgs([date], ids)
      )
    }
  }

  public func restore(ids: [String]) async throws {
    guard !ids.isEmpty else { return }
    try await dbQueue.write { db in
      try db.execute(
        sql: "UPDATE asset SET deletedAt = NULL WHERE id IN (\(Self.placeholdersList(ids.count)))",
        arguments: Self.sqlArgs(ids)
      )
    }
  }

  public func permanentlyDelete(ids: [String]) async throws {
    guard !ids.isEmpty else { return }
    try await dbQueue.write { db in
      try db.execute(sql: "DELETE FROM asset WHERE id IN (\(Self.placeholdersList(ids.count)))", arguments: Self.sqlArgs(ids))
      try db.execute(sql: "DELETE FROM assetExif WHERE assetId IN (\(Self.placeholdersList(ids.count)))", arguments: Self.sqlArgs(ids))
    }
  }

  /// Applies a successful `POST /assets/move` result — DECISIONS §6 rule 6: ownerId/albums/favorites/
  /// tags/faces/edits/ids never change, only the container fields.
  public func applyMoveResults(_ results: [MoveResult], target: MoveTarget) async throws {
    let movedIds = results.filter { $0.status == .moved }.map(\.assetId)
    guard !movedIds.isEmpty else { return }
    try await dbQueue.write { db in
      switch target {
      case .personal:
        try db.execute(
          sql: "UPDATE asset SET spaceId = NULL, libraryId = NULL WHERE id IN (\(Self.placeholdersList(movedIds.count)))",
          arguments: Self.sqlArgs(movedIds)
        )
      case .space(let spaceId):
        try db.execute(
          sql: "UPDATE asset SET spaceId = ?, libraryId = NULL WHERE id IN (\(Self.placeholdersList(movedIds.count)))",
          arguments: Self.sqlArgs([spaceId], movedIds)
        )
      case .library(let libraryId):
        try db.execute(
          sql: "UPDATE asset SET spaceId = NULL, libraryId = ? WHERE id IN (\(Self.placeholdersList(movedIds.count)))",
          arguments: Self.sqlArgs([libraryId], movedIds)
        )
      }
    }
  }

  public func upsertAlbumLocally(_ album: Album) async throws {
    try await dbQueue.write { db in try AlbumRecord(album).save(db) }
  }

  public func deleteAlbumLocally(id: String) async throws {
    try await dbQueue.write { db in
      try AlbumRecord.deleteOne(db, key: id)
      try db.execute(sql: "DELETE FROM albumUser WHERE albumId = ?", arguments: [id])
      try db.execute(sql: "DELETE FROM albumAsset WHERE albumId = ?", arguments: [id])
    }
  }

  public func addAssets(_ assetIds: [String], toAlbum albumId: String) async throws {
    guard !assetIds.isEmpty else { return }
    try await dbQueue.write { db in
      for assetId in assetIds {
        try AlbumAssetRecord(albumId: albumId, assetId: assetId).save(db)
      }
    }
  }

  public func removeAssets(_ assetIds: [String], fromAlbum albumId: String) async throws {
    guard !assetIds.isEmpty else { return }
    try await dbQueue.write { db in
      for assetId in assetIds {
        try AlbumAssetRecord.deleteOne(db, key: ["albumId": albumId, "assetId": assetId])
      }
    }
  }

  public func upsertSpace(_ space: Space) async throws {
    try await dbQueue.write { db in try SpaceRecord(space).save(db) }
  }

  public func deleteSpaceLocally(id: String) async throws {
    try await dbQueue.write { db in
      try SpaceRecord.deleteOne(db, key: id)
      try db.execute(sql: "DELETE FROM spaceMember WHERE spaceId = ?", arguments: [id])
      try db.execute(sql: "UPDATE asset SET spaceId = NULL WHERE spaceId = ?", arguments: [id])
    }
  }

  public func upsertSpaceMember(_ member: SpaceMember) async throws {
    try await dbQueue.write { db in try SpaceMemberRecord(member).save(db) }
  }

  public func removeSpaceMemberLocally(spaceId: String, userId: String) async throws {
    try await dbQueue.write { db in
      try SpaceMemberRecord.deleteOne(db, key: ["spaceId": spaceId, "userId": userId])
    }
  }

  static func placeholdersList(_ count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ",")
  }
}
