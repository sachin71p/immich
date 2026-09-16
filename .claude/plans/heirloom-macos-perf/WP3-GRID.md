# WP3 — Collection view: custom layout, headers, coordinator, cells, black-border fix, prefetch, context menu

Read `PLAN.md` first. **Prerequisite:** WP2 is merged (read `reports/WP2-REPORT.md`). Fixes R3 and R10,
the scroll side of R9, U4, U6, U10 and U14.

Owned files (exclusive):
- `Apps/macOS/Sources/MacCollectionGridView.swift`
- `MacGridCell.swift`
- new `MacTimelineLayout.swift`
- new `MacGridHeaderView.swift`

The inputs WP2 defined for `MacCollectionGridView` are the contract. You may add parameters with
defaults, but don't remove or rename existing ones without updating `MacTimelineGridPane` in
`MacMainWindow.swift`; if you need that, coordinate by reporting it rather than editing.

## 1. Layout — `MacTimelineLayout: NSCollectionViewLayout`
- Set by the coordinator: `snapshot` and `targetItemSide`, from the zoom slider and pinch.
  `aspectFit: Bool` doesn't affect geometry.
- `numberOfSections == snapshot.sections.count`, and items per section `== section.range.count`.
  Empty-range `.year` sections render only their header.
- `prepare()`: build `TimelineGridGeometry` (WP1) **only** when width, targetItemSide or
  snapshot.generation changed. The cost is O(sections).
- `layoutAttributesForElements(in:)`:
  - `geometry.sections(intersecting:)`, then header attributes (kind `.year`/`.month`) and
    `geometry.items(in:intersecting:)` → item attributes.
  - Reuse attribute objects from a dictionary cache cleared on prepare-with-change.
  - Must be O(visible).
- Implement `layoutAttributesForItem(at:)`,
  `layoutAttributesForSupplementaryView(ofKind: NSCollectionView.elementKindSectionHeader, at:)`,
  `collectionViewContentSize`, and `shouldInvalidateLayout(forBoundsChange:)`, which returns true when
  the width changes or when pinned headers need updating (below).
- **Pinned month header** (Photos-style): the header of the section at the top of the viewport sticks,
  with y = clamp(visibleRect.minY, sectionTop, sectionBottom − headerHeight).
  - Use an `NSCollectionViewLayoutInvalidationContext` that invalidates only supplementary elements on
    scroll. Don't re-prepare the geometry.
  - If this produces any hitch ≥ 50 ms in WP7, put pinning behind a `static let pinsHeaders` flag,
    set it false, and report.
- **Zoom anchoring**: when `targetItemSide` changes:
  1. Record the anchor: `geometry.indexPathNearest(y: visibleRect.minY + 1)`, plus the offset of that
     item's top from `visibleRect.minY`.
  2. Invalidate, then `layoutSubtreeIfNeeded`.
  3. Scroll so the anchor item sits at the same offset.

  Pinch and `+`/`−` must feel continuous. Clamp targetItemSide to 64…400, and quantize pinch changes to
  ≥ 4 pt steps to avoid thrashing.

## 2. Header view — `MacGridHeaderView: NSView, NSCollectionViewElement`
- Register it for `NSCollectionView.elementKindSectionHeader`.
- Month: "September 2025", `.systemFont(ofSize: 17, weight: .semibold)`. Year: "2025", 28 pt bold.
- Leading inset matches the grid inset (8 pt), vertically centered. `NSVisualEffectView` background
  (`.headerView` material) only while pinned; otherwise transparent.
- Frame-based layout (no Auto Layout).

## 3. Coordinator — `MacCollectionGridView.Coordinator`
- Data source: `numberOfSections`, `numberOfItemsInSection` and item/supplementary views all come from
  the snapshot. Map IndexPath ↔ flat index via `snapshot.flatIndex(section:item:)` and
  `sectionAndItem(forIndex:)`.
- `updateNSView`:
  - generation changed → set `layout.snapshot`, `reloadData()`, then reapply the selection;
  - `lastPatch.revision` changed → `reloadItems(at:)` only for the patched indexes currently in
    `indexPathsForVisibleItems()` (others will configure fresh);
  - itemSize changed → the zoom path above;
  - selection → a diff through `indexById`.

  Nothing in `updateNSView` may be O(rows).
- **Selection (U6)**: a single click selects, with native ⌘/⇧ extend. Clicking empty space deselects.
  Double-click and Return open; Space opens Quick Look; Esc clears the selection.
  `isSelectionMode` now only shows a checkmark badge on selected cells, as Photos does.
  `allowsMultipleSelection = true` and `isSelectable = true` always. Keep `onSelectionChange` semantics
  (ordered ids).
- **Hover**: one `NSTrackingArea` on the collection view (`.mouseMoved`, `.activeInKeyWindow`,
  `.inVisibleRect`). The coordinator maps the point to an index path and toggles hover on at most two
  cells. Remove the per-cell tracking areas in `MacThumbnailContainerView`.
- **Prefetch**:
  - Observe the clip view's `boundsDidChangeNotification`, with `postsBoundsChangedNotifications = true`.
  - Throttle to 50 ms. Estimate velocity in screens/s.
    - If velocity > 4, prefetch only thumbhash placeholders (`pipeline.placeholder`) for the upcoming
      1 screen, and defer network work.
    - When velocity < 4, or 120 ms after scrolling stops, call
      `pipeline.prefetch(items for visibleRect expanded 1.5 screens in scroll direction and 0.5 behind, tier: .thumbnail)`
      and `pipeline.cancelPrefetch(keeping:)` for that window's ids.
  - Sign-post `Prefetch`.
- **Type-to-jump**: keep the behavior, using `snapshot.dayKeys` (binary search is possible since order
  is known; a linear `firstIndex` is acceptable only because it runs on keypress), then
  `sectionAndItem`.
- **Context menu** (new): override `menu(for:)` on `MacKeyCollectionView`, or set `collectionView.menu`
  with `NSMenuDelegate` `menuNeedsUpdate`.
  - Right-click on an unselected item selects it first.
  - Items, built from the existing `MacAssetActions` fields passed in as a new optional parameter
    `actions: MacAssetActions?`: Open (`openViewer`), Quick Look (`preview`), Get Info
    (`toggleInspector`), Favorite/Unfavorite (`favorite`), Rotate Clockwise (`rotate`), Add to Album…
    (`addToAlbum`), Move to… (`move`), Delete (`trash`, destructive, with a separator before it).
  - Disable an item when its closure is known to be a no-op. Report which, if any.
- **Drag & drop**: keep WP2's behavior.

## 4. Cell — `MacGridCell` (rewrite; this is the black-border fix)
Root cause, verified: `prepareForReuse()` assigned `layer.borderColor = nil` while
`layer.borderWidth = 4`. CALayer renders a nil borderColor as opaque black, so every recycled cell got a
thick black frame. The `isSelected` didSet early-returned when the state was unchanged, so nothing
repaired it. WP2 patched the nil assignment; now remove the mechanism entirely.
- **No Auto Layout inside the cell.** Use a frame-based `layout()` override. `MacThumbnailContainerView`
  keeps `wantsLayer = true`, `layerContentsRedrawPolicy = .never`, and **`borderWidth = 0` always**.
- Image: a sublayer `imageLayer: CALayer`, not `NSImageView`.
  - `contents = CGImage`.
  - `contentsGravity = .resizeAspectFill` (square mode, Photos default) or `.resizeAspect` (aspect-fit
    mode, on a `NSColor.quaternaryLabelColor` background).
  - `masksToBounds = true`, `cornerRadius = 0`.
  - `contentsScale = window backingScaleFactor`.
  - Disable implicit animations: an actions dictionary with `NSNull()` for `contents`, `bounds` and
    `position`.
  - Placeholder background while loading: `quaternaryLabelColor`.
- Selection overlay: `selectionLayer: CALayer` with `borderWidth = 3`,
  `borderColor = controlAccentColor.cgColor` (always non-nil), and background accent at 12% alpha.
  Visibility comes from `isHidden = !(isSelected || highlightState == .forSelection)`, updated in the
  `isSelected` and `highlightState` didSets **without** early return.
  `prepareForReuse` sets `isHidden = true` and **never assigns nil colours**. When the appearance
  changes (`viewDidChangeEffectiveAppearance`), refresh the accent CGColor.
- Badges, as lightweight layers (`CATextLayer` with a cached font, `CALayer` with a template SF Symbol
  image rendered once and cached per symbol+scale):
  - bottom-right: video duration `m:ss` from `row.durationSeconds`, white 11 pt semibold with a subtle
    gradient scrim;
  - top-left: `livephoto` symbol for `.livePhoto`;
  - bottom-left: filled red heart if favorite (always visible); outline heart on hover only; click
    toggles, keeping the explicit hit-test approach from the old cell;
  - top-right: checkmark circle when in selection mode and selected.
- Configure (from the coordinator):
  1. Set the row and the badges.
  2. `if let img = pipeline.cachedImage(id, .thumbnail)` → set it and done.
  3. Else `pipeline.cachedPlaceholder(id)` → set it.
  4. Start `loadTask`:
     - `pipeline.placeholder` if needed;
     - then `pipeline.stream(id:thumbhash:tier:pixelSize:)`, with
       `pixelSize = min(512, ceil(itemSide * backingScale / 64) * 64)` for the thumbnail tier, or tier
       `.preview` when `itemSide * backingScale > 512`;
     - set the image on the main actor only if `representedId == id`.
- `prepareForReuse`: cancel the task, `imageLayer.contents = nil`, hide the badges and the selection
  layer, clear `representedId`.
- Accessibility: keep the `grid-cell-<id>` identifier; label "Photo, <date>" / "Video, <duration>".

## Acceptance
1. The Release build and PhotosCore tests pass.
2. The UI smoke test still passes: `xcodebuild test` for the macOS UITests with `--fixture-seed`. See
   `reports/WP0-REPORT.md` for the command; if WP0 couldn't add it, report that.
3. Scroll 50+ screens fast: no black frames, no letterboxing in square mode, headers visible in
   Months/Years, none in All Photos. Selecting shows the accent ring, and it survives scrolling away and
   back.
4. Profile with `profile.sh wp3 120`, running the WP7 scenario. Meet the PLAN budgets for grouping
   switch, selection, zoom and fast scroll. Paste the summary into `reports/WP3-REPORT.md`.
