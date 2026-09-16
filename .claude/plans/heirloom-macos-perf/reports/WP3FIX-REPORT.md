# WP3FIX — Gate-3 fix slice (sync reload, prefetch storm, launch signposts)

Branch: `perf/heirloom-macos-wp3fix` (worktree `../immich-wp3fix`), based on `7555a8991`.
Scope kept to the three tasked items in the five authorized files. No other source touched.

## Root cause (restated)

`MacAppState.syncNow()` bumped `timelineVersion` on every successful sync even with zero
applied changes → grid `reloadKey` changed → full `reloadData` → clip-view
`scrollBoundsDidChange` → `prefetchPass` re-issued hundreds of fetches → the next cycle
cancelled them (3,210 cancels in the Gate-3 trace) → main-thread completion bursts → hangs
(9 / 4.09 s / worst 1.14 s). 404 thumbnails had no negative cache, so every pass retried
them (138 404s for 899 ids idle) and error-logged each attempt (one id flooding dozens/ms).

## Change signal used (item 1)

`SyncCoordinator.syncWithResult()` → `SyncResult(didRun, appliedChanges)`. The signal is the
cheapest available: `flush()` now returns its applied `SyncChange` count and reset/mid-stream
`wipe()`s count as changes — no row diffs, no store-level journal. `syncNow() -> Bool` keeps
its contract (iOS `AppSession` untouched). `MacAppState.syncNow(userInitiated = true)` bumps
`timelineVersion` + `refresh()` only when `SyncResult.shouldReloadTimeline(userInitiated)`.
All current call sites (Sync button, `.macSyncNow`, launch task, login) are user-initiated, so
their behavior is unchanged; the timer path passes `false` when wired.

## Files and commits

- `PhotosCore/Sources/SyncEngine/SyncCoordinator.swift` — `SyncResult`, `syncWithResult`,
  `flush() -> Int`. Commit `3567a86b0`.
- `Apps/macOS/Sources/MacAppState.swift` — gated `syncNow(userInitiated:)`, signal documented
  on `timelineVersion`. Commit `031cc7301`.
- `PhotosCore/Sources/Media/MediaPipeline.swift` — 10-min negative cache for HTTP 400–499
  (classified through `DataLoader.Error.statusCodeUnacceptable` incl. the
  `ImagePipeline.Error.dataLoadingFailed` wrapper; 5xx/timeouts never held), consulted by
  `fetchTier` (the single choke point for prefetch + cell stream + person thumbnails);
  one throttled logging site (cancellations incl. `ImagePipeline.Error.cancelled` at debug;
  repeats collapsed to one error/id/minute); `PrefetchWindowTracker`. Commit `035d450d8`.
- `Apps/macOS/Sources/MacCollectionGridView.swift` — `prefetchPass` no-ops on unchanged
  settled window (window ids + snapshot generation). Commit `28f4ebba2`.
- `Apps/macOS/Sources/MacGridLoader.swift` — `GridLoad` around the load-task body,
  `SnapshotBuild` around the detached build, exact `HeirloomSignpost` names via a local
  signposter (same subsystem/category). Commit `28f4ebba2`.
- Tests: `PhotosCore/Tests/MediaPipelineTests.swift` (+5), new `PhotosCore/Tests/SyncResultTests.swift` (+4).

## Tests and build

- `swift test --package-path native-apple/PhotosCore`: **167/167 pass**, incl. 9 new WP3FIX
  tests (timer-no-change → no bump; user-initiated still reloads; applied reloads; dropped
  never reloads; classify matrix; 404 → repeat prefetch + stream issue zero network;
  5xx not held; cancelPrefetch keeps visible consumer at 1 request; tracker matrix).
- `make build-macos CONFIGURATION=Release`: **BUILD SUCCEEDED**.
- Pre-existing flakes (not mine, files untouched): `TimelinePerformanceTests` 102k/400ms and
  `TimelineGridSnapshotTests` 102k/60ms + `TimelineGridGeometryTests` 300-sections/1ms fail
  intermittently run-to-run; a full green 167/167 run was observed on the final tree.

## Deviations

- Signposts use a local `OSSignposter` with the exact `HeirloomSignpost` names rather than
  `HeirloomSignpost.interval()`: the helper's closures can't capture MainActor-isolated
  loader state under Swift 6 region isolation (build error observed and fixed).
- `cancelPrefetch(keeping:)` needed **no fix** — the visible refcount was already honored;
  the new test proves it (visible join survives `keeping: []`, still 1 network request).

## Open issues / findings for the orchestrator

1. `SyncCoordinator.startActiveTimer(interval: 30)` has **no caller anywhere in the tree**
   (macOS, iOS, Agent). The diagnosed 30 s timer chain does not exist in this checkout — the
   gate is in place for whenever it is wired (`userInitiated: false`), but the Gate-3 hangs'
   actual trigger should be re-confirmed on re-gate.
2. 401s take the 10-min negative hold like other 4xx. After a re-login the pipeline is
   rebuilt (hold cleared), but an in-place token refresh within the hold window stays
   suppressed. Consider exempting 401 if that flow matters.
3. Decode failures now flow through the generic throttled log as `nothingLoaded` instead of
   the old dedicated "decode failed" error line; the error value still distinguishes them.
4. No `--fixture-seed` iteration was needed (unit-test + build coverage only); re-gate on the
   owner's 102k library still required to confirm the hangs are gone.
