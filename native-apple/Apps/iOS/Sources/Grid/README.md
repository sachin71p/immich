# Grid (WP1) — the single grid component for W2

`AssetGridView` is the only grid every photo collection uses: Library All (WP2),
search results (WP5), albums/spaces (WP4), viewer filmstrip (WP3). W2 work packages
only *use* the three contracts below — they must not fork the controller or the cell.

## Contracts

- `AssetGridView` (SwiftUI) — data in, callbacks out. SwiftUI passes only small values
  (`columns` binding, `aspectFit`, selection model); all heavy state lives in the
  `LibraryGridLoader` (`@StateObject`) and the UIKit controller.
  - `source: AssetGridSource` — `.timeline(scope, granularity)` (one index query),
    `.ids([String])` (caller order kept: relevance, album), `.query(async closure)`
    (resolved to `.ids` before loading).
  - `columns: Binding<Int>` (parent-owned; pinch writes back through it),
    `aspectFit: Bool` (square cells stay; only the image content mode flips),
    `selection: GridSelectionModel?` (nil screens get an unused ephemeral instance —
    pass a persistent `@StateObject` model wherever selection UI exists).
  - `onOpen(ViewerRoute)`, `header: AnyView?` (album hero covers),
    `onRefresh` (pull-to-refresh), `onVisibleRange(first, last)` (title subtitles),
    `showsSectionHeaders` (false for All/search — the snapshot stays sectioned for
    diffing/scrubbing), `reloadToken` (bump to reload; timelines debounce, id lists
    reload immediately).
- `GridSelectionModel` (`ObservableObject`: `ids: Set<String>`, `isSelecting: Bool`) —
  shared truth between the controller and host screens. Main-thread confined by
  convention, deliberately not actor-isolated so view initializers can hold it.
- `ViewerRoute` (`Sendable`: `startId` + `@Sendable` index provider) — never an array
  copy per tap/update. The bridge builds it from the controller's immutable snapshot
  value at tap time; `resolveIds()` runs once per navigation (WP3 pages it lazily).

## Data flow

`PhotosLocalStore.timelineIndex` (one compact SQL query: id, date, flags, duration) →
detached `GridSnapshot.build` (sections of ids + index lookup + generation, `GridLoad` /
`SnapshotBuild` signposts) → `LibraryGridLoader` publishes (new generation only when
membership/order changed; flag-only changes refresh the row cache + reconfigure visible
cells) → `PhotoGridViewController` cheap setters (`applySnapshot` by generation via
diffable diffs, `setColumns`/`setAspectFit`/`setEditMode`/`setSelection` compare first).
Visible rows page through `assetsLite(ids:)` (`onNeedRows`); thumbhashes decode off-main
into `ThumbhashCache` (sync set on hit only); thumbnails prefetch by viewport proximity
with `cancelPrefetch(keeping:)` as the window moves.

## Files

- `AssetGridView.swift` — the component + `AssetGridSource` + the representable bridge.
- `PhotoGridViewController.swift` — setters, fixed square layout (1 pt gaps, no
  estimates), pinch steps `[1, 3, 5, 9, 13]` with anchor preservation, drag-select,
  pull-to-refresh, `FastScroller` wiring, `grid-perf-summary` hook.
- `PhotoGridCell.swift` — manual `layoutSubviews`, neutral fill → thumbhash →
  thumbnail stack, SF Symbol badges (`heart.fill` bottom-left, duration bottom-right
  via shared `VideoDurationFormat`, `person.2.fill` top-right), circle/check selection
  above the art. No live badge: there is no "Show" option yet (see report).
- `GridSnapshot.swift` — immutable reference-typed snapshot (O(1) publish), UTC
  integer bucketing/titles (no per-row `DateFormatter`), `bubbleTitle` for the scroller.
- `ThumbhashCache.swift`, `FastScroller.swift`, `GridStallMonitor.swift`,
  `GridSelectionModel.swift`, `ViewerRoute.swift` — as named.
- `PhotoGridView.swift` — interim pre-WP1 shim (Library model → setters). Removed in
  WP1 step 9; W2 must not use it.

## Perf notes (see `reports/WP1-REPORT.md` for numbers)

- Nothing O(rows) on the main actor or in a SwiftUI `body`: index decode + grouping are
  detached; publishing compares by snapshot generation; selection diffs against
  `indexPathsForSelectedItems`.
- No `DateFormatter`/`NumberFormatter` per call on hot paths (static month tables,
  integer formatting, shared duration formatter, cached symbol configs).
- `-gridPerfRun` starts the stall watchdog; the `grid-perf-summary` AX value carries
  `stalls / maxStall / firstPaint / gridLoad / snapshotBuild / snapshotApply /
  layoutPrepare` for the flick-scroll UI test.
