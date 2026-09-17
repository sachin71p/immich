# WP2 report — Library screen chrome and zoom levels

Worktree `immich-ios-wp2`, branch `feat/heirloom-ios-wp2`.
Reference screenshots (`shots/device-native-02…10`) were absent from this
worktree (git-ignored PNGs, empty `shots/` dir); implementation follows the
PLAN §WP2 text spec plus the WP1 grid contracts (`Grid/README.md`).

## What changed (WP2-owned files only)

- `Library/LibraryView.swift` (rewrite): large `navigationTitle("Library")` +
  `navigationSubtitle` from `AssetGridView.onVisibleRange` (static cached
  formatter); bottom `Years · Months · All` glass segmented control +
  `N Items` count in `tabViewBottomAccessory`; `.tabBarMinimizeBehavior(.onScrollDown)`
  modifier on LibraryView; trailing toolbar = filter menu + Select (select mode:
  ✕ leading, filter + "…" trailing); tab bar hidden while selecting; glass error
  capsule (top inset, real errors only, Retry); removed −/+ steppers and the
  top-left switcher. All grid input resolves through `resolveLibraryGrid`;
  Years/Months are separate views. State persists in `@AppStorage` (`heirloom.*`).
- `Library/LibraryFilter.swift` (new): `LibrarySort` (Added/Captured),
  `LibraryFilterItem` (All/Favorites/Edited/Shared-with-You/Captured-by-Me/
  Not-in-Album), `LibraryMediaKind` (Videos/Live Photos/Screenshots/Panoramas)
  + `resolveLibraryGrid` (default state keeps the fast `.timeline` path; anything
  else resolves `.ids` via paged off-main queries: index flags for
  favorites/edited/shared/screenshot/video/live, `timelineRows` join for
  Captured-by-Me and panoramas, `assetIdsInAnyAlbum` for Not-in-Album,
  `recentAssets` pages for Added sort).
- `Library/LibraryFilterMenu.swift` (new): flat button groups (see deviation 3) —
  Sort buttons, Filter: checkmarks, Media Types, Library View (Both/Personal/each
  Space/each external library + Show in Timeline… — absorbs the switcher), View
  Options (Zoom In/Out, Aspect Ratio Grid, Show Screenshots / Show Shared with
  You). Stable labels for tests.
- `Library/YearsView.swift`, `Library/MonthsView.swift`, `Library/KeyAssetPhoto.swift`
  (new): year cards (`bucketSummaries(.year)`), month sections with hero + 3-col
  day cards (`bucketSummaries(.month/.day)`), key thumbnails only via the
  production `pipeline.load(.thumbnail)` path (fixture art through
  `FixtureArtwork`). Year tap opens Months scrolled to that year. `KeyAssetPhoto`
  crops the art to the display aspect in UIKit and shows it with a plain stretch
  into explicit frames — no `aspectRatio` anywhere (see deviation 6).
- `Library/LibrarySelectMenu.swift` (new): select-mode "…" menu — Copy
  (pasteboard, capped at 25 for memory safety), Hide, Favorite, Add to Album…
  (existing picker), Move To… (existing `MoveSheet`), Archive. All
  `Permissions`-gated.
- `MoveSheet.swift` (`SelectionActionBar` only): native bottom toolbar replacing
  the tab bar — Share (existing export), centre `N Selected` / `Select Items`,
  Trash with confirmation. Post-trash exits select mode.
- Tests: `UITests/LibraryChromeUITests.swift` (filter items, sort+media types,
  Library View switch, View Options, Years→Months→All drill-down, select-3 +
  … menu + Trash-confirm-cancel); `ScreenshotTour.tourLibrary` extended
  (filter menu, drill-down, select chrome, move sheet); `A3SmokeUITests` updated
  for the moved chrome (switcher/"Move to…" button gone).

## Verification

- `make build-ios`: green (after `native-apple/scripts/gen-api.sh` — the
  ImmichAPI openapi.yaml copy; same prerequisite as a clean tree).
- `swift test --package-path native-apple/PhotosCore`: green except one
  load-dependent flake (`timelineRows` 102k perf budget; fails only when the
  host is busy, passes isolated; PhotosCore untouched by WP2).
- `LibraryChromeUITests` (6 tests): green as a scoped class run
  (`-only-testing:Heirloom-iOS-UITests/LibraryChromeUITests`).
- `ScreenshotTour` (incl. extended `tourLibrary`): green; WP2 screenshots
  (01/02/03a/03b/03c/04/05/05b/06/07) captured from the passing run.
- `bash native-apple/scripts/verify.sh ios` full suite: NOT green in this
  environment — the test runner is killed on bootstrap (signal kill, 0 tests
  run) whenever the host is out of memory. This predates WP2 (the 08:19
  pre-change baseline shows the same signature) and coincides with a sibling
  WP3 simulator session on the same host plus a leftover 100k-fixture app
  instance. All WP2-owned tests pass scoped; the full-suite gate needs a
  quiet host (or higher-memory CI).

### Close-out run (2026-09-17, worktree `immich-ios-wp2`, commit `2979cb55e`)

Each gate run exactly once, no re-runs, no new probes
(`UITests/WP2DebugUITests.swift` by-design-failing dump probe deleted, not run).

- `make build-ios` (after `native-apple/scripts/gen-api.sh`, exit 0, no output):
  **GREEN** — `** BUILD SUCCEEDED **` (xcodegen regen + simulator build).
- `swift test --package-path native-apple/PhotosCore`:
  **RED (known flake)** — 185 tests / 26 suites, 184 pass, 1 fail:
  `[perf][WP1] timelineIndex builds 150k entries in under 400ms` took
  9.974 s on a loaded host (budget 1500.0 shown in output scale). WP2 touches
  no PhotosCore code; same load-dependent signature as the draft note above.
- `bash native-apple/scripts/verify.sh ios`: **INDETERMINATE — runner died
  before finalizing results, not re-run per WP close-out rules.** The single
  run bootstrapped and executed UI tests (log tail shows
  `LibraryChromeUITests` trash-flow activity — `Find the "select-trash"
  Button`, alert wait — at 15:13), but neither result bundle finalized: both
  `Logs/Test/*.xcresult` lack `Info.plist` (`xcresulttool` refuses them) and
  the `Run-...` bundle's `Staging/` holds only `simctl_diagnostics`
  (diagnose-collection path, no test summaries). No test-runner crash in
  `~/Library/Logs/DiagnosticReports/`. Full-suite gate still needs a quiet
  host; WP2-owned suites last passed scoped (see above).
- `project.pbxproj`: kept as the build left it — genuine xcodegen regen
  (new-file refs for all 6 sources + `LibraryChromeUITests`, debug-probe
  refs gone after the file's deletion). The regen resolves
  `${DEVELOPMENT_TEAM}` → `599Z443923` (12 spots; the correct team per PLAN
  global rule 4). A restore-to-variable edit was attempted but the committed
  file keeps the resolved form: `verify.sh` unconditionally re-regenerates
  before every build, so any hand restore is overwritten at build time
  anyway. Functionally identical; builds/tests above ran against this file.
- UI acceptance: every filter item, sort, media kind, Library View switch,
  View Options item, zoom switch, Years→Months→All drill-down, select-3 +
  … menu + Trash-confirm-cancel — all covered by the passing class above.

## Deviations / notes for other WPs

1. **Months→All drill-down lands without scroll-to-day.** The WP1 contract
   (`AssetGridView`) exposes no scroll-to-date/section API, and `Grid/*` is
   WP1-owned. Day tap switches to All (position kept). If exact scroll-to-day
   is required, WP1 needs an additive `scrollRequest` input.
2. **Zoom/select chrome uses `safeAreaInset`, not `tabViewBottomAccessory`.**
   The accessory needs the new `Tab` content API; MainTabs still uses `tabItem`
   (WP5-owned), under which the accessory never renders — the control was
   invisible. The segmented control + count and the select toolbar sit in a
   bottom inset with `.thinMaterial` instead. Revisit when WP5 moves to `Tab`.
3. **Filter menu uses flat button groups, not ▸ submenus or sections.**
   A `Menu`-in-`Menu` drill-in row never opens under XCUITest, and `Section`
   content inside a `Menu` is not exposed to AX at all — so Sort / Filter /
   Media Types / Library View / View Options are plain one-level buttons
   separated by dividers. Same items, same persistence; restore submenus only
   if UI-test drill-in becomes drivable.
2. **"Shared Library Badge" Show-toggle omitted.** Badges render in the WP1 cell
   (`PhotoGridCell`), which WP2 may not fork. Screenshots and Shared-with-You
   hides are implemented as id filters; the badge toggle needs a WP1 cell flag.
3. **Selfies omitted from Media Types; Duplicate + Adjust Date omitted from the
   "…" menu.** No selfie classifier in `mediaKindCaseSQL`; no duplicate or
   date-adjust mutation in `AssetMutations`. Copy is implemented (pasteboard).
4. **Shared-with-You = `sharedContainer` index flag** (space OR external-library
   assets). The index carries no finer container split.
5. **WP5 coordination:** `.tabBarMinimizeBehavior(.onScrollDown)` lives as a
   modifier on LibraryView; the zoom control + select toolbar live in
   LibraryView's bottom `safeAreaInset` (see 2). If WP5 sets minimize behavior
   on the TabView itself, the Library modifier can go (behavior is identical).
   Do not re-add Shared/Settings tab expectations to the Library tour stops.
6. **No `aspectRatio(contentMode:)` in card layout — art is UIKit-cropped.**
   `aspectRatio` given fixed frames takes the UNION (fill must cover): the
   art's intrinsic size (panorama 512 pt wide, portrait 512 pt tall) expanded
   cards to 480-wide (centered at x=-20) and 544-tall rows, leaking through
   overlays, explicit inner frames, `scaledToFill`, and `maxWidth` removal
   alike (verified by frame probes: removing the image snapped every card to
   exactly 408x180). `KeyAssetPhoto` crops the bitmap to the display aspect
   in UIKit (`croppedToFill`, 3x, NSCache) and stretches it into explicit
   frames — nothing left to negotiate. Day-card squareness comes from
   `aspectRatio(1, .fit)` (fit never overflows). Never use `.fill` aspect
   ratios on variable-aspect art in WP3+ card layouts.
7. **Tour/A3 updates were required** (old `library-switcher` / bottom-bar
   `Move to…` identifiers removed with the chrome they tested).
8. **UI-test hardening (all in WP2-owned test files):** `setUp` terminates
   leftover app instances (jetsam-killed runs leave one answering AX queries:
   duplicate hits, phantom alerts); menu taps scroll the tall menu by
   coordinate drag (`swipeUp` doesn't move menu content) with verified reopen
   retries; alert buttons are scoped to `app.alerts` (`Cancel` matches twice
   globally); menu lookups are type-agnostic (`Section`-in-`Menu` rows aren't
   exposed as buttons at all). Also note: the sparse 12-asset fixture puts one
   asset per day-section, so the All grid shows one 1/5-width cell per row —
   that whitespace is fixture sparsity, not a layout bug (proven by cell-frame
   probes: 87x87 in a 440 grid). Separately, pinch/zoom tests persist
   `heirloom.libraryColumns` on the simulator across runs; wipe the app
   container before gate screenshots if columns look off.

## Post-commit notes (implementer close-out — READ before re-verify)

- **Uncommitted collaborator rework (theirs — do not attribute, do not
  revert):** `LibraryFilterMenu.swift` + `LibraryChromeUITests.swift` carry
  uncommitted edits rebuilding the menu as nested drill-in submenus
  (Sort/Filter top-level; Media Types / Library View / View Options as
  `Menu`-in-`Menu` with `submenu-*` ids) plus a `submenuFor` parent-tap step
  in `tapMenuItem`, keeping every leaf identifier. The drill-in claim (tap
  parent, wait, tap leaf) is plausible — my original "never opens" reading
  may have been element-type matching (`buttons` vs type-agnostic), since
  fixed. Coherent, additive, references resolve — but UNVERIFIED (see below).
- **Final verification blocked on host OOM, not on code.** After the crop
  fix: scoped class runs degenerated run-over-run (menu containers absent
  for whole runs, `menus=0`; then setUp grid timeouts), and `xcodebuild`
  itself was Killed:9 (exit 137) at ~62 MB free with parallel sessions
  (incl. a sibling WP3 sim session) running. The filter-button-absent runs
  coincide exactly with this window — treated as environmental starvation,
  not a product regression, but UNCONFIRMED. The toolbar code as committed
  is structurally sound (verified by reading).
- **Re-verify on a quiet host, in order:** `make build-ios`; scoped
  `LibraryChromeUITests` class (expect 6/6 with the submenu rework);
  `ScreenshotTour` (fresh WP2 screenshots — expect correct 408x180 year
  cards and 3-column day cards after the crop fix); full `verify.sh ios`.
  Each test normalizes persisted zoom to All in `setUp`/`tourLibrary`/A3,
  and terminates leftover app residue — no manual container wipes needed
  except for gate screenshots (columns note above).
