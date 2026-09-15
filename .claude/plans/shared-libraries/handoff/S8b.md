# S8b handoff — Web: library switcher, move action, favorites & album UI, upload target

## Summary
- Library switcher (Select) on `/photos` header, persisted; drives TimelineManager
  personalOnly/spaceId/libraryId via new `parseLibrarySource`.
- "Move to…" (bulk timeline menu + viewer menu) + `MoveToLibraryModal` (`computeMoveTargets`),
  calls `POST /assets/move`, toasts moved/unchanged/failed, removes moved assets from view.
- Permission helper `canEditAsset`/`canFavoriteAsset` (owner OR space/library member OR, for
  favorite, album member); wired into `getAssetActions`, `AssetViewerNavBar`, `DetailPanel`.
- Album add/remove no longer Editor-only: any member can add/remove (album page + viewer).
- Upload from a space page passes `spaceId`. Container badge added to viewer `DetailPanel`.

## Deviation: hand-patched `packages/sdk/src/fetch-client.ts`
SDK was stale vs S1-S7 server DTOs (never synced to the openapi spec). `mise run open-api` ->
`server:sync-open-api` fails on an unrelated pre-existing bug (`MetadataSearchDto` in
`search.dto.ts` missing `.meta({format:'double'})`). Hand-patched only what's needed, marked
`// fork: shared-libraries — hand-patched pending full SDK regen`: `AssetResponseDto.spaceId`,
`spaceId`/`libraryId`/`personalOnly` on `getTimeBucket(s)` (also fixes a latent bug: S8a's
space-page `spaceId` filter was silently dropped before).

## CODEMAP-FIX / real blocker (flagged, not fixed here)
`TimeBucketAssetResponseDto` has no per-asset spaceId/libraryId (only single-asset
`AssetResponseDto` does), so thumbnail badges (task 2) and bulk-select permission gates (task 4)
fall back to ownerId-only; viewer badge/permissions and "Move to…" work fully. Needs a server
DTO change + SDK regen — out of web-only scope.

## FORK.md patch-list lines
`packages/sdk/src/fetch-client.ts | hand-patched pending SDK regen | R7,R8 | S8b`
`web/src/lib/{modals/MoveToLibraryModal.svelte,components/timeline/{LibrarySourceSwitcher,actions/MoveToLibraryAction}.svelte,components/asset-viewer/actions/MoveToLibraryAction.svelte,utils/{library-source,move-targets,asset-permissions}.ts}` (new) | switcher, move action, permission helper | R4,R5,R7,R9,R10 | S8b`
`web/src/lib/{services/asset.service.ts,components/asset-viewer/{AssetViewerNavBar,DetailPanel}.svelte,components/timeline/TimelineAssetViewer.svelte,constants.ts,utils/actions.ts}` | permission gates + move wiring | R4 | S8b`
`web/src/routes/.../albums/.../+page.svelte | any album member may add/remove | R11 | S8b`
`web/src/lib/{layouts/UserPageLayout.svelte,utils/file-uploader.ts,managers/user-preferences-manager.svelte.ts},routes,i18n/en.json | upload target; switcher pref | R3,R8,R9 | S8b`

## Verify
typecheck pass · lint pass (fixed real defect: `Select` has no `aria-label`, used `placeholder`) ·
check:svelte 0 errors before documented TS 6.0.3 crash · test --run: 356/356 executed tests pass;
42/65 suites (incl. mine, like S8a's) hit the pre-existing documented localStorage crash; my 3
pure-logic specs ran and passed.

## Open issues
Bulk-timeline move/permission gates stay `isAllUserOwned`-scoped (root cause above). No
bulk-select bar on the S8a space page yet, so bulk `MoveToLibraryAction` is /photos-only.
