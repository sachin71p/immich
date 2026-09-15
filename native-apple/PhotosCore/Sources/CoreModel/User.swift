import Foundation

/// Mirrors `SyncUserV1`/`SyncAuthUserV1` (server/src/dtos/sync.dto.ts). The `AuthUsersV1` stream only ever
/// describes the signed-in user, so the admin-only fields are optional here and `nil` for every other user.
public struct User: Sendable, Identifiable, Hashable {
  public var id: String
  public var name: String
  public var email: String
  public var avatarColor: String?
  public var deletedAt: Date?
  public var hasProfileImage: Bool
  public var profileChangedAt: Date?
  public var isAdmin: Bool?
  public var storageLabel: String?
  public var quotaSizeInBytes: Int?
  public var quotaUsageInBytes: Int?

  public init(
    id: String,
    name: String,
    email: String,
    avatarColor: String? = nil,
    deletedAt: Date? = nil,
    hasProfileImage: Bool = false,
    profileChangedAt: Date? = nil,
    isAdmin: Bool? = nil,
    storageLabel: String? = nil,
    quotaSizeInBytes: Int? = nil,
    quotaUsageInBytes: Int? = nil
  ) {
    self.id = id
    self.name = name
    self.email = email
    self.avatarColor = avatarColor
    self.deletedAt = deletedAt
    self.hasProfileImage = hasProfileImage
    self.profileChangedAt = profileChangedAt
    self.isAdmin = isAdmin
    self.storageLabel = storageLabel
    self.quotaSizeInBytes = quotaSizeInBytes
    self.quotaUsageInBytes = quotaUsageInBytes
  }
}

/// Mirrors `SyncPartnerV1`.
public struct Partner: Sendable, Hashable {
  public var sharedById: String
  public var sharedWithId: String
  public var inTimeline: Bool

  public init(sharedById: String, sharedWithId: String, inTimeline: Bool) {
    self.sharedById = sharedById
    self.sharedWithId = sharedWithId
    self.inTimeline = inTimeline
  }
}
