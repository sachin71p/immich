# WP2 — V2 Route/Data/API Feasibility Matrix

Owner: Agent B (route/data/API feasibility). Status: read-only analysis complete.
Reference revision: `464f9122be29b807b854e109cf6eecfce4544c52` (PLAN header). Date: 2026-09-16.

Worktree status at start (`git status --short`):

```text
M .claude/plans/deploy-heirloom-docker.md
M native-apple/Apps/macOS/Sources/MacAppState.swift
M native-apple/PhotosCore/Sources/ImmichAPI/ImmichConnection.swift
?? .claude/plans/heirloom-web-v2/
```

The three modified files are pre-existing user changes and were not touched.
Only this file (`WP2-ROUTE-DATA-MATRIX.md`, the task-named deliverable for the
PLAN §WP2 `ROUTE-DATA-MATRIX.md`) was written.

## Verdict

**No server change required.** Every V2 target route maps to existing SDK
calls, stores/managers, and components. The items that look like gaps are
client-composition or product-semantics decisions (listed in §Gaps/risks),
not missing APIs. Viewer **Rotate** has no server field, but the correct
treatment is a documented browser exception (PLAN §4.3 pattern), not new
server work.

Reuse rule applied per PLAN §13: V2 composes existing services/managers;
presentation state (source/group/zoom/selection) lives in new V2-owned files.

## 0. URL / preference contract (PLAN §9)

| Param | Existing implementation | V2 work |
| --- | --- | --- |
| `source=all\|personal\|space:<uuid>\|library:<uuid>` | `parseLibrarySource` in `web/src/lib/utils/library-source.ts:16-27` returns `{ personalOnly }` / `{ spaceId }` / `{ libraryId }` / `{}` (all). Builders `spaceLibrarySource`/`librarySource` at lines 11-12. Persisted under `timeline-library-source` in `web/src/lib/managers/user-preferences-manager.svelte.ts:14,48-53`. Search-bar scope uses the same shape (`search-bar-utils.ts:275-291`). | Reuse parser verbatim; store under a **V2-only** preference key (must not overwrite classic key, PLAN §9 rule 6). |
| `group=years\|months\|all` | No existing utility. Timeline buckets arrive per-month from the server; grouping presentation is client-side. | New V2 parsing/normalization (unit-tested). No server involvement. |
| `zoom=64..300` | No existing utility (classic timeline is justified-flow, not fixed-tile). | New V2 parsing/normalization (unit-tested). Pure presentation (tile size). No server involvement. |
| Asset deep link `[[assetId=id]]` | Classic convention (`photos/[[assetId=id]]`, `albums/[albumId]/[[photos]]/[[assetId]]`, `Route.viewAsset`, `Route.viewAlbumAsset` in `web/src/lib/route.ts:53-54,96-102`). Viewer state via `asset-viewer-manager.svelte.ts:253 setAssetId`. | Reuse convention under `/v2/...`; V2 route builder per WP4. |

Precedence (URL > V2 prefs > native defaults) and no-reload-loop
normalization are new V2 logic; no existing helper was found, none needed
from server.

## 1. Route matrix

Conventions: `SDK` = `@immich/sdk` call; `Owner` = existing store/manager/
service/component that already owns the logic and must be reused, not forked.

### Library / timeline family

| V2 route | SDK call(s) | Store / manager / component | Filters | Mutations | Permission check | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `/v2/library/[[assetId=id]]` | `getTimeBuckets` (`GET /timeline/buckets`) via `TimelineManager` (`timeline-manager.svelte.ts`; options type `types.ts:8-12` accepts all bucket query params) | `TimelineManager` + `Timeline.svelte` + `asset-multi-select-manager` + `asset-viewer-manager`; source pref `user-preferences-manager.timelineLibrarySource` | `{ visibility: Timeline, withStacked: true, withPartners: true, ...parseLibrarySource(source) }` — exact pattern already shipped in `routes/(user)/photos/[[assetId=id]]/+page.svelte:55-61` | Favorite/archive/trash/delete/move/add-to-album via `getAssetActions` (`services/asset.service.ts:106-137`) + `utils/actions.ts` (`deleteAssets`, `restoreAssets`) | `canEditAsset` / `canFavoriteAsset` (`utils/asset-permissions.ts:20-41`) fed by `sharedSpaces` membership sets (`asset.service.ts:118-137`); bulk grid falls back to ownerId-only (known limitation, documented in file header) | Reuse; none |
| `/v2/collections` | `getAllAlbums({ isOwned: true })` + `getAllAlbums({ isShared: true })` — pattern in `routes/(user)/albums/+page.ts:8-9`; grouping pref `AlbumGroupBy.Year` (`stores/preferences.store.ts:109`) | Classic albums index page/components | Owned vs shared split; album evita | Album CRUD (§2) | Album ownership `albumUsers[0]` (`services/album.service.ts:46`) | Reuse; none. No classic `/collections` exists — V2 composes the albums index. |
| `/v2/media/photos`, `/v2/media/videos` | `GET /timeline/buckets` has **no** `type` param (spec param list verified: albumId, bbox, isFavorite, isTrashed, libraryId, order/orderBy, personId, personalOnly, spaceId, tagId, userId, visibility, withCoordinates/Partners/Stacked — no `type`). `MetadataSearchDto`/`SmartSearchDto` **do** carry `type` (spec property lists verified). | `searchAssets`/`searchSmart` (`routes/(user)/search/.../+page.svelte:146-149` pattern) or buckets + client filter | `type: AssetTypeEnum.IMAGE / VIDEO` via search DTOs | Same as library | Same as library | Reuse; **design decision for WP9**: search-backed listing (server-filtered) is recommended over buckets+client filter for large libraries. No server change (field exists). |
| `/v2/media/screenshots` | No existing screenshot filter found anywhere in web (scoped filename/extension search: no hits). `MetadataSearchDto` carries `originalFileName`, `fileExtensions`, `mimeTypes` (spec list verified). | `searchAssets` with filename/extension predicate composed client-side | e.g. `originalFileName` substring or `fileExtensions` set (exact predicate needs WP1 fixture validation) | Same as library | Same as library | Reuse; predicate choice is a WP9 fixture-validation item, not a server gap. |
| `/v2/spaces/[spaceId]` | Buckets with `{ spaceId }` — exact pattern shipped: `routes/(user)/shared-libraries/[spaceId=id]/[[photos=photos]]/+page.svelte:25` (`{ spaceId: space.id, withStacked: true }`); upload entry passes `spaceId` (`:65` → `openFileUploadDialog({ spaceId })`) | `TimelineManager`; space metadata via `sharedSpaces` store (`stores/shared-spaces.svelte.ts`, backed by `sdk.getAll()` + `sdk.getSharedLibraries()`) | `spaceId` bucket param | Move/add/upload scoped to space; member admin §2 | Space membership via `sharedSpaces.spaces`; move targets `computeMoveTargets` (`utils/move-targets.ts:13-38`) | Reuse; none |
| `/v2/libraries/[libraryId]` | Buckets with `{ libraryId }` (spec param exists; mirrors `spaceId` pattern) | `TimelineManager`; library metadata via `sharedSpaces.libraries` | `libraryId` bucket param; upload-path gating `library.hasUploadPath` (`move-targets.ts:31-33`) | Move targets exclude libraries without upload path (existing rule) | Library membership via `sharedSpaces.libraries` | Reuse; none. Upload-destination question → §Gaps G2 (verification item, not a claimed gap). |
| `/v2/albums/[albumId]` | `getAlbumInfo` + buckets with `{ timelineAlbumId }` — shipped in `routes/(user)/albums/[albumId=id]/.../+page.svelte:52,91,137,224-229`; cover update `handleUpdateThumbnail`; add/upload actions `getAlbumAssetsActions` (`services/album.service.ts:82-104`) | `TimelineManager` + album page components | `timelineAlbumId` | Add/remove/reorder/cover (§2) | `getAlbumActions` ownership gates (`album.service.ts:45-70`) | Reuse; none |

### Pinned (favorites / recent / map / people / memories)

| V2 route | SDK call(s) | Store / manager / component | Filters | Mutations | Permission check | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `/v2/favorites` | Buckets `{ isFavorite: true, withStacked: true }` — shipped `routes/(user)/favorites/.../+page.svelte:34` | `TimelineManager` | `isFavorite` | Unfavorite via `updateAsset({ isFavorite: false })` (`asset.service.ts:426`) | `canFavoriteAsset` | Reuse; none |
| `/v2/recently-saved` | Buckets `{ visibility: Timeline, withStacked: true, withPartners: true, orderBy: CreatedAt }` — shipped `routes/(user)/recently-added/.../+page.svelte:47-52` (`AssetOrderBy` ∈ {takenAt, createdAt}, spec-verified) | `TimelineManager` | Upload-order sort | Same as library | Same as library | Reuse; none — **but see semantics risk R1**: this is *upload* order, and macOS "Recently Saved" may mean something else. |
| `/v2/map` | `getMapMarkers` (`Map.svelte:21,243`); grid side is a buckets timeline; `mapSettings` prefs (`stores/preferences.store.ts`); bbox bucket param exists | `Map.svelte` + `MapTimelinePanel` + `TimelineManager` | `withCoordinates` / bbox | Same as library | Same as library | Reuse; none |
| `/v2/people` | `getAllPeople({ withHidden })`, `getPerson`, `searchPerson`, `updatePerson` (`routes/(user)/people/+page.svelte:20,75,99,136`); merge/name flows in-page; utils `utils/people-utils.ts`, `utils/person.ts` | People page + `PeopleCard`/`PeopleInfiniteScroll` | `withHidden` toggle | Rename/merge/hide via person service (`services/person.service.ts:16,102`) | Owner-level (people are user-scoped) | Reuse; none |
| `/v2/memories` | `searchMemories` via `memoryManager` (`managers/memory-manager.svelte.ts:7,206,339`; load/hide/delete/toggle-saved at lines 200-286); explore preload `getExploreData` + `getAllPeople` (`routes/(user)/explore/+page.ts:1,13-14`) | `memoryManager` + story player components | `MemoriesSearchDto` filters | Hide asset, delete memory/asset, toggle saved (manager-owned) | Owner-level | Reuse; none |

### Search

| V2 route | SDK call(s) | Store / manager / component | Filters | Mutations | Permission check | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `/v2/search/[[assetId=id]]` | `searchSmart` / `searchAssets` (`routes/(user)/search/.../+page.svelte:146-149`); route builder `Route.search(dto)` serializes DTO to `?query=` (`route.ts:105-109`) | `SearchManager` (`managers/search-manager.svelte.ts`: filter state, `setQuery`, `submit`) + `search.svelte.ts` store; scope mapping `search-bar-utils.ts:275-291` (space/library/personal) | Full `MetadataSearchDto` surface incl. `type`, `personIds`, `city/country`, EXIF (`make/model/iso/fNumber/...`, `withExif`), `ocr`, `takenAfter/Before`, `isFavorite`, `visibility` (spec lists verified) | Open-result → viewer; add-to-album from results | Scope-aware (search-bar scope filter); result actions reuse `getAssetActions` | Reuse; none. EXIF presentation reuses viewer `DetailPanelFullMetadata`; OCR reuses `ocr` store (`stores/ocr.svelte.ts:20,35`) + `OcrButton`/`OcrBoundingBox`. |

### Utilities (imports / trash / hidden / archive / locked)

| V2 route | SDK call(s) | Store / manager / component | Filters | Mutations | Permission check | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `/v2/imports` | **No server "imports" concept and no classic imports route found** (no `imports` route dir; utilities = duplicates/large-files/geolocation). | Candidates: `recently-added` pattern, `upload-manager` history, or library-scoped scan views | TBD by product | Upload via `openFileUploadDialog` (`utils/file-uploader.ts:27,73-80`: `{ albumId?, spaceId? }`) | Same as library | **Semantics risk R2** — needs WP1/product decision (§Gaps). No server change proposed. |
| `/v2/trash` | Buckets `{ isTrashed: true }` — shipped `routes/(user)/trash/.../+page.svelte:28` | `TimelineManager` | `isTrashed` | `handleEmptyTrash` / `handleRestoreTrash` (`services/trash.service.ts:24,40`); permanent delete `deleteAssets(force=true)`; undo via `restoreAssets` (`utils/actions.ts:23-60`) | Owner-level; trashed assets excluded from share (`asset.service.ts:142`) | Reuse; none |
| `/v2/hidden` | Hidden visibility is a first-class `AssetVisibility` value (favorites/archive/locked pages each pass a `visibility` bucket param; `AssetVisibility` plumbed through buckets spec). `getAllPeople({ withHidden })` precedent for hidden-inclusion flags. | `TimelineManager` with hidden visibility filter | Hidden visibility | Hide/unhide via `updateAsset` visibility (same path as archive toggle in photos page `:179`) | Owner-level | Reuse; none |
| `/v2/archive` | Buckets `{ visibility: Archive }` — shipped `routes/(user)/archive/.../+page.svelte:31` | `TimelineManager` | `Archive` visibility | Archive/unarchive via visibility update | `canEditAsset` | Reuse; none |
| `/v2/locked` | Buckets `{ visibility: Locked }` — shipped `routes/(user)/locked/.../+page.svelte:32`; PIN management UI exists (`user-settings/PinCodeSettings.svelte`, `PinCodeChangeForm.svelte`) | `TimelineManager` | `Locked` visibility (personal-only per `isPersonalAsset`, `asset-permissions.ts:34`, DECISIONS I7) | Lock/unlock via visibility update; share/slideshow explicitly excluded for Locked (`asset.service.ts:142,187`) | Personal-only; PIN gate via existing PIN settings | Reuse; none |

### Viewer (all `[[assetId=id]]` deep links)

Existing `AssetViewer.svelte` + `asset-viewer-manager.setAssetId` +
`DetailPanel*` (date, description, location, people, star rating, tags, full
metadata) + `OcrButton`/`OcrBoundingBox` + `ocr` store cover the WP8 list
except two items:

- **Favorite / Delete / Move / Add-to-Album / Info / Download / Share /
  video & Live Photos / prev-next / keyboard paging**: all exist
  (`getAssetActions` lines 106-200+, `asset-viewer-manager`, viewer
  subcomponents incl. `VideoNativeViewer`, `PhotoSphereViewerAdapter`).
- **Rotate**: no rotate action exists in web, and `UpdateAssetDto` carries
  **no rotation field** (spec property list verified: dateTimeOriginal,
  description, isFavorite, latitude/longitude, livePhotoVideoId, rating…).
  Treatment: documented browser exception (native photo-rotation has no
  server counterpart); V2 omits or disables with explanation. **No server
  work proposed** — adding an image-pipeline API would violate the
  minimum-change rule and WP10 scope.
- **Edit**: web editor exists but is smaller than native (PLAN §6 finding);
  WP10 decision gate applies. No data-layer gap.

## 2. Create / update / delete + member/role administration

| Operation | Existing implementation | V2 reuse |
| --- | --- | --- |
| Album create | `createAlbum` / `createAlbumAndRedirect` (`utils/album-utils.ts:25-42` → `sdk.createAlbum` + `goto(Route.viewAlbum)`) | Reuse; V2 redirect targets V2 album route |
| Album update (title/desc/cover/order) | `updateAlbumInfo` (`album.service.ts` via `getAlbumActions` page wiring `albums/[albumId]/...:52,137`); cover `handleUpdateThumbnail` | Reuse |
| Album delete | `deleteAlbum` (`album.service.ts:280`) | Reuse |
| Album add assets | `addAssetsToAlbum(s)` single + multi (`album.service.ts:106-131`, `addToAlbum`/`addToAlbums` SDK, events `AlbumAddAssets`) | Reuse |
| Album members/roles | `addUsersToAlbum`, `removeUserFromAlbum`, `updateAlbumUser` (`album.service.ts:4-10,177-222`); `AlbumUserRole`; `AlbumAddUsersModal`/`AlbumOptionsModal` | Reuse |
| Space create | `SharedSpaceCreateModal` (`modals/SharedSpaceCreateModal.spec.ts` exists) + `sharedSpaces.upsert/remove` cache (`stores/shared-spaces.svelte.ts:36-43`) | Reuse |
| Space members/roles | `SharedSpaceMembersModal`: `sdk.addMembers2`, `sdk.getMembers2`, `sdk.searchUsers` (lines 24-29) | Reuse |
| External library membership | Read via `sdk.getSharedLibraries()` in `sharedSpaces` store; admin lives in classic admin library-management (`Route.libraries/newLibrary/viewLibrary/editLibrary`, `route.ts:67-70`; `services/library.service.ts:146-293` create/update/folders/exclusion patterns) | V2 reads via store; library admin stays classic unless WP9 explicitly scopes it |
| Move personal↔space↔library | `moveAssets` (`POST /assets/move`, `AssetMoveDto` targets personal + space{id} + library{id} — spec-verified) via `MoveToLibraryModal` (`:7,47` + `toApiTarget`); allowed targets `computeMoveTargets` (`move-targets.ts`: personal iff all-owned; all member spaces; libraries with `hasUploadPath`); completion callback `OnMove` (`utils/actions.ts:23`) | Reuse entire chain |
| Trash / restore / empty | `utils/actions.ts deleteAssets/restoreAssets`; `trash.service.ts handleEmptyTrash/handleRestoreTrash` | Reuse |
| Upload / import destination | `openFileUploadDialog({ albumId?, spaceId? })` (`file-uploader.ts:27,73-80`); progress/queue via `upload-manager` + upload stores | Reuse; library-destination question → G2 |

## 3. Data-semantics risks (PLAN §13 explicit requirement)

- **R1 — "Recently Saved" ≠ "recently-added".** Server `recently-added` =
  buckets ordered by `createdAt` (upload/creation order), `visibility:
  Timeline`, `withPartners` (`recently-added/.../+page.svelte:47-52`).
  macOS sidebar "Recently Saved" may mean last-saved-to-library,
  last-modified, or save-to-disk events. If WP1 screenshots show ordering or
  membership inconsistent with upload order, the fix is a different
  `orderBy`/filter composition — not a server change. Decision needed from
  WP1 before WP9 builds this route.
- **R2 — "Imports" has no server counterpart.** No imports route, table, or
  DTO field was found in web or the open-api surface surveyed. Candidate
  meanings: (a) recent uploads (upload-manager/queue history), (b)
  `recently-added`, (c) external-library import/scan jobs. Each reuses
  existing data; the choice is product semantics, documented and tested per
  PLAN §13 rule 4. No server change proposed under any candidate.
- **R3 — Locked is personal-only.** `isPersonalAsset`
  (`asset-permissions.ts:34`) + Locked excluded from share/slideshow. V2
  locked route must not offer space/library source scoping. Existing rule,
  just applied.
- **R4 — Bulk-timeline permission fallback.** `TimelineAsset` (bucket DTO)
  lacks `spaceId`/`libraryId` (spec `TimeBucketAssetResponseDto` property
  list verified — ownerId only), so bulk selection gates are ownerId-only
  while single-asset gates are container-aware. V2 inherits this asymmetry
  by reusing the same helpers; any stricter bulk behavior is client-side
  enrichment (fetch full DTOs), not a server change.

## 4. Claimed gaps: none requiring server work

Per the task constraint, a server gap needs reproduction (failing test,
request/response pair, or missing-field evidence with file:line). No such
gap was found. The nearest candidates and why they are not server gaps:

1. **Buckets lack `type`** — evidence: `GET /timeline/buckets` param list
   (open-api spec, `operationId: getTimeBuckets`) has no `type`, while
   `MetadataSearchDto`/`SmartSearchDto` both have `type`. Resolution is
   client-side route design (search-backed media routes), using fields the
   server already exposes.
2. **No screenshot predicate** — evidence: scoped web search for
   screenshot/filename filters returned no hits. Resolution is a
   client-composed `originalFileName`/`fileExtensions`/`mimeTypes` search;
   all three fields exist on `MetadataSearchDto`.
3. **Viewer Rotate has no API** — evidence: `UpdateAssetDto` property list
   (open-api spec) contains no rotation/orientation-write field, and no web
   rotate caller exists. Resolution is a documented browser exception, not
   an API to build.

## 5. Unresolved / follow-up items (not server gaps)

- **G1 (product):** R1/R2 semantics need WP1 native evidence + a recorded
  decision before WP9 builds `/v2/recently-saved` and `/v2/imports`.
- **G2 (verify):** `openFileUploadDialog` accepts `{ albumId?, spaceId? }`
  but no `libraryId` (`file-uploader.ts:27`). Whether direct upload into an
  external library is supported server-side (and whether V2 needs it vs.
  upload-then-move) must be verified against the upload endpoint + a fixture
  run by the WP7/implementation owner. Not claimed as a gap: move-into-library
  already covers the destination need.
- **G3 (verify):** Search-suggestion / recents cemantics for `/v2/search`
  scope selector and EXIF presentation details were mapped at the
  manager/DTO level; suggestion-list SDK specifics (if any) belong to the
  WP9 search owner to confirm during implementation.
- **G4 (scope note):** PLAN filename is `ROUTE-DATA-MATRIX.md`; this task
  ordered `WP2-ROUTE-DATA-MATRIX.md`. Written to the task-ordered name;
  lead may rename/alias.

## 6. Files read (countable)

PLAN `.claude/plans/heirloom-web-v2/PLAN.md` (§§5,7,9,13,17 + WP tables);
`web/src/lib/route.ts`; `web/src/lib/utils/library-source.ts` (+spec);
`web/src/lib/utils/move-targets.ts` (+spec);
`web/src/lib/utils/asset-permissions.ts` (+spec);
`web/src/lib/utils/container-utils.ts`;
`web/src/lib/utils/actions.ts`; `web/src/lib/utils/album-utils.ts`;
`web/src/lib/utils/file-uploader.ts`; `web/src/lib/services/asset.service.ts`;
`web/src/lib/services/album.service.ts`; `web/src/lib/services/library.service.ts`;
`web/src/lib/services/trash.service.ts`; `web/src/lib/services/person.service.ts`;
`web/src/lib/stores/shared-spaces.svelte.ts`;
`web/src/lib/stores/ocr.svelte.ts`; `web/src/lib/stores/preferences.store.ts`;
`web/src/lib/managers/timeline-manager/types.ts`,
`timeline-manager.svelte.ts` (options/mismatch lines);
`web/src/lib/managers/search-manager.svelte.ts`;
`web/src/lib/managers/memory-manager.svelte.ts`;
`web/src/lib/managers/geolocation.manager.svelte.ts`;
`web/src/lib/managers/upload-manager.svelte.ts`;
`web/src/lib/managers/asset-viewer-manager.svelte.ts`;
`web/src/lib/managers/user-preferences-manager.svelte.ts`;
`web/src/lib/managers/asset-multi-select-manager.svelte.ts`;
`web/src/lib/components/shared-components/search-bar/search-bar-utils.ts`;
`web/src/lib/components/shared-components/map/Map.svelte`;
`web/src/lib/modals/MoveToLibraryModal.svelte`,
`SharedSpaceCreateModal.svelte`, `SharedSpaceMembersModal.svelte`;
routes `(user)/photos`, `favorites`, `recently-added`, `trash`, `archive`,
`locked`, `map` (+`MapTimelinePanel`), `search`, `people`, `places`
(+page.ts), `memories`, `explore` (+page.ts), `albums` (+page.ts + `[albumId]`
page), `shared-libraries` (+page + `[spaceId]` page), `user-settings`
(component list); `open-api/immich-openapi-specs.json` (`getTimeBuckets`,
`moveAssets`, `MetadataSearchDto`, `SmartSearchDto`,
`TimeBucketAssetResponseDto`, `UpdateAssetDto`, `AssetMoveDto`,
`AssetOrderBy` — queried, not edited).

## 7. Handoff (PLAN §14 format)

1. **Scope completed:** all 21 V2 target routes (§7) + album/space
   CRUD + member/role admin + move semantics + URL contract params mapped
   to SDK calls, stores/components, filters, mutations, permission checks.
2. **Files read:** see §6.
3. **Files changed:** `.claude/plans/heirloom-web-v2/WP2-ROUTE-DATA-MATRIX.md`
   (this file) only. No production or server edits. Pre-existing user
   modifications (`deploy-heirloom-docker.md`, `MacAppState.swift`,
   `ImmichConnection.swift`) untouched; worktree otherwise as found.
4. **Assumptions/decisions:** reuse-first per §13 (compose, don't fork);
   media routes search-backed (buckets lack `type`); Rotate = browser
   exception; R1/R2 left to WP1/product; V2 prefs keyed separately from
   classic (`timeline-library-source` precedent).
5. **Tests run:** no tests run — read-only analysis deliverable; no code
   changed, so no suite applies. Verification was by source+spec inspection
   with file:line evidence throughout.
6. **Unresolved gaps:** G1–G4 in §5 (product decisions + two implementation-time
   verifications; none is a server gap).
7. **Overlap with pre-existing changes:** none — owned output is a new file
   in the untracked `heirloom-web-v2/` dir; shared-libraries fork files read
   (`library-source`, `move-targets`, `asset-permissions`, `shared-spaces`
   store) but not modified.
8. **Next owner/action:** lead consolidates with WP1 (R1/R2 decisions) and
   hands per-route rows to WP4–WP9 implementers; WP7 owner verifies G2 with
   a fixture run; WP10 owns the editor/rotate exception wording.
