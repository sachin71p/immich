# WP2 Report — App grid data flow (snapshot loader, main window, change notifications)

Branch: `perf/heirloom-macos-wp2` (worktree `/Users/spatel/workspace/github/projects/immich-wp2`).
Brief: `WP2-LOADER.md`. Steps 1–3 by the prior implementer session; Steps 4–5 here.
Step 1–3 facts below are derived from `git log` + the code as built.

## Commits (all `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`)

| Step | SHA | Message | Files |
|---|---|---|---|
| 1 | `15aab149f` | `refactor(macos): split MacGridView into loader, grid view, cell` | MacGridView.swift → MacGridLoader.swift / MacCollectionGridView.swift / MacGridCell.swift (+ xcodegen regen churn, see Step 2 note) |
| 2 | `ad7e95a1a` | `feat(macos): add MacAssetChangeCenter and post mutations from main window` | new MacAssetChangeCenter.swift; mutation sites in MacMainWindow.swift post (reload stayed until Step 4) |
| 3 | `7f1cdf3d3` | `feat(macos): snapshot loader with generation-gated detached builds` | MacGridLoader.swift rewritten around `TimelineGridSnapshot` (legacy computed readers kept as compat) |
| 4 | `7e59ae4` | `feat(macos): WP2 Step 4 — main window reads snapshot, grid pane, change-center mutations` | MacMainWindow.swift, MacAppState.swift, MacGridLoader.swift, MacViewer.swift |
| 5 | `012858b` | `feat(macos): WP2 Step 5 — interim grid reads snapshot, row-based cell loads` | MacCollectionGridView.swift, MacGridCell.swift, MacSearchView.swift |

Note: the Step 4 commit alone does not build (`MacTimelineGridPane` references the
Step 5 grid inputs); Steps 4+5 are one buildable unit split across two commits for
review. A pure per-step-green sequence was not possible because the pane and the grid
change inputs in lockstep.

## What changed per step

**Step 1 — split (from log/diffstat).** `MacGridView.swift` (mechanical move, no behavior
change) into `MacGridLoader.swift` (`MacGridSection`, loader, `chunked`), `MacGridCell.swift`
(`MacThumbnailContainerView`, `MacGridCell`), `MacCollectionGridView.swift`
(`MacKeyCollectionView`, grid view + Coordinator, `Array[safe:]`, weak boxes, drag-prefetch
usage). `MacGridView.swift` deleted; project regenerated with xcodegen (regen churn landed
inside the Step 2 commit).

**Step 2 — change center (from log + code).** New `MacAssetChangeCenter.swift`: `@MainActor`
typed fan-out (`favorite` / `removedFromCurrentContexts` / `edited` / `albumsChanged`) over
`AsyncStream`, with posting a no-op when there are no subscribers. Mutation sites post on
success. No subscriber was wired until Step 4.

**Step 3 — loader (from log + code).** `MacGridLoader` publishes `snapshot:
TimelineGridSnapshot` (class → O(1) identity compare) + `phase` + `lastPatch`, keeps
`source`/`presentation`/tasks/generation `@ObservationIgnored`. `load` fetches with the WP1
single-transaction row queries (timeline buckets + `timelineRows`; `albumAssets` for albums),
builds the snapshot in `Task.detached(.userInitiated)`, assigns only if un-cancelled and
generation-current. Cancellation (incl. `URLError.cancelled`) is silent and keeps the
snapshot; other errors set `phase = .failed` via `HeirloomLog.timeline`. Destination change
clears to `.empty`; grouping/switcher/sync reloads keep the old snapshot. `setPresentation`
rebuilds off-main from a value-copied `@Sendable` predicate (edited → `row.isEdited`,
capturedByMe → `ownerId == userId`, notInAlbum → membership set). `apply` uses the WP1
`patching`/`removing` contract and evicts memory-cache entries on edit.

**Step 4 — main window (this session).**
- Deleted: `displayedSections`, `displayedRowIds`, `libraryDateRange`, `matchesQuickFilter`,
  per-row `dateString`/`rowDateFormatter`, the footer's `flatMap`/`filter` passes, and the
  per-album `assetIds(inAlbum:)` loop (one SQL query per album → gone).
- Footer reads `snapshot.photoCount`/`videoCount`; subtitle reads `snapshot.dateRange` with the
  existing static `dateRangeFormatter`.
- `store.assetIdsInAnyAlbum` is fetched only while `.notInAlbum` is active, else `nil`.
- `.onChange(of: timelineOrder/quickFilters)` → `setPresentation` via a cancellable
  `presentationTask`, so a slow membership fetch can never apply stale filters.
- `reloadKey` = destination + grouping + switcher + `state.timelineVersion`; `spaces.count` /
  `albums.count` removed. `timelineVersion` is new on `MacAppState`, bumped after every
  **successful** `syncNow` — `SyncCoordinator.syncNow()` returns `true` on any completed
  session (it only reports a dropped concurrent call, not a change count), so there is no
  "applied changes" signal to key off; documented on the property. Explicit `reload()` calls
  after `syncNow` were removed everywhere in this file; the key change re-runs `.task(id:)`.
- New `MacTimelineGridPane` (loader, pipeline, store, exporter, itemSize, square flag,
  selection mode + binding, sync text, callbacks): error banner, grid, footer. Toasts/hover/sync
  state no longer re-evaluate the grid; `MacLibraryBrowser.body` never touches
  `loader.snapshot.rows` (only O(1) `dateRange`/`photoCount` reads in subtitle/footer… the
  subtitle lives outside the pane; it reads `dateRange` only).
- Mutations (`toggleFavorite`/`trash`/move/add-to-album) post `MacAssetChange` with no reload;
  favorite reads current state from `snapshot.rows[snapshot.indexById[id]]` (store fallback only
  when the id is absent). A view-owned `.task(id: selection)` subscribes and applies changes
  with the current destination. Move-sheet posts `removed` only for `.moved` results.
- `viewerContext` is now `TimelineGridSnapshot?`; `openViewer` / New Viewer Window assign
  `loader.snapshot`. `MacViewer` finds the index via `indexById` and clamps (U7 display-order fix).
- Error banner: `loader.phase == .failed` as a compact inline banner with Retry; cancellation
  never shows; old `loader.error` red text removed. Spinner appears only past 150 ms of loading
  with an empty snapshot.
- Selection retarget: keeps only ids present in `snapshot.indexById` (O(selected)); display order
  refreshes from `snapshot.ids` at navigation frequency (see deviations).

**Step 5 — interim grid (this session).**
- `MacCollectionGridView` inputs are now `snapshot` / `lastPatch` / `pipeline` / `store` (+
  existing exporter/itemSize/square/selection/callbacks). `sections`, `assetsById`, `rowDates`
  deleted. `MacGridSection`, the legacy loader readers, and `chunked` are deleted with them.
- `updateNSView`: generation change → `reloadData`; else `lastPatch.revision` change →
  `reloadItems(at:)` in section 0; selection sync diffs through `indexById` and skips the write
  when the set is unchanged.
- `sizeForItemAt` uses `row.aspectRatio` (width/height; `height = itemSize / ratio`, same clamp
  as before), no dictionary lookup.
- Cells load via `pipeline.stream(id:thumbhash:tier:.thumbnail, edited:)` from the row, with a
  synchronous `cachedImage`-then-`cachedPlaceholder` probe first — the permanently-blank-cells
  fix (R1). `prepareForReuse` sets `borderColor = NSColor.clear.cgColor`, never `nil` (R10 minimal).
- Drag export resolves `Asset`s via `store.assets(ids:)` in `draggingSession(willBeginAt:)` into
  a fileName map (+ asset map for the bounded synchronous fallback); type-to-jump uses
  `snapshot.dayKeys`; Quick Look falls back to the store fetch (already did).
- `MacSearchView` (compile-necessary call-site update): builds a per-query result snapshot
  (fresh generation so the grid reloads) and passes the new inputs; its local `assetsById` was
  renamed `assetMap`; `openViewer` assigns the result snapshot; now-dead `dateString` removed.
- TimelineOrder: no work needed — Steps 2–3 had already unified on CoreModel's
  (`MacSidebarModel` holds only an `Equatable` extension; the app copy is deleted). PhotosCore
  untouched.

## Test output

- `make build-macos CONFIGURATION=Release`: **BUILD SUCCEEDED** (this session, after Steps 4+5).
- `swift test --package-path native-apple/PhotosCore`: **158 tests in 21 suites passed**.
- Acceptance grep `assetsById|allRowIds|displayedSections|flatMap(\.rows)` over
  `native-apple/Apps/macOS/Sources`: **clean** (one comment hit reworded to keep it clean).
- `profile.sh wp2 90` + hands-on checks (acceptance §3–4): **not runnable here**. `profile.sh`
  requires the installed app (`make install-macos` — forbidden to this WP) and a scripted
  hands-on driving session (launch, grouping ×3, scroll, select 5, favorite/unfavorite), which
  needs computer-use. Left to WP7; expect no ≥1 s hang, with flow-layout microhangs possibly
  remaining until WP3.

## Deviations from the brief

1. Step 4/5 commits are not independently green (pane + grid change inputs in lockstep); the
   pair builds and both carry the co-author trailer.
2. `setPresentation` early-returns on unchanged input (loader `Presentation` is now
   `Equatable`). The brief's reload path re-syncs presentation before every load; without the
   guard each reload would spawn a redundant rebuild (discarded by generation gating, but
   wasted CPU at 102k rows).
3. Selection retarget keeps one O(rows) `snapshot.ids` map at navigation frequency to refresh
   `GridSelectionModel.orderedIds` (needed for `selectedInOrder`/shift-extend correctness);
   the membership trim itself is O(selected) per the brief. Rebuilding `orderedIds` without any
   O(rows) pass would require editing `MacSelection.swift`, which WP4 owns.
4. Spinner has the specified 150 ms delay (implemented in the pane, not the loader).
5. Search's `onSelectionChange` stays `{ _ in }` (pre-existing behavior) and its snapshot build
   runs synchronously in `setResults` — result sets are bounded query pages, not the 102k timeline.

## Open issues (for WP3/WP4/WP5/WP7)

- Flow-layout O(n) layout with 102k items remains (R3) — WP3's custom layout replaces it;
  microhangs may persist until then.
- `applyPresentation` cancellation covers the membership fetch; a still-in-flight fetch that
  ignores cancellation resolves harmlessly via the post-fetch `isCancelled` guard.
- Sort/filter changes via `setPresentation` leave `GridSelectionModel.orderedIds` in the
  previous order until the next reload (same as pre-WP2 behavior for order flips); selection
  membership stays correct.
- Drag-out before the store fetch completes falls back to the id as the file name and skips
  prefetch for that drag (bounded sync fallback still applies once assets resolve).
- WP7 must verify: thumbnails ≤3 s post-launch, no red error text on grouping switches,
  `profile.sh wp2 90` summary, and the Gate 2 blank-grid check.
