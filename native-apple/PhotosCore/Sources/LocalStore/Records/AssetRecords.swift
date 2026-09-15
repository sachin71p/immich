import CoreModel
import Foundation
import GRDB

struct AssetRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "asset"

  var id: String
  var ownerId: String
  var originalFileName: String
  var thumbhash: String?
  var checksum: String
  var fileCreatedAt: Date?
  var fileModifiedAt: Date?
  var createdAt: Date?
  var localDateTime: Date?
  var durationSeconds: Int?
  var type: String
  var deletedAt: Date?
  var isFavorite: Bool
  var visibility: String
  var livePhotoVideoId: String?
  var stackId: String?
  var libraryId: String?
  var spaceId: String?
  var width: Int?
  var height: Int?
  var isEdited: Bool
  var localIdentifier: String?

  init(_ asset: Asset) {
    id = asset.id
    ownerId = asset.ownerId
    originalFileName = asset.originalFileName
    thumbhash = asset.thumbhash
    checksum = asset.checksum
    fileCreatedAt = asset.fileCreatedAt
    fileModifiedAt = asset.fileModifiedAt
    createdAt = asset.createdAt
    localDateTime = asset.localDateTime
    durationSeconds = asset.durationSeconds
    type = asset.type.rawValue
    deletedAt = asset.deletedAt
    isFavorite = asset.isFavorite
    visibility = asset.visibility.rawValue
    livePhotoVideoId = asset.livePhotoVideoId
    stackId = asset.stackId
    libraryId = asset.libraryId
    spaceId = asset.spaceId
    width = asset.width
    height = asset.height
    isEdited = asset.isEdited
    localIdentifier = asset.localIdentifier
  }

  var model: Asset {
    Asset(
      id: id, ownerId: ownerId, originalFileName: originalFileName, thumbhash: thumbhash, checksum: checksum,
      fileCreatedAt: fileCreatedAt, fileModifiedAt: fileModifiedAt, createdAt: createdAt,
      localDateTime: localDateTime, durationSeconds: durationSeconds, type: AssetKind(rawValue: type) ?? .other,
      deletedAt: deletedAt, isFavorite: isFavorite, visibility: AssetVisibilityKind(rawValue: visibility) ?? .timeline,
      livePhotoVideoId: livePhotoVideoId, stackId: stackId, libraryId: libraryId, spaceId: spaceId, width: width,
      height: height, isEdited: isEdited, localIdentifier: localIdentifier
    )
  }
}

struct AssetExifRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "assetExif"

  var assetId: String
  var description: String?
  var exifImageWidth: Int?
  var exifImageHeight: Int?
  var fileSizeInByte: Int?
  var orientation: String?
  var dateTimeOriginal: Date?
  var modifyDate: Date?
  var timeZone: String?
  var latitude: Double?
  var longitude: Double?
  var projectionType: String?
  var city: String?
  var state: String?
  var country: String?
  var make: String?
  var model: String?
  var lensModel: String?
  var fNumber: Double?
  var focalLength: Double?
  var iso: Int?
  var exposureTime: String?
  var profileDescription: String?
  var rating: Int?
  var fps: Double?

  init(_ exif: AssetExif) {
    assetId = exif.assetId
    description = exif.description
    exifImageWidth = exif.exifImageWidth
    exifImageHeight = exif.exifImageHeight
    fileSizeInByte = exif.fileSizeInByte
    orientation = exif.orientation
    dateTimeOriginal = exif.dateTimeOriginal
    modifyDate = exif.modifyDate
    timeZone = exif.timeZone
    latitude = exif.latitude
    longitude = exif.longitude
    projectionType = exif.projectionType
    city = exif.city
    state = exif.state
    country = exif.country
    make = exif.make
    model = exif.model
    lensModel = exif.lensModel
    fNumber = exif.fNumber
    focalLength = exif.focalLength
    iso = exif.iso
    exposureTime = exif.exposureTime
    profileDescription = exif.profileDescription
    rating = exif.rating
    fps = exif.fps
  }

  var domainModel: AssetExif {
    AssetExif(
      assetId: assetId, description: description, exifImageWidth: exifImageWidth,
      exifImageHeight: exifImageHeight, fileSizeInByte: fileSizeInByte, orientation: orientation,
      dateTimeOriginal: dateTimeOriginal, modifyDate: modifyDate, timeZone: timeZone, latitude: latitude,
      longitude: longitude, projectionType: projectionType, city: city, state: state, country: country,
      make: make, model: model, lensModel: lensModel, fNumber: fNumber, focalLength: focalLength, iso: iso,
      exposureTime: exposureTime, profileDescription: profileDescription, rating: rating, fps: fps
    )
  }
}
