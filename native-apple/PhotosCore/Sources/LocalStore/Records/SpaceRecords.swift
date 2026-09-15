import CoreModel
import Foundation
import GRDB

struct SpaceRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "space"

  var id: String
  var name: String
  var description: String
  var createdAt: Date
  var updatedAt: Date

  init(_ space: Space) {
    id = space.id
    name = space.name
    description = space.description
    createdAt = space.createdAt
    updatedAt = space.updatedAt
  }

  var model: Space {
    Space(id: id, name: name, description: description, createdAt: createdAt, updatedAt: updatedAt)
  }
}

struct SpaceMemberRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "spaceMember"

  var spaceId: String
  var userId: String
  var role: String
  var showInTimeline: Bool

  init(_ member: SpaceMember) {
    spaceId = member.spaceId
    userId = member.userId
    role = member.role.rawValue
    showInTimeline = member.showInTimeline
  }

  var model: SpaceMember {
    SpaceMember(
      spaceId: spaceId, userId: userId, role: SharedSpaceRoleKind(rawValue: role) ?? .contributor,
      showInTimeline: showInTimeline
    )
  }
}

struct LibraryRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "library"

  var id: String
  var name: String
  var ownerId: String
  var createdAt: Date
  var updatedAt: Date
  /// Not carried by `SyncSharedLibraryV1`; hydrated via the `getLibrary` REST fallback (A1 handoff).
  var uploadPath: String?
  var uploadPathHydrated: Bool

  init(_ library: Library, uploadPath: String? = nil, uploadPathHydrated: Bool = false) {
    id = library.id
    name = library.name
    ownerId = library.ownerId
    createdAt = library.createdAt
    updatedAt = library.updatedAt
    self.uploadPath = uploadPath
    self.uploadPathHydrated = uploadPathHydrated
  }

  var model: Library {
    Library(id: id, name: name, ownerId: ownerId, createdAt: createdAt, updatedAt: updatedAt)
  }
}

struct LibraryMemberRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "libraryMember"

  var libraryId: String
  var userId: String
  var role: String
  var showInTimeline: Bool

  init(_ member: LibraryMember) {
    libraryId = member.libraryId
    userId = member.userId
    role = member.role.rawValue
    showInTimeline = member.showInTimeline
  }

  var model: LibraryMember {
    LibraryMember(
      libraryId: libraryId, userId: userId, role: SharedSpaceRoleKind(rawValue: role) ?? .contributor,
      showInTimeline: showInTimeline
    )
  }
}
