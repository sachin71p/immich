# Heirloom macOS — Performance & Functionality Fix Plan (master)

Branch: `perf/heirloom-macos` (cut from WIP checkpoint `85b44a101` on `feat/shared-libraries`).
Repo root: `/Users/spatel/workspace/github/projects/immich`. App: `native-apple/` (Xcode project
`native-apple/Heirloom.xcodeproj`, scheme `Heirloom-macOS`, Swift package `native-apple/PhotosCore`).
Target library: 80,361 photos + 22,271 videos (~102k timeline rows) on the owner's Immich/Heirloom server.

## Evidence (read before starting any WP)
| File | What |
|---|---|
| `01-map.md` | Code map (Haiku scout — button inventory is incomplete, don't trust it) |
| `03-diagnosis.md` | Static diagnosis of hot paths (verified by Opus) |
| `04-baseline-profile.md` | Instruments baseline: 13 main-thread hangs, 12.9 s total, worst 2.0 s |
| `05-ui-audit.md` | Hands-on audit, issues U1–U27 |
| `06-facts.md` | File:line facts (Haiku). **Known wrong:** §4 claims MacMoveSheet has a Cancel button — it does not. Re-verify anything you rely on. |

## Root causes (verified)
- **R0** `make install-macos` builds and installs the **Debug** configuration (no `-configuration`; bundle
  contains `Heirloom-macOS.debug.dylib` and `__preview.dylib`). Unoptimized Swift magnifies every cost below.
- **R1** `MacGridLoader.load` publishes `sections` before `assetsById`. Cells skip thumbnail loading when
  `assetsById[id] == nil`. When `assetsById` arrives, `reloadIfNeeded` sees the same ids and never reloads,
  so visible cells stay blank (U2, U17, U21, U22, U25). `assetsById` loads full `Asset` values for all 102k
  rows in ~257 serial queries (~16 s on a GRDB reader thread).
- **R2** `@Observable` stored properties `sections: [MacGridSection]` and `assetsById: [String: Asset]`:
  every assignment runs a value-by-value `==` over 102k structs just to decide whether to notify (the
  worst hangs: 1.8–2.0 s). SwiftUI then diffs these values again in `MacCollectionGridView`.
- **R3** `NSCollectionViewFlowLayout` with one section of 102k variable-size items: synchronous O(n)
  layout with a `sizeForItemAt` dictionary lookup per item, on every reloadData or size change. Headers
  are never rendered because `numberOfSections == 1` (U4).
- **R4** SwiftUI body and `updateNSView` make 6–8 full passes over the rows on every state change:
  - `displayedSections`, `displayedRowIds`, `libraryDateRange`, footer counts;
  - `dateString` for all rows;
  - `reloadIfNeeded` (flatMap + array compare) and `syncSelection` (filter all).
- **R5** `bucketTitle` creates a new `DateFormatter` per bucket and mutates `dateFormat` twice (ICU reparse).
- **R6** Load cancellation is shown as an error and clears the grid (U3).
- **R7** Viewer paging context is `loader.allRowIds` (unfiltered, not reversed) instead of display order (U7).
- **R8** Mutations (favorite/trash/move) do a full reload plus one SQL query per album.
- **R9** Media pipeline:
  - Each thumbnail is downloaded twice (`service.data` then `service.image`).
  - Every request is `.high` priority, and the grid never calls the existing prefetch API.
  - There is no synchronous memory-cache hit when a cell is configured.
  - Cells need a full `Asset` to load.
  - `TieredMediaCache.init` scans the disk cache synchronously on the main thread.
- **R10** Cell border bug: `prepareForReuse` sets `layer.borderColor = nil` with `borderWidth = 4`, so
  CALayer paints an opaque black frame on every reused cell (U10). Thumbnails are aspect-fit
  (letterboxed), not Photos-style aspect-fill.
- **R11** `MacMoveSheet` has no Cancel button and no Escape handling, and it blocks app Quit (U12).
  Tapping a shared-library target moves immediately, with no confirmation.
- **R12** No logging anywhere (0 `Logger`/`os_log`/`print` in the app or PhotosCore) (U26).

## Work packages, order, and file ownership
Parallel WPs **must not** edit the same files. The ownership column is exclusive for the WP's duration.

| WP | Title | Brief | Depends on | Owns (exclusive while running) | Agent / model |
|---|---|---|---|---|---|
| WP0 | Build/install Release, logging API, perf harness, UI-test wiring, large fixture | `WP0-TOOLING.md` | — | `Makefile` (macOS targets), `native-apple/project.yml`, `native-apple/scripts/**`, new `scripts/heirloom-perf/**`, `Apps/macOS/Sources/FixtureSeed.swift`, new `Apps/macOS/Sources/HeirloomLog.swift`, `PhotosCore/Sources/CoreModel/Log.swift` | implementer / Sonnet |
| WP1 | PhotosCore: row fields + queries, grid snapshot, grid geometry, media pipeline, people/map/album queries | `WP1-CORE.md` | — | `PhotosCore/**` except `CoreModel/Log.swift` | implementer / Sonnet — **Opus reviews diff** |
| WP2 | App data flow: split grid file, snapshot loader, change center, main window, interim grid fix | `WP2-LOADER.md` | WP0, WP1 merged | `MacMainWindow.swift`, `MacAppState.swift`, `MacGridView.swift` → `MacGridLoader.swift` / `MacCollectionGridView.swift` / `MacGridCell.swift`, new `MacAssetChangeCenter.swift`; compile-only edits in `MacViewer.swift`, `MacSearchView.swift` | implementer / Sonnet — **Opus reviews diff** |
| WP3 | Custom layout + headers, coordinator, cells (black-border fix), prefetch, context menu | `WP3-GRID.md` | WP2 merged | `MacCollectionGridView.swift`, `MacGridCell.swift`, new `MacTimelineLayout.swift`, `MacGridHeaderView.swift` | implementer / Sonnet — **Opus reviews diff** |
| WP4 | Functional fixes: control inventory, sheets, quit, toolbar, titles, empty states, rotate, share, UI tests | `WP4-FUNCTIONAL.md` | WP2 merged | `MacMoveSheet.swift`, `MacLibrarySheets.swift`, `MacImport.swift`, `MacSidebarModel.swift`, `MacSidebar.swift`, `MacMenus.swift`, `MacStorageView.swift`, `MacSettings.swift`, `MacDragDrop.swift`, `MacSelection.swift`, `HeirloomMacOSApp.swift`, `MacConnectView.swift`, `Apps/macOS/UITests/**`, `FixtureSeed.swift`, `MacMainWindow.swift` (toolbar/sheets/titles only) | implementer / Sonnet |
| WP5 | Viewer: paging, instant open, preload, rotation fit, title, inspector/EXIF, keyboard, video/live | `WP5-VIEWER.md` | WP2 merged; rotate persistence decision from WP4 | `MacViewer.swift`, `MacLiveVideo.swift`, `MacLiveText.swift`, `MacEditView.swift`, new `MacInspectorView.swift`, new `PhotosCore/Sources/LocalStore/LocalStore+Exif.swift` | implementer / Sonnet |
| WP6 | Parity pages: People, Memories, Map, Collections, Search, All Albums, Duplicates | `WP6-PARITY.md` | WP3 + WP4 merged | `MacMemoriesView.swift`, `MacMapPlacesView.swift`, `MacAllAlbumsView.swift`, `MacSearchView.swift`, `MacDuplicatesView.swift`, new `MacPeopleView.swift`, `MacCollectionsView.swift`, `MacSidebarModel.swift` (new cases only), new `LocalStore+People.swift` / `+Counts.swift` | implementer / Sonnet |
| WP7 | Verification gate: build, tests, Instruments, scripted hands-on re-audit | `WP7-VERIFY.md` | after each wave | read-only source; writes `reports/` | verifier / Sonnet (§1–2) + orchestrator with computer-use (§2–4) |

**Waves**
1. **Wave 1:** WP0 step 2 (logging API) runs first, a ~10-minute commit, so `HeirloomLog` exists. Then
   WP1 ∥ the rest of WP0. → **Gate 1**
2. **Wave 2:** WP2. Step 1 (the file split) is its own commit. → **Gate 2**, which must show the
   blank-grid bug fixed.
3. **Wave 3:** WP3 ∥ WP4 ∥ WP5. Disjoint files. WP4 decides Rotate persistence first and writes it at the
   top of its report; WP5 reads it. → **Gate 3**, which must meet all grid, selection and viewer budgets.
4. **Wave 4:** WP6. → **Gate 4**, the final gate. The orchestrator then opens a PR (only if the owner
   asks) and installs the Release build.

Opus review (orchestrator) after WP1, WP2 and WP3:
- read the diff (`git diff <base>..HEAD -- <owned files>`);
- check concurrency, the "no O(rows) on main" rule, and API contract adherence;
- send fixes back to the same implementer, not a new one.

## Global rules for every executor
0. **Isolation.** Each WP runs in its own git worktree on branch `perf/heirloom-macos-wpN`, cut from the
   current tip of `perf/heirloom-macos`. The orchestrator uses `isolation: "worktree"` or runs
   `git worktree add ../immich-wpN -b perf/heirloom-macos-wpN perf/heirloom-macos`.
   - Plan files live in the main checkout at
     `/Users/spatel/workspace/github/projects/immich/.claude/plans/heirloom-macos-perf/`. Read them via
     that absolute path, and write your report there.
   - The orchestrator merges each WP branch into `perf/heirloom-macos` (`--no-ff`) after review. Later
     waves branch from the updated tip.
   - DerivedData: use a per-worktree `-derivedDataPath` (the Makefile's `native-apple/.build` is already
     per-checkout).
   - Only the orchestrator runs `make install-macos`, because `/Applications` is shared.
1. Read this file, your WP brief and the evidence files it cites. Re-read any source before editing, since
   line numbers drift.
2. Stay inside your owned files. If you need a change elsewhere, stop and report it; don't make the change.
3. Keep the code style of the surrounding code: 2-space indent, `///` doc comments for types, comments
   explaining *why*.
4. Swift 6 strict concurrency: no `@unchecked Sendable` unless the state is lock-guarded or the wrapped
   type is documented thread-safe (e.g. `NSCache`), with a comment saying which. No
   `MainActor.assumeIsolated` outside AppKit callbacks.
5. **Never** assign a large collection (>1k elements) to an `@Observable` stored property whose type is
   `Equatable`. Wrap it in a reference or an identity-compared box, as specified in WP1/WP2.
6. Don't run destructive actions (trash, lock, move, delete album) against the owner's real library.
   Destructive flows are tested with unit tests, `--fixture-seed`, or `make mock-server`.
7. Signing: keep `DEVELOPMENT_TEAM = 599Z443923` and automatic signing, so the installed app keeps its
   Keychain session. Don't change the bundle id `com.immich.heirloom.macos`.
8. Commit at the end of each WP step that builds, with Conventional Commit messages
   (`perf(macos): …`, `fix(macos): …`, `feat(macos): …`, `perf(photoscore): …`), ending with the
   `Co-Authored-By` line your harness provides. Don't push.
9. Definition of done for every WP:
   - The Release build succeeds (WP7 §1 command).
   - `swift test --package-path native-apple/PhotosCore` passes.
   - The WP's own acceptance checks pass.
   - A report is written to `reports/WPn-REPORT.md` covering: what changed (file list), commits, test
     results, deviations from the brief, and open issues.

## Performance budgets (WP7 enforces, on a Release build, with the owner's 102k library)
| Scenario | Budget |
|---|---|
| Cold launch → first screen of thumbnails (warm disk cache) | ≤ 2.0 s |
| Cold launch → first screen of thumbnails (empty disk cache) | ≤ 4.0 s |
| Switch Years ↔ Months ↔ All Photos | ≤ 300 ms, no hang ≥ 250 ms |
| Select / deselect one item, toggle favorite | main thread ≤ 16 ms per event, no full reload |
| Fast scroll through the whole library (scroll-bar drag top → bottom) | no hang ≥ 250 ms, no blank cell visible > 500 ms after scrolling stops |
| Sidebar destination switch (Photos/Videos/Favorites/album) | content visible ≤ 1 s |
| Pinch / + / − zoom | ≤ 100 ms per step |
| Resident memory after scrolling the whole library | ≤ 700 MB |
| Total Instruments "Hangs" during WP7 scripted scenario | 0 hangs ≥ 500 ms, ≤ 2 microhangs |
