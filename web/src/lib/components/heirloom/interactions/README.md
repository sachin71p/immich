# Heirloom V2 interactions (WP6)

Keyboard / selection / drag-drop glue over the read-only `heirloom/timeline`
grid. The grid itself is never edited — modifier clicks are intercepted in the
capture phase, tiles are marked `draggable` lazily, focus is tracked via
`focusin`.

## Files

- `selection-model.ts` — plain-TS selection state (single / toggle /
  Shift-range from anchor / select-all / clear / flat-delta arrow moves).
- `keyboard-controller.ts` — `TypeAheadBuffer` (1 s reset), `findDateMatch`
  (matches `YYYY[-MM[-DD]]` prefixes of `localDateTime`), `describeGridKey`
  (Cmd/Ctrl+A, Escape, Return, Space; arrows + type-ahead keys are routed by
  the caller).
- `HeirloomGridInteractions.svelte` — glue: wraps `V2SquareTimeline` with the
  model, `V2SelectionToolbar`, drag-out payload, file-drop delegation, and
  service-backed Download / Move. Props `onOpenAsset` (required),
  `onPreviewAsset` (Space falls back to open when absent), `onAddToAlbum` /
  `onFavorite` / `onDelete` (buttons omitted when absent — no inert controls).
- `V2SelectionToolbar.svelte` — count + working buttons only.
- `V2DropTarget.svelte` — drag mechanics + `data-drop-state` visuals for
  sidebar/collection targets. File drags pass through unless `onFilesDrop` is
  set, so the global `UploadCover` stays the default file-drop owner.
- `../heirloom/drag-drop.ts` — internal payload (`application/x-heirloom-assets`:
  `{version, assetIds, ownerIds, source}`) + `decideAssetDrop(payload, target,
  computeMoveTargets(...))`. Album → add; personal/space/library → move only
  when allow-listed; same-container and upload-path-less libraries reject with
  a reason the UI shows.

## Consumers

- Grid pages (WP9): render `HeirloomGridInteractions` with `dragSource`
  (`{type:'personal'}` / `{type:'space',id}` / …) and route callbacks.
- Sidebar/collection targets (WP4/WP7): wrap rows in `V2DropTarget`,
  compute `state` via `decideAssetDrop`, perform album adds with
  `addAssetsToAlbums([id], assetIds, {notify:true})`.

## Deferred

Marquee (rubber-band) selection is out of scope here; the model supports the
range primitive (`extend`) when a marquee owner lands.
