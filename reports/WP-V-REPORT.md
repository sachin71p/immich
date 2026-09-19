# WP-V Report — Viewer parity (pager, zoom, Live Text, video, transitions, chrome)

Branch: `feat/heirloom-macos-v` (worktree `/Users/spatel/workspace/github/projects/immich-mac-v`,
base `4cc8db194`).

## Commits

- `d9a2f12ef` — `type(macos): add ViewerTransitionSource protocol with no-op default`
  (solo protocol-first commit; `native-apple/Apps/macOS/Sources/MacViewerTransition.swift`).
- `df8325ac` — `type(macos): viewer parity pager, zoom overlay, video fixes,
  chrome, menu` (pager/pages/model/menu/chrome/video rebuild + `ViewerPagerTests`
  + `project.yml` test-target entry + regenerated `project.pbxproj` + this report).

## What landed

- **Transition protocol first (step 0).** `ViewerTransitionSource`
  (`frameInWindow`/`image`/`setHidden`/`scrollToVisible`, PLAN §2.3) +
  `NullTransitionSource` (cross-fade fallback). WP-G implements it against the grid;
  the viewer calls `scrollToVisible` before every close (`ViewerTransitionAnimator`).
- **P0 hotfixes, subsumed by the rewrite (step 1).** The Live Text toggle is gone:
  there is one zoomable path with the overlay as a document subview, so
  blank-on-toggle is structurally impossible (image is never nilled; V2).
  Video readiness gates on `isPlayable` and logs status/error via
  `HeirloomLog.media` (`VideoPlaybackLoader`, shared by both video pages); a
  failed load renders an explicit error instead of spinning. Arrows page on
  video pages (`PagingAVPlayerView` forwards ←/→ and dominant-x scroll to the
  pager; Space still plays/pauses inside the player).
- **Pager (step 3, V5/V6).** `NSPageController` `.horizontalStrip` host
  (`ViewerPagerViewController` + `MacViewerPager` representable). Arranged
  objects are asset ids only; page controllers are created lazily and pruned to
  the ±2 window on every landing (flat memory by construction). ←/→ use
  `navigateForward/Back`; a pending step collapses rapid presses and lands
  unanimated; Reduce Motion jumps without sliding. `isSwipeTracking…` off is
  honored by the strip natively (documented in `ViewerPagerMath`).
- **Zoom + Live Text (step 4, V1/V8).** `ImagePageController` (fit–8×,
  centred clip, double-click/`smartMagnify` fit↔2× at pointer,
  `setMagnificationValue` for the slider). Overlay scales with the document;
  analysis attaches lazily after 0.5 s settle. Preview→fullsize past 1.5×,
  tiers never blank. `MacLiveText.swift` (separate view path) deleted.
- **Pinch-close + transitions (step 5, V7).** Inward pinch at fit accumulates a
  close scale; `endGesture` resolves via `PinchCloseDecision` (< 0.8 → close).
  `ViewerTransitionAnimator` flies a snapshot cell↔viewer in 0.3 s and
  cross-fades with no source; wired to the close path (source = nil until WP-G
  implements the protocol).
- **Chrome (step 6, V9/V11/V13/V19).** Toolbar per SPEC §2a TV-3 (Back, zoom
  slider, Info·Share·Favorite·Rotate·Auto-Enhance, Edit); title = place else
  date, subtitle = `ViewerHeaderFormatter` ("N of M", grouped, de_DE "von",
  hidden for single-item); hover-gated edge chevrons (absent at rest, 0.15 s
  fade, hidden at ends); LIVE/HDR badges; keys Space(image)/Return→edit+notify/
  `.`/⌘R(menus)/⌥⌘R/Z/⌘±.
- **Context menu (step 7, V10).** `ViewerContextMenuSpec.titles` (Photos order,
  tested) + `ViewerMenuBuilder.menu` (`MacAssetActions.swift`, WP-G callable);
  viewer SwiftUI menu mirrors the same order. No disabled placeholders.
- **Info panel (step 8, V12/V16–V18).** Still the in-window trailing
  `.inspector` sidebar (owner decision), now following pager selection via
  per-page chrome load; all Heirloom fields preserved. EXIF check: `placeString`
  + `profileDescription` already served by `exifSummary` — no WP-F handoff needed.

## Spike (step 2): NSPageController — GO

Chosen per PLAN §2.1 without a throwaway spike: ids-only arranged objects,
lazy delegate creation, ±2 cache pruning, native 1:1 strip + rubber-band +
"swipe between pages" honoring. Side-by-side REF/AFTER recordings still owed
(main session, device foreground is exclusive).

## Tests

`verify.sh mac-unit` equivalent with `-derivedDataPath native-apple/.build-v/DerivedData`:
**46 passed, 0 failed** (18 new `ViewerPagerTests`, 28 pre-existing).

| ID | test(s) | red on base | green now | notes |
|----|---------|-------------|-----------|-------|
| V5 | preload ±2, clamp, direction, swipe-tracking gate, rubber-band | YES — undefined symbols (`ViewerPagerMath` not in test bundle) | 18/18 pass | controller-count ≤ window by pruning (code) |
| V6 | coalescing (≤1 pending, skip animation) | YES (same) | pass | |
| V7 | close < 0.8, inward velocity, cross-fade w/o source | YES (same) | pass | gesture-end wiring in `ZoomPageScrollView` |
| V8 | toggle fit↔2×, ×1.5 steps clamp 8 | YES (same) | pass | slider↔page binding in chrome (UI row owed) |
| V9/V19 | en_US grouping, de_DE "von", single-item omission, place>date | YES (same) | pass | RTL + album/filter-counter UI rows owed |
| V10 | photo/video/album/shared order | YES (same) | pass | right-click UI row owed |
| V11 | chevron ends/hover gating | YES (same) | pass | hover UI row owed; chevrons hover-gated so `testViewerGesturePaging` (no chevrons at rest) still holds by construction — verify in `mac-ui` |
| V1/V2 | — | — | — | covered by construction (single overlay path, never nils image); overlay-frame snapshot owed |
| V3/V4/V12–V15/V16–V18 | — | — | — | UI/snapshot rows owed (see below) |

## Owed to the main session (device foreground is exclusive — do NOT run here)

```sh
cd /Users/spatel/workspace/github/projects/immich-mac-v/native-apple && ./scripts/verify.sh mac-ui
```

plus, with `-HeirloomFixture`, Release config: REF-vs-AFTER swipe/pinch/zoom/
pinch-close/open-transition/video-paging recordings, `mpdecimate` frame metrics,
30-swipe Animation Hitches trace (< 5 ms/s), 500-photo memory flatness
(±50 MB), `pairs.sh` V1–V5/I1/I2 AFTER captures, and the TEST-PLAN UI rows
(V3 time advances, V4 arrows/swipe on video, V6 →→←, V11 hover chevrons, V13
Space/Return/favorite, V14 20× open, V15 sidebar dismisses viewer, V19
counter/filter/album cases, Info-panel §7 snapshots).

`complete=false` until `mac-ui` + recordings land.
