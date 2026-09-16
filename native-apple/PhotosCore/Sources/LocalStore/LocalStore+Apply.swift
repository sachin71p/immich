import CoreModel
import GRDB

extension PhotosLocalStore {
  /// Applies a batch of parsed sync-stream lines in a single transaction (brief task 2: "apply each
  /// entity in a DB transaction batch"). `currentUserId` is needed to tell "I lost access" apart from
  /// "someone else lost access" for `spaceMemberDelete` (DECISIONS §8).
  public func apply(_ changes: [SyncChange], currentUserId: String) async throws {
    try await dbQueue.write { db in
      for change in changes {
        try Self.applyOne(change, currentUserId: currentUserId, db: db)
      }
      try Self.recomputeAlbumSharingTypes(db: db)
    }
  }

  private static func applyOne(_ change: SyncChange, currentUserId: String, db: Database) throws {
    switch change {
    case .user(let user):
      try UserRecord(user).save(db)
    case .userDelete(let id):
      try UserRecord.deleteOne(db, key: id)

    case .partner(let partner):
      try PartnerRecord(partner).save(db)
    case .partnerDelete(let sharedById, let sharedWithId):
      try PartnerRecord.deleteOne(db, key: ["sharedById": sharedById, "sharedWithId": sharedWithId])

    case .asset(let asset):
      try AssetRecord(asset).save(db)
    case .assetDelete(let id):
      try AssetRecord.deleteOne(db, key: id)
      try AssetExifRecord.deleteOne(db, key: id)
    case .assetExif(let exif):
      try AssetExifRecord(exif).save(db)

    case .album(let album):
      try AlbumRecord(album).save(db)
    case .albumDelete(let id):
      try AlbumRecord.deleteOne(db, key: id)
      try db.execute(sql: "DELETE FROM albumUser WHERE albumId = ?", arguments: [id])
      try db.execute(sql: "DELETE FROM albumAsset WHERE albumId = ?", arguments: [id])
    case .albumUser(let member):
      try AlbumUserRecord(member).save(db)
    case .albumUserDelete(let albumId, let userId):
      try AlbumUserRecord.deleteOne(db, key: ["albumId": albumId, "userId": userId])
    case .albumAsset(let albumId, let assetId):
      try AlbumAssetRecord(albumId: albumId, assetId: assetId).save(db)
    case .albumAssetDelete(let albumId, let assetId):
      try AlbumAssetRecord.deleteOne(db, key: ["albumId": albumId, "assetId": assetId])

    case .stack(let stack):
      try StackRecord(stack).save(db)
    case .stackDelete(let id):
      try StackRecord.deleteOne(db, key: id)

    case .space(let space):
      try SpaceRecord(space).save(db)
    case .spaceDelete(let id):
      try dropSpace(id, db: db)
    case .spaceMember(let member):
      try SpaceMemberRecord(member).save(db)
    case .spaceMemberDelete(let spaceId, let userId):
      try SpaceMemberRecord.deleteOne(db, key: ["spaceId": spaceId, "userId": userId])
      if userId == currentUserId {
        try dropSpace(spaceId, db: db)
      }

    case .library(let library):
      // Preserve an already-hydrated uploadPath (REST fallback, see A1 handoff) across re-upserts.
      let existing = try Row.fetchOne(db, sql: "SELECT uploadPath, uploadPathHydrated FROM library WHERE id = ?", arguments: [library.id])
      try LibraryRecord(
        library,
        uploadPath: existing?["uploadPath"],
        uploadPathHydrated: existing?["uploadPathHydrated"] ?? false
      ).save(db)
    case .libraryDelete(let id):
      try LibraryRecord.deleteOne(db, key: id)
      try db.execute(sql: "DELETE FROM libraryMember WHERE libraryId = ?", arguments: [id])
      try db.execute(sql: "DELETE FROM asset WHERE libraryId = ?", arguments: [id])

    case .person(let person):
      try PersonRecord(person).save(db)
    case .personDelete(let id):
      try PersonRecord.deleteOne(db, key: id)
    case .face(let face):
      try FaceRecord(face).save(db)
    case .faceDelete(let id):
      try FaceRecord.deleteOne(db, key: id)

    case .memory(let memory):
      try MemoryRecord(memory).save(db)
    case .memoryDelete(let id):
      try MemoryRecord.deleteOne(db, key: id)
      try db.execute(sql: "DELETE FROM memoryAsset WHERE memoryId = ?", arguments: [id])
    case .memoryAsset(let memoryId, let assetId):
      try MemoryAssetRecord(memoryId: memoryId, assetId: assetId).save(db)
    case .memoryAssetDelete(let memoryId, let assetId):
      try MemoryAssetRecord.deleteOne(db, key: ["memoryId": memoryId, "assetId": assetId])

    case .userMetadata(let userId, let key, let valueJSON):
      try UserMetadataRecord(userId: userId, key: key, valueJSON: valueJSON).save(db)
    case .userMetadataDelete(let userId, let key):
      try UserMetadataRecord.deleteOne(db, key: ["userId": userId, "key": key])

    case .ack(let type, let value):
      try SyncAckRecord(type: type, ack: value).save(db)
    }
  }

  /// Container removal (brief task 2): drop the space row, its membership rows, and every asset
  /// currently in it.
  private static func dropSpace(_ id: String, db: Database) throws {
    try SpaceRecord.deleteOne(db, key: id)
    try db.execute(sql: "DELETE FROM spaceMember WHERE spaceId = ?", arguments: [id])
    try db.execute(sql: "DELETE FROM asset WHERE spaceId = ?", arguments: [id])
  }

  private static func recomputeAlbumSharingTypes(db: Database) throws {
    try db.execute(sql: """
      UPDATE album SET sharingType = CASE
        WHEN (SELECT COUNT(*) FROM albumUser WHERE albumUser.albumId = album.id) > 1 THEN 'shared'
        ELSE 'personal' END
      """)
  }
}
