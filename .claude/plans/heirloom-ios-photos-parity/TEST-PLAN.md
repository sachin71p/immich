# Heirloom iOS → Photos parity — regression test plan

Purpose: pin every gap in `PLAN.md §1` (F1–F5, V1–V8, G1–G7, C1–C5, E1–E7, P1–P7, L1–L3) so it cannot
silently reappear. Per `PLAN.md §0.8`: **every gap gets a test that FAILS against today's build
before the fix for that gap lands** (red-first). A gap is not closed until its test exists, is
red pre-fix, and is green post-fix on the physical device.

The existing files below (`native-apple/Apps/iOS/UITests/`) are referenced by name only — their
current contents were not audited for this plan. Treat every row in §1 as "add a test", not
"a test already exists".

Run a single case with:
```
xcodebuild -project native-apple/Heirloom.xcodeproj -scheme Heirloom-iOS \
  -only-testing:HeirloomUITests/<Class>/<method>
```
There is no `make` target for iOS tests yet — WP-T owns adding one.

---

> **Read PLAN.md §5a and §5b before writing any of these.** Profiling proved the editor is *idle*, not
> slow (~1% CPU), and that grid frame pacing already meets budget. Tests that assert on frame duration
> or CPU time will pass trivially and prove nothing. Assert on **content reaching the screen**.

## 1. Gap → test map

| Gap | Test name | Type | File | Pass criterion |
|---|---|---|---|---|
| F1 | `test_photoEditor_canvasReceivesImage_withoutAppSwitch` | non-black-frame | `EditorUITests.swift` (new) | Canvas clears the §3.1 threshold within 400 ms of editor present. **The test must never background the app** — no `XCUIDevice.shared.press(.home)`, no `activate()` — since backgrounding masks the defect. Today the canvas is black at 45 s+, so this is red on base. |
| F2 | `test_videoViewer_firstFrameNotBlack` | non-black-frame | `ViewerUITests.swift` | Player canvas clears threshold within 500 ms of tap-to-play; scrubber thumb position advances |
| F3 | `test_videoEditor_canvasReceivesImage` | non-black-frame | `EditorUITests.swift` (new) | Same as F1 for video. No app backgrounding. |
| F3b | `test_editorChrome_appearsWithoutSceneChange` | XCUITest timing | `EditorUITests.swift` (new) | Editor chrome is hit-testable within 300 ms **with no background/foreground cycle**. Covers §5b Defect 2, which is a *separate* root cause from the black canvas — keep it a separate test. |
| F4 | `test_libraryGrid_tabSwitchReturn_noBlankFrame` | perf/timing | `GridPerfUITests.swift` | First tile visible < 150 ms after Library tab re-selected |
| F5 | `test_libraryGrid_fastScroll_tilesHaveContent` | pixel sample | `GridPerfUITests.swift` | **Content, not pacing.** No empty/black tile on screen > 250 ms after scroll settles. Sample cell rects for non-uniform pixels. Frame pacing already passes (1 hitch / 8.33 ms in 30 s) — **do not assert on frame duration here**, it will pass trivially and hide the real defect. |
| F6 | `test_deviceBuild_isReleaseConfiguration` | build guard | `AppearanceUITests.swift` (new) or a CI check | Performance tests refuse to run against a Debug build: assert the binary is not `*.debug.dylib` / `DEBUG` is not defined. `make install-ios` installs Debug today (`Makefile:75,83`), so every perf number before WP-B is invalid. |
| V1 | `test_viewerTitle_showsPlaceWeekdayAndPeopleBadge` | XCUITest a11y-id | `ViewerUITests.swift` | Title label exposes place name + weekday + time; people badge element exists when faces present |
| V2 | `test_viewer_showsLiveBadgeAndEnhanceAffordance` | XCUITest a11y-id | `ViewerUITests.swift` | LIVE pill exists for a Live Photo asset; enhance control exists in top bar |
| V3 | `test_viewerToolbar_threeGroups` | XCUITest a11y-id | `ViewerUITests.swift` | Three distinct toolbar groups exist: share; heart/info/settings; delete — not one 5-icon pill |
| V4 | `test_infoPanel_allSectionsPresent` | XCUITest a11y-id | `InfoPanelUITests.swift` (new) | Caption field, device card, capture/EXIF card, map card, keywords field, provenance row all present per PLAN §2 |
| V5 | `test_infoPanel_dismissesBySwipeDown` | XCUITest gesture | `InfoPanelUITests.swift` (new) | Downward drag from sheet grabber dismisses sheet without using the toolbar button |
| V6 | `test_viewerLongPress_opensContextMenu` | XCUITest gesture | `ContextMenuUITests.swift` (new) | Long-press on open photo presents a menu; today it is a documented no-op |
| V7 | `test_videoScrubber_isFilmstripWithCCAndMute` | XCUITest a11y-id | `ViewerUITests.swift` | Scrubber exposes frame-thumbnail elements, CC control, mute control — not a plain bar |
| V8 | `test_viewerPinchIn_dismissesToGrid` | XCUITest gesture (`pinch`) | `ViewerUITests.swift` | `pinch(withScale: 0.5, velocity: -1)` on open photo returns to grid, not a floating shrunk rect |
| G1 | `test_grid_videoCellsShowDurationBadge` | XCUITest a11y-id | `GridPerfUITests.swift` | Every video cell exposes a duration label (`0:15` etc.) bottom-right |
| G2 | `test_grid_favouritedCellsShowHeartOverlay` | XCUITest a11y-id | `GridPerfUITests.swift` | Favourited asset cell exposes a heart overlay element |
| G3 | `test_grid_peopleBadgeIsSelectiveNotOnEveryCell` | XCUITest a11y-id | `GridPerfUITests.swift` | Fraction of visible cells with a people badge is below a fixed ceiling (e.g. not painted on every cell in a fixed 30-cell sample) |
| G4 | `test_grid_longPress_showsContextMenuNotViewer` | XCUITest gesture | `ContextMenuUITests.swift` (new) | Long-press on a cell presents preview + Copy/Duplicate/Hide, Share, Favorite, Add To, Adjust Info, Delete, Ask Siri; viewer must NOT open |
| G5 | `test_grid_zoomedOut_showsFloatingDateBadge` | XCUITest a11y-id | `GridPerfUITests.swift` | Floating date badge (e.g. "Aug 2026") appears while scrolling a zoomed-out (high column count) grid |
| G6 | `test_gridHeader_showsCountAtRestAndDateRangeWhileScrolling` | XCUITest a11y-id | `LibraryChromeUITests.swift` | Header subtitle is item count at rest, swaps to date range during scroll |
| G7 | `test_gridPinch_couplesColumnDensityToTimeLevel` | XCUITest gesture | `GridPerfUITests.swift` | Continuous pinch moves both column density AND the Years/Months/All selection; pills must not stay pinned |
| C1 | `test_chrome_isSingleFloatingBar` | XCUITest a11y-id | `LibraryChromeUITests.swift` | Library/segmented-control/search render in one bar element, not a pills row above a separate tab bar |
| C2 | `test_chrome_allSegmentLabel_isAll` | XCUITest a11y-id | `LibraryChromeUITests.swift` | Segment label text is exactly "All", not "All Photos" |
| C3 | `test_tabBar_persistentNotCollapsed` | XCUITest a11y-id | `LibraryChromeUITests.swift` | Library/Collections tabs are visible without a prior tap; separate search circle exists |
| C4 | `test_chrome_itemCount_inHeaderNotPersistentLine` | XCUITest a11y-id | `LibraryChromeUITests.swift` | Item count text lives in the header element; no separate persistent count line under the pills |
| C5 | `test_selectMode_toolbarOffersAddToAndFavorite` | XCUITest a11y-id | `ContextMenuUITests.swift` (new) | Select-mode toolbar exposes Add To and Favorite actions in addition to Share/Delete |
| E1 | `test_editor_tabTaxonomy_matchesTargetSet` | XCUITest a11y-id | `EditorUITests.swift` (new) | Tab bar exposes Styles/Live/Adjust/Crop/Tools identifiers (or the agreed final set — see note below) |
| E2 | `test_editorStyles_showLiveThumbnailPreviews` | XCUITest a11y-id | `EditorUITests.swift` (new) | Each style cell renders a live thumbnail of the current photo, not a text-only label; CUSTOMIZE control exists |
| E3 | `test_editorValueControl_isTickRulerDial` | XCUITest a11y-id | `EditorUITests.swift` (new) | Adjust slider control exposes a ruler/dial element with a centre marker, not a plain `UISlider`-style control |
| E4 | `test_editor_offersCleanUpExtendReframe` | XCUITest a11y-id | `EditorUITests.swift` (new) | Tools/Adjust surface exposes Clean Up, Extend, Reframe actions |
| E5 | `test_videoEditor_hasTrimFilmstripWithHandles` | XCUITest a11y-id | `EditorUITests.swift` (new) | Trim control exposes frame-thumbnail filmstrip, yellow trim handles, play button |
| E6 | `test_videoEditor_hasAudioMixTab` | XCUITest a11y-id | `EditorUITests.swift` (new) | Video editor tab bar exposes an Audio Mix tab |
| E7 | `test_editorPortraitTab_hiddenWhenNoDepthData` | XCUITest a11y-id | `EditorUITests.swift` (new) | Portrait tab is absent (or non-empty) for an asset with no depth data — not a permanent dead stub |
| P1 | `test_accountHeader_isCentredWithPhotoVideoCountsAndLastSynced` | XCUITest a11y-id | `SettingsUITests.swift` (new) | Header shows centred large avatar, name, `N Photos, M Videos`, `Last Synced …` |
| P2 | `test_settings_showsNameUserIdAndEmailTogether` | XCUITest a11y-id | `SettingsUITests.swift` (new) | Identity block exposes name, user ID, and email simultaneously |
| P3 | `test_settings_containsPhotosParityItems` | XCUITest a11y-id | `SettingsUITests.swift` (new) | Invitations/Access Requests, Manage Keywords, Zoom to Fill Screen, Show Ratings Controls, Featured section, Reset Suggested Memories, Reset People & Pets Suggestions all present — see PLAN §3 |
| P4 | `test_settings_preservesHeirloomOnlyItems` | XCUITest a11y-id (regression) | `SettingsUITests.swift` (new) | Sync Now, Last synced, Default Upload Target, Back Up Photos, Timeline Sources, Free Up Space, Optimize Storage, Cache Usage, Shared Libraries → Manage, Sign Out, About → Version all still present post-merge |
| P5 | `test_memories_rendersGeneratedCards` | XCUITest a11y-id | `SettingsUITests.swift` (new) | Memories surface shows at least one generated card and a "Type to Create" affordance, not the empty state |
| P6 | `test_search_hasNaturalLanguageSuggestionsAndPersistentField` | XCUITest a11y-id | `SettingsUITests.swift` (new) | Search surface exposes NL suggestion chips, Recents thumbnails, persistent bottom search field |
| P7 | `test_collections_hasTripsAndWallpaperSuggestions` | XCUITest a11y-id | `CollectionsPerfUITests.swift` | Collections grid exposes Trips and Wallpaper Suggestions chips alongside the existing sections |
| L1 | `test_viewer_followsLightAppearance` | XCUITest a11y + pixel | `AppearanceUITests.swift` (new) | With `UITraitCollection` light override, viewer chrome background samples light, not hard-coded dark |
| L2 | `test_libraryTitle_legibleOverGridInLight` | pixel sample | `AppearanceUITests.swift` (new) | In light appearance the "Library" title keeps white-on-scrim treatment; title/background contrast ratio ≥ 4.5:1 over a light photo |
| L3 | `test_infoAndEditor_appearanceParity` | manual + pixel | `AppearanceUITests.swift` (new) | Info sheet and editor match Photos' appearance behaviour once L1 lands; see manual checklist |

Note on E1: PLAN.md does not mandate Heirloom copy Photos' exact tab set — it documents the
divergence. Write the test against whatever final taxonomy WP-E's plan lands on; do not assert
"Styles/Live/Adjust/Crop/Tools" literally without confirming that's the agreed target first.

---

## 2. Test types

- **XCUITest a11y-id assertion.** `app.otherElements["<id>"].exists` / `.label` checks against
  accessibility identifiers exposed by the view. This is the default for chrome, layout, and
  content-presence gaps (V1–V3, V7, G1–G6, C1–C5, E1–E4, E6–E7, P1–P7). Every view referenced in
  a test above must carry a stable `accessibilityIdentifier` — if it doesn't yet, adding one is
  in scope for the owning work package, not the test.
- **XCTest performance measurement.** `measure(metrics: [XCTOSSignpostMetric.custom(...), XCTClockMetric()])`
  wrapping the interaction under test, used for every §4 budget (F1–F5 timing halves, F4, F5).
  Assert against the budget with `XCTAssertLessThan` on the measured value, not just `measure`'s
  own baseline comparison — baselines drift and silently stop catching regressions.
- **Non-black-frame assertion.** New technique, own subsection below (§3.1) — used for F1, F2, F3.
- **XCUITest gesture (`pinch`, `swipe*`).** Used for G7, V8, V5, V6, G4 and the swipe-regression
  set in §5.

### 2.1 Non-black-frame assertion (F1, F2, F3)

This is the one new mechanism this plan requires; get the threshold logic reviewed before wiring
it into CI, false negatives here defeat the whole point of "red-first."

1. Locate the rendering surface by accessibility identifier (e.g. `editorCanvas`,
   `videoPlayerCanvas`) and take an element-scoped screenshot: `element.screenshot().image` (a
   `UIImage`/`CGImage`), not a full-device screenshot — cropping in test code is unreliable
   across devices.
2. Convert to `CGImage`, pull the raw pixel buffer via `CGImage.dataProvider`.
3. Sample a fixed grid of points across the image (e.g. 10×10 = 100 samples, evenly spaced,
   avoiding the outer 5% margin to dodge rounded corners/letterboxing).
4. For each sample compute luminance (`0.299R + 0.587G + 0.114B`, 0–255 scale).
5. Compute mean and standard deviation of the 100 luminance samples.
6. **Fail the "is black" check** — i.e. assert the canvas is NOT black — when
   `mean < 8 AND stddev < 3` (both true: uniformly near-zero AND no variation). A real photo or
   video frame, even a dark one, will fail at least one of those two conditions.
7. Assert this check passes within the relevant §4 budget window (poll on an interval, e.g. every
   50 ms, up to the budget deadline; fail if still uniformly black at deadline).
8. Keep the threshold values (`8`, `3`) as named constants in the test file — they are
   calibration points, not magic numbers, and may need adjusting once real F1–F3 fixes land.

This must run against a real asset, not a blank test fixture — pick a stable, known asset in the
owner's library (or an app-bundled sample if editors support one) so the test is deterministic.

---

## 3. Performance budgets (PLAN §5)

All of the following: **Release build, physical device, never the Simulator** — the Simulator's
photo pipeline does not represent this library's decode/render behaviour, and a passing Simulator
run proves nothing about F1–F5.

| Budget | Measure | Test |
|---|---|---|
| Photo editor → photo visible: **< 400 ms** | Time from editor-present to non-black-frame pass (§3.1) | `test_photoEditor_canvasNotBlack` |
| Video → first frame drawn: **< 500 ms** | Time from play-tap to non-black-frame pass | `test_videoViewer_firstFrameNotBlack` |
| Video editor → usable: **< 2 s** | Time from editor-present to (chrome interactive AND non-black-frame pass) | `test_videoEditor_canvasNotBlack_andUsableUnder2s` |
| Library grid after tab switch: **< 150 ms** to first tiles | Time from tab-tap to first non-placeholder tile visible | `test_libraryGrid_tabSwitchReturn_noBlankFrame` |
| Grid scroll: **no frame > 16.7 ms** during a 5 s flick | `XCTOSSignpostMetric.animationHitchTimeRatio` or manual frame-timestamp sampling during a scripted flick gesture | `test_libraryGrid_fastScroll_noStaleTiles` |

Per PLAN §5's profiling note: do not run the full Instruments *Animation Hitches* template on
this machine without first freeing ≥60 GB (it wrote 5.9 GB in 40 s and exhausted disk last time).
Prefer `measure(metrics:)` with a narrow signpost, or wall-clock timestamps taken directly in test
code, over launching Instruments.

---

## 4. Gesture regression tests

Per PLAN §6, these already work today — they are regressions waiting to happen, not gaps, and
belong in the same swipe test as the gaps they sit next to so a future change can't break one
while fixing the other:

- Swipe left/right in viewer → next/previous photo (`ViewerUITests.swift`).
- Swipe up in viewer → info sheet opens (`ViewerUITests.swift`, adjacent to V4/V5 work).
- Swipe down on photo → exit viewer (`ViewerUITests.swift`).
- Grid pinch → column density change, ≈5 ↔ ≈10 columns (`GridPerfUITests.swift`, adjacent to G7 —
  the density behaviour must survive G7's zoom/time-level coupling fix).

**Pinch (G7, V8) cannot be synthesised through the Device Hub mirror** — that path only captures
manual screen recordings, it does not drive the app. Use XCUITest's native
`XCUIElement.pinch(withScale:velocity:)` directly against the app under test on the physical
device; this is the correct API for both G7 (grid density/time-level coupling) and V8 (viewer
pinch-to-dismiss) and should be preferred over any manual-only checklist entry for these two gaps.

---

## 5. Manual checklist

Automation cannot cover these; track them as sign-off items in WP-X, not as XCUITest cases:

- [ ] Light-appearance parity — re-capture Library, Viewer, Info, Editor, Settings in light
      appearance for both apps (DESIGN-REFERENCE.md §4 flags this as not yet captured) and
      confirm no light-mode-only regressions (contrast, missing tint adaptation).
- [ ] Visual design fidelity judged against `assets/pairs/*.png` — spacing, type scale, icon
      weight, corner radii. These are not asserted by accessibility identifiers and need an
      eyeball diff against each of the 15 pairs before WP-X sign-off.
- [ ] Portrait/Markup editor tabs against a photo that actually has depth data — DESIGN-REFERENCE
      §4 notes the capture set only exercised the empty state.
