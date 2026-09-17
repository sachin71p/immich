# Regression test plan: Photos parity program

**Rule:** every gap ID closed by this program has at least one automated test that **fails on the base
commit `9b9bb7f2e` and passes after the fix** (red → green).
- The WP report must show the failing run on base (or explain why the test is new infrastructure that
  can't run on base) and the passing run after.
- Gestures and visuals get the strongest test the platform allows. Where XCUITest can't drive the input
  (trackpad phases, pinch), the logic is tested one layer down with synthetic `NSEvent`s or injected
  inputs, and the hands-on gate covers the rest.

## 1. Test infrastructure (built first, by the WP that owns it)

Today there are only two macOS UI-test files (`Apps/macOS/UITests/MacFunctionalTests.swift`,
`MacSmokeTests.swift`) and `PhotosCore/Tests/PhotosCoreTests`. The previous program ended with 3/13 UI
tests passing. **WP-T (Wave 0) builds T0–T5, T8 and T9, plus the perf-test class in T6**, before any
feature WP starts. Feature WPs emit the T6 signposts in their own files. WP-F builds T7.

| # | Item | Details |
|---|---|---|
| T0 | **UI-test reliability** | Before adding new tests, make the existing suite pass on a quiet host.<br>• Fixture launch argument `-HeirloomFixture` (FixtureSeed): no server, deterministic 2,000-asset library with synthetic images, videos, live photos, albums, 2 shared libraries, people with names, 3 memories.<br>• Disable animations under test (`-HeirloomUITestNoAnimation`), except in transition tests.<br>• Replace sleeps with `waitForExistence` / expectation predicates |
| T1 | **macOS unit-test target** `Heirloom-macOS-Tests` | Hosted in the app. Add it in `project.yml` and to the Heirloom-macOS scheme's test action. Swift Testing (`@Test`) preferred; XCTest where perf/metrics APIs need it |
| T2 | **Snapshot testing** | Add `https://github.com/pointfreeco/swift-snapshot-testing` (test-only, T1 target). Snapshot `NSView`/`NSViewController` at fixed sizes (1728×1026 and 1280×800), light and dark, `precision: 0.99, perceptualPrecision: 0.98`. Baselines go in `Apps/macOS/Tests/__Snapshots__/` and are rendered **only from synthetic fixture assets** (generated gradients/shapes with fixed seeds), never personal photos. The OS major version is in the snapshot name; re-record deliberately with `SNAPSHOT_RECORD=1` and review the diff in the PR |
| T3 | **Accessibility identifier contract** | `Apps/macOS/Sources/AXIDs.swift` holds constants used by both app and tests:<br>• `sidebar.<destination>`, `toolbar.<item>`, `grid.cell.<assetId>`;<br>• `grid.yearCard.<yyyy>`, `grid.monthCard.<yyyy-mm>`;<br>• `viewer`, `viewer.page.<assetId>`, `viewer.zoomSlider`, `viewer.title`, `viewer.subtitle`, `viewer.chevron.prev|next`;<br>• `inspector`, `edit.mode`, `edit.tab.<name>`, `edit.done`, `edit.cancel`;<br>• `collections.shelf.<name>`, `search.field`, `search.results`.<br>UI tests must use only these, never labels or coordinates |
| T4 | **Synthetic gesture events** (`Apps/macOS/Tests/Support/SyntheticEvents.swift`) | Build scroll events with trackpad phases:<br>`CGEvent(scrollWheelEvent2Source:units:.pixel,…)`, then set `.scrollWheelEventIsContinuous=1`, `.scrollWheelEventScrollPhase` (mayBegin 128 / began 1 / changed 2 / ended 4 / cancelled 8), `.scrollWheelEventMomentumPhase`, `.scrollWheelEventPointDeltaAxis1/2`, then `NSEvent(cgEvent:)`.<br>Deliver them **directly** (`view.scrollWheel(with:)`); nothing is posted, so no Accessibility permission is needed.<br>Helpers: `swipe(dx:steps:velocity:)`, `partialSwipe`, `flick`, `momentumTail` |
| T5 | **Injectable gesture inputs** | Zoom, pinch-close and grid-pinch logic live in pure controllers that take `MagnifyInput(phase, magnificationDelta, locationInView, timestamp)` and `SmartMagnifyInput(location)`. The AppKit overrides (`magnify(with:)`, `smartMagnify(with:)`) only translate and forward. The controllers are unit-tested; the adapters are one-liners |
| T6 | **Signposts + perf tests** | `HeirloomLog` signposts: `Launch.FirstThumbnails`, `Library.Return`, `Page.FirstPaint`, `Timeline.Query`, `Edit.Open`, `Viewer.Page`, `Viewer.OpenTransition`, `Grid.PinchCommit`.<br>A `Heirloom-macOS-PerfTests` UI-test class uses `measure(metrics:)` with `XCTApplicationLaunchMetric(waitUntilResponsive: true)`, `XCTOSSignpostMetric(subsystem:category:name:)` for each signpost, and `XCTHitchMetric` where the SDK supports it on macOS (otherwise the harness in T8).<br>Baselines live in the scheme's `.xcbaseline` on the owner's Mac. The run uses the **large fixture** (102k synthetic rows) via `-HeirloomFixture large` |
| T7 | **DB performance and query-plan tests** (PhotosCore) | A 102k-row synthetic store is built once per test run in a temp dir. `EXPLAIN QUERY PLAN` assertions per query, plus timing assertions at 2× budget (CI tolerance) |
| T8 | **Hands-on harness** | `scripts/heirloom-parity/`:<br>• `record.sh <name> <seconds>`: ffmpeg avfoundation 60 fps;<br>• `framestats.sh <clip> [crop]`: mpdecimate changed-frames/s, p50/p10, and the longest static run during motion;<br>• `pairs.sh`: rebuilds `evidence/design/pairs` from fresh captures using the pair list in DESIGN-REFERENCE.md.<br>Not CI-gating; used by WP-X §3 |
| T9 | **verify.sh modes** | `scripts/verify.sh mac-unit` (T1+T2), `mac-ui` (UI tests, fixture), `mac-perf` (T6, owner's Mac only), `core` (PhotosCore incl. T7). The pre-merge gate is `core` + `mac-unit` + `mac-ui`; `mac-perf` runs at every WP-X gate |

## 2. Test matrix by gap ID

Legend:
- **U** = macOS unit test (T1); **S** = snapshot (T2); **UI** = XCUITest on fixture; **P** = perf (T6/T7);
  **C** = PhotosCore unit test; **H** = hands-on gate only (listed so it isn't forgotten).
- File names are suggestions; keep one test file per feature area.

### Viewer (WP-V): `ViewerPagerTests`, `ViewerZoomTests`, `ViewerUITests`, `ViewerSnapshotTests`
| ID | Tests |
|---|---|
| V1 | U: with a Live Text analysis attached, the image page is still the zoomable controller, and `magnify` input changes magnification. U: the Live Text overlay's frame tracks the document view at 1×, 2× and 4×. UI: open a photo; `viewer.zoomSlider` → 200 % changes the page's AX value (magnification exposed as `accessibilityValue`) |
| V2 | U: toggling analysis on/off never sets the displayed image to nil (hold the image through the state change). S: page snapshot with the overlay on equals the snapshot with it off (the overlay is transparent until interaction) |
| V3 | U: `VideoPageController` reaches `readyToPlay` for a fixture MP4 served through the same loader path as production (a local `URLProtocol` stub with the auth header asserted). UI: open a fixture video, press Space (or click play), and assert `viewer.video.time` advances within 3 s |
| V4 | UI: on a video page, `typeKey(.rightArrow)` moves to the next asset id (`viewer.page.<id>`), and so does ←. U: synthetic swipe (T4) delivered to the video page's view reaches the pager and pages |
| V5 | U (T4): 1:1 tracking, meaning after N changed events the strip offset equals the Σdx (±1 pt). Partial swipe (30 % and slow) on end → returns to the same index with a spring. Flick (15 % and fast) → commits. Chained flicks ×3 within 300 ms → index +3. At the first index a right swipe rubber-bands (offset ≤ 1/3 of travel) and settles back. Zoomed page: horizontal scroll pans until the edge, then pages. `isSwipeTrackingFromScrollEventsEnabled == false` → no paging from scroll. Natural direction: dx<0 → next. U: only the ±2 neighbours are instantiated or preloaded, even with 102k ids (assert the controller count ≤ 5). **H:** REF vs AFTER swipe clips |
| V6 | U: `navigateForward` animates (the transition's duration > 0 unless Reduce Motion is on); five rapid → presses end at +5 with ≤ 1 pending animation. UI: → → ← ends at +1 |
| V7 | U: pinch-close controller: scale < 0.8 at end → close; ≥ 0.8 and outward velocity → restore; with no `ViewerTransitionSource` it cross-fades. U: the source's `scrollToVisible` is called before `frameInWindow`. UI: open from the grid, press Space → `viewer` disappears and `grid.cell.<id>` is hittable. **H:** pinch-close and open transition clips |
| V8 | U: smart magnify at point p from fit → magnification 2.0 and p stays under the pointer (±2 pt); again → fit. Z toggles; ⌘+ ×3 → 1.5³ clamped to 8. UI: double-click on the page → `viewer.zoomSlider` value > 100 % |
| V9 | S: viewer chrome at 1728×1026 light/dark (title, subtitle, toolbar order). U: title/subtitle formatter: place > date fallback; "Month d, yyyy at h:mm:ss a · N of M" with locale en_US and one RTL locale |
| V10 | U: `MacAssetActions.menu(for:context:)` returns the item titles in exactly the spec order for photo / video / live / shared-library / album contexts, with key equivalents (data-driven from `Tests/Specs/context-menu.json`). UI: right-click a photo page → the menu contains "Get Info", "Add to Album", "Delete" |
| V11 | U: hover tracking shows the chevron within 0.15 s near an edge and hides it at the first/last index. UI: hover near the right edge → `viewer.chevron.next` exists; click → next page |
| V19 | See `SPEC-TOOLBAR-SETTINGS.md` §2a tests (TV-4): counter formatting/locale, updates on paging, per-context totals, badges, zoom-slider binding |
| V12, V16–V18 | See `SPEC-INFO-PANEL.md` §7: Info sidebar snapshots (4 variants), formatter goldens, in-window sidebar (no new window) with all old Heirloom fields preserved, follows paging, grid selection drives Info, EXIF sync mapping, Adjust sheet Cancel makes no write |
| V13 | UI: Space closes the viewer; Return opens `edit.mode`; `.` toggles favourite (AX value of `toolbar.favorite`) |
| V14 | UI: 20 consecutive double-clicks on random `grid.cell.*` all open the viewer (100 %) |
| V15 | UI: with the viewer open, click `sidebar.search` → `viewer` doesn't exist and `search.field` is focused. Same for every sidebar destination (parameterised) |

### Grid (WP-G): `GridLayoutTests`, `GridPinchTests`, `GridUITests`, `GridSnapshotTests`
| ID | Tests |
|---|---|
| G1 | UI: open a photo, Back → at least 20 `grid.cell.*` are hittable within 500 ms. Repeat ×10, also after resizing the window while the viewer is open |
| G2 | UI: scroll to fixture month M, open photo X, page to Y, Back → `grid.cell.Y` is visible; the anchor offset is restored ±1 row. Same across a sidebar round-trip (Library → Collections → Library) |
| G3/G4 | U: bucket → card model (key-photo heuristic, titles, counts) golden tests. S: Years and Months pages. UI: click `grid.yearCard.2024` → Months scrolled to 2024; click a month card → All Photos with that month's first cell visible |
| G5 | S: All Photos with content under the toolbar (no opaque band). U: the visible date-range publisher is throttled (≤ 10 updates/s under a synthetic scroll) and O(1) (its time doesn't grow with row count: 2k vs 102k rows within 20 %) |
| G6 | P: Grid scroll perf test (large fixture): scripted `scroll(byDeltaX:deltaY:)` flicks; `XCTHitchMetric` or the signpost-based frame-interval metric; baseline set with hitch ratio < 5 ms/s. U: cell configure makes no allocations beyond the pool (Instruments-free check: count `CALayer` creations across 10k configure calls). U: layout-attribute query is O(log n) (timing scales ≤ 2× from 10k to 1M synthetic rows). **H:** grid flick clip |
| G7 | U (T5): pinch controller snaps to the nearest of the 6 levels; the anchor item stays under the pinch location (±1 cell) after commit; no reload happens during an active pinch (spy). **H:** grid pinch clip, no blank frames |
| G8 | UI: ⌥T toggles the aspect grid; cell frames change within 300 ms without the footer count resetting. S: both modes |
| G9 | UI: click selects (subtitle "1 Photo Selected"); ⌘-click adds; ⇧-click selects a range (count matches); ⌘A selects all; Space opens the viewer; no `toolbar.select` exists |
| G10 | Shared with V10 (same builder, grid context) |
| G11 | S: cell badges (favourite, video duration, shared, live) light/dark |

### Chrome (WP-C): `MenuSpecTests`, `ToolbarTests`, `SidebarUITests`
| ID | Tests |
|---|---|
| C1 | U (hosted): every top-level `NSApp.mainMenu` title is unique; File/Image/View items and key equivalents match `Tests/Specs/menu-bar.json` (generated from EVIDENCE.md, limited to supported actions). UI: in the viewer, the Image › "Add to Album…" item is enabled; with no selection in the grid it is disabled |
| C2/C3 | S: toolbar at 1728 and 1280 widths, light/dark. U: toolbar item identifiers are in spec order; there is no Select or standalone Sync item |
| C4 | UI: sidebar contains Library, Collections, the Pinned defaults, Shared Libraries and Albums, and no Search / Media Types section. Unpin then relaunch → the pin state persists (UserDefaults suite injected in the fixture) |
| C5 | UI: type "bea" in `search.field` → the suggestion popover shows rows with counts; Return → `search.results` appears. U: debounce and cancellation (only the last query's results are applied) |
| C6 | UI: ⌃⌘S hides and shows the sidebar |
| C7–C9 | See `SPEC-TOOLBAR-SETTINGS.md` §5: toolbar snapshots at 3 widths, item order/identifiers, scope capsule full name, Settings tabs, preference-key round-trip, and **no Download-Originals option** |

### Edit (WP-E): `EditModeTests`, `RecipeCompatTests` (PhotosCore), `EditUITests`, `EditSnapshotTests`
| ID | Tests |
|---|---|
| E1 | UI: one click on `toolbar.edit` → `edit.mode` exists within 500 ms (×10 runs). Escape with no changes → exits. Escape after changing Exposure → a confirm dialog appears; Discard → the recipe is unchanged (fixture). S: Markup panel isn't clipped at 1280×800 |
| E2 | S: edit mode shell light and dark. UI: entering hides the sidebar and exiting restores it |
| E3/E4 | S: Adjust panel with each section collapsed and expanded. C: each new adjustment key renders a synthetic image deterministically (perceptual hash golden per key at 3 strengths). U: the filmstrip thumbnails are generated off-main (main-thread checker) |
| E5 | C: each Undertone and Mood preset matches its golden render. C: **back-compat**: recipes encoded by base `9b9bb7f2e` (golden JSON fixtures committed) decode and render identically (pixel-exact on the synthetic image) |
| E6 | U: crop-rect math: handle drags clamp to image bounds; aspect presets keep the ratio; straighten auto-scales to avoid empty corners. S: crop overlay |
| E7 | U: edit opens with the proxy immediately (`Edit.Open` signpost < 300 ms in test), the original load is async, Done stays disabled until it arrives, then re-renders. The stubbed original is delayed 2 s |
| E8 | U: the Tools tab lists only tools whose `isAvailable` is true; the tab is hidden when none are |
| E9 | UI: hold M → before image (AX value "Original"); ⇧⌘C then ⇧⌘V on another fixture asset copies the recipe |

### Pages (WP-P): `CollectionsTests`, `SearchTests`, `PagesUITests`, `PagesSnapshotTests`
| ID | Tests |
|---|---|
| P1 | C: `LocalStore+Counts` returns the correct counts for every Collections row on the fixture (compare to independent COUNT queries). UI: `collections.shelf.mediaTypes` rows show non-zero counts on first paint; the Albums/People/Memories shelves are non-empty |
| P2 | C: search service with a stubbed `/search/smart` + `/search/metadata` → merged, deduped, rank preserved; offline → local only with the flag set. U: "beach" on the fixture returns exactly the fixture assets tagged beach (not all). UI: search "beach" → the result count equals the fixture's beach count |
| P3 | P: `Page.FirstPaint` ≤ 1 s (large fixture) for Videos, Screenshots, a shared library and an album |
| P4 | S: Collections page (all shelves) light/dark. UI: collapsing a shelf persists across relaunch |
| P5 | S: search results page. UI: switch the Photos \| Collections segment |
| P6 | S: Map (with the MapKit tiles stubbed or snapshot-excluded), People, Memories, All Albums |
| P8 | C: people with names in the API → names shown; unnamed → "Add Name". UI: a fixture person name is visible |

### Performance and data (WP-F): `TimelineQueryPlanTests`, `SnapshotCacheTests`, `LaunchTests`
| ID | Tests |
|---|---|
| F1 | U: `TimelineSnapshotCache` hit returns synchronously with no store call (spy); a change-center event invalidates only the affected keys; LRU eviction at 7 entries; memory-pressure purge. UI + P: Library → Collections → Library, `Library.Return` ≤ 150 ms |
| F2 | C (T7): for every timeline/filter query, `EXPLAIN QUERY PLAN` contains `USING COVERING INDEX` / `USING INDEX asset_timeline…` and no `SCAN asset`; no `assetExif` join in the grid projection. The 102k-row query is ≤ 3 s cold / ≤ 600 ms warm (2× budget). The migration is idempotent (run twice) and additive (the base schema's data survives) |
| F3 | UI: launch with a signed-in fixture → `connect.form` **never** exists (poll every 16 ms for the first 3 s); the footer never shows "0 Photos" when the persisted snapshot exists. P: `XCTApplicationLaunchMetric` + `Launch.FirstThumbnails` baseline. U: the persisted snapshot round-trips and its version mismatch triggers a rebuild |
| F4 | C: filter queries use indexes (as in F2) |
| F5 | U: the micro-thumbnail tier is used for the 13- and 21-column levels; decoding is off-main; velocity-aware prefetch skips cells that will pass within 100 ms (injected velocity) |

## 3. How the gates use this
- **Each WP report** has a table: `ID | test name(s) | red on base? | green now | notes`. A row without a
  test needs an orchestrator-approved reason (only **H** rows).
- **WP-X §1** runs `verify.sh core mac-unit mac-ui`. Any failure is FAIL. Snapshot diffs must be
  intentional, with re-recorded images reviewed by the orchestrator.
- **WP-X §2** runs `verify.sh mac-perf` against baselines (median of 3); a regression > 10 % fails.
- **WP-X §3** (hands-on) covers the **H** items with REF-vs-AFTER clips, using `scripts/heirloom-parity`.
- **After the program:** these suites stay in `verify.sh`. Any future change to viewer, grid, chrome,
  edit, pages or the store must keep them green, and a new bug in these areas gets a red-first test in
  the same file family.
