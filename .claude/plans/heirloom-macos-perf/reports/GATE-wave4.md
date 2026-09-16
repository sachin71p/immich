# GATE Wave 4 — FINAL verdict (all waves merged)

Branch `perf/heirloom-macos`. Verifier, read-only source (writes: this report only).
Prior gate: `GATE-wave3.md` = CONDITIONAL PASS (0 hangs ≥500 ms, 2/2 microhangs,
storm fixed, launch budget unevidenced). Raw logs: `/tmp/heirloom-perf/build-gate4.log`,
`test-gate4.log`, `uitest-gate4.log`, `gate4warm-20260916-140550.trace`,
`gate4empty-20260916-140912.trace`, `summary-gate4warm.txt`, `summary-gate4empty.txt`.

## Part A — build / tests / guards / bundle: PASS

- `make build-macos CONFIGURATION=Release` — **BUILD SUCCEEDED, zero warnings**
  (full-log warning/error scan clean).
- `swift test --package-path native-apple/PhotosCore` — **174 tests / 24 suites,
  ALL PASS** (up from 168/22 at Gate 3: +6 WP6 tests).
- Static guards **clean**: only hit is the `MacGridCell.swift:47` `///` doc comment
  explaining why `borderColor = nil` must never return. No `assetsById` / `allRowIds`
  / `displayedSections` in `Apps/macOS`.
- Bundle: no `*.debug.dylib`, `Identifier=com.immich.heirloom.macos`,
  `TeamIdentifier=599Z443923`. Pass.

## Part B — warm leg (gate4warm-20260916-140550, 120 s, launch+idle, real 102k library)

- **Hangs: 4 total, 1.25 s combined, worst 0.36 s — all Microhang** (256/358/306/331 ms).
  Budget: 0 hangs ≥ 500 ms ✓; microhangs 4 vs ≤ 2 ✗ (over by 2).
- **GridLoad ×1, 5.508 s** — exceeds the ≤ 2.0 s warm launch budget ✗. Grounded in
  source (`MacGridLoader.swift:99-115`): GridLoad = `fetch` (store queries, off-main)
  + `buildSnapshot` + publish, starting when `load()` is called (after app boot +
  connection setup, so true launch→thumbnails is slightly *larger*). SnapshotBuild
  itself was 47–50 ms, so the 5.5 s is fetch-dominated; load/fetch/timelineSections
  still own ~56% of main-thread Running samples (18.9/18.3/17.6%). Caveat: GridLoad
  includes server-dependent fetch — warm 5.5 s vs empty 3.9 s inversion shows
  network variance dominates single samples; treat both as noisy n=1.
- SnapshotBuild ×2 ≤ 0.050 s; Prefetch ×3 ≤ 0.044 s; ScrollMainThreadInterval max 0.007 s.
- ThumbnailDecode ×175 (no ThumbnailFetch — fully warm cache, as expected).

## Part C — empty-cache leg (gate4empty-20260916-140912, 150 s)

Cache dir identified from source (`MacAppState.swift:99-102`):
`~/Library/Caches/Heirloom/Media` (tier subdirs `preview/`, `thumbnail/`).
Only that dir's contents were moved aside to `/tmp/heirloom-perf/cache-stash/`;
library, Keychain, defaults untouched.

- **Hangs: 2 total, 1.23 s combined, worst 0.75 s** (477 ms Microhang + 749 ms Hang).
  Budget: 0 hangs ≥ 500 ms ✗ (1 over); microhangs 1 vs ≤ 2 ✓.
- **GridLoad ×1, 3.899 s** — inside the ≤ 4.0 s empty launch budget ✓ (narrowly).
- ThumbnailFetch ×134 (p50 84 ms, p95 368 ms, max 754 ms); ThumbnailDecode ×136
  (p95 6 ms); Prefetch ×1 0.765 s; ScrollMainThreadInterval max 0.003 s;
  SnapshotBuild ×2 ≤ 0.047 s.
- **Cache RESTORED.** Note: the app recreated `Media/{preview,thumbnail}` during the
  empty run, so the stashed dir initially landed one level deep; fixed by copying the
  stashed `.bin` files back with `cp -n` (union preserved, nothing overwritten) and
  removing the nesting. Final state: `Media/{preview,thumbnail}`, 12,495 files,
  241 MB — same size as before the leg. No user data touched.

## Part D — log checks (both windows, `com.immich.heirloom`)

- Warm window: zero persisted app lines in category `media`; the only 5 error-level
  hits nearby are `swiftpm-testing-helper` stub failures from the unit-test run
  (expected), not the app. **No 404-flood, no error-level cancel spam.**
- Empty window: zero persisted `com.immich.heirloom` lines at any level.
  (Cancellations log at `.debug`, which the store does not persist — established Gate 3.)

## Part E — UI suite (`make test-macos-ui`, one run, ~336 s)

**3 passed / 10 failed** (xcresult `Test-Heirloom-macOS-2026.09.16_14-13-31--0500`).
Passing (all `MacFunctionalTests`, all new WP4/WP6 sheet/page tests — genuine progress
vs Gate 3's 13/13 fail at the sidebar-render gate):
- `testMinimalToolbarOnMapPeopleMemories` (14 s)
- `testNewAlbumSheetCancelAndEscape` (18 s)
- `testNewSpaceSheetCancelAndEscape` (15 s)
Failing (10): all 3 `MacSmokeTests` (incl. `testSidebarAndGridRender`, 32 s — the known
environmental gate: window titles resolve, content empty) + 7 functional
(AddToAlbum, CameraImport, FavoriteTwo, ManageSpace, MoveSheet, SidebarTitles,
TrashNoReload). No test regressed from pass→fail (Gate 3 had zero passes); three moved
fail→pass. Main-thread runtime warnings persist (same class as Gate 3).

## Overall verdict: CONDITIONAL PASS

- Green: build (0 warnings), 174/24 unit tests, guards, bundle; logs clean both legs;
  UI 0→3 passing with no pass→fail regression.
- Missed on n=1 evidence: warm 4 microhangs vs ≤2; warm GridLoad 5.5 s vs ≤2.0 s;
  empty one 749 ms hang vs 0 ≥500 ms (empty GridLoad 3.9 s vs ≤4.0 s met narrowly).
  Single samples with server-dependent fetch variance (warm/empty inversion proves
  noise); the empty-run 749 ms hang coincides with VisionKit/LiveText frames in the
  profile — needs a second sample before calling it a code regression. Not comparable
  to Gate 3's 2-microhang re-gate (that trace missed launch entirely — no GridLoad).
- OWNER-HANDS remainder (unchanged): driven scenario B–H with screenshots; page
  budgets (switch ≤300 ms, select/favorite ≤16 ms, zoom ≤100 ms/step, sidebar ≤1 s,
  memory ≤700 MB); launch-budget re-sample under controlled server conditions;
  UI suite re-run on a quiet host (this run shared the machine with two 120–150 s
  Instruments recordings).
