# Fork: Shared Libraries

This is a fork of [immich-app/immich](https://github.com/immich-app/immich) that adds shared
libraries (spaces) and related features. See
[`.claude/plans/shared-libraries/DECISIONS.md`](.claude/plans/shared-libraries/DECISIONS.md)
for the full product/design spec.

## Base

- Upstream tag: `v3.1.0`
- Base sha: `e55ac299a4ec7cb372e35dbf2c6c05ee9ce77f6c`

## Migration re-run (remediation, Sep-2026)

Migration `1789426700279-SharedLibraries.ts` was amended in place after first landing
(`asset.spaceId` FK `SET NULL` → `RESTRICT`, plus a new `asset_container_not_locked`
CHECK; the `asset_space_library_exclusive` CHECK pre-existed). The amended bytes have
never run anywhere: any fork database migrated with the old bytes carries the old FK and
no `not_locked` CHECK. Re-running the migration from scratch (fresh database) is the only
supported path — there is no down-migration or repair job for the old shape. The table
definition (`asset.table.ts`: `RESTRICT` + matching `@Check`) mirrors the amendment.

## Merge procedure

1. `git fetch upstream --tags`.
2. Create a branch `merge/<tag>` and run `git merge <tag>` on it.
3. Resolve conflicts using the patch list below.
4. Regenerate generated files instead of hand-merging them: `mise //server:sync-open-api`,
   `mise :open-api-typescript`, `mise :open-api-dart`, `mise //server:sql`.
5. Run the S10 verify list.
6. Run the regression gate below — the merge is not accepted with any
   failing fork case or INV-02/INV-03 failure.

## Regression gate (TESTING.md §7)

- During development: `scripts/fork-test/run.sh unit` (+ `medium` when Docker exists).
- Before committing a phase that touches server behaviour:
  `scripts/fork-test/run.sh unit medium e2e-api coverage`.
- After every upstream merge: `scripts/fork-test/run.sh all upgrade`.
- CI (`.github/workflows/fork-tests.yml`) runs `unit`, `medium`, `e2e-api`,
  `e2e-web`, `coverage` on pushes to `feat/**` and `main`.

## Cadence

Merge every upstream minor release (approximately monthly); apply security releases
immediately.

## Conflict hotspots (S10)
Files with the most `fork: shared-libraries` hooks need re-application review on
every merge (counts from 16-Sep-2026; see the rehearsal record below):
1. `server/src/schema/index.ts` (23) — space/library tables, audit tables.
2. `server/src/utils/access.ts` (19) — R11 viewer add/remove, AssetFavorite/Move.
3. `server/src/repositories/person.repository.ts` (18) — space people scope.
4. `web/.../search-bar/SearchFilters.svelte` (17), `search-bar-utils.ts` (9).
5. `server/src/enum.ts` (16) — space/library roles, permissions, fork jobs.
6. `server/src/repositories/access.repository.ts` (14) — container membership checks.
7. `server/src/services/person.service.ts`, `server/src/repositories/sync.repository.ts`,
   `server/src/repositories/asset.repository.ts` (13 each).
8. `server/src/services/{sync,asset}.service.ts` (10 each).
Rule: never resolve a hotspot by accepting upstream (`theirs`) blindly — every
`fork:` marker in these files is load-bearing. Resolve `pnpm-lock.yaml`,
`uv.lock`, `package.json` versions, and `open-api/immich-openapi-specs.json`
by accepting upstream, then regenerate (see merge procedure).

## Merge rehearsal (S10, 16-Sep-2026, throwaway worktree — never committed)
- Merged upstream tag `v3.2.2` (58 commits past the `e55ac299` base) into a
  detached worktree at `ad4c7ae28`; 64 files changed in `server/src`+`web/src`.
- 26 conflicted paths: 15 mechanical (5 `package.json`, `pnpm-lock.yaml`,
  `uv.lock`, `pyproject.toml`, mobile fastlane/pubspec/people-picker,
  `Info.plist` (auto-merged), `open-api` spec (regenerate), `mappers.ts`,
  `response.ts`, `e2e/package.json`) and 11 fork-logic
  (`person.repository.ts`, `person.service.ts`, `sync.service.ts` + spec,
  `metadata.service.ts`, `asset-job.repository.ts`, `fetch-client.ts`,
  `search-bar-utils.ts` + spec, medium `person.service.spec.ts`).
- The merge itself takes minutes. Resolution estimate: ~30 min mechanical
  (accept upstream, reinstall, regen SQL/OpenAPI/SDK) + ~half a day fork-logic
  (re-apply markers in the hotspot files above, rerun medium + e2e-api).

## Patch list

| upstream file | change | reason | phase |
|---|---|---|---|
| `server/src/{database,enum}.ts` | registers shared-library database schema and enums | shared schema support | S1 |
| `server/src/dtos/asset-response.dto.ts` | exposes shared container fields in asset responses | shared schema support | S1 |
| `server/src/schema/{index,enums,functions}.ts` | registers shared-library schema and audit hooks | shared schema support | S1 |
| `server/src/schema/tables/{asset,library}.table.ts` | adds container fields and invariants | shared schema support | S1 |
| `server/src/schema/migrations/ORDER` | registers shared-library migration | shared schema support | S1 |
| `server/src/{repositories/sync.repository,services/sync.service}.ts` | prunes new audit tables | shared schema support | S1 |
| `server/src/services/asset-media.service.spec.ts` | adapts fixture for asset container fields | shared schema support | S1 |
| `server/test/{factories/asset.factory,small.factory}.ts` | adapts asset fixtures for container fields | shared schema support | S1 |
| `server/src/{enum.ts,utils/access.ts,repositories/access.repository.ts}` | grants container-aware asset and shared-space access | shared access control | S2 |
| `server/src/services/{asset.service.ts,album.service.ts}` | protects shared favorites, roles, and Locked visibility | shared access control | S2 |
| `server/src/utils/access.ts` (`AlbumAssetCreate`/`Delete` → Viewer), `server/src/services/album.service.ts` (`canAlwaysRemove` → `AlbumAssetDelete`), `e2e/.../album.e2e-spec.ts` (3 tests) | R11: every album member of any role may add/remove any asset — intentional upstream behavior change, see hotspots | album allow-rules | B1 |
| `server/src/cores/storage.core.ts` | namespaces generated files by shared-space storage key | shared storage relocation | S3 |
| `server/src/services/asset-relocation.service.ts` | resumes and performs crash-safe asset file relocations | shared storage relocation | S3 |
| `server/src/{repositories/asset.repository.ts,services/library.service.ts}` | guards external scans/watchers while moves are pending | shared storage relocation | S3 |
| `server/src/utils/container-scope.ts` | resolves visibility scope and emits container SQL predicates | visibility scope | S5 |
| `server/src/repositories/{asset,search,map,trash}.repository.ts` | applies container-scoped listing and mutation queries | visibility scope | S5 |
| `server/src/services/{timeline,search,map,asset,trash,user,memory}.service.ts` | resolves and applies request visibility scopes | visibility scope | S5 |
| `server/src/{controllers,dtos}/shared-space.*` (new), `server/src/{repositories,services}/shared-space.*` (new) | shared-space CRUD, members, ownership transfer API | spaces & library-member API | S4 |
| `server/src/controllers/library.controller.ts`, `server/src/dtos/library.dto.ts`, `server/src/services/library.service.ts` | external-library member endpoints, `uploadPath`, `GET /libraries/shared` | spaces & library-member API | S4 |
| `server/src/{controllers/asset.controller.ts,dtos/asset.dto.ts,services/asset.service.ts,repositories/asset.repository.ts}` | `POST /assets/move` (live-pair/stack expansion, target rules, crash-safe relocation) | move API | S4 |
| `server/src/{dtos/asset-media.dto.ts,services/asset-media.service.ts}` | upload target resolution (explicit spaceId → preference → personal) | upload target | S4 |
| `server/src/{dtos/user-preferences.dto.ts,types.ts,utils/preferences.ts}` | `sharedLibraries` preference block (default upload target, timeline toggles) | preferences | S4 |
| `server/src/services/user.service.ts` | user-deletion pre-step: transfer/delete owned spaces, reassign ownerId, inline relocation, re-queue face detection | lifecycle §8 | S4 |
| `server/src/database.ts` | adds `uploadPath` to `Library` type | bugfix (type gap from S1) | S4 |
| `server/src/{services,sync.repository}.ts` | shared-space/library sync streams, membership backfill, audit removals | sync I5, favorites §4 | S6 |
| `server/src/{enum,dtos/sync,database}.ts` | additive sync types and `spaceId` asset DTO field | sync I5 | S6 |
| `server/src/controllers/asset.controller.ts` | full EXIF endpoint | R12 | S7 |
| `server/src/repositories/metadata.repository.ts` | group-aware full exiftool reader | R12 | S7 |
| `server/src/{dtos/search.dto.ts,utils/database.ts,repositories/search.repository.ts,services/search.service.ts}` | scoped rich metadata filters and extension suggestions | R13 | S7 |
| `web/src/{routes/(user)/shared-libraries,lib/stores/shared-spaces.svelte.ts}` (new), `web/src/lib/modals/{SharedSpaceCreateModal,SharedSpaceMembersModal,LibraryMembersModal}.svelte` (new), `web/src/routes/(user)/user-settings/LibrarySettings.svelte` (new) | shared-library pages, scoped timeline, cache | R2,R7,R8 | S8a |
| `web/src/{lib/components/shared-components/side-bar/UserSidebar.svelte,lib/route.ts,routes/(user)/user-settings/UserSettingsList.svelte,routes/admin/library-management/[id]/+layout.svelte,test-data/factories/preferences-factory.ts,i18n/en.json}` | sidebar entry, routes, settings registration, admin library members/uploadPath UI | R3,R8,R9 | S8a |
| `web/src/{routes/(user)/shared-libraries,lib/stores/shared-spaces.svelte.ts}` | shared-library pages, scoped timeline, cache | R2,R7,R8 | S8a |
| `web/src/{lib/modals,routes/(user)/user-settings,routes/admin/library-management}` | shared-space and external-library management UI | R3,R8,R9 | S8a |
| `packages/sdk/src/fetch-client.ts` | hand-patched pending SDK regen (also carries S8c type additions, committed here) | R7,R8 | S8b |
| `web/src/lib/{modals/MoveToLibraryModal.svelte,components/timeline/{LibrarySourceSwitcher,actions/MoveToLibraryAction}.svelte,components/asset-viewer/actions/MoveToLibraryAction.svelte,utils/{library-source,move-targets,asset-permissions}.ts}` (new) | switcher, move action, permission helper | R4,R5,R7,R9,R10 | S8b |
| `web/src/lib/{services/asset.service.ts,components/asset-viewer/{AssetViewerNavBar,DetailPanel}.svelte,components/timeline/TimelineAssetViewer.svelte,constants.ts,utils/actions.ts}` | permission gates + move wiring | R4 | S8b |
| `web/src/routes/(user)/albums/[albumId=id]/[[photos=photos]]/[[assetId=id]]/+page.svelte` | any album member may add/remove | R11 | S8b |
| `web/src/lib/{layouts/UserPageLayout.svelte,utils/file-uploader.ts,managers/user-preferences-manager.svelte.ts},routes,i18n/en.json` | upload target; switcher pref | R3,R8,R9 | S8b |
| `web/src/lib/components/asset-viewer/{DetailPanel.svelte,DetailPanelFullMetadata.svelte}` | full metadata viewer | R12 | S8c |
| `web/src/lib/components/shared-components/search-bar/{SearchExposureSection,SearchFileSection,SearchLibrarySection}.svelte` | extended metadata filters + library scope | R13 | S8c |
| `web/src/lib/{components/shared-components/search-bar/search-bar-utils.ts,managers/search-manager.svelte.ts,types.ts}` | filter<->URL query mapping | R13 | S8c |
| `packages/sdk/src/fetch-client.ts` | hand-added AssetFullExifResponseDto/getAssetFullExif + rich search fields (SDK hunks ride with the S8b commit) | R12/R13 | S8c |
| `server/src/schema (person.spaceId, person_audit.spaceId, shared_space.clusterGroupId, migration 1789426700280), dtos, repositories, services (person/asset/search/metadata)` | space-scoped people, space recognition, move detach, member sync | S9 sketch §11 | S9 |
| `native-apple/` (fork-only tree; `Heirloom` apps, bundle IDs `com.immich.heirloom.*`) | iOS/macOS companion apps over the fork API | Apple track | A0–A9 |
| `server/src/{enum.ts (ContainerPathsAudit jobs),types.ts,services/job.service.ts,services/asset-relocation.service.ts,repositories/asset.repository.ts}` | `container-paths-audit` manual/admin job: report-only §7 placement audit | integrity | S10 |
| `scripts/fork-test/{upgrade.sh,openapi-diff.sh}`, `scripts/fork-test/run.sh` (`upgrade` tier) | UP-01 base-tag upgrade gate; INV-02 OpenAPI additions-only gate | upgrade gate | S10 |
