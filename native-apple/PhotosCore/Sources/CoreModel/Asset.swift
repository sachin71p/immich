import Foundation

/// The local mirror of a server asset — a superset of `SyncAssetV2` (server/src/dtos/sync.dto.ts)
/// plus the fork's `spaceId` and Apple-only "source" bookkeeping flags used by Upload/A2.
public struct Asset: Sendable, Identifiable, Hashable {
  public var id: String
  public var ownerId: String
  public var originalFileName: String
  public var thumbhash: String?
  public var checksum: String
  public var fileCreatedAt: Date?
  public var fileModifiedAt: Date?
  public var createdAt: Date?
  public var localDateTime: Date?
  public var durationSeconds: Int?
  public var type: AssetKind
  public var deletedAt: Date?
  public var isFavorite: Bool
  public var visibility: AssetVisibilityKind
  public var livePhotoVideoId: String?
  public var stackId: String?
  public var libraryId: String?
  /// fork: shared-libraries — DECISIONS §10.
  public var spaceId: String?
  public var width: Int?
  public var height: Int?
  public var isEdited: Bool

  /// Apple-only bookkeeping (not part of `SyncAssetV2`): where a not-yet-uploaded asset came from,
  /// populated by the Upload module; `nil` for assets that only exist because sync pulled them down.
  public var localIdentifier: String?

  public init(
    id: String,
    ownerId: String,
    originalFileName: String,
    thumbhash: String? = nil,
    checksum: String,
    fileCreatedAt: Date? = nil,
    fileModifiedAt: Date? = nil,
    createdAt: Date? = nil,
    localDateTime: Date? = nil,
    durationSeconds: Int? = nil,
    type: AssetKind,
    deletedAt: Date? = nil,
    isFavorite: Bool = false,
    visibility: AssetVisibilityKind = .timeline,
    livePhotoVideoId: String? = nil,
    stackId: String? = nil,
    libraryId: String? = nil,
    spaceId: String? = nil,
    width: Int? = nil,
    height: Int? = nil,
    isEdited: Bool = false,
    localIdentifier: String? = nil
  ) {
    self.id = id
    self.ownerId = ownerId
    self.originalFileName = originalFileName
    self.thumbhash = thumbhash
    self.checksum = checksum
    self.fileCreatedAt = fileCreatedAt
    self.fileModifiedAt = fileModifiedAt
    self.createdAt = createdAt
    self.localDateTime = localDateTime
    self.durationSeconds = durationSeconds
    self.type = type
    self.deletedAt = deletedAt
    self.isFavorite = isFavorite
    self.visibility = visibility
    self.livePhotoVideoId = livePhotoVideoId
    self.stackId = stackId
    self.libraryId = libraryId
    self.spaceId = spaceId
    self.width = width
    self.height = height
    self.isEdited = isEdited
    self.localIdentifier = localIdentifier
  }

  /// The container this asset currently belongs to — DECISIONS §10.
  public var container: Container {
    if let spaceId { return .space(spaceId) }
    if let libraryId { return .library(libraryId) }
    return .personal(ownerId)
  }
}

/// Mirrors `SyncAssetExifV1` (server/src/dtos/sync.dto.ts).
public struct AssetExif: Sendable, Hashable {
  public var assetId: String
  public var description: String?
  public var exifImageWidth: Int?
  public var exifImageHeight: Int?
  public var fileSizeInByte: Int?
  public var orientation: String?
  public var dateTimeOriginal: Date?
  public var modifyDate: Date?
  public var timeZone: String?
  public var latitude: Double?
  public var longitude: Double?
  public var projectionType: String?
  public var city: String?
  public var state: String?
  public var country: String?
  public var make: String?
  public var model: String?
  public var lensModel: String?
  public var fNumber: Double?
  public var focalLength: Double?
  public var iso: Int?
  public var exposureTime: String?
  public var profileDescription: String?
  public var rating: Int?
  public var fps: Double?

  public init(
    assetId: String,
    description: String? = nil,
    exifImageWidth: Int? = nil,
    exifImageHeight: Int? = nil,
    fileSizeInByte: Int? = nil,
    orientation: String? = nil,
    dateTimeOriginal: Date? = nil,
    modifyDate: Date? = nil,
    timeZone: String? = nil,
    latitude: Double? = nil,
    longitude: Double? = nil,
    projectionType: String? = nil,
    city: String? = nil,
    state: String? = nil,
    country: String? = nil,
    make: String? = nil,
    model: String? = nil,
    lensModel: String? = nil,
    fNumber: Double? = nil,
    focalLength: Double? = nil,
    iso: Int? = nil,
    exposureTime: String? = nil,
    profileDescription: String? = nil,
    rating: Int? = nil,
    fps: Double? = nil
  ) {
    self.assetId = assetId
    self.description = description
    self.exifImageWidth = exifImageWidth
    self.exifImageHeight = exifImageHeight
    self.fileSizeInByte = fileSizeInByte
    self.orientation = orientation
    self.dateTimeOriginal = dateTimeOriginal
    self.modifyDate = modifyDate
    self.timeZone = timeZone
    self.latitude = latitude
    self.longitude = longitude
    self.projectionType = projectionType
    self.city = city
    self.state = state
    self.country = country
    self.make = make
    self.model = model
    self.lensModel = lensModel
    self.fNumber = fNumber
    self.focalLength = focalLength
    self.iso = iso
    self.exposureTime = exposureTime
    self.profileDescription = profileDescription
    self.rating = rating
    self.fps = fps
  }

  /// Whether the projection type marks this as an equirectangular 360° photo (AP media-type heuristic).
  public var isPanorama: Bool {
    projectionType?.lowercased() == "equirectangular"
  }
}
