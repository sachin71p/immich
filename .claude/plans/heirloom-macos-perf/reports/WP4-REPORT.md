# WP4 Report — Functional fixes

## Rotate decision (U27) — YES, persistable (written first for WP5)

A persisted 90° rotation path exists and the grid now uses it. `EditRecipe.crop.quarterTurns`
maps through `EditSplitter.split` to a single upstream `rotate` item (`angle = turns × 90`,
`PUT /assets/:id/edits`), followed by a recipe-KV save (`EditPersistencePayload`) — the same
path as `MacEditView.macSavePhoto`, minus the render/upload, which pure rotation does not need
(`requiresClientRender == false`). Verified server-side `replaceAll` semantics
(`asset-edit.repository.ts`: DELETE-all-then-insert), so repeats compose and the full merged
split is re-sent each time. Grid `rotate(ids:)` (MacMainWindow): fetches the stored recipe
(404 → fresh; other fetch errors fail the item rather than clobber), bumps quarter-turns,
splits against the `Asset.width/height` already in the store (no original download), applies
upstream edits + saves the KV (preserving `renderedAssetId`), posts
`MacAssetChange.edited(ids:)`, shows a progress toast then a summary toast, and logs every
failure via `HeirloomLog.ui`. Videos are skipped with a "need the viewer" report (their
rotation is a `VideoRecipe` client export, owned by WP5). Edge handled: a 4th rotate wraps to
0 turns and emits no upstream item, so the grid calls `clearUpstreamEdits` instead of hitting
the empty no-op guard and leaving a stale server-side rotate. Wired through `gridActions`,
so the grid toolbar button, the context path, and Image › Rotate Clockwise (⌘R) all persist.
Known limitation for WP5: rotating a source that already has a rendered upload leaves the
rendered copy 90° stale (link preserved, not re-rendered).

## Changes
- `native-apple/Apps/macOS/Sources/MacMainWindow.swift` ONLY: `import Editing`, toolbar
  Rotate button now calls `rotate(ids:)` (disabled with empty selection) instead of the
  toast-only stub, `gridActions.rotate` wired to `rotate(ids:)`, new `rotate(ids:)`.

## Verification (Rotate slice)
- `make build-macos CONFIGURATION=Release`: BUILD SUCCEEDED (only pre-existing
  SyncEngine dependency-scan warnings).
- `swift test --package-path native-apple/PhotosCore`: 158 tests, all pass except
  `[perf]` timing-budget tests (snapshot 102k build, timelineBuckets/Assets/ Rows) —
  confirmed pre-existing by re-running those suites on clean base `f8beb9f24` (same
  failures, 4 issues there). Unrelated: this slice touches no PhotosCore file.
- Note: `swift test` first failed on missing `ImmichAPI/openapi.yaml` (gitignored
  generated file); regenerated via `bash native-apple/scripts/gen-api.sh` (untouched by
  the commit).
- No destructive verification run: rotate posts to the real server only on user action;
  logic verified by build + existing `EditingTests.upstreamMapping` split contract, no
  fixture-seed UI run in this slice (deferred to WP4 Step 3).

## Close-out — all slices (branch `perf/heirloom-macos-wp4`, base `9395dd233`)

### Slices, files, commits (each ends `Co-Authored-By: Claude Opus 5`)

- `6bd4efcb5` docs — Step 1 control inventory (`reports/WP4-CONTROLS.md`; 113 rows).
- `07e4aea7a` feat — Rotate persists via upstream edits + recipe KV (Rotate section above).
- `275b7495e` fix — Move sheet select-then-move with Cancel/Escape + space-move
  confirmation parity (`MacMoveSheet.swift`).
- `81518dd1b` fix — Cancel/Escape/default-button pattern on every sheet
  (`MacDragDrop.swift`, `MacImport.swift`, `MacLibrarySheets.swift`).
- `f321d952e` fix — ⌘Q/AppleScript quit while a sheet is open (`terminateNow`, upload/move
  NSAlert guard) (`HeirloomMacOSApp.swift`, `MacMainWindow.swift`).
- `462220e20` fix — resolved space/album/library titles, per-destination toolbar gating,
  sidebar persistence, menu empty-selection guards (`MacMenus.swift`, `MacSidebar.swift`,
  `MacSidebarModel.swift`).
- `a2b84b593` fix — grid toolbar (U5 fixed title width), Share via `NSSharingServicePicker`,
  per-destination empty states, snapshot-count footers, human error toasts + `HeirloomLog.ui`
  (`MacMainWindow.swift`).
- `03c9b5599` fix — per-space timeline toggle in the manage sheet, settings/storage error
  logging (`MacLibrarySheets.swift`, `MacSettings.swift`, `MacStorageView.swift`).
- `946954a08` + `11601e731` + `7558c03fb` test/fix — Step 3: new `MacFunctionalTests.swift`
  (10 tests) + enablers: fixture-mode local favorite/trash, `favorite-button` /
  `space-manage-button` / `sidebar-new-album` identifiers, device-less camera-sheet Done row.
- `FixtureSeed.swift`: no extension needed — a space (`space-family`) and an album
  (`album-trip`) are already seeded.

### Test results (worktree, this session)

- `make build-macos CONFIGURATION=Release` — **BUILD SUCCEEDED** (pre-existing warnings only).
- `make test-core` — **158/158 PhotosCore tests pass** (21 suites, incl. the `[perf]` timing
  suites that were red on base `f8beb9f24` during the Rotate slice — environment-sensitive,
  green here).
- `make test-macos-ui` (the WP0 command) — **suite red ONLY at the pre-existing environment
  gate: the app launches and reaches foreground, but the sidebar never renders within the
  30 s wait.** Per test:
  - `MacSmokeTests` (3, pre-existing): `testSidebarAndGridRender` fails at `:24`
    ("sidebar renders", 51 s); `testKeyboardSelectionAndMoveTargets` fails at `:60`
    (asset-grid wait, 36 s); `testLibrarySwitcherFiltersGrid` fails at `:89` (asset-grid
    wait, 39 s) — **identical signature to the WP0 baseline** (proven pre-existing there by
    re-running on the true-baseline tree).
  - `MacFunctionalTests` (10, new): `testSidebarDestinationsShowResolvedTitles`,
    `testMoveSheetCancelEscapeAndQuit`, `testNewSpaceSheetCancelAndEscape`,
    `testNewAlbumSheetCancelAndEscape`, `testAddToAlbumSheetCancelAndEscape`,
    `testManageSpaceSheetDoneAndEscape`, `testCameraImportSheetDismisses`,
    `testFavoriteTwoShowsThemInFavorites`, `testTrashRemovesWithoutFullReload`,
    `testMinimalToolbarOnMapPeopleMemories` — **all 10 compile, launch, reach foreground,
    then fail at the same first gate** (`launchAndWaitForLibrary`, "sidebar renders",
    33–39 s each). **Identical cause, zero new failure modes.** Needs a host GUI-session
    re-run (WP7) to prove green; never PASS from the sandbox (TESTING.md §8).

### CONTROLS.md disposition (every non-yes row)

Fixed here: Share toast-only → real picker (`a2b84b593`); Move-sheet Cancel/Escape
(`275b7495e`); Add-to-Album / Manage-Done / New-space / New-album / Camera / Chooser
Cancel/Escape (`81518dd1b`, device-less Done `946954a08`); Move/Add-to-Album
empty-selection menu guards (`462220e20`); quit-while-sheet-open (`f321d952e`); resolved
titles, toolbar gating, sidebar persistence (`462220e20`); U5 width, U23 empty states,
snapshot footers, human toasts + logging (`a2b84b593`, `03c9b5599`); Rotate persistence
(`07e4aea7a`); per-space timeline toggle (`03c9b5599`).
Assigned WP5-viewer (viewer-owned files/behavior): editor control group, viewer Rotate
stub, viewer Quick-Look no-op, viewer New-Viewer-Window no-op, live-video pair, viewer
Edit content.
Assigned WP6-page (parity files owned by WP6; all rows already yes, ownership only):
search group, memories group, parity nav, EXIF copy.
OPEN: grid right-click context menu still missing (CONTROLS row said "fix here") — adding
it requires WP3-owned pane internals (`MacCollectionGridView`/`MacGridCell`), which WP4
may not touch ("never pane internals"). Rotate stays reachable via toolbar + ⌘R. Proposed:
WP3 follow-up, or record removal.

### Deviations from the brief

1. "Heart badge accessibility value": not directly assertable — heart/heart.fill share one
   image description and the cell badge exposes no value, and the cell files are WP3-owned.
   The test asserts the same state via Favorites membership (both items render, count == 3).
   Proposed one-line hook (not made): identifier + value on the favorite button in
   `MacGridCell.setFavorite`.
2. Favorite/trash under `--fixture-seed` always failed: `AssetMutations` goes network-first
   against `fixture.invalid`. Added a seeded branch in `toggleFavorite`/`trash` applying
   straight to the local store (production path unchanged; detected via the same
   `--fixture-seed` flag the app boots on).
3. Camera sheet's device-less layout had no dismiss control (Done row only rendered with
   devices) — added Done + `.cancelAction`, completing Step 2's "every sheet" pattern.
4. Import-chooser Cancel/Escape verified by code only (same `.cancelAction` pattern): opening
   it requires satisfying a modal `NSOpenPanel`, which XCUITest cannot drive.

### Open issues

1. UI suite needs a host GUI re-run to prove green (gate above blocks all 13 tests equally).
2. Grid context menu missing (see disposition; needs a WP3-pane decision).
3. The ⌘Q-while-sheet-open test (quit ≤ 15 s) is validated only to the same gate as the rest.
