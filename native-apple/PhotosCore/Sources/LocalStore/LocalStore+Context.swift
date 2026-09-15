import CoreModel
import Foundation
import GRDB
import Rules

extension PhotosLocalStore {
  /// Builds the `Rules.AccessContext` for `userId` from `space_members`/`library`/`library_members`.
  public func accessContext(for userId: String) async throws -> AccessContext {
    try await dbQueue.read { db in
      let memberSpaceIds = try Set(
        String.fetchAll(db, sql: "SELECT spaceId FROM spaceMember WHERE userId = ?", arguments: [userId])
      )
      let ownedLibraryIds = try Set(
        String.fetchAll(db, sql: "SELECT id FROM library WHERE ownerId = ?", arguments: [userId])
      )
      let memberLibraryIds = try Set(
        String.fetchAll(db, sql: "SELECT libraryId FROM libraryMember WHERE userId = ?", arguments: [userId])
      )
      let libraryUploadPathIds = try Set(
        String.fetchAll(db, sql: "SELECT id FROM library WHERE uploadPath IS NOT NULL")
      )
      let lockedAssetIds = try Set(
        String.fetchAll(db, sql: "SELECT id FROM asset WHERE visibility = 'locked'")
      )
      let albumRows = try Row.fetchAll(
        db, sql: "SELECT assetId, albumId FROM albumAsset WHERE albumId IN (SELECT albumId FROM albumUser WHERE userId = ?)",
        arguments: [userId]
      )
      var memberAlbumIdsByAsset: [String: Set<String>] = [:]
      for row in albumRows {
        let assetId: String = row["assetId"]
        let albumId: String = row["albumId"]
        memberAlbumIdsByAsset[assetId, default: []].insert(albumId)
      }

      return AccessContext(
        currentUserId: userId,
        memberSpaceIds: memberSpaceIds,
        accessibleLibraryIds: ownedLibraryIds.union(memberLibraryIds),
        ownedLibraryIds: ownedLibraryIds,
        libraryUploadPathIds: libraryUploadPathIds,
        lockedAssetIds: lockedAssetIds,
        memberAlbumIdsByAsset: memberAlbumIdsByAsset
      )
    }
  }

  /// Builds the `Rules.TimelineContext` for `userId` from prefs + memberships — DECISIONS §9/§10.
  public func timelineContext(
    for userId: String,
    explicitFilter: ExplicitContainerFilter? = nil
  ) async throws -> TimelineContext {
    try await dbQueue.read { db in
      let prefs = try Self.readPrefs(userId: userId, db: db)
      let partners = try PartnerRecord
        .filter(sql: "sharedWithId = ?", arguments: [userId])
        .fetchAll(db)
        .map(\.model)
      let spaceMemberships = try SpaceMemberRecord
        .filter(sql: "userId = ?", arguments: [userId])
        .fetchAll(db)
        .map(\.model)
      let ownedLibraries = try Set(
        String.fetchAll(db, sql: "SELECT id FROM library WHERE ownerId = ?", arguments: [userId])
      )
      let libraryMemberships = try LibraryMemberRecord
        .filter(sql: "userId = ?", arguments: [userId])
        .fetchAll(db)
        .map(\.model)

      return TimelineContext(
        currentUserId: userId,
        prefs: prefs,
        partners: partners,
        spaceMemberships: spaceMemberships,
        ownedLibraries: ownedLibraries,
        libraryMemberships: libraryMemberships,
        explicitFilter: explicitFilter
      )
    }
  }

  /// `sharedLibraries` `UserMetadataV1` payload (DECISIONS §9), decoded from `userMetadata`; defaults
  /// when absent (no sync received yet).
  static func readPrefs(userId: String, db: Database) throws -> SharedLibraryPrefs {
    guard
      let json = try String.fetchOne(
        db, sql: "SELECT valueJSON FROM userMetadata WHERE userId = ? AND key = 'sharedLibraries'",
        arguments: [userId]
      ),
      let data = json.data(using: .utf8)
    else {
      return SharedLibraryPrefs()
    }
    return (try? PrefsCoding.decode(data)) ?? SharedLibraryPrefs()
  }

  /// Extension/agent entry points have no signed-in user id handy; the prefs payload is
  /// per-user but backup/network flags are device-wide in practice — first row wins.
  public func anyPrefs() async throws -> SharedLibraryPrefs {
    try await dbQueue.read { db in
      if let json = try String.fetchOne(
        db, sql: "SELECT valueJSON FROM userMetadata WHERE key = 'sharedLibraries' LIMIT 1",
        arguments: []
      ), let data = json.data(using: .utf8), let prefs = try? PrefsCoding.decode(data) {
        return prefs
      }
      return SharedLibraryPrefs()
    }
  }

  public func prefs(for userId: String) async throws -> SharedLibraryPrefs {
    try await dbQueue.read { db in try Self.readPrefs(userId: userId, db: db) }
  }

  /// Optimistic local write for a preferences change, ahead of `PUT /users/me/preferences` completing —
  /// brief task 5 "prefs" mutation.
  public func setPrefs(_ prefs: SharedLibraryPrefs, for userId: String) async throws {
    let json = try PrefsCoding.encode(prefs)
    try await dbQueue.write { db in
      try UserMetadataRecord(userId: userId, key: "sharedLibraries", valueJSON: json).save(db)
    }
  }
}

/// `SharedLibraryPrefs.UploadTarget` needs a wire shape distinct from Swift's default enum-with-payload
/// encoding (`{type, spaceId}`, matching `sharedLibraries.defaultUploadTarget` — DECISIONS §9) — kept
/// next to the reader/writer above rather than as `Codable` conformance on the `CoreModel` type itself.
enum PrefsCoding {
  private struct Wire: Codable {
    struct UploadTarget: Codable {
      var type: String
      var spaceId: String?
    }
    var defaultUploadTarget: UploadTarget
    var showPersonalInTimeline: Bool
    var hiddenOwnedLibraryIds: [String]
    // A5 backup fields. Defaults keep pre-A5 payloads decodable (synthesized init uses
    // `decodeIfPresent` for defaulted properties, so old rows decode to backup-off).
    var backupEnabled: Bool = false
    var backupAlbumIds: [String] = []
    var useCellularForPhotos: Bool = false
    var useCellularForVideos: Bool = false
    var allowLowPowerUploads: Bool = false
    var uploadOriginalPlusEdit: Bool = false
    var deleteAfterImport: Bool = false
  }

  static func decode(_ data: Data) throws -> SharedLibraryPrefs {
    let wire = try JSONDecoder().decode(Wire.self, from: data)
    let target: SharedLibraryPrefs.UploadTarget =
      wire.defaultUploadTarget.type == "space" && wire.defaultUploadTarget.spaceId != nil
        ? .space(wire.defaultUploadTarget.spaceId!)
        : .personal
    return SharedLibraryPrefs(
      defaultUploadTarget: target,
      showPersonalInTimeline: wire.showPersonalInTimeline,
      hiddenOwnedLibraryIds: wire.hiddenOwnedLibraryIds,
      backupEnabled: wire.backupEnabled,
      backupAlbumIds: wire.backupAlbumIds,
      useCellularForPhotos: wire.useCellularForPhotos,
      useCellularForVideos: wire.useCellularForVideos,
      allowLowPowerUploads: wire.allowLowPowerUploads,
      uploadOriginalPlusEdit: wire.uploadOriginalPlusEdit,
      deleteAfterImport: wire.deleteAfterImport
    )
  }

  static func encode(_ prefs: SharedLibraryPrefs) throws -> String {
    let target: Wire.UploadTarget
    switch prefs.defaultUploadTarget {
    case .personal: target = .init(type: "personal", spaceId: nil)
    case .space(let id): target = .init(type: "space", spaceId: id)
    }
    let wire = Wire(
      defaultUploadTarget: target, showPersonalInTimeline: prefs.showPersonalInTimeline,
      hiddenOwnedLibraryIds: prefs.hiddenOwnedLibraryIds,
      backupEnabled: prefs.backupEnabled,
      backupAlbumIds: prefs.backupAlbumIds,
      useCellularForPhotos: prefs.useCellularForPhotos,
      useCellularForVideos: prefs.useCellularForVideos,
      allowLowPowerUploads: prefs.allowLowPowerUploads,
      uploadOriginalPlusEdit: prefs.uploadOriginalPlusEdit,
      deleteAfterImport: prefs.deleteAfterImport
    )
    let data = try JSONEncoder().encode(wire)
    return String(decoding: data, as: UTF8.self)
  }
}
