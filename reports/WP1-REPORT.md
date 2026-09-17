# WP1 report — grid engine (branch `feat/heirloom-ios-wp1`)

## Commits

- `bd87c1f32` `feat(core): timeline index, bucket summaries, year granularity`
- `24f52fc95` `feat(ios): generation-gated grid loader over the timeline index`
- `c5a5feecf` `perf(ios): square grid layout, cheap render setters, new cell, scroller`
- `f29773a4e` `feat(ios): AssetGridView plus GridSelectionModel and ViewerRoute contracts`
- `28fde2682` `feat(ios): LibraryView and SearchView onto AssetGridView, drop interim grid`
- `8e81920bf` `perf(ios): flick-stall fixes and synchronous first-paint delivery`
- this report (`docs`, next commit)

## Public API for W2 (`Grid/README.md` is the contract doc)

- `AssetGridView(source:store:pipeline:columns:aspectFit:selection:onOpen:header:onRefresh:onVisibleRange:showsSectionHeaders:reloadToken:)`.
  Sources: `.timeline(scope, granularity)`, `.ids([String])` (order kept),
  `.query(@Sendable async closure)` (resolved to ids, then loaded).
- `GridSelectionModel` (`ObservableObject`: `ids`, `isSelecting`; main-confined, not
  actor-isolated so view inits can hold it).
- `ViewerRoute` (`Sendable`: `startId` + `@Sendable` provider; `resolveIds()` once per
  navigation). The bridge builds it from the controller's tap-time snapshot value —
  never an array copy per tap or per update.

## L14 root cause (confirmed, fix already on this branch)

Server `duration` is integer **milliseconds**
(`server/.../1777667825574-ChangeDurationToInteger.ts`, `sync.dto.ts:101`).
`WireTypes.swift` stored it verbatim as `durationSeconds` (1000× too large — the
`1249:26`-style badges in `03-audit.md:60–61`, plus the `m:ss`-only formatter dropping
hours). Landed before WP1: ms→s mapping in `WireAsset.model`, one-shot
`v4_asset_duration_ms_to_s` migration (stale rows converge; old migrations untouched),
shared `CoreModel.VideoDurationFormat` (`m:ss` < 1 h, `h:mm:ss` ≥ 1 h, `0:01` floor),
`DurationFixTests`, grid badges reuse the formatter. Badge-on-photo cells from the audit
were a classification gap, now closed: badges derive from the SQL media-kind
projection + index flags, never from drumbeat heuristics in the cell.

macOS note (no macOS files touched): macOS shares the bug path through PhotosCore —
`WireAsset` mapping and the v4 migration fix it there too on next sync/migrate. macOS
has no badge formatter of its own.

## What changed (plan steps 1–9)

1. **Timeline index** (`LocalStore+TimelineIndex.swift`, additive): `timelineIndex`
   (one query: id, julianday date, six flag bits, duration), `bucketSummaries`
   (windowed: count, favorite-preferring key asset, date range; year/month/day),
   `assetsLite(ids:)` (500-chunk visible paging, input order kept). `Granularity.year`
   added; `TimelineRow.originalFileName` added (defaulted — macOS/iOS call sites
   unaffected) for real media-format classification.
2. **L14**: verified landed (above), no new migration needed.
3. **Loader**: publishes immutable `GridSnapshot` + `isLoading` only. Index + grouping
   detached (`GridLoad`/`SnapshotBuild` signposts + wall-time mirrors); generation
   gating (newer cancels older, silent); sync bumps debounce (leading + one trailing
   per 2 s); identical re-queries never republish; first window pages via `assetsLite`.
4. **Layout**: always fixed square (`1/columns` both axes, 0.5 pt insets = 1 pt gaps),
   no estimates, no-headers mode; pinch `[1,3,5,9,13]` animated with anchor kept;
   `LayoutPrepare` signposts. All defaults to 5 columns; Days removed.
5. **Render**: comparing setters only (snapshot by generation through diffable diffs;
   edit-mode/selection reconfigure in place; selection diffs
   `indexPathsForSelectedItems`). Subtitle uses one static `DateFormatter`.
6. **Cell**: manual `layoutSubviews`; `secondarySystemFill` base; off-main thumbhash
   `NSCache` (sync set on hit only); SF Symbols (`heart.fill` BL, duration BR,
   `person.2.fill` TR); circle/check selection above art; loads cancelled on reuse.
   No live badge: no "Show" option exists yet — flagged for WP2's View Options menu.
7. **Scroller**: UIKit edge pill + glass date bubble; rotated `Slider` deleted;
   prefetch ordered by viewport proximity with `cancelPrefetch(keeping:)`.
8. **Component + README** (above). First-paint delivery does not rely on
   SwiftUI's async update pass alone: `GridBridge` subscribes to the loader's
   `$snapshot` and applies synchronously on publish (generation guard dedupes
   against `updateUIViewController`); loader stamps `lastFirstPaintMs` *before*
   the assignment so the synchronous subscriber reads settled timings.
9. **LibraryView** on `AssetGridView` (visible-range subtitle, token = timelineVersion,
   no Days/Square/Slider); **SearchView** on `.ids` (relevance order kept, no asset
   hydration); interim `LibraryGridModel`/`PhotoGridView` shim deleted.

## Numbers (simulator; device gate owns the budgets)

- `swift test --package-path native-apple/PhotosCore`: 171 tests / 23 suites green
  (incl. 4 new `TimelineIndexTests`: flags/order/duration, summaries/key-asset/ranges,
  paging, 150k-row index build).
- `make build-ios`: BUILD SUCCEEDED. `bash native-apple/scripts/verify.sh ios`:
  **TEST SUCCEEDED** — A3 smoke, A9 extras, GridPerf ×2, ScreenshotTour, Sync ×2,
  all passed on iPhone 17 Pro Max simulator.
- Perf UI test (`GridPerfUITests`, `-fixtureSeedCount=100000` + `-gridPerfRun`),
  full-gate run: `firstPaint=984ms` (budget 1500), `gridLoad=965ms`,
  `snapshotBuild=272ms`, `snapshotApply=219ms`; stall gate green with zero
  post-settle marks (`stalls=5 maxStall=110ms` overall, all five marks before the
  settle watermark at ping 664 — shader/compile + first-window costs the gate
  windows out by design).
- Viewer open (default fixture): test PASSED. The `VIEWER PRESENT` print reads
  ~1.1–1.4 s on the simulator because it includes ~1 s of XCUI tap synthesis; the
  gate itself measures presentation after the tap returns against the 250 ms budget
  (device-Release owns the real number).

## Perf fixes inside the gate (all WP1-owned, no contract change)

- Animated diffs apply only to small updates on a live grid (≤2000 ids); the 100k
  first paint applies non-animated (animated 100k diffs wedged main for minutes).
- Cell: SF-symbol images rasterized once (per-cell creation summed to ~105 ms
  bursts); fixture-art decode already off-main; the triple memory-cache warm now
  also runs off-main (completions flooding main showed up as scroll stalls).
- Perf hook (`-gridPerfRun` only): the AX `layoutChanged` nudge posts on quiescent
  moments/force only — mid-fling posts re-snapshot a 110k-item AX tree on main.
- No-paint flake, root-caused via sim-log tracing: seed (110k rows, ~16 s) and load
  both completed, but no SwiftUI update pass ever delivered the published snapshot
  to the VC (app alive, main responsive, zero cells for 300 s+). Fix is the
  synchronous `$snapshot` subscription above; it also covers any future lost update
  since nothing re-renders a quiescent grid. Pre-existing double fixture-seed on
  back-to-back activations (two in-memory stores, last wins, both valid) left alone
  — benign, out of WP1 scope.
- Gate hygiene that kept biting: run one `xcodebuild` at a time (a lingering
  packager + a fresh runner fight over install/launch and produce empty-grid
  runs), one simulator booted, no manual `simctl` launches mid-gate (`simctl`
  argv does not reach the app the way XCTest injection does).

## Deviations / flags for W2 + Gate 1

- Viewer still takes an id array (`ViewerRequest` from `route.resolveIds()`); WP3's
  pager consumes the route lazily. 100k-viewer paging is WP3's problem, not WP1's.
- No item-count source for the "12,165 Items" footer — proposed: `loader.snapshot.count`
  surfaced via `onVisibleRange`-style callback in WP2 (5 lines).
- `GridSelectionModel` is main-confined by convention, not `@MainActor`-isolated
  (view-init ergonomics); all current writers are main-actor bound.
- 150k PhotosCore perf test asserts the 400 ms budget only on `-c release` runs
  (1500 ms under DEBUG, same convention as the existing 102k test).
