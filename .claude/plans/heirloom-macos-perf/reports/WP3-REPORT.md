# WP3 Report — Custom layout, coordinator, cells (slices 1–2)

Branch `perf/heirloom-macos-wp3` (worktree `/Users/spatel/workspace/github/projects/immich-wp3`).
Implements WP3-GRID.md §1–4 (slice 1: §1–2; slice 2: §3–4).

## Commits (all end `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`)

- `b6e0ec178` slice 1 — `MacTimelineLayout` custom grid layout + `MacGridHeaderView`
  (pre-existing at slice-2 start; compile-only wiring in `MacCollectionGridView`).
- `84dfe0fa5` slice 2a — snapshot coordinator (sections, prefetch, menu, hover).
- `a126400a3` slice 2b — frame-based grid cell (black-border fix).

## Files changed

- `native-apple/Apps/macOS/Sources/MacTimelineLayout.swift` (new, slice 1) — geometry-backed
  layout, pinned month/year headers, zoom anchoring, `pinsHeaders` kill-switch.
- `native-apple/Apps/macOS/Sources/MacGridHeaderView.swift` (new, slice 1) — frame-based
  headers, material only while pinned.
- `native-apple/Apps/macOS/Sources/MacCollectionGridView.swift` (slice 2) — section-aware
  data source (`flatIndex`/`sectionAndItem`), visible-only patch reloads, zoom path with
  anchor, `indexById` selection diff, ordered-ids callback, Esc, quantized pinch, one
  collection-view hover area, clip-view prefetch (50 ms throttle, velocity>4 placeholders
  only, 120 ms settle pass, `Prefetch` signpost), dayKeys type-to-jump, `MacAssetActions`
  context menu, `actions` param (default nil), WP2 drag kept (section-aware).
- `native-apple/Apps/macOS/Sources/MacGridCell.swift` (slice 2) — frame-based rewrite, no
  borders ever, `CALayer` image + selection overlay, light layer badges, WP3 §4 load order.
- `native-apple/Apps/macOS/Sources/MacMainWindow.swift` — **minimal REQUIRED WP4-owned edit**:
  `MacTimelineGridPane.actions: MacAssetActions? = nil` + passthrough + `actions: gridActions`
  at the `gridView` construction site. No other call sites touched (default nil keeps them
  compiling). See open issue 1.

## Test results

- `make build-macos CONFIGURATION=Release` — **BUILD SUCCEEDED** after each slice commit
  (2a and 2b). No new warnings in owned files.
- `swift test --package-path native-apple/PhotosCore` — **156–157/158 pass**. The only failures
  are load-flaky perf-budget asserts in WP1-owned files this WP never touches
  (`TimelineGridSnapshotTests` 102k-build <60 ms; `TimelinePerformanceTests` timelineRows
  <400 ms): run A failed 1, run B failed 2, focused re-run passed. Pre-existing/environmental.
- `make test-macos-ui` (Release, `--fixture-seed` wired by WP0 in `MacSmokeTests`) —
  **3/3 FAIL, pre-existing**: `testSidebarAndGridRender` (sidebar never appears within 30 s),
  `testKeyboardSelectionAndMoveTargets`, `testLibrarySwitcherFiltersGrid`. Identical signature to
  WP0-REPORT's true-baseline run (sidebar never renders in this environment); WP3 touches no
  sidebar/launch path. Needs WP4/host triage.

## Profile summary

`profile.sh wp3` **not run here**: scripted UI driving (WP7 scenario A–H, 50-screen fling, zoom
steps) is impossible in this environment — same constraint as the pre-existing UI-test sidebar
failure; there is no reachable grid to scroll. Signpost coverage for WP7 is in place (`Prefetch`
intervals, same subsystem/category as `HeirloomSignpost`). **Left to WP7 on the host.**

## Deviations from the brief

1. `NSCollectionViewItem` has neither `layout()` nor `viewDidChangeEffectiveAppearance()` —
   both live on `MacThumbnailContainerView` (`onLayout`/`onAppearanceChange` callbacks); the cell
   does the work. Same behavior, view-owned hooks.
2. `aspectFit` flag derives from existing `usesSquareThumbnails` (`aspectFit = !usesSquareThumbnails`);
   no new parameter (brief allowed additions with defaults; none were needed).
3. `sizeForItemAt` + `NSCollectionViewDelegateFlowLayout` conformance removed (dead under the
   custom layout; geometry owns item frames). `MacTimelineGridPane` otherwise untouched.
4. `Prefetch` signpost uses a local `OSSignposter` (same subsystem/category), not an extension of
   PhotosCore's closed `HeirloomSignpost` set (WP1-owned).
5. Stream `.placeholder` steps are skipped in the cell task (the task already decoded the
   placeholder synchronously in step 3); tier steps convert `NSImage`→`CGImage` for the layer.
6. Preview tier passes `pixelSize: nil` (device-sized default); thumbnail tier uses the
   `min(512, ceil(side*scale/64)*64)` formula.

## Open issues

1. **MERGE REVIEW (WP4): `MacMainWindow.swift` pane edit.** Three lines: `actions` param
   (default nil), passthrough, `actions: gridActions`. Required for a functional context menu;
   reverting to nil just disables the menu. WP4 owns the file otherwise — do not extend this edit.
2. **Context menu, disabled as known no-ops: Rotate Clockwise only.** `gridActions.rotate` is an
   empty closure (`MacMainWindow.swift`); invoking it would silently do nothing. All other items
   (Open / Quick Look / Get Info / Favorite-Unfavorite / Add to Album… / Move to… / Delete with
   separator) are enabled whenever `actions != nil`. When WP4 implements rotate persistence,
   delete the disable + this issue.
3. **Menu-action freshness:** menu items call the passed `MacAssetActions` closures, which read the
   focused selection. Right-click select-first pushes through the SwiftUI binding before the menu
   tracks, and user invoke latency covers the re-render — verified by reading, not by clicking
   (UI driving impossible here). If WP7 sees a stale-selection menu, build per-item closures.
4. **`pinsHeaders` state: `MacTimelineLayout.pinsHeaders = true`** (slice 1 default, unchanged).
   If WP7 measures any pinning hitch ≥ 50 ms, set false per the brief.
5. **Not verifiable here (needs WP7/host):** no black frames after 50-screen fling, no letterboxing
   in square mode, accent-ring survival across scroll, all PLAN §budgets. Build + unit evidence is
   green; behavior evidence is host-only.
