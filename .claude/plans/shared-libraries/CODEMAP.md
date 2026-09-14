# Code Map (verified by scouts at upstream commit e55ac299a)

Compressed facts so implementers do not re-survey. Paths are relative to repo root. Line numbers drift after
edits — locate by function name. If a fact here is wrong, note it in your handoff (`CODEMAP-FIX:`), then proceed
with the real code.

## §A Authorization
- `Permission` enum: `server/src/enum.ts` (~L109–329). `AlbumUserRole` (Editor/Owner/Viewer): `server/src/enum.ts` ~L67.
- Branch table: `server/src/utils/access.ts` `checkAccess` (~L44–366).
  - AssetRead/View/Download: owner | album | partner (~L117). AssetShare: owner | partner (~L124).
  - AssetUpdate/Delete/Copy/EditCreate/EditDelete/FileRead: owner only (~L148–173).
  - AlbumRead: owner | shared (viewer+) (~L176). AlbumAssetCreate / AlbumAssetDelete: owner | editor (~L186, ~L230).
  - AlbumUpdate/AlbumShare: owner | editor (~L196–218). TimelineRead: owner | partner (~L274).
- `server/src/repositories/access.repository.ts`: `asset.checkOwnerAccess` (~L187, `ownerId = userId AND
  (visibility != Locked OR elevated)`), `asset.checkPartnerAccess` (~L204), `asset.checkAlbumAccess` (~L146),
  `album.checkOwnerAccess` (~L76), `album.checkSharedAlbumAccess` (~L98, role list), `timeline.checkPartnerAccess` (~L409).
- Album asset removal extra rule: `server/src/utils/asset.util.ts` ~L81–85. Album user role update: `album.service.ts` ~L343.
- Endpoint permission decorator: `@Authenticated({ permission: Permission.X })`. Service base: `BaseService`, `requireAccess()`.

## §B Favorites
- `isFavorite` column: `server/src/schema/tables/asset.table.ts` ~L84 (global). Updated via `UpdateAssetDto` /
  `AssetBulkUpdateDto` in `asset.service.ts` (~L138/151/178), gated by `Permission.AssetUpdate` (`asset.controller.ts` ~L68, ~L152).
- Sync forces `isFavorite` false for non-owners: `asset.repository.ts` ~L826 and sync queries (see §F).

## §C Storage
- `server/src/cores/storage.core.ts`: `getLibraryFolder({storageLabel,id})` ~L112, `getPersonThumbnailPath` ~L120,
  `getImagePath(asset,{fileType,format,isEdited})` ~L124 (uses ownerId), `getEncodedVideoPath` ~L132,
  `getHlsSessionFolder` ~L136, `getAndroidMotionPath` ~L144, `moveFile` ~L198–274 (move_history, rename → EXDEV
  copy+verify, recovery), verification ~L276–310, `getNestedFolder(folder, ownerId, filename)` ~L356 →
  `folder/<ownerId>/xx/yy`, `getNestedPath` ~L360.
- Enums (`server/src/enum.ts`): `StorageFolder` ~L343, `AssetFileType` ~L54 (FullSize, Preview, Thumbnail, Sidecar,
  EncodedVideo), `AssetPathType` ~L454, `PersonPathType` ~L459, `UserPathType` ~L463, `PathType` union ~L467.
- `move_history`: `server/src/schema/tables/move.table.ts` (entityId, pathType, oldPath, newPath; unique
  (entityId,pathType) and (newPath)).
- `asset_file`: `server/src/schema/tables/asset-file.table.ts` (assetId, type, path, isEdited, …; unique (assetId,type,isEdited)).
- Storage template: `server/src/services/storage-template.service.ts` — jobs `StorageTemplateMigrationSingle`
  (on `AssetMetadataExtracted`) and `StorageTemplateMigration` (~L136–180); skipped when template disabled
  (~L144, ~L178); root `library/<storageLabel||userId>` ~L276; sidecar move ~L247–254; live motion ~L160–169;
  render ~L391–430.
- Upload staging: `AssetMediaService.getUploadFolder()` `server/src/services/asset-media.service.ts` ~L104
  (`upload/<ownerId>/xx/yy/`), filename ~L91; `server/src/middleware/file-upload.interceptor.ts` ~L112.
- Folder markers: `server/src/utils/maintenance.ts` ~L31–63.
- User storageLabel: sanitized in `server/src/dtos/user.dto.ts` ~L85/102, unique column `user.table.ts` ~L66; no reserved values.
- Live photo: `livePhotoVideoId` on asset; motion part is a hidden asset. Stack: `stack.table.ts` (primaryAssetId, ownerId).

## §D Visibility scoping sites (all use `ownerId = anyUuid(userIds)` or `ownerId = x`)
| Area | Location | userIds source |
|---|---|---|
| Timeline buckets / bucket | `asset.repository.ts` getTimeBuckets ~L753, getTimeBucket ~L815 | `timeline.service.ts` buildTimeBucketOptions + `getMyPartnerIds` |
| Search legacy (metadata/statistics/random/smart/large) | `search.repository.ts` ~L228–317 via `searchAssetBuilderLegacy` `server/src/database.ts` ~L426/L489 | `search.service.ts` `getUserIdsToSearch` ~L356 |
| Search V3 | `search.repository.ts` ~L541–587 via `searchAssetBuilder` `database.ts` ~L795/L798 (`AssetSearchScope`) | `resolveSearchScopeV3` |
| Suggestions (countries/states/cities/make/model/lens) | `search.repository.ts` ~L485–537 via `getExifField` `database.ts` ~L599 | `getUserIdsToSearch` |
| Assets by city | `search.repository.ts` ~L427 (~L434, ~L450) | `getUserIdsToSearch` |
| Map markers | `map.repository.ts` getMapMarkers ~L82 (~L107) | `map.service.ts` + partners |
| Memories | `memory.repository.ts` ~L32–68 (~L49, single owner) | memory service |
| Statistics / calendar heatmap | `asset.repository.ts` getStatistics ~L710, getCalendarHeatmap ~L729 | single owner |
| Explore (city ids, recently created) | `asset.repository.ts` ~L974, ~L1001 | single owner |
| Day of year (memories source) | `asset.repository.ts` getByDayOfYear ~L461 (~L485) | ownerIds |
| Trash | `trash.repository.ts` restore/empty/restoreAll ~L15–47 | single owner (restoreAll by ids: no owner filter) |
| People | `person.repository.ts` (~L100–442) | per-owner — NOT changed (§11) |
| Albums list | `album.repository.ts` buildAlbumBaseQuery ~L190 | unchanged |
| Tags | `tag.repository.ts` | per-user, unchanged |
- Partner id helper: `getMyPartnerIds` `server/src/utils/asset.util.ts` ~L119 (callers: timeline.service ~L35,
  search.service ~L361, map.service ~L12).
- Timeline DTO: `server/src/dtos/time-bucket.dto.ts` (userId, albumId, personId, tagId, isFavorite, isTrashed,
  withStacked, withPartners, order, orderBy, visibility, withCoordinates, bbox). `AssetVisibility` enum `enum.ts` ~L1171.

## §E External libraries & user deletion
- `library.table.ts` (ownerId CASCADE, importPaths, exclusionPatterns, deletedAt, refreshedAt). Asset: `libraryId`
  (CASCADE), `isExternal`, `isOffline` (`asset.table.ts` ~L113–148).
- Jobs (`enum.ts` ~L874–881): LibraryScanQueueAll, LibrarySyncFilesQueueAll, LibrarySyncFiles, LibrarySyncAssetsQueueAll,
  LibrarySyncAssets, LibraryRemoveAsset. `library.service.ts`: watcher ~L89–150, import-path validation ~L295–334
  (read-only check), library delete job ~L372–397, `LibraryRemoveAsset` ~L683–695 (**hard-deletes asset row by path on
  file unlink**).
- `asset.repository.ts`: `detectOfflineExternalAssets` ~L1085–1109 (outside importPaths or excluded → offline + trashed),
  `filterNewExternalAssetPaths` ~L1112–1131 (match by originalPath+libraryId).
- Library endpoints admin-only: `library.controller.ts` ~L22–125.
- User delete: `user.service.ts` ~L254–296 (UserDeleteCheck → UserDelete: deletes user folders, albums, then user row;
  assets/persons/partners cascade via FKs). No code anywhere changes `asset.ownerId`.

## §F Sync
- `server/src/controllers/sync.controller.ts` (POST /sync/stream jsonlines, GET/POST/DELETE /sync/ack).
- `SyncRequestType` `enum.ts` ~L1010–1042; `SyncEntityType` ~L1049–1130; order `SYNC_TYPES_ORDER` `sync.service.ts` ~L64–92.
- Ack = `type|updateId|extraId` (`server/src/utils/sync.ts`); checkpoints in `session_sync_checkpoint`.
- updateId = `immich_uuid_v7()` (`server/src/schema/functions.ts` ~L3–23). Delete audits via triggers
  (`functions.ts` ~L84–329) into `*_audit` tables (`server/src/schema/tables/*-audit.table.ts`); cleanup job prunes >30 days.
- Backfill pattern: `sync.service.ts` ~L334–391 (partner) and ~L566–636 (album), uses member `createId` + extraId `complete`.
- Album asset sync queries: `sync.repository.ts` (see `server/src/queries/sync.repository.sql` ~L134–169; isFavorite
  owner-conditional ~L81, ~L117, ~L157). Partner assets ~L838–875.
- DTOs `server/src/dtos/sync.dto.ts`: SyncAssetV1 ~L60, SyncAssetV2 ~L85, SyncAssetExifV1 ~L129, SyncStreamDto ~L520.
- Medium tests for sync live under `server/test/medium/` (find `sync` specs; copy the album-asset spec pattern).

## §G Tooling (run from repo root unless noted)
- Schema: `server/src/schema/tables/*.table.ts` (decorators), registered in `server/src/schema/index.ts` ~L102–167.
  Enums/functions/triggers in `server/src/schema/enums.ts` / `functions.ts` (copy album patterns).
- Migrations `server/src/schema/migrations/<timestamp>-<Name>.ts`: `cd server && pnpm run migrations:generate`
  (diff-based; review output), `pnpm run migrations:run`.
- OpenAPI + SDKs: `mise //server:sync-open-api` → `mise :open-api-typescript` (packages/sdk) → `mise :open-api-dart`
  (mobile/openapi). SQL docs: `mise //server:sql`.
- Server: `cd server && pnpm run check && pnpm run lint && pnpm run test` (single file: `pnpm exec vitest <path>`);
  medium (needs Docker): `pnpm run test:medium`.
- Web: `cd web && pnpm run check:typescript && pnpm run check:svelte && pnpm run lint && pnpm run test --run`.
- E2E (Docker): `mise //e2e:test-web`; dev stack `mise //:dev`.
- Jobs: `QueueName`/`JobName` in `enum.ts`; handlers `@OnJob({ name, queue })`; queue via `this.jobRepository.queue(...)`.
  Events: `@OnEvent({ name, server: true })`. Controllers/services/repositories registered in their `index.ts`.
  Template for a small service: `server/src/services/activity.service.ts`.
- i18n (web): `i18n/en.json`, `$t('key')`.

## §H Web
- Routes `web/src/routes/(user)/{photos,albums,favorites,archive,trash,search,people,map,sharing}`; admin
  `web/src/routes/admin/library-management`; settings `web/src/routes/(user)/user-settings/{+page.svelte,UserSettingsList.svelte}`.
- Timeline manager: `web/src/lib/managers/timeline-manager/timeline-manager.svelte.ts` (~L255 getTimeBuckets),
  options type `.../types.ts` ~L8.
- Multi-select bar `web/src/lib/components/timeline/AssetSelectControlBar.svelte`; actions in
  `web/src/lib/components/timeline/actions/*Action.svelte` (template: `FavoriteAction.svelte`); viewer actions
  `web/src/lib/components/asset-viewer/actions/`.
- Detail panel `web/src/lib/components/asset-viewer/DetailPanel.svelte`.
- Search filters `web/src/lib/components/shared-components/search-bar/{SearchFilters.svelte,Search*Section.svelte,search-bar-utils.ts}`.
- Album modals `web/src/lib/modals/{AlbumAddUsersModal,AlbumEditModal,AssetAddToAlbumModal}.svelte`.
- Sidebar `web/src/lib/components/sidebar/Sidebar.svelte`. Upload `web/src/lib/utils/file-uploader.ts` (~L26, ~L203).
- Component test example `web/src/lib/components/SharedLinkFormFields.spec.ts`.
