# Heirloom macOS — static diagnosis (Opus, verified by reading code)

Library scale: 100k+ assets (per MacGridView.swift comment). All below are O(n) over the full library.

## Confirmed hot paths

### A. SwiftUI body does multiple full-library passes per evaluation (MacMainWindow.swift)
Any state change that re-evaluates `MacLibraryBrowser.body` (selection change, hover, toast, sync flag) runs:
- `displayedSections` (~L502): filter every row + optional reverse copy. Referenced more than once → recomputed each time.
- `displayedRowIds` (~L513): flatMap of the above (another full pass).
- `libraryDateRange` (~L495): flatMap all rows + min + max. Used by `librarySubtitle` → recomputed on each selection change.
- `footer` (~L574): flatMap + 2 filters over all rows.
- `matchesQuickFilter` looks up `loader.assetsById` per row.
=> clicking a thumbnail (selection change) costs ~6+ passes over 100k rows on main thread.

### B. NSViewRepresentable.updateNSView does O(n) work every SwiftUI update (MacGridView.swift)
- `reloadIfNeeded` (~L456): `sections.flatMap` to build a 100k [String] and compares to `flatIds` (string array equality).
- `syncSelection` (~L494): `flatIds.indices.filter { selectedIds.contains }` — full pass per update.
- `MacGridLoader.allRowIds` (L27) is a computed flatMap, called on openViewer / reload / retarget.

### C. Layout: NSCollectionViewFlowLayout, single section of 100k+ items, variable heights
- `sizeForItemAt` (~L573) called for every item on every layout invalidation (dictionary lookup of full `Asset`).
- Flow layout computes all item frames synchronously → multi-second hang at launch, on pinch/zoom (`applyItemSize` → invalidateLayout), and on each reloadData.
- `numberOfSections` = 1, so the loader's month/year sections are not rendered as headers.
- estimatedItemSize attempt caused recursion (comment L365).

### D. Data loading
- `MacGridLoader.load` loads full `Asset` records for every row (`assetsById`), in chunks — memory + time proportional to library.
- `reload()` (MacMainWindow ~L610) after every mutation (favorite, trash): full timeline refetch + one `assetIds(inAlbum:)` query per album, sequentially → reloadData → full layout again. So favoriting one photo = full-library reload + multi-second layout.

### E. Thumbnails
- One unstructured Task per cell, no prefetching; cancellation only in prepareForReuse.

### F. Stubs
- `gridActions.rotate: {}` (MacMainWindow ~L646) — menu Image > Rotate does nothing from the grid; toolbar Rotate only shows a toast.

## Direction (to be confirmed by profiling)
1. Custom `NSCollectionViewLayout` (justified/square grid) with layout computed once off-main into flat arrays; `layoutAttributesForElements(in:)` via binary search over row offsets; month section headers as supplementary views. Width/size change recomputes in O(n) off-main with cheap Float math (no dictionary lookups: carry aspect ratio in TimelineRow).
2. Move all derived collections (displayed sections, flat ids, date range, counts, index maps) into `MacGridLoader` as stored properties recomputed only when inputs (rows, filters, order) change.
3. updateNSView: compare a generation counter instead of flatMapping ids; selection sync via id→index dictionary, only diff changed ids.
4. Mutations: patch rows in place (favorite flag) + `reloadItems(at:)`; trash = delete items; no full reload. Album membership set computed in one SQL query.
5. Lazy `Asset` fetch (only for visible/selected/viewer), not all 100k upfront.
6. Thumbnail prefetch via `prefetchItemsAt`-equivalent on visible-rect change; neighbor preloading in viewer.
