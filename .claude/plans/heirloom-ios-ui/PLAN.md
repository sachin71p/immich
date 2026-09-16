# Heirloom iOS: native-Photos look, working controls, smooth scrolling

**Goal.** The Heirloom iOS app should look and behave like the iOS 27 Photos app on the owner's
iPhone:
- every control works;
- a 102k-asset library launches and scrolls smoothly.

**Evidence** (read before starting):
- `03-audit.md`: findings P1–P9, L1–L18, V1–V7, C1–C6, S1–S4, T1–T5.
- `02-profile.md`: device traces.
- `01-controls.md`: control inventory.
- `shots/`:
  - `device-native-*`: **the design reference, treat it as the spec.**
  - `device-heirloom-*`: current state.
  - The PNGs contain personal photos. They are git-ignored; never commit them, never upload them.

**Base.**
- Branch `fix/heirloom-ios-sync` @ `b38ea8217`, which includes the working sync.
- Integration branch: `feat/heirloom-ios-native-ui`, cut from that commit.
- Repo: `/Users/spatel/workspace/github/projects/immich`. App code lives in `native-apple/Apps/iOS/Sources`.
- The xcodegen project is `native-apple/project.yml`. Deployment target is iOS 27, so the iOS 26+
  SwiftUI APIs (Liquid Glass, `Tab(role: .search)`, `tabBarMinimizeBehavior`,
  `tabViewBottomAccessory`, `navigationSubtitle`) need no availability checks.

## Global rules
1. **Isolation**
   - Each WP runs in its own worktree: `git worktree add ../immich-ios-wpN -b feat/heirloom-ios-wpN <base>`.
   - Never work in the main checkout: another session owns it, on `perf/heirloom-macos`.
   - Never touch `main`, `feat/shared-libraries` or `perf/heirloom-macos*`.
   - Don't use the `../immich-ios-sync` worktree: it has `feat/shared-libraries` checked out.
2. **Ownership.** Edit only the files your WP owns (table below). New files go under
   `native-apple/Apps/iOS/Sources/<Area>/`. xcodegen picks up sources by folder; run `make xcodegen`
   and commit the regenerated project.
   - `Apps/Shared/*` is shared with macOS: keep its public API unchanged.
   - PhotosCore changes are additive only (new functions or files); `swift test --package-path native-apple/PhotosCore` must stay green.
3. **No destructive actions on the real library.** Don't use trash, delete, move, hide, lock or
   archive on the owner's server. Verify those flows only with `-useFixtureStore` UI tests.
4. **Signing.** Keep team `599Z443923` and bundle id `com.immich.heirloom.ios`.
5. **Device.** Only the orchestrator installs to the device (see Gates). Subagents build and test on the simulator.
6. **Commits.**
   - Conventional Commits (`feat(ios): …`, `fix(ios): …`, `perf(ios): …`), one per step, each
     ending with the Co-Authored-By trailer.
   - No push, no PR, no merges except by the orchestrator.
7. **Main-actor discipline.**
   - No O(rows) work on the main actor or in any SwiftUI `body`/computed property.
   - No `DateFormatter` or `NumberFormatter` allocation per call (use static cached formatters).
   - `CancellationError` is never an error for the user.
8. **Logging.** Use `HeirloomLog` categories and `HeirloomSignpost` intervals (`GridLoad`,
   `SnapshotBuild`, `LayoutPrepare`, `ThumbnailFetch`, `ThumbnailDecode`, `ViewerOpen`). They are
   used by the perf gate.

## Performance budgets
Measured on the owner's iPhone 17 Pro Max, Release build, ~102k assets:

| Metric | Now | Budget |
|---|---|---|
| Cold launch → first real thumbnails | ~10 s | **≤ 1.5 s** |
| Hangs (Instruments "Hangs") in the 3-min Gate scenario | 10 (worst 2.1 s) | **0 over 250 ms** |
| `updateUIViewController` + `render` main-thread cost | 41% of main | **p95 ≤ 2 ms**, independent of library size |
| Thumbhash decode on the main thread | 23–34% | **0** (off-main, cached) |
| Viewer open from Library | 0.9 s hang | **≤ 250 ms** |
| Years / Months / All switch | multi-second | **≤ 300 ms** |
| Collections first paint / all counts | slow, unbounded | **≤ 500 ms / ≤ 2 s** |
| Sync completion while idle | full library rebuild | incremental diff, no hang |

## Work packages

| WP | Title | Owns (edit rights) | Depends on |
|---|---|---|---|
| WP0 | Scaffolding, fixture visuals, quick S1 fixes | `LibraryGrid.swift` (split only), `FixtureSeed.swift` (+ a fixture media path), `Settings.swift` (L2/T4/L18 only), cancellation filtering in any iOS file (L2 only), `UITests/*`, `project.yml` (iOS test wiring only) | — |
| WP1 | Grid engine: data, layout, cells, perf | `Grid/*` (from WP0's split), `Library/LibraryGridLoader.swift`, `Library/LibraryView.swift` (step 9 swap only), `SearchView.swift` (grid call-site only), PhotosCore `LocalStore/LocalStore+TimelineIndex.swift` (new), `SyncEngine/WireTypes.swift` + a new LocalStore migration (L14 only) + tests | WP0 |
| WP2 | Library screen chrome and zoom levels | `Library/LibraryView.swift`, `Library/*` (new: filter menu, Years/Months views, selection bars), `MoveSheet.swift` (`SelectionActionBar` only) | WP1 |
| WP3 | Photo viewer | `Viewer.swift`, `Viewer/*` (new), `LiveVideo.swift` | WP1 |
| WP4 | Collections + all detail screens | `Collections.swift`, `Albums.swift`, `Spaces.swift`, `MemoriesView.swift`, `Collections/*` (new) | WP1 |
| WP5 | App shell, Search, account/settings | `HeirloomIOSApp.swift` (MainTabs), `SearchView.swift`, `Settings.swift`, `Search/*`, `Account/*` (new) | WP1 |
| WP6 | Verification gate | reports only | each wave |

Waves:
- **W1:** WP0 → WP1 (sequential), then Gate 1.
- **W2:** WP2 ∥ WP3 ∥ WP4 ∥ WP5 from the merged W1 tip, then Gate 2 (final).

W2 interface contracts (defined by WP1; W2 WPs must only *use* them):
- `AssetGridView` (SwiftUI) is the single grid component for every photo collection.
- `GridSelectionModel`
- `ViewerRoute`

---

### WP0: scaffolding, fixture visuals, quick S1 fixes
1. **Split `LibraryGrid.swift` (no behaviour change).** Move the code verbatim into:
   - `Grid/PhotoGridCell.swift`, `Grid/BucketHeaderView.swift`, `Grid/PhotoGridViewController.swift`, `Grid/PhotoGridView.swift` (the representable);
   - `Library/LibraryGridLoader.swift`, `Library/LibraryView.swift` (with `LibraryZoomLevel`, `LibrarySource`, `ViewerRequest`).

   Delete `LibraryGrid.swift`. Build green and UI tests green before continuing.
2. **Fixture visuals.** In `-useFixtureStore` mode, cells, album covers and the viewer currently
   render blank.
   - Give fixture assets deterministic **generated images**: solid hue per asset id plus a
     large index number. Drawn with `UIGraphicsImageRenderer`, cached, served by a fixture
     `MediaPipeline` path.
   - Add fixture thumbhashes.
   - Mix aspect ratios (portrait, landscape, panorama) and include videos with durations
     (0:07, 1:05:03) and live photos.
   - Add `-fixtureSeedCount=<N>` (N ≤ 150000, dates spread over 15 years) for perf runs in the
     simulator, through the same `apply()` path.
3. **L2.**
   - Treat `CancellationError` (and `URLError.cancelled`) as non-errors everywhere a
     `lastError`/`actionError` is set in the iOS app. Add a tiny helper
     `Error.isCancellation` in `Library/ErrorFilter.swift`.
   - Clear a stale cancellation message on launch.
4. **L3 / L5, a minimal interim fix** (WP1 replaces the cell later):
   - render the selection overlay **above** the image;
   - reconfigure visible headers when `editMode` changes.
5. **Remove developer text** shown to users: the About footer (T4) and the "External Libraries"
   placeholder (L18). Hide that section when it has no content.
6. **UI-test harness.**
   - Add `UITests/ScreenshotTour.swift`: with fixture data, it visits every tab, sheet and menu
     listed in `01-controls.md` and attaches screenshots (`XCTAttachment`, lifetime `.keepAlways`).
   - Make sure `bash native-apple/scripts/verify.sh ios` runs it.
   - W2 WPs extend the tour for their screens.

**Done.** `make build-ios` and `verify.sh ios` are green. `reports/WP0-REPORT.md` lists the file
map (old line → new file), the fixture image approach, and the test list.

### WP1: grid engine (fixes P1–P5, P7, L1, L3, L4, L13–L15)
Design constraints:
- the collection view gets data from an **index**, not a hydrated model;
- all heavy work happens off-main;
- SwiftUI passes only small value parameters.

1. **Timeline index (PhotosCore, additive).** Add `LocalStore+TimelineIndex.swift` with:
   - `timelineIndex(scope:) -> TimelineIndex`: a compact array of `(id, localDateTime, flags)`
     for all visible assets, **one** SQL query ordered by date desc. Flags cover
     video/live/favorite/shared-container/screenshot/edited. Add `durationSeconds` for videos.
   - `bucketSummaries(scope:, granularity: .year/.month/.day)`: key, count, key asset id
     (prefer favorite, else the most recent), and date range. Add `.year` to `Granularity`.
   - `assetsLite(ids:)`: batched per visible page.

   Add unit tests, including a 150k-row perf test (index build ≤ 400 ms on the Mac).
2. **L14 (confirmed root cause): duration unit bug.** The server sends `duration` as integer
   **milliseconds** (`server/src/schema/migrations/1777667825574-ChangeDurationToInteger.ts`,
   `sync.dto.ts:101`). `WireTypes.swift:104` stores it unchanged as `durationSeconds`, so badges
   show 1000× the real length (110,708 ms is shown as "1845:08").
   Fix, in PhotosCore (this step may touch `SyncEngine/WireTypes.swift` and add a `LocalStore`
   migration):
   - (a) map `durationSeconds = Int((Double(ms) / 1000).rounded())`;
   - (b) add a one-time GRDB migration: `UPDATE asset SET durationSeconds = CAST(ROUND(durationSeconds / 1000.0) AS INTEGER) WHERE durationSeconds IS NOT NULL`;
   - (c) add unit tests for the mapping and the migration.

   Display format: `m:ss` under 1 h, `h:mm:ss` from 1 h. The macOS app shares the bug through
   PhotosCore; tell the macOS orchestrator in the report (don't edit macOS files).
3. **Loader.** `LibraryGridLoader` (a `@MainActor` `ObservableObject`) publishes only:
   - an immutable `final class GridSnapshot` (reference type): sections, ids per section, index
     lookup and a generation counter;
   - `isLoading`.

   Build the snapshot in a detached task, gated by generation (a newer request cancels an older
   one). Cancellation is silent.

   **Sync updates:** re-query the index and apply a **diff**. Never tear down the grid. Debounce
   `timelineVersion` bumps to at most 1 per 2 s.
4. **Layout (L1).**
   - Always use fixed square cells: `fractionalWidth(1/columns)` for width and height, with 1 pt
     spacing like native (`device-native-02`).
   - "Aspect Ratio Grid" keeps the square cell and changes the image to `scaleAspectFit` on a
     neutral fill.
   - Remove every `.estimated` size.
   - Default columns: 5 in All.
   - Pinch steps `[1, 3, 5, 9, 13]`, animated with a layout transition that keeps the pinch
     anchor item in place.
   - Section headers: none in All; Months/Years are separate views (WP2); Days is removed.
5. **Render path (P3).** Split `updateUIViewController` into cheap setters. Each setter compares
   against the old value and does minimal work:
   - `snapshot`: apply only when the generation changes, with `apply(_, animatingDifferences:)`
     and a diff;
   - `columns`/`aspectFit`: `setCollectionViewLayout` only on change;
   - `editMode`: **no snapshot or layout reset (L4)**; reconfigure visible cells only;
   - selection: diff against `indexPathsForSelectedItems`, never loop over all rows.

   Wrap the setters in `HeirloomSignpost` `GridLoad` / `SnapshotBuild` / `LayoutPrepare`.
6. **Cell (L3, L13, L15, P4).** Rewrite `PhotoGridCell` with manual `layoutSubviews`, no Auto Layout:
   - Placeholder fill `secondarySystemFill`, then the thumbhash image, then the thumbnail.
   - **Thumbhash decode is off-main**, in an `NSCache` keyed by asset id. The cell is set
     synchronously only from a cache hit.
   - Badges are SF Symbols matching native:
     - `heart.fill` bottom-left;
     - duration bottom-right, formatted `m:ss` / `h:mm:ss` with a static formatter;
     - `person.2.fill` top-right for shared-library/space assets;
     - `livephoto` only when the "Show" option wants it.
   - Selection (native `device-native-09`): in edit mode every cell shows an empty
     `circle` bottom-right; selected cells show `checkmark.circle.fill` (white on tint) plus a
     light dim. The overlay sits above the image.
   - Cancel loads in `prepareForReuse`. Use the prefetch data source for thumbnails, with priority
     by visibility.
7. **Fast scroller (L12).**
   - Remove the rotated `Slider`.
   - Add a UIKit scroll handle on the right edge: it appears while scrolling and can be dragged.
   - While dragging, show a floating glass date bubble ("Sep 2018") from the index.
8. **Public component for W2.** `AssetGridView` (SwiftUI) takes:
   - a data source: `timeline(scope)`, `ids([String])` or `query(async closure)`;
   - `columns: Binding`, `aspectFit: Bool`, `selection: GridSelectionModel?`
     (`ObservableObject`: ids set, `isSelecting`);
   - `onOpen(ViewerRoute)`, where `ViewerRoute` holds an **index provider plus a start id**
     (never an array copy of all ids);
   - `header: AnyView?` (for album hero covers);
   - `onRefresh`;
   - `visibleRange` callback (first/last visible dates, for the title subtitle).

   Document it in `Grid/README.md`.
9. **Keep LibraryView working** (WP2 restyles it): swap it onto `AssetGridView`, remove the Days
   case, and remove the Square toggle (aspect fit defaults to off). Search's `PhotoGridView` use
   must still compile; WP5 moves it later.

**Done.**
- Unit and UI tests are green.
- With `-fixtureSeedCount=100000` in the simulator: first grid paint ≤ 1.5 s. A scripted
  flick-scroll UI test runs with no main-thread stall over 100 ms (record a signpost summary).
- `reports/WP1-REPORT.md` covers the API, the L14 root cause, and the numbers.

### WP2: Library screen (L6–L11, L16, L17, P5)
Spec: `device-native-02` … `10`.
1. **Title.**
   - `.navigationTitle("Library")` in large display mode.
   - `navigationSubtitle` shows the visible date range from `AssetGridView.visibleRange`, with
     cached formatters, e.g. "Dec 19, 2017 – Feb 9, 2025".
   - At the very bottom, show "12,165 Items" (a count from the index).
   - While syncing, append " · Syncing…".
2. **Trailing toolbar**, native glass buttons.
   - **Filter menu** (`line.3.horizontal.decrease`), mirroring `native-06/07/08`:
     - Sort section: Added / Captured, as two large buttons at the top.
     - "Filter:" items with checkmarks: All Items, Favorites, Edited (if the flag exists,
       otherwise omit), Shared with You (= space assets), Captured by Me, Not in an Album.
     - Media Types ▸ (Videos, Live Photos, Screenshots, Selfies, Panoramas: whatever the store
       supports).
     - **Library View ▸**: Both Libraries / Personal Library / each Space / each external library,
       with a checkmark on the current one, plus "Show in Timeline…" (existing sheet). This
       replaces the top-left switcher (L10).
     - **View Options ▸**: Zoom In, Zoom Out, Aspect Ratio Grid (toggle), and "Show:" Screenshots /
       Shared with You / Shared Library Badge.
     - Persist all of these in `@AppStorage`.
   - **Select** button.
   - Remove "−/+", the Square toggle row and the top-left button.
3. **Zoom levels (L7, L8).**
   - Use a glass segmented control **Years · Months · All** in `tabViewBottomAccessory` (or the
     minimized tab-bar region), matching `native-02`. Drop Days.
   - The tab bar uses `.tabBarMinimizeBehavior(.onScrollDown)` (WP5 owns MainTabs; coordinate
     through the modifier on LibraryView, or tell WP5 in the report).
   - **Years view** (`Library/YearsView.swift`, spec `native-05`): vertical list of full-width
     rounded (≈16 pt) cards, one per year, with the key photo and year label top-left. Tapping
     one opens Months scrolled to that year.
   - **Months view** (`native-04`): a section per month ("Sep 2026" header). Each has a hero card
     (key photo of the month) and a 3-column row of day cards with the day number top-left.
     Tapping a day opens All scrolled to that day.
   - Both views are UIKit/compositional or `LazyVStack`, driven by `bucketSummaries`, and load
     only key thumbnails.
4. **Select mode (L16, spec `native-09/10`).**
   - Top bar: filter button, "…" menu, ✕.
   - The "…" menu holds: Copy, Duplicate (if supported, else omit), Hide, Favorite, Add To ▸
     (albums), Move To ▸ (Personal / Spaces: the existing `MoveSheet`), Archive, Adjust Date
     (only if supported).
   - The bottom toolbar **replaces the tab bar**: Share (`ShareLink` over exported files; keep the
     existing implementation), a centre "N Selected" label (or "Select Items" when 0), and Trash
     (with confirmation).
   - Permission gating stays as it is (`Permissions`).
   - Replace `SelectionActionBar`.
   - Drag-to-select keeps working. Entering or leaving Select mode never moves the scroll position.
5. The **error banner** shows only real errors, as a glass capsule under the title, with Retry.

**Done.** Fixture UI tests cover:
- each filter item, Library View switch and View Options item;
- zoom switches;
- Years → Months → All drill-down;
- selecting 3 items, the … menu opens, the Trash confirmation appears and is cancelled.

Also: screenshots added to the tour, and `reports/WP2-REPORT.md`.

### WP3: photo viewer (V1–V7, P6)
Spec: `device-native-11` … `14`.
1. **Reproduce V1 first.** Write a fixture UI test that opens the viewer and taps Info, "…" and
   Share. Confirm they fail, identify the cause, and record it in the report. Suspects:
   - the `.gesture(DragGesture())` on the NavigationStack (`Viewer.swift:~235`);
   - bottom-bar items inside the full-screen cover.
2. **Pager.** Replace the SwiftUI `TabView(ForEach(ids))` with a UIKit pager: a horizontal paging
   `UICollectionView` or `UIPageViewController`.
   - It is driven by `ViewerRoute` (index provider plus start id), so it's O(1) to open.
   - It prefetches ±2 pages (preview tier, then full size).
   - It supports pinch and double-tap zoom (a `UIScrollView` per page).
   - A single tap toggles the chrome.
   - An **interactive swipe-down dismiss** is done in UIKit, so it doesn't conflict with the bars.
3. **Chrome.**
   - Top: glass back chevron (not ✕); a centre glass pill with location (city, from exif) on
     line 1 and date · time on line 2; a "…" menu on the right.
   - Badge row: LIVE (tap to play), and "From <owner name>" for space assets.
   - Bottom: a **filmstrip** of neighbouring thumbnails (tap to jump), then a glass bar:
     - Photos: Share · Favorite · Info · Adjust · Trash.
     - Videos: native-style scrubber with play/pause and mute above the bar (`native-11`).
     - The existing permission gating decides which buttons appear.
   - The "…" menu (`native-14`): Copy, Duplicate (if supported), Hide, Slideshow (if a simple
     one exists, else omit), Add To ▸, Move To ▸, Archive, Lock, Adjust Info (date/location, if
     supported).
4. **Info (V2, V6).**
   - Swiping up (or tapping Info) slides the photo up and reveals an inline panel (`native-13`):
     - a caption/description field (if supported);
     - a card with date · time and file name;
     - a camera card with make/model, lens, MP · dimensions and the ISO/mm/ev/ƒ/shutter row;
     - a map card (existing `MiniMap`);
     - people (face chips), albums, and the "Container" info as "Library: Personal / <Space>".
   - Swiping down closes it.
5. **Signposts.** `ViewerOpen` on open, `ThumbnailFetch` per page.

**Done.** UI tests cover:
- open viewer, swipe to the next item, open and close Info, open the … menu;
- Favorite toggles in fixture mode;
- Trash shows its confirmation (cancel it);
- swipe-down dismisses.

With 100k fixture assets, opening the viewer takes ≤ 250 ms (signpost). Also
`reports/WP3-REPORT.md`, including the V1 root cause.

### WP4: Collections and detail screens (C1–C6, P9)
Spec: `device-native-15` … `21`, `23`.
1. **Counts and loading (P9).** Add PhotosCore count/summary queries (additive):
   - `collectionCounts(scope:)`: one query returning favorites, recents, trash, hidden, archive,
     locked, captured-by-me, each media type and located;
   - `personSummaries(owner:)`: one GROUP BY with count and a face-crop/cover asset.

   The screen paints section shells immediately and fills them in lazily per section.
2. **Investigate C1a first:** why are person counts 0 and names empty? Check face/person sync.
   - Fix it if it's a mapping bug.
   - Always hide people who are unnamed **and** have zero assets.
   - Load face thumbnails via the Immich person thumbnail endpoint (through the existing
     API/media layer; add a `Media` tier or request if needed, additively).
3. **Layout (C3).** Use a `ScrollView` of collapsible sections, each with a "Title ›" header and
   a chevron toggle, in native order:
   - Memories: large 3:4 cards, horizontal.
   - Pinned: Favorites / Recents / Map tiles, plus Edit (reorder pinned; persist it).
   - Albums › (square tiles with title overlay).
   - People › (face cards, name overlay).
   - Shared Albums › (with owner avatar).
   - Shared Libraries (the Spaces tiles; "+" creates one via the existing flow; this replaces the
     Shared tab).
   - Recent Days (day tiles).
   - Media Types (2-column pill grid with SF Symbols).
   - Utilities (pill grid: Favorites, Hidden 🔒, Recently Deleted 🔒, Duplicates,
     Captured by Me, Archive, Locked 🔒).
   - Places (map tile). Camera models go under Utilities › "Captured With".
   - Reorder at the bottom; persist section order and collapse state.

   Header: large title "Collections"; trailing "…" and an **account avatar button** (WP5 provides
   `AccountButton`; until then use a placeholder view named `AccountButtonPlaceholder`).
4. **All detail screens (C2).**
   - Replace all 11 `AssetRowList` uses with `AssetGridView`.
   - Albums, Spaces, Memories and People get a **hero cover header** (`native-20`): key photo,
     title, item count, and a play/slideshow button where one exists.
   - Utilities and media types get a simple large title plus the grid.
   - Delete `AssetRowList`/`RowThumbnail` when they're unused.
5. **Albums › page (C4, `native-19`).** Personal / Shared segments, a 2-column rounded tile grid,
   and "+" (existing create flow).
6. **People › page (`native-21`).** A 3-column face-card grid with a Sort menu. Groups are
   optional: omit them unless the data exists.
7. **Space timeline (C5).** Use the grid, sorted by date desc.
8. **Memories page (C6, `native-23`).** Full-width cards with title/date and a play button.

**Done.** Fixture UI tests open every section and every detail type. Collections first paint is
≤ 500 ms with 100k fixture assets. `reports/WP4-REPORT.md` includes the C1a root cause.

### WP5: app shell, Search, account (T1–T5, S1–S4)
1. **Tabs (T1).**
   - `TabView`: `Tab("Library")`, `Tab("Collections")` and `Tab(role: .search)`, with
     `.tabBarMinimizeBehavior(.onScrollDown)`.
   - Remove the Shared and Settings tabs. Shared lives in Collections (WP4) and the filter menu
     (WP2); Settings moves behind the account avatar.
   - Keep deep links, intents and state restoration working: check `Intents/` and `Extensions/`
     for tab references.
2. **Account (T3, T4).**
   - `Account/AccountButton.swift` is the avatar (initials fallback) used in the Collections
     toolbar.
   - `Account/AccountSheet.swift`, a sheet with:
     - the user's **name and email** (from `/users/me`; never the UUID) and the server host;
     - Sync (Sync Now, Last synced, last *real* error);
     - Upload/Backup, Timeline sources, Storage/Free Up Space, cache usage;
     - Shared Libraries management (list + create);
     - Sign Out (with confirmation) and About (version only).
   - Reuse existing `SettingsView` sections by moving them. Keep behaviour.
3. **Search (S1–S4, spec `native-22`).**
   - A search tab with a large title "Search". The system bottom search field comes with the
     search role (`.searchable`), plus a mic if available.
   - Body when the query is empty:
     - **Recents** row of image cards (recent queries with the top result's thumbnail; Clear, ›);
     - suggestion pills near the bottom (People names, Places, "Videos", recent months).
   - Typing: debounce by 300 ms, cancel stale tasks, and put results in `AssetGridView`.
   - Keep the existing scope ("All" → Library View filter) and Filters, as a toolbar menu
     instead of rows.
   - **Investigate S2a:** why are Places/Camera suggestions empty and People names blank? Fix it
     or document it.
4. **T5.** Make sure the built Info.plist actually contains `BGTaskSchedulerPermittedIdentifiers`.
   The sync REPORT (F1) says `project.yml` has it but the bundle doesn't. Verify with
   `plutil -p <app>/Info.plist`.

**Done.** Fixture UI tests cover:
- the 3 tabs;
- the account sheet opens and shows a name;
- Sign Out shows its confirmation (cancel it);
- search typing → results grid → viewer;
- Recents appear.

Also `reports/WP5-REPORT.md`.

### WP6: gates (orchestrator + verifier)
For each gate:
1. `→ verifier (sonnet)`: `make build-ios`, the device Release build (command in
   `../heirloom-ios-sync/PLAN.md` §Verification), `swift test --package-path native-apple/PhotosCore`,
   and `bash native-apple/scripts/verify.sh ios`. It summarizes the results and collects the
   tour screenshots into `reports/gateN-shots/` (git-ignored).
2. **Orchestrator, device.**
   - Ask the owner once before the first install.
   - Install: `xcrun devicectl device install app --device 00008150-0002604111A1401C <Release-iphoneos>/Heirloom-iOS.app`.
     Same bundle and team, so data and sign-in are kept.
   - Launch, then record while running the scenario:
     `xcrun xctrace record --template 'Time Profiler' --instrument Hangs --device 00008150-0002604111A1401C --attach <pid> --time-limit 180s`
     (get the pid from `xcrun devicectl device info processes`).
3. **Scenario** (drive via Device Hub live view with computer-use; see "Driving the device"):
   1. cold launch;
   2. fling the Library 10×;
   3. drag the scroller;
   4. Years → Months → tap a day;
   5. pinch zoom;
   6. filter menu → Favorites → All Items;
   7. Library View → Personal → Both;
   8. Select 3 → … menu → dismiss → ✕;
   9. open the viewer, swipe 5×, Info up/down, close;
   10. Collections: scroll to the bottom, open an album, a person and Recently Deleted;
   11. Search: type "beach", open a result;
   12. account sheet.

   **Never confirm** trash, delete, move, hide, lock or archive on the real library.
4. `→ verifier (sonnet)`: summarize the trace against the budgets and `02-profile.md`.
5. **Orchestrator.**
   - Capture device screenshots of each screen: `xcrun devicectl device capture screenshot --device … --destination <file>`.
   - Compare each against its `device-native-*` counterpart.
   - Update the statuses in `03-audit.md` (add a Status column: FIXED / OPEN / WONTFIX + reason).
   - Write `reports/GATE-N.md`.

**Driving the device (lessons from the audit):**
- Device Hub (`com.apple.dt.Devices`) live view accepts clicks as taps and `left_click_drag` as
  swipes. Mouse-wheel scroll does **not** work.
- Take coordinates from a full-screen screenshot of the Device Hub window.
- Notification banners cover the top of the screen: wait about 5 s or swipe them up before
  capturing.
- Typed text is only partially forwarded; prefer fixture UI tests for text entry.
- If another session is running macOS UI tests (`AutomationModeUI` overlay), don't click; wait.
- Don't capture or save screens showing identity documents; scroll past them.

Final deliverable:
- Gate 2 green;
- `03-audit.md` fully statused;
- `reports/FINAL.md` with before/after numbers and side-by-side screenshot pairs (paths only).
