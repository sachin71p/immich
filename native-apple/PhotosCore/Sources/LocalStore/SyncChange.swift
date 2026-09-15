import CoreModel

/// One parsed sync-stream line, entity-shaped rather than wire-shaped — `SyncEngine` decodes the
/// `{type, data, ack}` JSON-lines envelope (CODEMAP §F) into these; `PhotosLocalStore.apply(_:)` is the
/// only place that knows how each change maps onto tables. Every `SyncRequestType` the A1 brief lists
/// funnels into one of these cases; several wire `SyncEntityType`s that share a DTO shape (e.g. every
/// asset/exif stream, personal or partner or space/library-scoped) collapse onto the same case because
/// they upsert into the same `asset`/`assetExif` tables — the row's own `ownerId`/`spaceId`/`libraryId`
/// already say which container it's in (DECISIONS §10), so no per-stream branching is needed.
public enum SyncChange: Sendable {
  case user(User)
  case userDelete(id: String)
  case partner(Partner)
  case partnerDelete(sharedById: String, sharedWithId: String)

  case asset(Asset)
  /// `AssetDeleteV1` (hard delete), `PartnerAssetDeleteV1`, `SharedSpaceAssetRemoveV1`,
  /// `SharedLibraryAssetRemoveV1` (asset left this device's visibility) — all remove the local row.
  case assetDelete(id: String)
  case assetExif(AssetExif)

  case album(Album)
  case albumDelete(id: String)
  case albumUser(AlbumMember)
  case albumUserDelete(albumId: String, userId: String)
  case albumAsset(albumId: String, assetId: String)
  case albumAssetDelete(albumId: String, assetId: String)

  case stack(Stack)
  case stackDelete(id: String)

  case space(Space)
  /// The space container itself was deleted / this device lost all access — cascades to a drop of every
  /// asset row with a matching `spaceId` (brief task 2: "container removals").
  case spaceDelete(id: String)
  case spaceMember(SpaceMember)
  /// A specific member's access ended. If it's the signed-in user, this device also loses visibility of
  /// the space's remaining assets (DECISIONS §8: contributions stay in the space, just not visible to the
  /// removed member) and the row cascades like `spaceDelete`; otherwise only the membership row is dropped.
  case spaceMemberDelete(spaceId: String, userId: String)

  case library(Library)
  case libraryDelete(id: String)

  case person(Person)
  case personDelete(id: String)
  case face(Face)
  case faceDelete(id: String)

  case memory(Memory)
  case memoryDelete(id: String)
  case memoryAsset(memoryId: String, assetId: String)
  case memoryAssetDelete(memoryId: String, assetId: String)

  case userMetadata(userId: String, key: String, valueJSON: String)
  case userMetadataDelete(userId: String, key: String)

  /// Advances the per-`SyncEntityType` resume checkpoint; applied in the same transaction as the data it
  /// protects so an ack is never persisted before its data is durable.
  case ack(type: String, value: String)
}
