# WP-G — Library grid parity and scroll performance

Read first: `PLAN.md` (§0, §1 G-rows, §2.3, §2.6, §3), `EVIDENCE.md`, and
`evidence/video/REF-photos-grid-scroll-pinch.mp4` vs `CUR-heirloom-grid-scroll-pinch.mp4`. Photos screens:
`evidence/photos-screens/01–04`.

Base: the Gate 1 merge. It contains WP-F's snapshot cache and micro-thumbnail API, and WP-V's
`MacViewerTransition.swift`.

Current code:
- `MacCollectionGridView.swift`: NSCollectionView plus a coordinator; magnify gesture at :121.
- `MacTimelineLayout.swift`, `MacGridCell.swift`, `MacGridHeaderView.swift`, `MacSelection.swift`.
- The toolbar segmented control lives in `MacMainWindow.swift`:381. That file is WP-C's; coordinate via
  the grouping binding only.

## Steps

1. **P0: blank after the viewer (G1) and scroll restore (G2).**
   - Reproduce: open a photo, go Back → blank grid until a layout pass (`evidence/traces/blank-grid.sample.txt`
     shows the app idle).
   - Fix the root cause. Likely causes: the representable being torn down and rebuilt with a zero-size
     frame, or `reloadData` running while hidden with no later invalidation.
   - Preferred structure: keep the grid view alive underneath the viewer (a ZStack or overlay) instead of
     swapping it out.
   - Persist the anchor item plus its offset per page. On return, restore it, then
     `scrollToVisible(lastViewedId)`.
   - Add a UI test on the fixture: open, back, assert that cells are visible.
2. **Implement `ViewerTransitionSource`** in the grid coordinator (cell frame in window, cached image,
   hide/unhide the cell, scroll to visible).
   - Pinch-out on a cell (magnify > threshold while the pointer is over a cell) opens the viewer with the
     interactive transition from WP-V.
   - Double-click opens 100 % of the time. Investigate the ~50 % miss: probably the gesture recognizer
     racing with `mouseDown` selection.
3. **Selection (G9).**
   - Click selects; ⌘-click toggles; ⇧-click selects a range; drag rubber-band; ⌘A / ⇧⌘A.
   - Space or double-click opens. Remove the "Select" mode button; ask WP-C to drop it from the toolbar.
   - The selection count goes in the window subtitle (WP-C renders the title).
4. **All Photos under glass (G5).**
   - The collection view's scroll view extends under the toolbar (`automaticallyAdjustsContentInsets`
     with the safe area). There are no section headers in All Photos.
   - Publish the visible date range (first/last visible item) to the window subtitle via a lightweight
     binding: throttled to 10 Hz, O(1) from layout attributes.
5. **Years and Months cards (G3, G4).**
   - `MacYearMonthCards.swift`: two card layouts (NSCollectionView compositional or a custom layout) over
     *buckets*, not assets. Use WP-F's bucket API: counts, key asset id, place name if available.
   - Years: one large card per year (≈ 2 per row at default width), with the year title over the key photo.
   - Months: moment cards (hero photo, title such as "Houston" or the date, subtitle with the date range),
     large for recent months, 2–3 per row.
   - Click drills in (Years → Months scrolled to the year; Months → All Photos scrolled to the month) with
     a zoom transition. Esc / Back goes up a level.
   - Key photo choice: Immich doesn't rank "best" photos. Use a favourite in the bucket, else the photo
     with the most faces or people, else the middle item. Document the heuristic.
6. **Zoom and pinch (G7, G8).**
   - About 6 levels (columns at 1728 pt width: 3, 5, 7, 9, 13, 21-mosaic).
   - During a pinch, scale the collection view's layer (`CATransform3D`) around the anchor; on end, snap
     to the nearest level, set the layout, and restore the anchor item under the fingers. No blank frames.
   - Toolbar ± and ⌘+/⌘− animate the same way.
   - The square/aspect toggle (⌥T) switches instantly with a cross-fade.
   - Use the micro-thumbnail tier for the 13- and 21-column levels.
7. **Scroll performance (G6).**
   - Profile with Animation Hitches on flicks through the 102k library. Cell configure must be O(1) and
     allocation-free: reuse layers, set `contents` from a memory-cache hit synchronously, and apply a
     thumbhash placeholder otherwise.
   - No Auto Layout inside cells; use layer-backed drawing with `wantsUpdateLayer`.
   - Layout attribute queries must be O(log n) (binary search over row offsets).
   - Use velocity-aware prefetch (WP-F API).
   - Target: ≥ 55 fps, hitch ratio < 5 ms/s, placeholders resolved in ≤ 150 ms.
8. **Cells (G11) and context menu (G10).**
   - Cell badges per the PLAN.
   - Context menu comes from WP-V's `MacAssetActions.menu(for:context: .grid)`; don't build a second one.

## Proof (`reports/WP-G-REPORT.md`)
- Before/after recordings: back from the viewer, flick scroll, pinch zoom, Years→Months→All Photos drill.
- Animation Hitches trace summary.
- Screenshots of Years and Months beside the Photos equivalents.
- UI tests for G1 and G2, and for selection.

## Design references (open these before coding)
`DESIGN-REFERENCE.md` pairs: **L1, L2, L3, L7, photos/09-allphotos-min-zoom.png**, in `evidence/design/pairs/`. Match the left side (Apple Photos).
Your report must include AFTER captures of the same screens (`scripts/heirloom-parity/pairs.sh` rebuilds
the pairs).

## Regression tests (mandatory; see `TEST-PLAN.md` §2)
Implement every test listed for **G1–G11** in TEST-PLAN §2, in files under `Apps/macOS/Tests/<Area>/`,
`Apps/macOS/UITests/<Area>/` and/or `PhotosCore/Tests`.
- **Red first:** run each new test on base `9b9bb7f2e` (or on your branch before the fix) and record
  the failure, then fix and record the pass.
- Use `AXIDs` identifiers, the fixture library (`-HeirloomFixture`), `SyntheticEvents` for trackpad
  phases, and `GestureInputs` controllers for pinch and smart zoom. All of these come from WP-T.
- Report table: `ID | test(s) | red on base | green now | notes`. Only rows marked **H** in TEST-PLAN
  may lack an automated test.
