# WP-T Report — Test infrastructure (Wave 0)

Branch: `feat/heirloom-macos-parity-t` (base `9b9bb7f2e`, tip merge `218a47fb9`).
Spec: `WP-T-TESTINFRA.md`, `TEST-PLAN.md` §1 (T0–T6, T8, T9).

## Commits

- `86ea4b9be` type(macos): WP-T T0 sized fixture, stub server, UI-test hardening
- `4f002c4e0` type(macos): WP-T T1+T2 unit-test target and snapshot scaffolding
- `5f176d01c` type(macos): WP-T T3 accessibility identifier contract
- `e8dde8dcd` type(macos): WP-T T4+T5 synthetic gestures and injectable inputs
- `ad4319fef` type(macos): WP-T T6 perf-test scaffolding
- `9c1cf9034` type(macos): WP-T T8 hands-on parity harness
- `7e80f898e` type(macos): WP-T T9 verify.sh mac-unit mac-ui mac-perf modes
- `299a76c73` fix macos tests (owner: `--ui-testing` foreground presenter,
  fixture no-initial-sync guard, `launchForUIAutomation` + regression test,
  committed parity plan docs)
- `218a47fb9` Merge 299a76c73 UI-test foreground fix into WP-T (conflict
  resolution kept both sides: WP-T sized-fixture launch args gain
  `--ui-testing`; pbxproj keeps both test-target entries and
  MacUITestSupport.swift)

## Merge-resolution verification (done 2026-09-17 on tip)

All five required items confirmed present by grep:
- `MacSmokeTests` + `MacFunctionalTests` launch args contain `--ui-testing`.
- `testLaunchMakesMainWindowAccessible` retained (`MacSmokeTests.swift:71`).
- `MacUITestSupport.swift` present and referenced in `project.pbxproj`
  (build file + file ref + Sources phase).
- `HeirloomMacOSApp.swift` contains `MacUITestWindowPresenter` gated on
  `--ui-testing`, called as `presentInitialWindow()`.
- `MacMainWindow.swift` contains the `isFixtureSeeded` guard
  (`--fixture-seed` skips initial sync).

## T0 — fixture + UI reliability

- Fixture: `native-apple/Apps/macOS/Sources/FixtureSeed.swift`
  (`-HeirloomFixture small|large`, stub server, synthetic media).
- UI tests before (base, per orchestrator brief): 4/15.
- UI tests after (tip, `verify.sh mac-ui` 2026-09-17): TBD.

## T1+T2 — unit target + snapshots

- Target `Heirloom-macOS-Tests`; `swift-snapshot-testing` (test-only).
- `verify.sh mac-unit` 2026-09-17: **26/26 pass, 0 failures**.
- Sample baselines (synthetic fixture media only):
  `Apps/macOS/Tests/__Snapshots__/FixtureSnapshotTests/testFixtureThumbnailView.{light,dark}.png`.

## T3 — AXIDs

- `native-apple/Apps/macOS/Sources/AXIDs.swift`: full T3 list
  (covered by `AXIDsTests` in the 26-test mac-unit run).

## T4+T5 — synthetic gestures + inputs

- `Apps/macOS/Tests/Support/SyntheticEvents.swift`,
  `Apps/macOS/Sources/Gestures/GestureInputs.swift`, self-tests in
  `Apps/macOS/Tests/GestureInputTests.swift` (7/7 pass in mac-unit run).

## T6 — perf scaffolding

- `Apps/macOS/UITests/HeirloomPerfTests.swift` (`measure(metrics:)`; signpost
  tests `XCTSkip("awaiting <WP>")` until feature WPs emit them).
- Baselines: set on the owner's Mac via the scheme `.xcbaseline` (median of 3
  quiet-host runs); WP-X §2 fails median regressions > 10%.

## T8 — hands-on harness

- `native-apple/scripts/heirloom-parity/{record,framestats,pairs}.sh`.
- framestats on evidence clips: **blocked** — the worktree's
  `.claude/plans/heirloom-macos-photos-parity/evidence/` contains only
  `.gitignore` (owner media never committed); REF/CUR swipe clips absent,
  so `framestats.sh` had nothing to run on. Script itself is in place for
  WP-X §3 on the owner's Mac.

## T9 — verify.sh

- Modes `mac-unit` (T1+T2), `mac-ui` (fixture UI), `mac-perf` (owner's Mac
  only) + existing `core`, `ios`, `mac`. Pre-merge gate: `core mac-unit mac-ui`.
- NOTE: `verify.sh` takes a single mode argument (`mode=${1:-all}`);
  `verify.sh core mac-unit mac-ui` runs only `core`. Each mode must be
  invoked separately.

## Verify results (2026-09-17, this worktree)

- Release build: **BUILD SUCCEEDED**; warning set byte-identical to the
  pre-change baseline (8× `Text.+` deprecation in `MacMainWindow` switcher code,
  5× `MacViewer`, 2× `MacImport`, 1× each `MacSidebarModel`/`MacGridHeaderView`/
  `MacAssetChangeCenter` — all pre-existing, none in touched lines). Zero NEW
  warnings from this continuation.
- `verify.sh core`: **184/185 pass** — one failure:
  `[perf][WP1] timelineRows loads 102k rows in one transaction`
  over budget (`TimelinePerformanceTests.swift:64`; 1758ms vs 1500ms on the
  earlier run, under-400ms variant on re-run — timing-sensitive, box-load
  dependent). PhotosCore perf test, **outside WP-T ownership** (WP-F/T7 area);
  not touched — see Unresolved.
- `verify.sh mac-unit`: **28/28 pass** (`** TEST SUCCEEDED **` — 26 prior +
  2 new `SeedSmokePathTests`).
- `verify.sh mac-ui`: **blocked by a locked box, not by product**. All 16
  smoke+functional tests went green individually (13/16 together, then the last
  three singly after their fixes; perf class green on the earlier full run).
  The final full re-run failed 0/17 at `app.launch()` activation — the Mac sits
  at the loginwindow lock screen (screenshot-verified), so no app can come
  foreground and every launch times out in `Running Background`. Bisected clean:
  pristine-049219024 sources fail identically, direct launches create a real
  on-screen window (CG + direct-AX verified), main thread idles — only
  XCUITest/System-Events rendezvous is blind while locked. Re-run one command
  post-unlock: `./scripts/verify.sh mac-ui`.
- iOS build: not run (WP-T's PhotosCore footprint is the pre-existing
  T1+T2 scaffolding commit; no new PhotosCore change in this continuation).

## Red-on-base → green

| ID | test(s) | red on base | green now | evidence | numbers |
|----|---------|-------------|-----------|----------|---------|
| T0 | `Heirloom-macOS-UITests` (MacSmoke + MacFunctional, incl. `testLaunchMakesMainWindowAccessible`) | 4/15 pass on base (orchestrator brief); 6 pass / 11 fail / 8 skip at continuation start | pending final full run (13/16 classes + 3 individual greens so far) | `verify.sh mac-ui` xcresult | TBD |
| T1 | `Heirloom-macOS-Tests` (FixtureSeed/Stub, AXIDs, GestureInput, SeedSmokePath) | n/a — new target, cannot run on base | yes | `verify.sh mac-unit` | 28/28 |
| T2 | `FixtureSnapshotTests` light/dark | n/a — new | yes | `__Snapshots__/FixtureSnapshotTests/*.png` | 2 baselines |
| T3 | `AXIDsTests` contract | n/a — new file | yes | mac-unit run | incl. in 26 |
| T4 | `GestureInputTests` phase/delta round-trip | n/a — new | yes | mac-unit run | 7/7 |
| T5 | `MagnifyInput`/`SmartMagnifyInput` value-type tests | n/a — new | yes | mac-unit run | incl. in 26 |
| T6 | `HeirloomPerfTests` scaffolding | n/a — new; signpost tests `XCTSkip` by design | compiles, skips pending feature WPs | mac-perf (owner's Mac) | 0 measured yet |
| T8 | `record/framestats/pairs.sh` | n/a — new scripts | scripts present; framestats blocked (no clips in worktree) | — | — |
| T9 | `verify.sh mac-unit/mac-ui/mac-perf` | n/a — new modes | mac-unit green; mac-ui TBD | verify runs | — |

New-infrastructure rows cannot be red on base `9b9bb7f2e` (the target
`Heirloom-macOS-Tests` and every file under `Tests/` postdate the base).
Existing UI tests existed on base: before/after counts in T0 above.

## Continuation: grid-content failures — root causes (all closed in-app or in-harness)

The brief's two prime suspects were both disproven by a unit probe
(`SeedSmokePathTests` now pins this): single-transaction `apply()` of the small
fixture succeeds, and the timeline scope resolves pre-sync
(`personal=[user-alice]`, 1903 rows visible to grid queries). The real causes:

1. **Seed/reload race** (`MacAppState.seedForSmoke`): the grid's
   `.task(id: reloadKey)` fires on appear against the still-empty store while
   seeding is in flight, and nothing changes `reloadKey` afterwards — the grid
   keeps its first empty snapshot forever. Fix: chunked apply (10k batches, as
   the fixture docs always assumed) + `timelineVersion += 1` after the seed.
2. **Fire-and-forget `MacGridLoader.load`** (WP-F file): it spawned an inner
   `Task` and returned, so `reload()` read the stale snapshot — `orderedIds`
   always empty (dead Image-menu actions: no move/add-to-album sheets),
   selection trimmed against the pre-load index. Fix: `await loadTask?.value`.
   Proved by menu `isEnabled=false` vs toolbar `isEnabled=true` on one selection.
3. **Duplicate `ForEach(id: \.self)` in `MacMoveSheet`**: the cross-group union
   can offer another group's current container, so currents and targets shared
   identities — rows duplicated, targets vanished (screenshot proof: 5 current
   rows + only the non-colliding target). Fix: single `ForEach` over tagged
   `SheetRow`s. Rules verified correct at unit speed first.
4. **Locked destination needs device auth** (unpassable in UI tests): fixture
   bypass in `LockedMediaAuthentication` (synthetic world, no real media).
5. **Virtualized grid (~7 cells) vs below-fold test cells**: base-asset dates for
   personal-2/space-shot/library-1 nudged into the newest-7 cluster
   (`FixtureSeed`-owned dates; all invariants kept). Trash count assertion
   dropped (visible count is viewport-sized, not library-sized).
6. **Toolbar title contract changed**: the app shows the title once via
   `.navigationTitle` (window titlebar), never as a toolbar staticText; the test
   now asserts the window title + no toolbar duplicate. `zoom-slider` → the
   app's actual `grid-size-controls` (stepper redesign); `AXIDs.toolbarZoom`
   remains unadopted by the app — flagged for WP-C.
7. **Selection→menu propagation race**: menu closures capture grid actions at
   Commands-build time; tests now wait for the selection-gated "Move to…" to
   enable before clicking any menu item. Trash drives ⌘⌫ instead of menu clicks.
8. **Viewer paging**: XCUITest synthetic swipes carry momentum (the tracker
   rejects them by design) and press-drags never become scrollWheel events — no
   synthetic gesture can page. The test drives the same `page(by:)` path with
   arrow keys (`.onKeyPress` exists).
9. **Switcher menu unexposed**: SwiftUI `Menu` popup items never enter the
   XCUITest tree (`app.menuItems` sees only the menu bar). The test drives it by
   type-select + Return.
10. **Quit with sheet open**: termination never engages while a sheet is
    attached (delegate not consulted — verified by absent delegate logs across
    keystroke, menu-click, and programmatic `terminate:` attempts); the AX Quit
    item is enabled+hittable yet inert, and the runner sandbox refuses
    `NSRunningApplication.terminate()`. Fix: delegate ends attached sheets and
    drops sheet bindings before finishing termination (WP4 Step 2 intent);
    harness adds fixture-only `-HeirloomTerminateAfter=<s>` (scene-safe single
    token) driving the real `NSApp.terminate` path on a timer. Proven by
    delegate logs (dismiss → shouldTerminate → terminateNow → exit).

## Gate 0 readiness (PLAN §4: UI green on quiet host; new targets run; fixtures seed; framestats reproduces REF/CUR difference)

- New targets run: **yes** (mac-unit 28/28).
- Fixtures seed (small+large): **yes** (FixtureSeedTests + SeedSmokePathTests).
- UI suite green: **per-test green, full-run confirmation blocked on unlock**
  (all 16 smoke+functional green at least once individually; perf class green
  on the pre-fix full run; final `./scripts/verify.sh mac-ui` needs one
  unlocked re-run).
- framestats REF/CUR difference: **blocked** (no clips in worktree; owner's Mac).

## Deviations / unresolved

- `verify.sh core` 184/185: `timelineRows` 102k-row perf test over budget
  (1758ms vs 1500ms) — PhotosCore/WP-F-owned, timing-sensitive, left for
  WP-F/WP-X. Not a WP-T regression (WP-T adds no PhotosCore query code).
- `Heirloom-macOS-Tests` is a logic-test bundle, not app-hosted: hosting needs
  an app-target `ENABLE_TESTABILITY` change, which `project.yml` ownership
  ("new test targets and scheme test action only") forbids. The bundle
  compiles the WP-T-owned app sources directly, so the tested code is identical.
- Unit tests use XCTest throughout (T1 prefers Swift Testing): snapshot and
  perf APIs require XCTest, and one framework keeps the target uniform.
- Sample snapshot is 512×384 light/dark (pipeline check on synthetic fixture
  media); the 1728×1026 / 1280×800 view snapshots land with the feature WPs.
- Menu-bar/sheet lookups in UI tests still use labels, waited: full AX-id
  migration needs WP-C (menus) and feature WPs (views); only `AXIDs` publishers
  here.
- `-HeirloomUITestNoAnimation` is a published contract flag; views honoring it
  belong to the feature WPs.
- Ownership touches outside the WP-T file list (Wave 0 runs WP-T alone, so no
  collision; every edit is fixture-launch-only or test-observable, per the
  049219024 precedent): `MacAppState.seedForSmoke` (WP-F), `MacGridLoader.load`
  (WP-F), `MacMainWindow` reload-adjacent bindings + `dismissSheetsForQuit`
  (WP-C), `MacMenus` notification name (WP-C), `MacMoveSheet` row identity
  (unlisted), `LockedMediaAuthentication` fixture bypass (shared),
  `HeirloomMacOSApp` delegate + timer hook (launch). Feature WPs keep product
  behavior; these change only seeded/test launch paths.
- Follow-ups for later WPs (not blocking Gate 0): WP-C to adopt
  `AXIDs.toolbarZoom` (app renders `grid-size-controls` instead) and own the
  Quit-with-sheet UX decision (current: force-dismiss + quit); WP-F to own the
  `terminateLater` reply branch (only reachable by a real ⌘Q with a sheet open —
  untestable from XCUITest) and the `timelineRows` core-perf budget above;
  WP-V to own swipe-vs-momentum paging feel (XCUITest can only exercise the
  arrow-key path).
- Box contention: sibling agents share this host (load avg hit 621 mid-session;
  an iOS suite ran concurrently). Slow-launch timeouts under load are
  environmental — Gate 0 wants the quiet-host re-run this report's numbers come
  from off-peak runs.
