# Heirloom macOS: Apple Photos UI/UX + performance parity plan (master)

Goal: Heirloom's macOS app should look, feel and perform like Apple Photos on macOS 27. That means the
same layout and chrome, the same gestures (above all the **interactive trackpad swipe** and **pinch** in
the viewer), the same edit mode, and launch/scroll performance that matches Photos. Immich features Photos
doesn't have (shared libraries, external libraries, server sync) stay, placed where Photos would put the
nearest equivalent.

- **Repo:** `/Users/spatel/workspace/github/projects/immich`.
- **App:** `native-apple/` (project `Heirloom.xcodeproj`, generated from `project.yml`; scheme
  `Heirloom-macOS`; Swift package `native-apple/PhotosCore`).
- **Base:** `feat/shared-libraries` @ `9b9bb7f2e`. This is the commit that produced the build installed
  2026-09-17 09:32.
- **Integration branch:** `feat/heirloom-macos-photos-parity`. Each work package (WP) gets its own branch
  and worktree off it.
- **Read first:**
  - `DESIGN-REFERENCE.md` and the side-by-side images in `evidence/design/pairs/` (Photos target vs
    Heirloom current, for every screen).
  - `TEST-PLAN.md`: the required regression tests per gap ID.
  - `SPEC-TOOLBAR-SETTINGS.md`: owner-reviewed toolbar and Settings spec (binding for WP-C).
  - `SPEC-INFO-PANEL.md`: owner-requested Info panel spec (binding for WP-V).
  - `EVIDENCE.md`: measurements, what Photos does, what Heirloom does.
  - The reference videos in `evidence/video/`.
  - The previous perf program `../heirloom-macos-perf/PLAN.md` and its `reports/FINAL.md`. Its gates
    "passed", but today's hands-on audit found the P0s below, so **don't trust earlier green reports
    without hands-on proof**.

## 0. Hard rules for every executor

1. **Evidence before claims.** Every "done" needs proof:
   - for UI: a screenshot or screen recording of the running app;
   - for performance: an Instruments trace or signpost numbers from the Release build on the owner's
     102k library.
   - Unit tests alone are not proof for UI or performance.
2. **Release builds only** for performance numbers. Build and install with `make install-macos` (see
   `native-apple/scripts/`), then verify the bundle has no `.debug.dylib`.
3. **Nothing O(rows) on the main thread.** 102k rows is the design point.
4. **File ownership is exclusive** per WP while it runs (§4). Anything outside your list is read-only; if
   you need a change there, ask the orchestrator.
5. **PhotosCore is shared with live iOS work.** Worktrees `immich-ios-wp2`…`wp5` are active. Before
   merging any `PhotosCore/**` change, the orchestrator runs
   `git diff 9b9bb7f2e..feat/heirloom-ios-wpN -- native-apple/PhotosCore` for N=2..5 and resolves overlaps.
   Keep PhotosCore changes additive: new files, or new functions with defaults.
6. **Never delete or modify user data** while testing. No trash, move or edit-save on real assets. Use the
   UI-test fixture library (`FixtureSeed.swift`) for destructive flows. For hands-on checks, open editors
   and **Cancel**.
7. **Use Apple's APIs before custom machinery:**
   - `NSPageController` / `NSEvent.trackSwipeEvent`;
   - `NSScrollView` magnification and `smartMagnify`;
   - `NSMagnificationGestureRecognizer`;
   - `AVPlayerView`;
   - `NSSearchToolbarItem`;
   - `NSSplitViewController` / `NavigationSplitView`;
   - Liquid Glass toolbar APIs (`.glassEffect`, `NSGlassEffectView`, `toolbarBackgroundVisibility`) on
     macOS 27.
8. **Honor system settings.** Check `NSEvent.isSwipeTrackingFromScrollEventsEnabled` ("Swipe between
   pages"), Reduce Motion (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`), natural scrolling
   and appearance.
9. **Logging:** use `HeirloomLog` categories plus `os_signpost` intervals named in §3. No `print`.
10. **Commits:** one logical change each, message `type(macos): …`, ending with the attribution line the
    orchestrator provides. **No push and no PR** unless the owner asks.
11. **Red-first regression tests.**
    - Every gap ID you close gets the tests listed for it in `TEST-PLAN.md` §2.
    - Write the test first, show it failing on base `9b9bb7f2e` (or say why it can't run there), then fix.
    - A fix without its test isn't done.
    - UI tests use only the `AXIDs` identifiers and the fixture library.
    - Snapshot baselines use synthetic fixture images only.
12. **Design fidelity.**
    - Before building any UI, open the `evidence/design/pairs/*` images listed for your gap IDs in
      `DESIGN-REFERENCE.md`, and match Photos (left side).
    - Your report includes a fresh AFTER screenshot of the same screen for each pair you touched.

## 1. Gap inventory

P0 means broken or regressed; fix it first inside its WP. P1 is a core Photos-parity experience. P2 is
polish or a secondary feature. The WP column assigns ownership.

### Viewer (WP-V)
| ID | Pri | Gap | Photos target |
|---|---|---|---|
| V1 | P0 | Pinch and double-tap do nothing. Root cause: `liveTextEnabled = true` default (MacViewer.swift:44) routes every photo through `MacLiveTextView`, which has no zoom | Zoom always available. Live Text is an *overlay* on the zoomable view (`ImageAnalysisOverlayView` on top of the scroll view's document view), never a replacement view. Remove the toolbar toggle; Live Text is automatic, like Photos |
| V2 | P0 | Toggling Live Text blanks the photo | Gone with V1 |
| V3 | P0 | Video never plays (grey placeholder, dead play button) | `AVPlayerView` with floating inline controls; poster frame first; plays on click or Space (⌥Space in Photos) |
| V4 | P0 | While a video is shown, ←/→ and swipe are swallowed, so there is no way out | The pager owns horizontal swipe and ←/→ for every page type. The player gets only clicks on its controls |
| V5 | P1 | Swipe is a hard cut after 80 pt (`PageSwipeTracker`) | Interactive 1:1 paging with neighbour pages visible, velocity-based commit, spring settle ~0.3 s, rubber-band at the ends, chained flicks, natural direction. See `WP-V-VIEWER.md` §2 |
| V6 | P1 | ←/→ is an instant cut | Same slide animation as swipe (≈0.25 s), cancelable by the next key press |
| V7 | P1 | No pinch-to-close; no open/close transition | Pinch-in past fit shrinks the photo into its grid cell and closes. Open grows from the cell. Grid pinch-out on a cell opens it (joint with WP-G via the `ViewerTransitionSource` protocol) |
| V8 | P1 | No smart zoom | Double-click and two-finger double-tap (`smartMagnify(with:)`) toggle fit ↔ 2× at the pointer. Z toggles; ⌘+/⌘− step |
| V9 | P1 | Toolbar differs | Left: back chevron, zoom slider. Centre: place title + "date · N of M" subtitle. Right: Info, Share, Favorite, Rotate, Auto Enhance, **Edit** text button. Trash, Move and Add to Album go to menus and context menu only (Photos) |
| V10 | P1 | Right-click on a photo shows only 4 VisionKit items | Full Photos-order menu (EVIDENCE.md) limited to actions Immich supports; VisionKit subject items merged at the top when a subject is under the pointer |
| V11 | P2 | No edge-hover chevrons | Chevron buttons fade in near the left/right edges on hover |
| V12 | P1 | Inspector content and styling don't match Photos | Photos Info content and styling per **`SPEC-INFO-PANEL.md`**, as an **in-window trailing sidebar (not a floating window; owner decision)**, keeping all existing Heirloom fields |
| V19 | P1 | Viewer header lacks Photos' details: no "6,388 of 12,108" position counter, no place title, no zoom slider, no LIVE/HDR badge, no Auto Enhance | `SPEC-TOOLBAR-SETTINGS.md` §2a, exactly |
| V16 | P0 | Grid Info ignores selection ("Select an item…" while 1 photo is selected) | Info follows grid and viewer selection (SPEC-INFO-PANEL §1, §3) |
| V17 | P1 | Inspector shows "No camera information"; EXIF possibly not synced or projected | SPEC-INFO-PANEL §5 |
| V18 | P2 | No Adjust Date and Time, Assign Location or Add Faces | SPEC-INFO-PANEL §4 |
| V13 | P2 | Space doesn't close the viewer; Return doesn't open Edit; `.` doesn't favorite | Photos key map (EVIDENCE.md "Keys") |
| V14 | P1 | Double-click in the grid opens the viewer only ~50 % of the time | 100 % (WP-G owns the grid side; WP-V makes sure presentation never drops a request) |
| V15 | P0 | With the viewer open, choosing another sidebar item (e.g. Search) highlights it but leaves the viewer on screen (`design/pairs/V5-…`) | Any sidebar or navigation change dismisses the viewer (with the close transition) and shows the destination. WP-V owns the viewer-dismiss hook; WP-C calls it from the router |

### Library grid (WP-G)
| ID | Pri | Gap | Photos target |
|---|---|---|---|
| G1 | P0 | Grid blank after closing the viewer, until a layout pass (app idle) | The grid is never blank. The collection view stays in the hierarchy (hidden or covered), or it invalidates layout and reloads visible items on re-show |
| G2 | P0 | Scroll position lost after the viewer or a page switch | Restore to the anchor item, and scroll so the just-viewed photo is visible (Photos does this) |
| G3 | P1 | Years = month grid | Year cards (one large key-photo card per year, with the year title). Click → Months, scrolled to that year |
| G4 | P1 | Months = continuous grid with headers | Month "moment" cards (hero photo, title, location, date). Click → All Photos, scrolled to the month |
| G5 | P1 | All Photos has section headers and an opaque toolbar band | Continuous grid scrolling under glass; a floating date-range title top left that updates while scrolling |
| G6 | P1 | Scroll perf median ≈ 22 changed frames/s, blurred placeholders mid-flick | ≥ 55 fps sustained on flicks; placeholder→thumbnail ≤ 150 ms at normal flick speed; hitch ratio < 5 ms/s |
| G7 | P1 | Grid pinch has a blank gap and discrete levels | Continuous pinch anchored at the fingers, snapping to ~6 levels including the dense mosaic. No blank frames: scale the existing layer during the gesture, relayout on end |
| G8 | P1 | Square toggle applies only after a reload | Instant (⌥T, View › Aspect Ratio Grid) |
| G9 | P1 | "Select" mode button | Photos model: click selects, ⌘/⇧-click extends, drag-select, ⌘A; double-click or Space opens (Photos: Space = Quick Look-like open). No Select button |
| G10 | P1 | Grid context menu differs | Same Photos-order menu as V10, for a single item or the selection |
| G11 | P2 | Cells | Favorite heart bottom left, video duration bottom right, shared-library badge top right, Live Photo badge, selection ring 3 pt accent with inner white stroke |

### Chrome, sidebar, menus (WP-C)
| ID | Pri | Gap | Photos target |
|---|---|---|---|
| C1 | P0 | Two "View" menus (the system View with Show Tab Bar / Enter Full Screen, plus a custom View with Show Info / Select All / Quick Look); File has 5 items; Image has 5 items; "Add to Album…" was disabled in the viewer in one observation and enabled in a later one (state-dependent; the test must pin it) | One menu bar exactly in Photos' order with Photos' shortcuts (EVIDENCE.md), limited to supported actions. Commands target the viewer's current asset when the viewer is open |
| C2 | P1 | Opaque toolbar band | Unified glass toolbar; content scrolls under it; title + subtitle top left |
| C3 | P1 | Toolbar controls differ | Photos order: sidebar toggle · scope icon menu (Both/Personal/Shared → Heirloom: All Libraries / Personal / each Shared Library) · zoom capsule · Years/Months/All Photos · Filter icon menu · Sort icon menu · "…" · Info · Share · Favorite · Rotate · Search field. Sync moves to the "…" menu, with status in the sidebar footer |
| C4 | P1 | Sidebar structure | Library, Collections. **Pinned** (owner-customizable: Favorites, Recently Saved, Map, Videos, Screenshots, People, Recently Deleted with lock). **Shared Libraries** (Heirloom extra, kept). **Albums** (All Albums + albums with thumbnail icons, folders). Search leaves the sidebar. Media Types move to Collections and View › Media Types |
| C5 | P1 | Search is a sidebar page with two fields | `NSSearchToolbarItem` in the toolbar with a suggestions popover (recent views, completions with counts); Return shows the Search results page (WP-P renders it) |
| C7 | P1 | Toolbar layout differs from Photos (title block, scope capsule, button groups and semantics, Select/Sync buttons, no search field, sidebar-toggle placement) | `SPEC-TOOLBAR-SETTINGS.md` §1–2. **Owner exception:** the scope capsule shows the icon **plus the full library name** with Photos' ⌃⌄ capsule style |
| C8 | P1 | Settings is one long form | Photos-style tabs General · Server · Shared Libraries · Storage, merged per owner decisions. **Never offer "Download Originals"** (`SPEC-TOOLBAR-SETTINGS.md` §3) |
| C9 | P2 | Photos-only General settings missing | Add the ones Heirloom/Immich supports (§3); omit the rest |
| C6 | P2 | Shared-library suggestion banner, Hide Sidebar ⌃⌘S, full-screen toolbar behaviour | As Photos |

### Edit mode (WP-E)
| ID | Pri | Gap | Photos target |
|---|---|---|---|
| E1 | P0 | First click on Edit ignored; Escape doesn't cancel; Markup panel clipped | Opens on the first click or Return. Escape = Cancel (confirm if dirty). No clipping |
| E2 | P1 | Modal sheet | Full-window edit mode: dark appearance, sidebar collapsed, top bar as in EVIDENCE.md, yellow Done |
| E3 | P1 | Tabs Adjust/Filters/Crop/Portrait/Markup | Adjust / Styles / Crop / Tools. Markup lives in the "…" menu. Portrait depth becomes an Adjust section ("Depth"), shown only when depth data exists |
| E4 | P1 | Plain sliders | Collapsible sections with filmstrip smart slider, AUTO, per-section reset and enable toggle, and an Options disclosure. Sections: Light, Color, Black & White, White Balance, Curves, Levels, Definition, Selective Color, Noise Reduction, Sharpen, Vignette, (Red-Eye P2). Reset Adjustments |
| E5 | P1 | Filters | Styles: Undertone and Mood presets (names as Photos), Tone/Color/Palette pad, Intensity, Reset Style. Keep the old filters available as a "Classic" group only if existing recipes reference them (migration) |
| E6 | P1 | Crop UI | On-image crop handles and rule-of-thirds grid; Straighten/Vertical/Horizontal dials; Flip; Aspect list as Photos; Auto; Reset |
| E7 | P1 | Edit opens after ~4 s with no feedback | Chrome and the preview proxy appear in ≤ 300 ms. Full-resolution original loads in the background with a spinner bottom right; sliders work on the proxy immediately and re-render on the original when it arrives |
| E8 | P2 | Tools | Clean Up / Extend / Reframe tiles. Implement only what we can do on-device (e.g. Vision subject-lift + CoreImage inpaint is out of scope). Unsupported tools are **not shown** (don't ship dead buttons) |
| E9 | P2 | Before/after | Compare button and press-and-hold `M`; Revert to Original; ⇧⌘C / ⇧⌘V copy/paste edits |

### Pages and data (WP-P)
| ID | Pri | Gap | Photos target |
|---|---|---|---|
| P1 | P0 | Collections: every tile "0 items"; Albums/People/Memories shelves empty; "No Photos" | Correct counts and key photos from the local store, shown on first paint |
| P2 | P0 | Search returns everything | Server smart search (Immich `/search/smart`, CLIP), plus metadata search (place, person, date, filename) merged locally. Suggestions with counts. Offline: local metadata only, with a clear banner |
| P3 | P0 | Media-type / shared-library / shared-album pages take 5–20 s+ | ≤ 1 s to first thumbnails from the local store (same snapshot pipeline as Library) |
| P4 | P1 | Collections layout | Photos shelves (EVIDENCE.md): Memories carousel, Pinned, Albums, People, Featured Photos, Shared Albums, Recent Days, Trips, Media Types list with counts, Utilities list with counts. Headers with "›" and a collapse chevron, persisted per user. Plus Heirloom: Shared Libraries shelf |
| P5 | P1 | Search results page | "Search" title, Photos \| Collections segmented control, Top Results row, "N Results" grid (reuses the WP-G grid) |
| P8 | P1 | People page shows every face as "Add Name" (Photos shows names) | Show Immich person names; "Add Name" only when truly unnamed. Verify against the server API first; it may be a mapping bug |
| P6 | P2 | Map, People, Memories, All Albums | Side-by-side audit against Photos, fixing the deltas: Map/Satellite/Grid control, thumbnail cluster pins with counts, People face tiles with names, Memories 16:9 cards with play |

### Performance and data pipeline (WP-F)
| ID | Pri | Gap | Target |
|---|---|---|---|
| F1 | P0 | Returning to Library re-runs `timelineRows` (18 s–2 min) | Timeline snapshot cached in memory per (scope, filter, grouping) and invalidated by the change center / sync deltas only. Return ≤ 150 ms |
| F2 | P0 | `timelineRows` itself can take minutes (`sqlite3_step`, LEFT JOIN assetExif) | `EXPLAIN QUERY PLAN` every timeline query. Add covering indexes, e.g. `asset(visibility, deletedAt, localDateTime DESC, id)` + scope columns. Drop the exif join from the grid projection (load lazily for the inspector). `PRAGMA mmap_size`. Cold query ≤ 1.5 s, warm ≤ 300 ms on 102k rows |
| F3 | P1 | Launch ~7 s with a "Connect to server" flash and a "0 Photos" flash | Decide the signed-in state synchronously from the keychain / defaults flag, so the connect screen never flashes. Show the last snapshot persisted on disk (ids + geometry + thumbhash) immediately, then refresh. Thumbnails ≤ 3.0 s cold (Photos 2.9 s), ≤ 1.5 s warm |
| F4 | P1 | Filter pages slow (P3 root) | Same snapshot builder with a SQL-side filter; covering indexes for type / shared-library / album membership |
| F5 | P1 | Thumbnail tiers for tiny zoom levels | Micro tier (≤ 64 px) generated or cached for mosaic zoom; decode off-main; velocity-aware prefetch |

## 2. Architecture decisions (made; executors follow them)

1. **Viewer pager.** Use `NSPageController` with `transitionStyle = .horizontalStrip`, hosted in a
   `NSViewControllerRepresentable`. It gives Photos' exact interactive swipe (1:1, spring, rubber-band,
   honours "Swipe between pages") and animated `navigateForward/Back` for ←/→.
   - Each page is an `NSViewController`: a zoomable image page (NSScrollView magnification + Live Text
     overlay) or a video page (AVPlayerView).
   - While a page is zoomed (magnification > 1), the page's scroll view consumes horizontal scroll until
     it reaches its edge, then lets the event bubble to the pager. This matches Photos.
   - The arranged objects are **asset ids** (display-order snapshot), never 102k view controllers.
     `NSPageController` asks for identifiers lazily and caches only neighbours.
   - **Fallback, only if the spike in WP-V step 1 shows `NSPageController` can't meet a requirement:**
     a custom `ViewerPagerView` driven by `NSEvent.trackSwipeEvent(options: [.lockDirection,
     .clampGestureAmount], …)`, with a 3-page recycling strip and `CASpringAnimation`
     (damping ratio 1.0, response 0.3). Write the reason in the WP report.
2. **Live Text** is an overlay on the zoomable page (`ImageAnalysisOverlayView`, with
   `trackingImageView` / contentsRect synced to the scroll view's magnification). It is never a separate
   view path.
3. **Viewer ↔ grid transitions.**
   - A small protocol in a new shared file `MacViewerTransition.swift` (owned by WP-V, read by WP-G):
     `protocol ViewerTransitionSource { func frameInWindow(for assetId: String) -> CGRect?;
     func image(for assetId: String) -> NSImage?; func setHidden(_: Bool, assetId: String);
     func scrollToVisible(assetId: String) }`.
   - The grid implements it. The viewer animates a snapshot layer between the cell rect and the fit rect
     (0.3 s spring). The pinch-close transition is interactive: the layer follows the gesture's scale.
4. **Edit mode** is a window-level mode (the main window's content swaps to `MacEditModeView`, the sidebar
   collapses, `NSAppearance.darkAqua` is applied to the window), not a sheet. The existing recipe model
   (`PhotosCore/Editing`) stays the storage format. New adjustments are new recipe keys with defaults, so
   old recipes still decode.
5. **Timeline snapshot cache** lives in `MacAppState` (or a new `TimelineSnapshotCache`) and is keyed by
   (scope, filter, grouping, sort). Disk persistence (F3) stores only compact columns.
6. **Grouping views.** Years and Months are separate lightweight card layouts backed by the same snapshot,
   using per-bucket key photos. They are not the 102k-item layout with different headers.

## 3. Budgets and how to measure them (Release, owner's library)

| Signpost / measure | Budget | Tool |
|---|---|---|
| `Launch.FirstThumbnails` (process start → first thumbnail drawn) | cold ≤ 3.0 s, warm ≤ 1.5 s | signpost + screen recording |
| `Library.Return` (sidebar click → grid drawn) | ≤ 150 ms | signpost |
| `Page.FirstPaint` (media type, shared library, album, Collections, Search results) | ≤ 1.0 s | signpost |
| Timeline query cold / warm | ≤ 1.5 s / ≤ 300 ms | signpost + `EXPLAIN QUERY PLAN` in the report |
| Grid scroll / flick | ≥ 55 fps, hitch ratio < 5 ms/s, no placeholder > 150 ms | Instruments Animation Hitches + recording |
| Grid pinch | no blank frame, ≥ 55 fps | recording, frame-by-frame |
| Viewer swipe / key paging | 1:1 tracking, settle ≤ 350 ms, ≥ 58 fps | Animation Hitches + recording compared side by side with `REF-photos-trackpad-swipe.mp4` |
| Viewer pinch / smart zoom | ≥ 58 fps, anchored at the pointer | recording |
| Viewer open/close transition | ≤ 300 ms, no blank frame | recording |
| Edit mode open | chrome + proxy ≤ 300 ms | signpost `Edit.Open` |
| Hangs | 0 hangs ≥ 250 ms in a 5-minute scripted session | Instruments Hangs |
| Memory | ≤ 1.0 GB after the 5-minute session | `footprint` |

**Measurement protocol.** Close the iOS simulator and Xcode test runs first; they contend for kperf and
the CPU. Run each measurement 3 times and report the median. Use the frame-counting recipe from
`EVIDENCE.md` for recordings:

```
ffmpeg -i clip.mp4 -vf "crop=…,scale=325:-2,mpdecimate=hi=64*4:lo=64:frac=0.1,showinfo" -f null -
```

## 4. Work packages, ownership, waves

| WP | Title | Brief | Owns (exclusive) | Agent / model |
|---|---|---|---|---|
| WP-T | Test infrastructure: fixture, unit + snapshot targets, AX identifiers, synthetic gestures, perf scaffolding, parity scripts | `WP-T-TESTINFRA.md` | `project.yml` (test targets), `Apps/macOS/Tests/**`, `Apps/macOS/UITests/**`, `AXIDs.swift`, `FixtureSeed.swift`, `Sources/Gestures/GestureInputs.swift`, `scripts/verify.sh`, `scripts/heirloom-parity/**` | implementer / Sonnet |
| WP-F | Timeline cache, query plans, launch path, filter pages, micro thumbnails | `WP-F-PERF.md` | `MacGridLoader.swift`, `MacAppState.swift`, `MacConnectView.swift`, `HeirloomMacOSApp.swift` (launch/sign-in gating only), new `TimelineSnapshotCache.swift`, `PhotosCore/Sources/LocalStore/**`, `PhotosCore/Sources/Media/**` | implementer / Sonnet. **Opus reviews the diff** |
| WP-V | Viewer: pager, zoom, Live Text overlay, video, transitions, toolbar, keys, context menu, inspector | `WP-V-VIEWER.md` | `MacViewer.swift` (split into files as needed), `MacLiveVideo.swift`, `MacLiveText.swift`, new `MacViewerPager.swift`, `MacViewerPages.swift`, `MacViewerTransition.swift`, `MacInspectorView.swift`, `MacAssetActions.swift` (menu builder, shared with WP-G by call only) | implementer / Sonnet. **Opus reviews the diff** |
| WP-E | Edit mode | `WP-E-EDIT.md` | `MacEditView.swift` → new `MacEditMode*.swift`, `PhotosCore/Sources/Editing/**` | implementer / Sonnet |
| WP-G | Grid: blank-after-viewer, scroll restore, Years/Months cards, glass scrolling, perf, pinch, selection, cells | `WP-G-GRID.md` | `MacCollectionGridView.swift`, `MacTimelineLayout.swift`, `MacGridCell.swift`, `MacGridHeaderView.swift`, `MacSelection.swift`, new `MacYearMonthCards.swift` | implementer / Sonnet. **Opus reviews the diff** |
| WP-C | Chrome: toolbar, glass, sidebar, menus, search field, Settings | `WP-C-CHROME.md` + `SPEC-TOOLBAR-SETTINGS.md` | `MacMainWindow.swift`, `MacSidebar*.swift`, `MacMenus.swift`, `MacSettings.swift`, `MacStorageView.swift`, `HeirloomMacOSApp.swift` (commands only, after WP-F merges) | implementer / Sonnet |
| WP-P | Pages: Collections, Search, Map, People, Memories, All Albums | `WP-P-PAGES.md` | `MacCollectionsView.swift`, `MacSearchView.swift`, `MacMapPlacesView.swift`, `MacMemoriesView.swift`, `MacPeopleView.swift`, `MacAllAlbumsView.swift`, `MacDuplicatesView.swift`, `PhotosCore/Sources/Search/**`, new `LocalStore+Counts.swift` additions (after WP-F merges) | implementer / Sonnet |
| WP-X | Verification gate after each wave | `WP-X-VERIFY.md` | read-only; writes `reports/` | verifier / Sonnet (build, tests, traces) + orchestrator (Opus, computer-use hands-on) |

Exact file names come from the scout map (`../heirloom-macos-perf/06-facts.md` is partially wrong). Before
Wave 1, the orchestrator has `scout` confirm every owned path exists and that no file is listed under two
WPs. Where a listed file doesn't exist, the WP creates it.

**Feature WPs and tests:** feature WPs add their tests under `Apps/macOS/Tests/<Area>/` and
`Apps/macOS/UITests/<Area>/`, in new files named for their area. Those files are owned by the feature WP
even though WP-T owns the folders.

**Waves**
0. **Wave 0:** WP-T alone. → **Gate 0**:
   - the existing UI tests are green on a quiet host;
   - the new targets run;
   - the fixture (small and large) seeds;
   - `framestats.sh` reproduces the REF/CUR swipe difference.
1. **Wave 1:** WP-F ∥ WP-V ∥ WP-E. They touch disjoint files. WP-V creates `MacViewerTransition.swift`
   first, commits it alone and reports its SHA so WP-G can build against it. → **Gate 1**: the P0s
   F1, F2, V1–V4, E1 are fixed with proof, and the swipe side-by-side video is accepted by the orchestrator.
2. **Wave 2:** WP-G ∥ WP-C ∥ WP-P, based on the Gate 1 merge. → **Gate 2**: the P0s G1, G2, C1, P1–P3
   are fixed, every §3 budget is met or has a documented, owner-accepted exception, and the full hands-on
   side-by-side walkthrough (WP-X §3) is done.
3. **Wave 3:** fix-ups from Gate 2 plus the remaining P2 items, sent back to the same WP agent. →
   **Gate 3 (final)**, then Release install and a report to the owner. No PR unless asked.

## 5. Definition of done (whole program)

- Every P0 and P1 row in §1 is closed with evidence: a screenshot or clip pair in `reports/` named
  `<ID>-before/after`. P2 rows are closed or explicitly deferred by the owner.
- `REF-*` vs `AFTER-*` recordings for swipe, pinch, grid scroll and launch sit side by side in
  `reports/FINAL.md`, with frame metrics.
- Budgets in §3 are met (median of 3).
- The build has zero warnings. `verify.sh core mac-unit mac-ui` is green on a quiet host, and
  `mac-perf` meets its baselines.
- Every gap ID has its `TEST-PLAN.md` tests, shown red on base and green at the tip. The final report
  holds the full ID → test table.
- Every pair in `DESIGN-REFERENCE.md` has an AFTER capture that the orchestrator judged a match (or has an
  owner-accepted deviation).
- No regressions in the iOS targets that share PhotosCore: `xcodebuild -scheme Heirloom-iOS build`
  succeeds.
