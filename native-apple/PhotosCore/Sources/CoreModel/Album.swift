import Foundation

/// Mirrors `SyncAlbumV2` (owner comes from `AlbumUsersV1` rows, not the album row itself — see
/// `syncAlbumV2ToV1` in server/src/dtos/sync.dto.ts).
public struct Album: Sendable, Identifiable, Hashable {
  public var id: String
  public var name: String
  public var description: String
  public var createdAt: Date
  public var updatedAt: Date
  public var thumbnailAssetId: String?
  public var isActivityEnabled: Bool
  public var order: String

  public init(
    id: String,
    name: String,
    description: String,
    createdAt: Date,
    updatedAt: Date,
    thumbnailAssetId: String? = nil,
    isActivityEnabled: Bool = false,
    order: String = "desc"
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.thumbnailAssetId = thumbnailAssetId
    self.isActivityEnabled = isActivityEnabled
    self.order = order
  }
}

/// Mirrors `SyncAlbumUserV1` — DECISIONS §4 "every album member of any role may add/remove any asset;
/// role only gates album-level settings".
public struct AlbumMember: Sendable, Hashable {
  public var albumId: String
  public var userId: String
  public var role: AlbumUserRoleKind

  public init(albumId: String, userId: String, role: AlbumUserRoleKind) {
    self.albumId = albumId
    self.userId = userId
    self.role = role
  }
}

/// Mirrors `SyncStackV1`.
public struct Stack: Sendable, Identifiable, Hashable {
  public var id: String
  public var createdAt: Date
  public var updatedAt: Date
  public var primaryAssetId: String
  public var ownerId: String

  public init(id: String, createdAt: Date, updatedAt: Date, primaryAssetId: String, ownerId: String) {
    self.id = id
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.primaryAssetId = primaryAssetId
    self.ownerId = ownerId
  }
}

/// Mirrors `SyncPersonV1`.
public struct Person: Sendable, Identifiable, Hashable {
  public var id: String
  public var createdAt: Date
  public var updatedAt: Date
  public var ownerId: String
  public var name: String
  public var birthDate: Date?
  public var isHidden: Bool
  public var isFavorite: Bool
  public var color: String?
  public var faceAssetId: String?

  public init(
    id: String,
    createdAt: Date,
    updatedAt: Date,
    ownerId: String,
    name: String,
    birthDate: Date? = nil,
    isHidden: Bool = false,
    isFavorite: Bool = false,
    color: String? = nil,
    faceAssetId: String? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.ownerId = ownerId
    self.name = name
    self.birthDate = birthDate
    self.isHidden = isHidden
    self.isFavorite = isFavorite
    self.color = color
    self.faceAssetId = faceAssetId
  }
}

/// Mirrors `SyncAssetFaceV2`.
public struct Face: Sendable, Identifiable, Hashable {
  public var id: String
  public var assetId: String
  public var personId: String?
  public var imageWidth: Int
  public var imageHeight: Int
  public var boundingBoxX1: Int
  public var boundingBoxY1: Int
  public var boundingBoxX2: Int
  public var boundingBoxY2: Int
  public var sourceType: String
  public var deletedAt: Date?
  public var isVisible: Bool

  public init(
    id: String,
    assetId: String,
    personId: String? = nil,
    imageWidth: Int,
    imageHeight: Int,
    boundingBoxX1: Int,
    boundingBoxY1: Int,
    boundingBoxX2: Int,
    boundingBoxY2: Int,
    sourceType: String,
    deletedAt: Date? = nil,
    isVisible: Bool = true
  ) {
    self.id = id
    self.assetId = assetId
    self.personId = personId
    self.imageWidth = imageWidth
    self.imageHeight = imageHeight
    self.boundingBoxX1 = boundingBoxX1
    self.boundingBoxY1 = boundingBoxY1
    self.boundingBoxX2 = boundingBoxX2
    self.boundingBoxY2 = boundingBoxY2
    self.sourceType = sourceType
    self.deletedAt = deletedAt
    self.isVisible = isVisible
  }
}

/// Mirrors `SyncMemoryV1`. `data` is kept as opaque JSON text (memory-type specific payload).
public struct Memory: Sendable, Identifiable, Hashable {
  public var id: String
  public var createdAt: Date
  public var updatedAt: Date
  public var deletedAt: Date?
  public var ownerId: String
  public var type: String
  public var dataJSON: String
  public var isSaved: Bool
  public var memoryAt: Date
  public var seenAt: Date?
  public var showAt: Date?
  public var hideAt: Date?

  public init(
    id: String,
    createdAt: Date,
    updatedAt: Date,
    deletedAt: Date? = nil,
    ownerId: String,
    type: String,
    dataJSON: String,
    isSaved: Bool = false,
    memoryAt: Date,
    seenAt: Date? = nil,
    showAt: Date? = nil,
    hideAt: Date? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.deletedAt = deletedAt
    self.ownerId = ownerId
    self.type = type
    self.dataJSON = dataJSON
    self.isSaved = isSaved
    self.memoryAt = memoryAt
    self.seenAt = seenAt
    self.showAt = showAt
    self.hideAt = hideAt
  }
}
