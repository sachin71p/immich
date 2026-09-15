import CoreModel
import Foundation
import GRDB

struct AlbumRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "album"

  var id: String
  var name: String
  var description: String
  var createdAt: Date
  var updatedAt: Date
  var thumbnailAssetId: String?
  var isActivityEnabled: Bool
  var order: String

  init(_ album: Album) {
    id = album.id
    name = album.name
    description = album.description
    createdAt = album.createdAt
    updatedAt = album.updatedAt
    thumbnailAssetId = album.thumbnailAssetId
    isActivityEnabled = album.isActivityEnabled
    order = album.order
  }

  var model: Album {
    Album(
      id: id, name: name, description: description, createdAt: createdAt, updatedAt: updatedAt,
      thumbnailAssetId: thumbnailAssetId, isActivityEnabled: isActivityEnabled, order: order
    )
  }
}

struct AlbumUserRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "albumUser"

  var albumId: String
  var userId: String
  var role: String

  init(_ member: AlbumMember) {
    albumId = member.albumId
    userId = member.userId
    role = member.role.rawValue
  }

  var model: AlbumMember {
    AlbumMember(albumId: albumId, userId: userId, role: AlbumUserRoleKind(rawValue: role) ?? .viewer)
  }
}

struct AlbumAssetRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "albumAsset"

  var albumId: String
  var assetId: String

  init(albumId: String, assetId: String) {
    self.albumId = albumId
    self.assetId = assetId
  }
}

struct StackRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "stack"

  var id: String
  var createdAt: Date
  var updatedAt: Date
  var primaryAssetId: String
  var ownerId: String

  init(_ stack: Stack) {
    id = stack.id
    createdAt = stack.createdAt
    updatedAt = stack.updatedAt
    primaryAssetId = stack.primaryAssetId
    ownerId = stack.ownerId
  }

  var model: Stack {
    Stack(id: id, createdAt: createdAt, updatedAt: updatedAt, primaryAssetId: primaryAssetId, ownerId: ownerId)
  }
}
