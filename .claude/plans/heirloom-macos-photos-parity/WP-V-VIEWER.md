# WP-V — Viewer parity (pager, zoom, Live Text, video, transitions, chrome)

Read first: `PLAN.md` (§0 rules, §1 V-rows, §2 decisions 1–3, §3 budgets) and `EVIDENCE.md`. Then watch
`evidence/video/REF-photos-trackpad-swipe.mp4`, `REF-photos-pinch-zoom-close-open.mp4`,
`CUR-heirloom-trackpad-swipe.mp4` and `CUR-heirloom-pinch-doubletap.mp4`. Extract frames with ffmpeg if you
can't play video.

Owned files: listed in the PLAN §4 WP-V row. Current code:
- `native-apple/Apps/macOS/Sources/MacViewer.swift` (792 lines):
  - `liveTextEnabled` default at :44;
  - page body at :121–160;
  - `PageSwipeTracker` at :607;
  - `ViewerPagingScrollView` at :652;
  - `MacZoomableImageView` at :670.
- `MacLiveVideo.swift`: `MacVideoPageView` / `MacLivePhotoPageView`.
- `MacLiveText.swift`.

## Steps (commit each separately)

0. **Transition protocol first.** Create `MacViewerTransition.swift` with `ViewerTransitionSource`
   (PLAN §2.3) and a no-op default. Commit it and report the SHA immediately.
1. **P0 hotfixes on the current structure, before the rewrite** (small, shippable):
   - Set `liveTextEnabled` to default `false`, and fix the blank-on-toggle (V1 and V2 quick fix).
   - Fix video playback (V3). Find why the player never becomes ready: asset URL, auth header,
     `AVURLAsset` resource loader, or a HEVC/transcode path. Log the `AVPlayerItem.status` and
     `error` via HeirloomLog.
   - Make ←/→ and horizontal swipe work while a video is shown (V4). Add a key monitor at the viewer
     level, and a scroll-forwarding `AVPlayerView` subclass.
   - Prove each with a recording.
2. **Spike (≤ half a day): `NSPageController` `.horizontalStrip`.** Host it with the viewer's snapshot ids
   as `arrangedObjects` (ids only). Measure:
   - 1:1 tracking;
   - settle time;
   - chained flicks;
   - rubber-band at the ends;
   - behaviour with a zoomed page (pan first, then page at the edge);
   - memory with 102k ids (it must not create 102k controllers);
   - `completeTransition` timing, and flicker with `takeSelectedViewControllerSnapshot`.

   Record a side-by-side against the REF video. **Go/no-go:** choose `NSPageController` unless a
   requirement fails. Otherwise build the fallback from PLAN §2.1 and write down why.
3. **Pager implementation (V5, V6).**
   - Pages are `NSViewController`s: `ImagePageController` and `VideoPageController`.
   - Reuse the tiered image loading (preview → fullsize on zoom > 1.5×) and neighbour preload from the
     current viewer. Preload ±2 around the current page.
   - ←/→ call `navigateForward/Back` (animated). Rapid presses queue at most one pending step and skip
     the animation when more than 1 is pending.
   - Honour `NSEvent.isSwipeTrackingFromScrollEventsEnabled`. When it's off, trackpad horizontal scroll
     pans or does nothing, as in Photos, and arrows still page.
   - With Reduce Motion on, use a cross-fade instead of a slide.
   - Delete `PageSwipeTracker`, `ViewerPageCatcherView` and `ViewerPagingScrollView` once unused.
4. **Zoom (V1 full, V8).**
   - `ImagePageController` uses an NSScrollView (`allowsMagnification`, min = fit, max 8×) with a centred
     document view. Its clip view keeps the image centred when it's smaller than the viewport.
   - Override `smartMagnify(with:)` and handle a double-click → toggle fit ↔ 2× at the pointer
     (animated `setMagnification(_:centeredAt:)`).
   - Z toggles; ⌘+/⌘− step ×1.5.
   - A toolbar zoom slider is bound to the magnification.
   - Live Text: `ImageAnalysisOverlayView` added as an overlay subview of the document view (so it
     scales with it). Analysis runs lazily, only after the page has been settled for 0.5 s.
   - Remove the Live Text toolbar toggle.
5. **Pinch-to-close and open/close transitions (V7).**
   - When magnification is at fit and the pinch continues inward (magnify event `magnification < 0`),
     start an interactive close. A snapshot layer scales toward `source.frameInWindow(for:)`.
   - On gesture end: close if scale < 0.8 or velocity is inward, otherwise spring back.
   - The open transition grows from the cell rect.
   - When no source is available (standalone window, search), use a cross-fade.
   - Call `source.scrollToVisible` before the close starts, so the target cell exists.
6. **Chrome (V9, V11, V13, V19).** Implement `SPEC-TOOLBAR-SETTINGS.md` §2a exactly, including the "N of M" position counter and the LIVE/HDR badges.
   - Toolbar per PLAN V9.
   - Title: place (city/landmark from EXIF reverse geocode or Immich `exifInfo.city`), falling back to
     the date.
   - Subtitle: "Month d, yyyy at h:mm:ss a · N of M".
   - Edge-hover chevrons (tracking areas, fade 0.15 s).
   - Key map per EVIDENCE.md: Space closes; Return → Edit (post a notification that WP-E handles;
     until WP-E lands, open the existing sheet); `.` toggles Favorite; ⌘R / ⌥⌘R rotate.
7. **Context menu (V10).**
   - Build it in `MacAssetActions.swift` as `func menu(for ids: [String], context: .viewer|.grid) -> NSMenu`,
     in Photos' order: Get Info, Copy, Share…, Make Album Cover (album context), Show in All Photos,
     Rotate Left/Right, Copy Edits, Paste Edits, Revert to Original, Add to ›, Add to Album, Edit With ›,
     Duplicate, Hide, Delete, Remove from Album (album context), Move to Library › (shared libraries).
   - Omit what Immich can't do; don't show disabled placeholders except where Photos also disables.
   - Merge VisionKit's subject items at the top via the overlay's menu delegate.
8. **Info panel (V12, V16–V18).** Implement **`SPEC-INFO-PANEL.md`** exactly: **in-window trailing inspector sidebar** (owner decision; not a floating panel), selection-following, Heirloom fields preserved, content/states/styling, and the tests in its §7. Do the §5 EXIF data check first (hand store fixes to WP-F). Rebuild `pairs/I1` and `pairs/I2` from AFTER captures.

## Proof required in `reports/WP-V-REPORT.md`
- Side-by-side recordings (REF vs AFTER) for swipe (slow, fast, partial, chained, ends), arrows, pinch,
  smart zoom, pinch-to-close, open transition and video paging.
- Frame metrics from the `mpdecimate` recipe, plus an Animation Hitches trace of a 30-swipe session:
  hitch ratio < 5 ms/s.
- Memory footprint after paging through 500 photos: flat (±50 MB).
- Unit tests for index math and preload windows. UI test: open the viewer from the fixture, ← → with
  keys, Space closes.

## Design references (open these before coding)
`DESIGN-REFERENCE.md` pairs: **V1–V5, I1, I2, L7-grid-context-menu (shared menu)**; also every file in `evidence/design/info/`, in `evidence/design/pairs/`. Match the left side (Apple Photos).
Your report must include AFTER captures of the same screens (`scripts/heirloom-parity/pairs.sh` rebuilds
the pairs).

## Regression tests (mandatory; see `TEST-PLAN.md` §2)
Implement every test listed for **V1–V15**, plus **V12 and V16–V18 from SPEC-INFO-PANEL §7**, in TEST-PLAN §2, in files under `Apps/macOS/Tests/<Area>/`,
`Apps/macOS/UITests/<Area>/` and/or `PhotosCore/Tests`.
- **Red first:** run each new test on base `9b9bb7f2e` (or on your branch before the fix) and record
  the failure, then fix and record the pass.
- Use `AXIDs` identifiers, the fixture library (`-HeirloomFixture`), `SyntheticEvents` for trackpad
  phases, and `GestureInputs` controllers for pinch and smart zoom. All of these come from WP-T.
- Report table: `ID | test(s) | red on base | green now | notes`. Only rows marked **H** in TEST-PLAN
  may lack an automated test.
