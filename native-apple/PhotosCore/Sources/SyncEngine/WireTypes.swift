import CoreModel
import Foundation

/// Hand-written mirrors of `server/src/dtos/sync.dto.ts`'s per-entity schemas. `/sync/stream`'s response
/// has no `content` in the OpenAPI document (it's written with Nest's raw `@Res()`, bypassing DTO
/// serialization — `server/src/controllers/sync.controller.ts`), so swift-openapi-generator never emits
/// types for these; unlike every other request in `ImmichAPI`, these can't come from the generated module.
/// See the A1 handoff for the full explanation.
enum WireDecoding {
  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)
      if let date = isoWithFractional.date(from: string) { return date }
      if let date = isoPlain.date(from: string) { return date }
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date format: \(string)")
    }
    return decoder
  }()

  // `ISO8601DateFormatter` isn't `Sendable`, but these are only ever read (never mutated) after
  // initialization, so sharing them across concurrent decode calls is safe.
  nonisolated(unsafe) private static let isoWithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}

// MARK: - Users / partners

struct WireUser: Decodable {
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

  var model: User {
    User(
      id: id, name: name, email: email, avatarColor: avatarColor, deletedAt: deletedAt,
      hasProfileImage: hasProfileImage, profileChangedAt: profileChangedAt, isAdmin: isAdmin,
      storageLabel: storageLabel, quotaSizeInBytes: quotaSizeInBytes, quotaUsageInBytes: quotaUsageInBytes
    )
  }
}

struct WireUserDelete: Decodable { var userId: String }

struct WirePartner: Decodable {
  var sharedById: String
  var sharedWithId: String
  var inTimeline: Bool

  var model: Partner { Partner(sharedById: sharedById, sharedWithId: sharedWithId, inTimeline: inTimeline) }
}

struct WirePartnerDelete: Decodable { var sharedById: String; var sharedWithId: String }

// MARK: - Assets / exif

/// `SyncAssetV2` — also used for `PartnerAssetV2`/`*BackfillV2`, `AlbumAsset{Create,Update,Backfill}V2`,
/// `SharedSpaceAsset{Create,Update,Backfill}V1`, `SharedLibraryAsset{Create,Update,Backfill}V1`.
struct WireAsset: Decodable {
  var id: String
  var ownerId: String
  var originalFileName: String
  var thumbhash: String?
  var checksum: String
  var fileCreatedAt: Date?
  var fileModifiedAt: Date?
  var createdAt: Date?
  var localDateTime: Date?
  var duration: Int?
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

  var model: Asset {
    Asset(
      id: id, ownerId: ownerId, originalFileName: originalFileName, thumbhash: thumbhash, checksum: checksum,
      fileCreatedAt: fileCreatedAt, fileModifiedAt: fileModifiedAt, createdAt: createdAt,
      localDateTime: localDateTime, durationSeconds: duration, type: AssetKind(rawValue: type) ?? .other,
      deletedAt: deletedAt, isFavorite: isFavorite, visibility: AssetVisibilityKind(rawValue: visibility) ?? .timeline,
      livePhotoVideoId: livePhotoVideoId, stackId: stackId, libraryId: libraryId, spaceId: spaceId, width: width,
      height: height, isEdited: isEdited
    )
  }
}

/// `AssetDeleteV1` — also used for `PartnerAssetDeleteV1`, `SharedSpaceAssetRemoveV1`,
/// `SharedLibraryAssetRemoveV1`.
struct WireAssetDelete: Decodable { var assetId: String }

/// `SyncAssetExifV1` — also used for `PartnerAssetExifV1`/`*BackfillV1`,
/// `AlbumAssetExif{Create,Update,Backfill}V1`, `SharedSpaceAssetExif{Create,Update,Backfill}V1`,
/// `SharedLibraryAssetExif{Create,Update,Backfill}V1`.
struct WireAssetExif: Decodable {
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

// MARK: - Albums

/// `AlbumV2` (no `ownerId` — owner comes from `AlbumUserV1` rows, `syncAlbumV2ToV1`).
struct WireAlbum: Decodable {
  var id: String
  var name: String
  var description: String
  var createdAt: Date
  var updatedAt: Date
  var thumbnailAssetId: String?
  var isActivityEnabled: Bool
  var order: String

  var model: Album {
    Album(
      id: id, name: name, description: description, createdAt: createdAt, updatedAt: updatedAt,
      thumbnailAssetId: thumbnailAssetId, isActivityEnabled: isActivityEnabled, order: order
    )
  }
}

struct WireAlbumDelete: Decodable { var albumId: String }

struct WireAlbumUser: Decodable {
  var albumId: String
  var userId: String
  var role: String

  var model: AlbumMember { AlbumMember(albumId: albumId, userId: userId, role: AlbumUserRoleKind(rawValue: role) ?? .viewer) }
}

struct WireAlbumUserDelete: Decodable { var albumId: String; var userId: String }
struct WireAlbumToAsset: Decodable { var albumId: String; var assetId: String }
struct WireAlbumToAssetDelete: Decodable { var albumId: String; var assetId: String }

// MARK: - Stacks

/// `StackV1` — also used for `PartnerStackV1`/`PartnerStackBackfillV1`.
struct WireStack: Decodable {
  var id: String
  var createdAt: Date
  var updatedAt: Date
  var primaryAssetId: String
  var ownerId: String

  var model: Stack { Stack(id: id, createdAt: createdAt, updatedAt: updatedAt, primaryAssetId: primaryAssetId, ownerId: ownerId) }
}

struct WireStackDelete: Decodable { var stackId: String }

// MARK: - Shared spaces / libraries (fork: shared-libraries)

struct WireSharedSpace: Decodable {
  var id: String
  var name: String
  var description: String
  var createdAt: Date
  var updatedAt: Date

  var model: Space { Space(id: id, name: name, description: description, createdAt: createdAt, updatedAt: updatedAt) }
}

struct WireSharedSpaceDelete: Decodable { var spaceId: String }

struct WireSharedSpaceMember: Decodable {
  var spaceId: String
  var userId: String
  var role: String
  var showInTimeline: Bool

  var model: SpaceMember {
    SpaceMember(spaceId: spaceId, userId: userId, role: SharedSpaceRoleKind(rawValue: role) ?? .contributor, showInTimeline: showInTimeline)
  }
}

struct WireSharedSpaceMemberDelete: Decodable { var spaceId: String; var userId: String }

struct WireSharedLibrary: Decodable {
  var id: String
  var name: String
  var ownerId: String
  var createdAt: Date
  var updatedAt: Date

  var model: Library { Library(id: id, name: name, ownerId: ownerId, createdAt: createdAt, updatedAt: updatedAt) }
}

struct WireSharedLibraryDelete: Decodable { var libraryId: String }

// MARK: - People / faces

struct WirePerson: Decodable {
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

  var model: Person {
    Person(
      id: id, createdAt: createdAt, updatedAt: updatedAt, ownerId: ownerId, name: name, birthDate: birthDate,
      isHidden: isHidden, isFavorite: isFavorite, color: color, faceAssetId: faceAssetId
    )
  }
}

struct WirePersonDelete: Decodable { var personId: String }

/// `AssetFaceV2` (`AssetFaceV1` fields + `deletedAt`/`isVisible`).
struct WireFace: Decodable {
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

  var model: Face {
    Face(
      id: id, assetId: assetId, personId: personId, imageWidth: imageWidth, imageHeight: imageHeight,
      boundingBoxX1: boundingBoxX1, boundingBoxY1: boundingBoxY1, boundingBoxX2: boundingBoxX2,
      boundingBoxY2: boundingBoxY2, sourceType: sourceType, deletedAt: deletedAt, isVisible: isVisible
    )
  }
}

struct WireFaceDelete: Decodable { var assetFaceId: String }

// MARK: - Memories

struct WireMemory: Decodable {
  var id: String
  var createdAt: Date
  var updatedAt: Date
  var deletedAt: Date?
  var ownerId: String
  var type: String
  var data: JSONValue
  var isSaved: Bool
  var memoryAt: Date
  var seenAt: Date?
  var showAt: Date?
  var hideAt: Date?

  var model: Memory {
    Memory(
      id: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, ownerId: ownerId, type: type,
      dataJSON: data.rawJSONString, isSaved: isSaved, memoryAt: memoryAt, seenAt: seenAt, showAt: showAt, hideAt: hideAt
    )
  }
}

struct WireMemoryDelete: Decodable { var memoryId: String }
struct WireMemoryAsset: Decodable { var memoryId: String; var assetId: String }
struct WireMemoryAssetDelete: Decodable { var memoryId: String; var assetId: String }

// MARK: - User metadata (prefs)

struct WireUserMetadata: Decodable {
  var userId: String
  var key: String
  var value: JSONValue
}

struct WireUserMetadataDelete: Decodable { var userId: String; var key: String }

/// A minimal untyped-JSON box — `Memory.data`/`UserMetadata.value` are `Record<string, unknown>` on the
/// server, re-serialized to disk as opaque JSON text rather than modeled column-by-column.
enum JSONValue: Decodable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
    else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
    else if let value = try? container.decode(String.self) { self = .string(value) }
    else if let value = try? container.decode(Double.self) { self = .number(value) }
    else if let value = try? container.decode(Bool.self) { self = .bool(value) }
    else { self = .null }
  }

  var rawJSONString: String {
    let data = (try? JSONEncoder().encode(self)) ?? Data("{}".utf8)
    return String(decoding: data, as: UTF8.self)
  }
}

extension JSONValue: Encodable {
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}
