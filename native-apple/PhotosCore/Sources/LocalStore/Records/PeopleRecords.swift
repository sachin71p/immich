import CoreModel
import Foundation
import GRDB

struct PersonRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "person"

  var id: String
  var createdAt: Date
  var updatedAt: Date
  var ownerId: String
  var name: String
  var birthDate: Date?
  var isHidden: Bool
  var isFavorite: Bool
  var color: String?
  var faceAssetId: String?

  init(_ person: Person) {
    id = person.id
    createdAt = person.createdAt
    updatedAt = person.updatedAt
    ownerId = person.ownerId
    name = person.name
    birthDate = person.birthDate
    isHidden = person.isHidden
    isFavorite = person.isFavorite
    color = person.color
    faceAssetId = person.faceAssetId
  }

  var model: Person {
    Person(
      id: id, createdAt: createdAt, updatedAt: updatedAt, ownerId: ownerId, name: name, birthDate: birthDate,
      isHidden: isHidden, isFavorite: isFavorite, color: color, faceAssetId: faceAssetId
    )
  }
}

struct FaceRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "face"

  var id: String
  var assetId: String
  var personId: String?
  var imageWidth: Int
  var imageHeight: Int
  var boundingBoxX1: Int
  var boundingBoxY1: Int
  var boundingBoxX2: Int
  var boundingBoxY2: Int
  var sourceType: String
  var deletedAt: Date?
  var isVisible: Bool

  init(_ face: Face) {
    id = face.id
    assetId = face.assetId
    personId = face.personId
    imageWidth = face.imageWidth
    imageHeight = face.imageHeight
    boundingBoxX1 = face.boundingBoxX1
    boundingBoxY1 = face.boundingBoxY1
    boundingBoxX2 = face.boundingBoxX2
    boundingBoxY2 = face.boundingBoxY2
    sourceType = face.sourceType
    deletedAt = face.deletedAt
    isVisible = face.isVisible
  }

  var model: Face {
    Face(
      id: id, assetId: assetId, personId: personId, imageWidth: imageWidth, imageHeight: imageHeight,
      boundingBoxX1: boundingBoxX1, boundingBoxY1: boundingBoxY1, boundingBoxX2: boundingBoxX2,
      boundingBoxY2: boundingBoxY2, sourceType: sourceType, deletedAt: deletedAt, isVisible: isVisible
    )
  }
}
