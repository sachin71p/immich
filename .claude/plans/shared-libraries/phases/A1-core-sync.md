# A1 — Core: session, sync engine, local store, timeline queries

Depends on: A0, S6 (regenerate ImmichAPI first) · Reads: A0 Architecture+Rules · DECISIONS §4, §9, §10 · CODEMAP §F · handoff S6.

## Tasks
1. LocalStore (GRDB) schema v1: users, partners, assets (all SyncAssetV2 fields + spaceId + source flags),
   exif (SyncAssetExifV1 fields), albums, album_users, album_assets, stacks, spaces, space_members, libraries
   (shared), library_members, people, faces, memories, memory_assets, user_metadata/prefs, sync_acks, media_cache
   index. Migrations via GRDB `DatabaseMigrator`. Indices for (localDateTime), (spaceId), (libraryId), (ownerId).
2. SyncEngine: POST `/sync/stream` with request types: AuthUsersV1, UsersV1, PartnersV1, AssetsV2 (or V3 per S6
   handoff), AssetExifsV1, PartnerAssetsV2, PartnerAssetExifsV1, AlbumsV2, AlbumUsersV1, AlbumAssetsV2,
   AlbumAssetExifsV1, AlbumToAssetsV1, StacksV1, PartnerStacksV1, PeopleV1, AssetFacesV2, MemoriesV1,
   MemoryToAssetsV1, UserMetadataV1, SharedSpacesV1, SharedSpaceMembersV1, SharedSpaceAssetsV1,
   SharedSpaceAssetExifsV1, SharedLibrariesV1, SharedLibraryAssetsV1, SharedLibraryAssetExifsV1.
   Streaming JSON-lines parser (bounded memory), apply each entity in a DB transaction batch, POST acks every N
   lines/seconds, handle `SyncResetV1` (wipe + full resync), `SyncCompleteV1`, backfill `complete` extraIds,
   container removals (drop all assets of a space/library on its Delete entity). Triggers: app foreground, pull to
   refresh, timer while active, websocket events if trivially available (optional).
3. Rules module: `TimelineScope` resolution from local prefs + memberships (§10 purpose timeline/manage/locked +
   explicit filter), `Permissions.canEdit/canFavorite/canDelete/canMove(asset, context)` (§4), `MoveTargets.allowed(selection)` (§6).
4. Timeline queries on LocalStore: month/day buckets with counts for a scope, assets page for a bucket, favorites,
   recents (createdAt), media types (video, live, panorama/360, screenshots via exif heuristics), trash (manage scope),
   per-space/library/album timelines. All queries return lightweight rows (id, thumbhash, ratio, type, flags).
5. Mutations through API then local optimistic update: favorite, archive, trash/restore/delete, move (`/assets/move`
   with per-asset result handling), add/remove album, space CRUD + members, prefs.

## Tests (swift test)
Fixture streams: initial sync, incremental update, move out of space (RemoveV1), membership loss, reset; rules
tables mirroring DECISIONS §4/§6/§10 cases from S2/S4/S5 test lists; bucket queries on a 50k-asset generated DB
must return in <50 ms (performance test).

Verify: `native-apple/scripts/verify.sh core`.
