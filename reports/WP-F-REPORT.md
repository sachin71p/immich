# WP-F Report — Timeline cache, query plans, launch path, filter pages, micro thumbnails

Branch `feat/heirloom-macos-f`, worktree `/Users/spatel/workspace/github/projects/immich-mac-f`
(base `4cc8db194`; TEST-PLAN red base `9b9bb7f2e` — the F-touched projection/migration
code is identical in both; red runs below executed pre-fix in this worktree).

## Outcome

All F1–F5 implemented red-to-green. `verify.sh core` 211/212 (sole failure is the
pre-existing WP1 102k DEBUG budget test flaking under parallel-suite load — it fails
on the unmodified base the same way, passes isolated with and without this WP),
`verify.sh mac-unit` **TEST SUCCEEDED**, iOS Simulator **BUILD SUCCEEDED**.
`mac-ui` / `mac-perf` were not run (device foreground is owned by the main session);
the exact commands are listed under Proof owed.

## What changed (by item)

**F2 — query plans, grid projection, mmap.**
`PhotosCore/Sources/LocalStore/Schema.swift` gains migration `v5_timeline_perf`:
denormalized `asset.projectionType` (backfilled from `assetExif`, guarded for
partial-schema DBs), covering partial `asset_timeline` (datetime-first, carries the
whole grid projection) plus lean `asset_timeline_{space,library,owner,type,favorite,
created,deleted}` variants and `albumAsset_on_albumId`. `LocalStore+Timeline.swift`
drops the `assetExif` join from `rowSelectSQL` (panorama arm now reads the
denormalized column); `LocalStore+Apply.swift` mirrors `projectionType` on every
`.assetExif` and repairs exif-before-asset ordering once per batch
(`reattachProjectionTypes` — a per-row probe measured 0.7 s/20 k applies and was
replaced; paired bench mine 3.12 s vs base 3.18 s per 20 k, i.e. zero write-path
delta). `LocalStore.swift` sets `PRAGMA mmap_size = 268435456` on every pool
connection via `Configuration.prepareDatabase`. `LocalStore+Browse.swift`
`albumAssets` is now an equi-JOIN (no IN-list materialization).
`LocalStore+Search.swift` adds its own explicit exif join only when an exif
predicate is present (pure column searches stay join-free).
Deliberate deviation: v5 `DROP INDEX asset_on_localDateTime`. Verified by EXPLAIN
probe — the narrow datetime index hijacked every grid ORDER BY into a non-covering
scan with one heap fetch per row; the migration is otherwise data-preserving and
idempotent (`IF EXISTS` + migrator tracking + partial-schema guards).

**F1 — snapshot cache.** New `PhotosCore/Sources/LocalStore/TimelineSnapshotCache.swift`:
keyed `(scope, filter, grouping, sort)` (plain strings), LRU-6, sync hits, dirty
marking vs scoped invalidation, memory-pressure purge. `MacGridLoader` serves hits
synchronously (clean hits: zero store I/O; dirty hits: render now, revalidate in
background), publishes fresh builds to the cache, and maps change-center events
(favorite/edited → dirty; removal → evict-all; albumsChanged → dirty only
notInAlbum keys). Emits `Library.Return`.

**F3 — launch.** `LaunchGate` (new, unit-tested): synchronous
serverURL + token-presence + persisted-userID decision. `MacAppState` persists the
user id on login/adopt, restores it synchronously (`restorePersistedSession`), and
revalidates without ever flashing connect (`revalidateSession` keeps the offline
session on network failure). `HeirloomMacOSApp` uses the gate. New
`TimelineDiskSnapshot`: compact `timeline-<scope>.bin` (ids, ratios, thumbhash,
kinds, dates, counts, versioned) saved after each build, served on cold miss inside
`Launch.FirstThumbnails`; version/corrupt/scope mismatch → rebuild. Both footers
show a spinner (`library-loading`) instead of "0 Photos" while loading.
`AXIDs.connectForm = "connect.form"` added to `MacConnectView`.

**F4 — filter pages.** Favorites/media/album/visibility/recents run fully SQL-side
through the F2 indexes (album rewritten as JOIN); loader emits `Page.FirstPaint`
for non-Library destinations; store row queries emit `Timeline.Query`.

**F5 — micro tier.** `MediaTier.micro` (rank below thumbnail, 64 px, thumbnail-bytes
viewSize, isolated fallback), new `MicroThumbnail` (13/21-column mosaic gate, 100 ms
velocity gate, CoreGraphics downsample + off-main wrapper), and
`MediaPipeline.prefetchMicro(items:velocity:)` for WP-G. No grid files touched.

## Red → green

| ID | test(s) | red on base | green now | notes |
|----|---------|-------------|-----------|-------|
| F2 | `TimelineQueryPlanTests` (6) | 4 fail pre-fix (exif join present, mmap 0, no `asset_timeline` in plans) | 6 pass | +1 ordering test added with fix (batch repair) |
| F4 | `filterQueriesUseIndexes` (in above) | 3 plan assertions fail pre-fix | pass | album JOIN shape |
| F1 | `TimelineSnapshotCacheTests` (8) | absent on base (new infra) | 8 pass | sync hit, scoped invalidate, dirty, LRU-6+recency, purge |
| F3 | `TimelineDiskSnapshotTests` (6) + `LaunchGateTests` (5, mac-unit) | absent on base (new infra) | 11 pass | round-trip, version/corrupt/scope rebuild paths, gate truth table, footer rule |
| F5 | `MicroThumbnailTests` (7) | absent on base (new infra) | 7 pass | mosaic levels, fallback isolation, 100 ms gate incl. boundary, downsample, cache isolation |
| F3 | `MacFunctionalTests.testSignedInLaunchNeverShowsConnect` (mac-ui) | n/a (new) | **owed to main session** | polls connect.form q16 ms × 3 s, footer-flash guard |
| F1–F4 | `HeirloomPerfTests` signpost tests (mac-perf) | were `XCTSkip` | implemented, **owed to main session** | corrected subsystem/category to `com.immich.heirloom`/`timeline` |

## Verification observed

- `PhotosCore swift test`: 212 tests — 211 pass; `wholeTimelinePerformance` (WP1 102 k
  DEBUG <1500 ms) fails only under full-suite parallel load (10–11 s) and passes
  isolated; the unmodified base fails it identically under load (7.7 s). Sandbox load
  was 12–18 throughout (parallel workers).
- `verify.sh mac-unit`: **TEST SUCCEEDED** (incl. 5 new `LaunchGateTests` and the
  20 s large-seed gate; one earlier 21.1 s run at load 18 traced to the since-removed
  per-row probe — paired bench shows zero remaining delta).
- `xcodebuild -scheme Heirloom-iOS -destination 'generic/platform=iOS Simulator' build`
  with `-derivedDataPath native-apple/.build-f/DerivedData` (since removed):
  **BUILD SUCCEEDED** (PhotosCore API source-compatible; only additive changes).

## Proof owed to the main session (exclusive foreground — not run here)

- `cd native-apple && ./scripts/verify.sh mac-ui` (runs
  `testSignedInLaunchNeverShowsConnect` + full functional suite).
- `cd native-apple && ./scripts/verify.sh mac-perf` on the large fixture
  (`-HeirloomFixture large`, Release, quiet host, median of 3): `Launch.FirstThumbnails`,
  `Library.Return` (≤150 ms), `Page.FirstPaint` (Videos, Screen Recordings, Family,
  shared album, ≤1 s), `Timeline.Query` (cold ≤1.5 s / warm ≤300 ms), plus the
  after-launch recording (no connect flash, no "0 Photos") and AFTER design-pair
  captures (`scripts/heirloom-parity/pairs.sh`).
- Before/after query-plan + timing table (cold/warm, median of 3) Tanner the owner DB
  copy: committed EXPLAIN assertions pin the after-plans; wall-clock medians need the
  quiet host.

## Risks / notes

- Timing gates (`wholeTimelinePerformance`, 20 s seed) are load-sensitive in shared
  sandboxes; both flaked here on base too. Re-run gates on a quiet host before
  treating a failure as a regression.
- `Page.FirstPaint` is co-owned with WP-P (its skip referenced WP-P); emission now
  lives in `MacGridLoader` — WP-P should assert, not re-emit.
- `Heirloom.xcodeproj/project.pbxproj` regenerated by xcodegen (required by the
  `project.yml` test-target addition); `Package.resolved` left untouched.
