# WP5 — Viewer: paging, rotation, title, info inspector, preloading

Read `PLAN.md` first. **Prerequisite:** WP2 is merged; `viewerContext` is now a `TimelineGridSnapshot?`.
Runs in parallel with WP3 and WP4.
- Owned: `MacViewer.swift`, `MacLiveVideo.swift`, `MacLiveText.swift`, `MacEditView.swift`, and a new
  `MacInspectorView.swift`.
- You may **add** new files under `PhotosCore/Sources/LocalStore/` (for example
  `LocalStore+Exif.swift`) with read-only queries. Don't edit existing PhotosCore files; report any
  change you need there.

## Items
1. **Paging (U7).**
   - Use `viewerContext.indexById[currentId]` → ±1 → `rows[i].id`.
   - **Clamp, don't wrap** (Photos stops at the ends).
   - Disable the previous/next affordances at the ends.
   - Arrow keys must be handled exactly once: make sure the grid's key handling doesn't also receive
     them while the inline viewer is visible, and verify focus.
   - If `viewerContext` is nil (a window opened from Search, Map or a deep link), build a one-element
     context.
2. **Instant open.** On open:
   - show `pipeline.cachedImage(id, .thumbnail)` synchronously (scaled up);
   - then stream `.preview`;
   - then `.fullsize` when magnification > 1.5 or the window is larger than the preview pixel size.
   - The old image stays visible until the new tier arrives; no flash to blank between pages.
3. **Neighbor preload.** After a page change settles (100 ms), call
   `pipeline.prefetch(neighbors ±2, tier: .preview)` and `cancelPrefetch(keeping:)` for that set.
4. **Rotation (U11).**
   - Rotate by 90° steps, with the image **re-fit** to the container: swap the aspect ratio for 90° and
     270° when computing the fit size, and animate 0.2 s.
   - Persistence follows the decision at the top of `reports/WP4-REPORT.md`:
     - If it's persistable, save through the same edit path and post `MacAssetChange.edited(ids: [id])`.
     - Otherwise, label the control "Rotate (preview only)" in its tooltip and reset the rotation on
       page change.
   - If WP4 hasn't decided yet, implement the re-fit and leave persistence behind a single function
     that WP4's decision fills in, then report.
5. **Title (U8).** Window/toolbar title shows the capture date ("February 8, 2026") and subtitle time,
   plus the place if known ("1:44 AM · San Jose, California"). The filename moves to the inspector.
6. **Inspector (U9)** — new `MacInspectorView`, sectioned like Photos' Info panel:
   - editable caption and title, if the store/API supports description updates; otherwise read-only
     and reported;
   - date and time;
   - camera make/model, lens, ƒ-number, exposure time (1/250 s), ISO, focal length (mm);
   - dimensions and megapixels, file size, file name, format (HEIC/RAW/HDR badge from
     `MediaFormatInfo`);
   - location: city/state/country and a non-interactive `MKMapView` snapshot (`MKMapSnapshotter`,
     cached per asset) with a pin;
   - people names in the photo, if the store has face links (WP1 reports whether it does);
   - library/owner, favorite.

   Query EXIF from the `assetExif` table via a new `LocalStore+Exif.swift`
   (`func exifSummary(assetId:) async throws -> ExifSummary?`). Check column names in `Schema.swift`.
7. **Mutations in the viewer.**
   - Favorite, delete, lock, move and add-to-album post `MacAssetChange` (see `MacAssetChangeCenter`)
     so the grid updates without a reload.
   - After delete or lock, advance to the next item (or the previous one at the end), or close the
     viewer if the context becomes empty.
   - Delete asks for confirmation only when the server has no trash; follow the current behavior and
     report.
8. **Keyboard.**
   - Esc closes the inline viewer (back to the grid, reselecting the item and scrolling it into view via
     the existing callback).
   - Space toggles Quick Look off.
   - ⌘I toggles the inspector; ⌘. toggles favorite (match `MacMenus` shortcuts, read-only there).
9. **Video and Live Photo.**
   - Video uses `AVPlayerView` with inline controls. Pause on page change and release the player on
     close.
   - Live Photo plays on hover over the LIVE badge and on long-press, as in Photos. Verify
     `MacLiveVideo` does this; fix it if not.
10. **Live Text.** The button toggles the overlay. Verify it works on the preview tier, and disable it
    for videos.

## Acceptance
- Release build and tests pass.
- Manual/automated checks:
  - → then ← returns to the same photo;
  - paging 50 photos quickly has no blank frames;
  - rotation stays inside the bounds;
  - the inspector shows EXIF for a JPEG with EXIF.

  If you can't drive UI, document how WP7 should check.
- Report: `reports/WP5-REPORT.md`.
