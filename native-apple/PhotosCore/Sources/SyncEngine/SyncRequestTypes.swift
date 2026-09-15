/// Mirrors `SyncRequestType` (`server/src/enum.ts`) as plain strings rather than
/// `ImmichAPI.Components.Schemas.SyncRequestType`. The checked-out `open-api/immich-openapi-specs.json`
/// predates S6 (its own handoff: "OpenAPI/SDK/SQL regeneration was not run" — `mise` was unavailable), so
/// the generated enum is missing every fork addition (`SharedSpacesV1`, `SharedLibrariesV1`, …) — see the
/// A1 handoff. `POST /sync/stream`'s request body is built from this list directly instead.
public enum SyncRequestTypes {
  /// Every type the A1 brief's SyncEngine task lists, in the same order they're listed there.
  public static let all: [String] = [
    "AuthUsersV1",
    "UsersV1",
    "PartnersV1",
    "AssetsV2",
    "AssetExifsV1",
    "PartnerAssetsV2",
    "PartnerAssetExifsV1",
    "AlbumsV2",
    "AlbumUsersV1",
    "AlbumAssetsV2",
    "AlbumAssetExifsV1",
    "AlbumToAssetsV1",
    "StacksV1",
    "PartnerStacksV1",
    "PeopleV1",
    "AssetFacesV2",
    "MemoriesV1",
    "MemoryToAssetsV1",
    "UserMetadataV1",
    "SharedSpacesV1",
    "SharedSpaceMembersV1",
    "SharedSpaceAssetsV1",
    "SharedSpaceAssetExifsV1",
    "SharedLibrariesV1",
    "SharedLibraryAssetsV1",
    "SharedLibraryAssetExifsV1",
  ]
}
