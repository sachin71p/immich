import CoreModel
import Foundation
import GRDB

/// GRDB record for the `user` table — mirrors `CoreModel.User`. Kept as a distinct type (rather than
/// conforming `CoreModel.User` itself to GRDB's protocols) so persistence concerns never leak into the
/// value types other targets (`Rules`, `SyncEngine`) depend on.
struct UserRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "user"

  var id: String
  var name: String
  var email: String
  var avatarColor: String?
  var deletedAt: Date?
  var hasProfileImage: Bool
  var profileChangedAt: Date?
  var isAdmin: Bool?
  var storageLabel: String?
  var quotaSizeInBytes: Int?
  var quotaUsageInBytes: Int?

  init(_ user: User) {
    id = user.id
    name = user.name
    email = user.email
    avatarColor = user.avatarColor
    deletedAt = user.deletedAt
    hasProfileImage = user.hasProfileImage
    profileChangedAt = user.profileChangedAt
    isAdmin = user.isAdmin
    storageLabel = user.storageLabel
    quotaSizeInBytes = user.quotaSizeInBytes
    quotaUsageInBytes = user.quotaUsageInBytes
  }

  var model: User {
    User(
      id: id, name: name, email: email, avatarColor: avatarColor, deletedAt: deletedAt,
      hasProfileImage: hasProfileImage, profileChangedAt: profileChangedAt, isAdmin: isAdmin,
      storageLabel: storageLabel, quotaSizeInBytes: quotaSizeInBytes, quotaUsageInBytes: quotaUsageInBytes
    )
  }
}

struct PartnerRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "partner"

  var sharedById: String
  var sharedWithId: String
  var inTimeline: Bool

  init(_ partner: Partner) {
    sharedById = partner.sharedById
    sharedWithId = partner.sharedWithId
    inTimeline = partner.inTimeline
  }

  var model: Partner {
    Partner(sharedById: sharedById, sharedWithId: sharedWithId, inTimeline: inTimeline)
  }
}
