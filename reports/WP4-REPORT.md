# WP4 Report — Collections and detail screens

## C1a root cause: why person counts read 0 with empty names
CONFIRMED by test (PhotosCore `LocalStoreCountsTests.personCountsComeFromFaceJoin`,
green): **no sync mapping bug**. The persist path is lossless end to end
(`SyncRequestTypes` requests PeopleV1+AssetFacesV2 → `SyncLineParser` parses →
`LocalStore+Apply` saves via `PersonRecord`/`FaceRecord`, fields 1:1). Counts are 0
because the person↔asset link is the `face` join
(`face.personId = ? AND face.isVisible = 1`, non-trashed asset):
- faces that synced clustered/unconfirmed (`WireFace.personId == nil`) join to nobody;
- server persons are unnamed until the user names them (`WirePerson.name` passes
  through untouched), and an unnamed person with no faces returns count 0.
Fix per plan §2: the UI hides people who are unnamed **and** have zero assets
(`CollectionsLoader` stage 3, same predicate in `PeopleListView.load`). No sync change.
Person thumbnails ride the existing `MediaPipeline.personThumbnail(id:)` path (cached
`person:` tier, `GET /people/{id}/thumbnail`), falling back to the person's cover
asset — fixture mode has no person thumbnails, so cards still paint.

## What changed
PhotosCore (additive only):
- `LocalStore+Counts.swift`: `capturedByMeCount`, `archiveCount`, `lockedCount`
  (each mirrors its destination predicate), `dayAssetIds` (mirrors the `.day`
  bucket predicate, date desc).
- Tests: 5 `@Test` functions — utility counts, day ids, and the C1a join-hypothesis test.
iOS (`Collections.swift`, `Albums.swift`, `Spaces.swift`, `MemoriesView.swift`,
new `Collections/`):
- `CollectionsView` is a `ScrollView` of collapsible sections in native order
  (Memories · Pinned · Albums › · People › · Shared Albums › · Shared Libraries ·
  Recent Days · Media Types · Utilities · Places, then Reorder). Shells paint
  immediately; `CollectionsLoader` fills staged (counts → albums → people →
  memories/on-this-day → days/cameras). Collapse, section order, and pinned order
  persist in UserDefaults. Toolbar: "…" menu + `AccountButtonPlaceholder`
  (defined in `Collections/CollectionTiles.swift`, used in `Collections.swift:52`).
- Every detail is an `AssetGridView` (5 cols, no section headers): hero-cover
  grids for album/person/space/library, plain-title grids for utilities, media
  types, cameras, and days. `AssetRowList`/`RowThumbnail` deleted (verified: only a
  doc comment in `CollectionTiles.swift:92` still names them).
- `AlbumsListView` (Personal/Shared segments, 2-col tiles, create, sort menu),
  `PeopleListView` (3-col face grid, Sort menu; groups omitted — no API),
  `MemoriesView` (full-width cards + play → existing story player; no Create —
  no API), `PlacesView` (clustered map + selection grid), space timeline via live
  `.timeline` scope (date desc from the index, C5).
- Album/space member management survives below the grid (bottom bars); removal
  selection is id-based so grid reloads don't lose it.

## Verification (session 2026-09-17, verifier turn; host shared with sibling builders)
- `make build-ios`: GREEN — `** BUILD SUCCEEDED **` (after `make xcodegen`).
- `swift test --package-path native-apple/PhotosCore`: 188 tests / 26 suites —
  187 pass, 1 fail: `[perf][WP1] timelineRows loads 102k rows … under 400ms`
  (pre-existing WP1 timing gate, missed budget only under full-suite parallel load
  at host load ~10). Re-ran `--filter TimelinePerformanceTests` in isolation:
  3/3 PASS. All 5 new WP4 `LocalStoreCountsTests` green in both runs.
- `CollectionsPerfUITests.testCollectionsFirstPaintOn100kFixture`: PASSED once in
  isolation (own DerivedData `/tmp/wp4-dd`, `-only-testing`, 95.6 s wall including
  100k-row seeding + cold launch; section shells + `person-Bob` tile both appeared
  inside their 60 s XCUITest timeouts). FAILED on two loaded runs (shells assert
  once at host load ~20; runner SIGKILL once at load ~28 — see below).
  The printed `collections-first-paint-ms=` / `collections-people-tile-ms=` numbers
  were NOT recovered (test stdout lives in the xcresult activity log; export did
  not surface it and no quiet window remained for a logging re-run). Re-run with
  full log capture in a quiet window to record the ms values.
- `ScreenshotTourUITests.testScreenshotTour`: NO green run observed this session —
  runner SIGKILL ×2 (`Early unexpected exit … signal kill`, host load 19–28).
  Tour code covers every section and every detail type (stops 11–21: collections
  shells, memories page + empty state, albums › Personal/Shared segments, album
  detail, people › + person detail, pinned-edit sheet, utility pills incl. Locked
  denied view and Duplicates, space detail date-desc, Places map, collapse toggle,
  reorder sheet). Shots attach as `XCTAttachment`s (never committed; `shots/`
  gitignores `*.png`). Needs one quiet-window run; visual confirmation left to
  the orchestrator (no image files were opened in this turn).
- `GridPerfUITests.testFlickScrollHasNoStallsOn100kFixture`: RED (stalls=88,
  maxStall=138 ms full run; stalls=454, maxStall=182 ms isolated retry as host load
  climbed 10→19). NOT a WP4 gate and NOT WP4-caused: WP4 touches no grid files
  (verified: WP4 diff has no `*Grid*` path; test last touched in `8e81920bf`),
  and both failures correlate with shared-host load. Flagged for orchestrator —
  likely needs a quiet-window re-run or a less load-sensitive stall budget.

## Deviations / notes for the orchestrator
- Plan §1 names `collectionCounts(scope:)` (one query) and `personSummaries(owner:)`
  (one GROUP BY); implementation instead adds per-destination count queries mirroring
  each predicate plus `dayAssetIds`. Same additive contract, staged loader unchanged.
- Plan "≤ 500 ms first paint": the committed perf test prints the timing but asserts
  only shell/people existence (deliberately — simulator XCUITest round-trips inflate
  wall time; see test header). The 500 ms bar is therefore print-only until a device
  or quiet-sim run records the ms values (see above).
- Map/Pinned/space tiles: icon + count where no snapshot API exists (key photos
  wired everywhere a cover id exists).
- `Apps/Shared/*` public API unchanged. Team/bundle id untouched. No PNGs committed.
- Swift 6: persistence uses computed UserDefaults accessors (stored statics trip
  `#MutableGlobalVariable`).
- Harness note: `verify.sh ios()` runs bare `xcodegen generate` WITHOUT the
  Makefile's `DEVELOPMENT_TEAM=599Z443923` export, so every verify run rewrites all
  `DevelopmentTeam` lines to `"${DEVELOPMENT_TEAM}"` (restored, not committed).
  Consider exporting the team id in `verify.sh` or ignoring the churn.
- `chore(ios): regenerate project for WP4 perf test target` (`76365deb8`) commits
  the genuine xcodegen delta (`CollectionsPerfUITests.swift` build references).

## Commits (base `9b9bb7f2e`, branch `feat/heirloom-ios-wp4`)
- `aa44e8494` feat: collection count queries + C1a verification
- `5dd3e5891` feat: Recent-Days id query for day tiles
- `170843d49` feat: Collections screens and grid detail views
- `03d4d25d3` test: tour covers every section and detail type
- `7d0c45d8e` test: A9 smoke fixes for the new Collections UI
- `f51e22065` feat: key-photo covers on pinned and container tiles
- `c0fab9b90` test: bidirectional tour taps for off-screen sections
- `76365deb8` chore: regenerate project for WP4 perf test target
- (this) docs: WP4 close-out report
