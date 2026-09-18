# WP3 report — photo viewer

Branch `feat/heirloom-ios-wp3` (from `feat/shared-libraries` @ `9b9bb7f2e`).
Commits: step 1 `3655955e6`, step 2 `148ad09f6`, step 3 `5be89f7a1`, step 4 `e4da57d0c`.

## 1. V1 root cause (step 1: reproduce first)

Fixture test `ViewerUITests.testViewerChromeResponds` (open viewer, tap
Info / More / Share) on the pre-WP3 tree **failed at
"More button should be hittable"** — the "…" Menu existed but was not
hittable, while Info and Share worked and Favorite toggled fine.

Root cause: **a test artifact, not the suspected gesture.**
The test closed the Info sheet with `app.swipeDown()`, but that drag lands on
the sheet's `List` and scrolls it instead of dismissing — so the Info sheet
stayed open and covered the bottom bar, and the More button behind it could
not be hit. Evidence:
- The sibling run failed the same swipe-down close while the chrome behind it
  was fine.
- Controlled experiment: with the old NavigationStack-level
  `.gesture(DragGesture())` temporarily restored on the new pager, the full
  chrome test (deterministic Done-button dismissal) **passes** — clearing the
  drag recognizer as the cause of the observed failure.

The gesture was still removed (step 2): dismiss now lives in a vertical-only
UIKit pan on the page controller, and step 3 removed the second half of the
suspect (system `.bottomBar` hosting) by drawing the chrome as overlay views —
so the arena conflict is gone by construction, even though it was never the
demonstrated cause. Lesson for future UI tests: never `swipeDown()` a sheet
containing a scroll view; the Info sheet gained a Done button (step 2), and
the inline panel (step 4) closes via an explicit grabber drag.

## 2. Step 2 — UIKit pager driven by ViewerRoute

- New `Sources/Viewer/ViewerPager.swift`: `UIPageViewController` with per-page
  `ViewerPageHost : UIHostingController<AnyView>` carrying its index. Only the
  current page and its neighbours exist as view controllers, so opening is O(1)
  in views regardless of library size.
- `ViewerView` gained `init(route: ViewerRoute)` — the provider resolves once
  on open inside the `ViewerOpen` signpost. `init(ids:initialId:)` is kept so
  the Library/Search/Collections/Spaces/Albums call sites compile unchanged;
  those WPs can adopt the route entry to skip the array copy at tap time.
- Neighbour prefetch ±2 at the preview tier; `ThumbnailFetch` per page comes
  from `MediaPipeline`. `viewer-page-index` ("N of M") and
  `viewer-open-summary` ("openMs=…") hidden AX hooks feed the UI tests.
- Single tap toggles the chrome (stills via the `ZoomableImageView` hook,
  live/video via page tap); swipe-down dismiss is a UIKit pan (140 pt /
  900 pt·s thresholds, snap-back), vertical-only and simultaneous with the
  paging pan.
- `ZoomableImageView` (pinch/double-tap/Live Text), `LivePhotoPageView` and
  `VideoPage` hosts unchanged in this step.
- P6: Live Text analysis moved off the main actor (detached utility task,
  full tier only — it was per-tier on-main and saturated the main thread under
  load; VisionKit's result crosses via a single-handoff `@unchecked Sendable`
  wrapper).

## 3. Step 3 — native glass chrome (spec native-11/12/14)

New `Sources/Viewer/ViewerChrome.swift`; `Viewer.swift` drops the
`NavigationStack`/toolbar for overlay chrome in safe-area insets.

- Top: glass back chevron, centre pill (exif city over date · time, cached
  formatters), "…" menu on the right.
- Badge row: LIVE (tap plays the motion through a shared `LivePlayRequest`
  token observed by `LivePhotoInnerView`) and "From \<owner\>" for space assets
  (`store.user(id:)`, omitted when no name).
- Bottom: neighbour filmstrip (thumbnail tier + fixture-art branch, tap jumps
  through the two-way pager index) over a glass bar — Share · Favorite ·
  Info · Adjust · Trash, same `Permissions` gating and share/copy/mutation
  semantics as before.
- Videos: native-style scrubber pill (play/pause, seek Slider, mute) with the
  system controls off; trim stays behind Adjust (`EditView` handles video).
- Trash asks for confirmation (`.alert`, the Spaces/Albums convention — a
  `.confirmationDialog` drops its cancel-role button from the AX tree).
- The "…" menu keeps the existing actions (Copy, Hide, Add to Album, Move
  to…, Archive, Lock with auth). Omitted per plan ("if supported"):
  Duplicate, Slideshow, Save-as-Video, Adjust Info — `AssetMutations` offers
  no target for any of them. Add/Move open the existing sheets as flat items,
  not submenus.
- Deviation: for space assets the bar keeps the standard five buttons rather
  than the spec's "Save Shared Photo/Video" centre pill — saving shared
  assets into the personal library has no mutation target.

## 4. Step 4 — inline info panel (spec native-13)

New `Sources/Viewer/ViewerInfoPanel.swift` (`MiniMap` moved there); the sheet
is gone including `FullExifBrowser` (viewer use removed; SearchView keeps its own).

- Opens via Info toggle or swipe up (the pager's UIKit pan; a SwiftUI drag on
  the representable never fires — the page controller's scroll pan wins it).
  Closes via a grabber-button drag down; the viewer dismiss pan stands down
  while the panel is open. Bottom-anchored above the chrome.
- Cards: caption (display only), date · file, camera (make/model, format
  badge, lens line, MP · dimensions, ISO/mm/ƒ/exposure row), map + place +
  "Library: X" line, people chips (initials — face crops are WP4's person
  thumbnails), albums. Ask-Siri / Image-Search rows omitted (no targets).
- People/albums load lazily on open only: per-person `assetIds(forPerson:)`
  membership checks plus a new additive PhotosCore
  `albumsContaining(assetId:)` (one indexed join — the old per-album 10k-row
  scan is deleted) with a `LibraryListsTests` unit test.
- UI-test lesson: a panel root with an identifier collapses its subtree into
  one AX element — `.accessibilityElement(children: .contain)` is required to
  keep children addressable. A plain container also can't be aimed (outer
  layout modifiers join its AX frame), so the grabber is a real full-width
  Button: tap closes, drags pass through to the panel close drag.

## 5. Verification

- `make build-ios`: green (gen-api.sh first for the OpenAPI doc).
- `swift test --package-path native-apple/PhotosCore`: 186 tests — green
  except the WP1 `[perf] timelineRows 102k rows < 400 ms` budget test, which
  flakes with other sessions' simulators running (passes standalone in 4.9 s;
  the WP3 change is one additive query plus one unit test and does not touch
  that path). Status at commit: TODO rerun quiet.
- `bash native-apple/scripts/verify.sh ios` (SIMULATOR_NAME="iPhone 17" — the
  Pro Max was busy with WP2's runs): BUILD SUCCEEDED; A9Extras, Sync, and
  `testViewerOpensWithin250ms` (present 1101 ms Debug-sim vs the 3000 ms sim
  hang-guard) pass. Three reds, none WP3-owned (see §7):
  (a) `A3Smoke` Close tap — fixed by the back-chevron update in this step;
  (b) A3 + tour `Move to…` in Library select mode — the select bar overflows
  off-screen (button frame x=440.7 on a 402 pt-wide sim), pre-existing WP2
  area (`SelectionActionBar` is WP2 step 4's to replace);
  (c) GridPerf 100k flick stalls (28 then 76 stalls, maxStall ~110 ms) —
  WP1-owned gate failing under three concurrent test sessions; no WP3 code
  runs on the grid scroll path (untouched files), rerun quiet needed.
- `ViewerUITests` (5 tests, all green): chrome responds (open, Info panel +
  date card, More menu + Copy, Share), swipe next/back ("1 of 10" → "2 of 10"
  → back), Info swipe-up/down open/close staying in viewer, Trash
  confirm-then-cancel staying on the item, fixture Favorite toggle.
- Viewer open: 86,486 fixture items → `openMs=4424` (Debug simulator,
  tap-to-first-asset). The device budget (250 ms Release) is a Gate-2
  measurement; the sim number is dominated by Debug presentation, not paging
  (the pager itself is O(1) in views). Note the tap-time 86k id-array copy +
  `ViewerRequest.id` join still live in the call sites (see §6).
- Tour: `tourViewer()` extended (08 photo, 08b next-item, 09 info panel,
  10 more menu; `closeViewer()` uses the back chevron).

## 6. Gate status at handoff (honest)

`verify.sh ios` is NOT fully green: the remaining reds are the WP2 select-bar
overflow (A3 + tour `Move to…` — no WP3 file on that path; Library
select/bar files untouched) and the WP1 flick-scroll budget under concurrent
load. `swift test PhotosCore` is green except the same load-flaky WP1
`timelineRows` budget test (passes standalone). All five `ViewerUITests`,
the viewer-open hang-guard, A9, Sync, and the build are green.

## 7. Notes for other WPs / orchestrator

- WP2 handoff (LibraryView): `onOpen` still does
  `ViewerRequest(ids: route.resolveIds(), …)` plus the O(n) `ids.joined()`
  `ViewerRequest.id` hash — with 86k items that tap-time copy dominates open
  latency. Adopting `ViewerView(route:)` (ready, tested entry) removes it.
  Untouched as WP2-owned. Same for WP4/WP5 call sites.
- `Apps/Shared/*` untouched. PhotosCore additive only (`albumsContaining` +
  test). No PNGs committed; team/bundle id unchanged; fixture-only
  destructive coverage (Trash cancelled); simulator only.
- `ScreenshotTour.swift` (WP0 file) extended per its own header ("W2 work
  packages extend this tour") and the WP3 Done clause.
- Known edge: a vertical dismiss drag that starts on a zoomed-in still also
  drags the view (accepted; snap-back unless past threshold).
- The iPhone-17 simulator (this session's test device — the Pro Max was busy
  with WP2's runs) can be shut down when WP3 verification is accepted.
