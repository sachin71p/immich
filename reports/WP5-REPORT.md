# WP5 Report — app shell, Search, account/settings

Worktree `immich-ios-wp5`, branch `feat/heirloom-ios-wp5` (base `9b9bb7f2e`).
Commits: `896b9d595` (PhotosCore), `ac20df777` (shell/search/account/tour).

## What changed (by plan step)

**1. Tabs (T1).** `HeirloomIOSApp.swift` `MainTabs` is now 3 new-style tabs —
`Tab("Library", systemImage: "photo", value: "library")`,
`Tab("Collections", …, value: "collections")`,
`Tab(value: "search", role: .search)` — with
`.tabBarMinimizeBehavior(.onScrollDown)` on the `TabView`. Shared/Settings tabs
deleted. Deep-link contract preserved: `session.requestedTab` values
(`"library"`/`"collections"`/`"search"`) and the `Heirloom.pendingRoute` key
consumed by `AppSession.checkPendingRoute()` are untouched, as is
`OpenSearchIntent`. No `Extensions/` tab references exist (verified by WP5 prep).

**2. Account (T3/T4).** New `Account/AccountButton.swift` (avatar with initials,
person-glyph fallback, presents its own sheet) and `Account/AccountSheet.swift`
(`AccountProfileStore` + sheet: name/email/host, Sync, Upload/Backup, Timeline
sources, Storage, cache usage, Shared Libraries via `SpacesListView`, confirmed
Sign Out, version-only About). Section bodies reuse the `SettingsView`
components in place (`UploadTargetPicker`, `BackupSettingsSection`,
`TimelineSourcesSheet`, `FreeUpSpaceView`); `Settings.swift` itself is
**untouched** and `SettingsView` is now dead code behind the deleted tab (left
for WP6/orchestrator to remove — deleting it is a larger diff with no benefit
now). Profile comes from the new additive `ImmichConnection.currentUser()`
(`CurrentUserProfile`: id/name/email from the same `getMyUser` payload);
fixture mode reads the mirror user row, else "Fixture User". The raw UUID is
never shown. Until WP4 wires the Collections toolbar, Search hosts an
`AccountButton` so the sheet is reachable and tour-covered.

**3. Search (S1–S4, spec device-native-22).** `SearchView.swift` rewritten:
empty-query body = Recents image-card row (top-result thumbnails via
`RecentCardThumb`, Clear + expand chevron) + suggestion pills (People, Places,
Camera, Lens, File type, Videos, 4 recent-month pills using
`takenAfter`/`takenBefore`); typing debounces 300 ms through `.task(id:)`
cancellation plus a `searchGeneration` guard, results in WP1 `AssetGridView`
(`.ids`, `ViewerRoute` → full-screen `ViewerView`, same as before until WP3's
pager). Scope + Filters moved to a toolbar menu/sheet. New
`Search/SearchSuggestions.swift` loads all five chips local-first (S2a fix),
server only as fallback. No `DateFormatter` per call (static month formatter).

**4. Tour.** `ScreenshotTour` updated in the same step as the tab deletion:
`tourShared`/`tourSettings` removed; `tourSearch` rewritten for `.searchable`
(debounce wait, results, viewer, clear-to-idle asserting the "IMG" Recents
card); new `tourAccount` (name shown, ≠ `u1`, sign-out confirmation cancelled).
`A9ExtrasUITests` now taps the Collections tab by label (new `Tab` API drops
identifier propagation). Shots renumbered 18–24 (search 18–22, account 23–24).

## S2a (investigate-first → fixed)

Root cause confirmed as prepped: server `search/suggestions` returns `[]`
offline/in fixture, and people chips mapped unfiltered names. Fix, all
additive in PhotosCore (`LocalStore+Suggestions.swift` + `SuggestionsTests`,
4/4 green): `distinctCities`, `distinctLensModels`, `distinctFileExtensions`,
`cameraModels` (pre-existing) feed Places/Camera/Lens/File-type chips;
`namedPeople` excludes blank names. Remaining gap (documented, not fixed):
person rows with zero assets are a face/person **sync** gap owned by WP4 (C1a);
the suggestions layer only hides the blank names.

## T5 (investigate-first → documented, still open)

Real build-config bug, not an xcodegen serialization bug: the generated
`project.pbxproj` carries the array correctly, `xcodebuild
-showBuildSettings` resolves `INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers
= com.immich.heirloom.backup-processing` and `INFOPLIST_KEY_UIBackgroundModes
= processing`, yet `plutil -p` on the built `Heirloom-iOS.app/Info.plist`
shows **neither** (nor `HeirloomAppIdentifierPrefix`), while scalar known keys
(`UISupportedInterfaceOrientations`, `NSPhotoLibraryUsageDescription`) land.
So Xcode's generated-plist step drops them. Fix direction needs an
orchestrator call (`project.yml` is shared/WP0-owned): explicit `Info.plist`
file or capability enablement. `BackupScheduler.register` at launch is
unaffected (code-side registration exists).

## Verification

- `make build-ios`: green (after `gen-api.sh`; one `import ImmichAPI` fix,
  one `Color.accentColor` fix).
- `swift test --package-path native-apple/PhotosCore`: 189 tests; the only
  failure seen was WP1 `timelineRows` 102k timing under parallel load
  (1714 ms vs 1500 ms budget) — passes in isolation (4.5 s suite run);
  flaky/environmental, untouched by this WP.
- `bash native-apple/scripts/verify.sh ios`: **blocked by shared-box contention,
  not by WP5 code.** 4/6 UI tests pass (A3 smoke, A9 extras with the new label
  tap, GridPerf 100k, viewer performance). The screenshot tour dies at a
  different spot on every run — switcher menu, timeline-sources→viewer, zoom
  levels — all in untouched Library/Viewer code, always as a runner SIGKILL
  followed by the known 600 s `simctl diagnose` hang. The box runs 4–6
  concurrent sibling `xcodebuild test` sessions with ~70 MB free RAM, and the
  distress is visible inside the runs (later screenshot attachments are dropped
  from the xcresult). One run reached the WP5 steps: account sheet opened, name
  asserted, shot 23 taken. Two tour-script issues found there are fixed in
  `0be2b28` (sign-out scrolled into view; `.searchable` moved onto the
  `NavigationStack` per the search-tab pattern after `searchFields` timed out
  once under the same distress). Re-run when the box is quiet:
  `xcodebuild -project native-apple/Heirloom.xcodeproj -scheme Heirloom-iOS
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
  -only-testing:Heirloom-iOS-UITests/ScreenshotTourUITests/testScreenshotTour test`
  Full-log evidence in `/tmp/wp5-tour-rerun*.log` (scratch, not committed).
- `make xcodegen`: regen committed (`-f`, file is tracked-but-ignored;
  precedent `28fde2682`).

## Coordination notes

- WP2: `.tabBarMinimizeBehavior(.onScrollDown)` is on `MainTabs`' `TabView`
  per plan; if WP2 also sets it on `LibraryView` the values converge — no
  conflict by design. Do not remove either.
- WP4: mount `AccountButton()` in the Collections toolbar and remove the
  Search-hosted one; consider deleting dead `SettingsView`.
- WP3: search opens the viewer with `ViewerRoute.resolveIds()` into the
  existing `ViewerView(ids:initialId:)`; lazy paging will subsume it.
- macOS orchestrator: `durationSeconds` ms→s bug class does not recur here;
  no shared-API changes (`Apps/Shared/*` untouched, PhotosCore additive only).
