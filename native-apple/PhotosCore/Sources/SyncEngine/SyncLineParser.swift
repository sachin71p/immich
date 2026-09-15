import Foundation
import LocalStore

/// Decodes one JSON-lines line of `POST /sync/stream` (CODEMAP §F: `{type, data, ack}`,
/// `server/src/utils/sync.ts` `serialize`/`toAck`) into either data changes to apply or a control signal.
enum SyncLineParser {
  enum Outcome {
    case changes([SyncChange])
    /// `SyncResetV1` — brief task 2: wipe the local mirror and let the (already reconnecting) stream
    /// refill it from scratch.
    case reset
    /// `SyncCompleteV1` — every requested type has caught up to "now" for this session.
    case complete
  }

  private struct TypeEnvelope: Decodable { var type: String; var ack: String }
  private struct Envelope<T: Decodable>: Decodable { var type: String; var data: T; var ack: String }

  /// The client-side mirror of `server/src/utils/sync.ts` `fromAck`: the ack string's own leading
  /// `SyncEntityType` token is what gets checkpointed, which for `SyncAckV1` backfill-complete lines
  /// differs from the outer envelope `type`.
  private static func ackEntityType(of ack: String) -> String {
    String(ack.split(separator: "|", maxSplits: 1)[0])
  }

  static func parse(_ line: Data) throws -> Outcome {
    let header = try WireDecoding.decoder.decode(TypeEnvelope.self, from: line)
    let ackChange = SyncChange.ack(type: ackEntityType(of: header.ack), value: header.ack)

    switch header.type {
    case "SyncResetV1":
      return .reset
    case "SyncCompleteV1":
      return .complete
    case "SyncAckV1":
      // Backfill-complete marker for `ackEntityType(of:)`'s type; no data payload of its own.
      return .changes([ackChange])

    case "AuthUserV1":
      return .changes([.user(try decode(Envelope<WireUser>.self, line).data.model), ackChange])
    case "UserV1":
      return .changes([.user(try decode(Envelope<WireUser>.self, line).data.model), ackChange])
    case "UserDeleteV1":
      return .changes([.userDelete(id: try decode(Envelope<WireUserDelete>.self, line).data.userId), ackChange])

    case "PartnerV1":
      return .changes([.partner(try decode(Envelope<WirePartner>.self, line).data.model), ackChange])
    case "PartnerDeleteV1":
      let data = try decode(Envelope<WirePartnerDelete>.self, line).data
      return .changes([.partnerDelete(sharedById: data.sharedById, sharedWithId: data.sharedWithId), ackChange])

    case "AssetV2", "PartnerAssetV2", "PartnerAssetBackfillV2",
      "AlbumAssetCreateV2", "AlbumAssetUpdateV2", "AlbumAssetBackfillV2",
      "SharedSpaceAssetCreateV1", "SharedSpaceAssetUpdateV1", "SharedSpaceAssetBackfillV1",
      "SharedLibraryAssetCreateV1", "SharedLibraryAssetUpdateV1", "SharedLibraryAssetBackfillV1":
      return .changes([.asset(try decode(Envelope<WireAsset>.self, line).data.model), ackChange])
    case "AssetDeleteV1", "PartnerAssetDeleteV1", "SharedSpaceAssetRemoveV1", "SharedLibraryAssetRemoveV1":
      return .changes([.assetDelete(id: try decode(Envelope<WireAssetDelete>.self, line).data.assetId), ackChange])
    case "AssetExifV1", "PartnerAssetExifV1", "PartnerAssetExifBackfillV1",
      "AlbumAssetExifCreateV1", "AlbumAssetExifUpdateV1", "AlbumAssetExifBackfillV1",
      "SharedSpaceAssetExifCreateV1", "SharedSpaceAssetExifUpdateV1", "SharedSpaceAssetExifBackfillV1",
      "SharedLibraryAssetExifCreateV1", "SharedLibraryAssetExifUpdateV1", "SharedLibraryAssetExifBackfillV1":
      return .changes([.assetExif(try decode(Envelope<WireAssetExif>.self, line).data.domainModel), ackChange])

    case "AlbumV1", "AlbumV2":
      return .changes([.album(try decode(Envelope<WireAlbum>.self, line).data.model), ackChange])
    case "AlbumDeleteV1":
      return .changes([.albumDelete(id: try decode(Envelope<WireAlbumDelete>.self, line).data.albumId), ackChange])
    case "AlbumUserV1", "AlbumUserBackfillV1":
      return .changes([.albumUser(try decode(Envelope<WireAlbumUser>.self, line).data.model), ackChange])
    case "AlbumUserDeleteV1":
      let data = try decode(Envelope<WireAlbumUserDelete>.self, line).data
      return .changes([.albumUserDelete(albumId: data.albumId, userId: data.userId), ackChange])
    case "AlbumToAssetV1", "AlbumToAssetBackfillV1":
      let data = try decode(Envelope<WireAlbumToAsset>.self, line).data
      return .changes([.albumAsset(albumId: data.albumId, assetId: data.assetId), ackChange])
    case "AlbumToAssetDeleteV1":
      let data = try decode(Envelope<WireAlbumToAssetDelete>.self, line).data
      return .changes([.albumAssetDelete(albumId: data.albumId, assetId: data.assetId), ackChange])

    case "StackV1", "PartnerStackV1", "PartnerStackBackfillV1":
      return .changes([.stack(try decode(Envelope<WireStack>.self, line).data.model), ackChange])
    case "StackDeleteV1", "PartnerStackDeleteV1":
      return .changes([.stackDelete(id: try decode(Envelope<WireStackDelete>.self, line).data.stackId), ackChange])

    case "SharedSpaceV1":
      return .changes([.space(try decode(Envelope<WireSharedSpace>.self, line).data.model), ackChange])
    case "SharedSpaceDeleteV1":
      return .changes([.spaceDelete(id: try decode(Envelope<WireSharedSpaceDelete>.self, line).data.spaceId), ackChange])
    case "SharedSpaceMemberV1", "SharedSpaceMemberBackfillV1":
      return .changes([.spaceMember(try decode(Envelope<WireSharedSpaceMember>.self, line).data.model), ackChange])
    case "SharedSpaceMemberDeleteV1":
      let data = try decode(Envelope<WireSharedSpaceMemberDelete>.self, line).data
      return .changes([.spaceMemberDelete(spaceId: data.spaceId, userId: data.userId), ackChange])

    case "SharedLibraryV1":
      return .changes([.library(try decode(Envelope<WireSharedLibrary>.self, line).data.model), ackChange])
    case "SharedLibraryDeleteV1":
      return .changes([.libraryDelete(id: try decode(Envelope<WireSharedLibraryDelete>.self, line).data.libraryId), ackChange])

    case "PersonV1":
      return .changes([.person(try decode(Envelope<WirePerson>.self, line).data.model), ackChange])
    case "PersonDeleteV1":
      return .changes([.personDelete(id: try decode(Envelope<WirePersonDelete>.self, line).data.personId), ackChange])
    case "AssetFaceV1", "AssetFaceV2":
      return .changes([.face(try decode(Envelope<WireFace>.self, line).data.model), ackChange])
    case "AssetFaceDeleteV1":
      return .changes([.faceDelete(id: try decode(Envelope<WireFaceDelete>.self, line).data.assetFaceId), ackChange])

    case "MemoryV1":
      return .changes([.memory(try decode(Envelope<WireMemory>.self, line).data.model), ackChange])
    case "MemoryDeleteV1":
      return .changes([.memoryDelete(id: try decode(Envelope<WireMemoryDelete>.self, line).data.memoryId), ackChange])
    case "MemoryToAssetV1":
      let data = try decode(Envelope<WireMemoryAsset>.self, line).data
      return .changes([.memoryAsset(memoryId: data.memoryId, assetId: data.assetId), ackChange])
    case "MemoryToAssetDeleteV1":
      let data = try decode(Envelope<WireMemoryAssetDelete>.self, line).data
      return .changes([.memoryAssetDelete(memoryId: data.memoryId, assetId: data.assetId), ackChange])

    case "UserMetadataV1":
      let data = try decode(Envelope<WireUserMetadata>.self, line).data
      return .changes([.userMetadata(userId: data.userId, key: data.key, valueJSON: data.value.rawJSONString), ackChange])
    case "UserMetadataDeleteV1":
      let data = try decode(Envelope<WireUserMetadataDelete>.self, line).data
      return .changes([.userMetadataDelete(userId: data.userId, key: data.key), ackChange])

    default:
      // Forward-compatible: an entity type this build doesn't know about yet (e.g. AssetEditV1,
      // AssetMetadataV1, AssetOcrV1 — out of A1 scope). Still ack it so the stream advances past it.
      return .changes([ackChange])
    }
  }

  private static func decode<T: Decodable>(_ type: T.Type, _ line: Data) throws -> T {
    try WireDecoding.decoder.decode(type, from: line)
  }
}
