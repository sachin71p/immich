# GATE 1 — Wave 1 (WP0 + WP1 merged) verification

Branch `perf/heirloom-macos`, tip `d7048f652` (merge of WP1). Verifier run 2026-09-16 ~10:20 CDT.
Working tree note: uncommitted `Makefile` diff (iOS `build-ios-device`/`install-ios` targets only,
orchestrator's — does not touch any macOS target used below). `make install-macos` was run by the
orchestrator (bundle stamped 10:17, after the 10:15 tip); verifier did not reinstall.
Wave 1 has no perf budgets — gate checks builds/tests only, no regressions vs WP0/WP1 reports.

## 1. `make xcodegen` — PASS
Project regenerated cleanly. No `openapi.yaml` gap this time (file already generated in tree).

## 2. `make build-macos CONFIGURATION=Release` — PASS
`** BUILD SUCCEEDED **` (log: `/tmp/heirloom-perf/build.log`, complete from invocation).
Zero errors. Zero `warning:` lines in the captured (incremental) output; the pre-existing warnings
named in WP0/WP1 (SwiftUI `Text(+)` deprecation, ICCameraDevice downcast, SyncEngine/Media/Nuke
dep-scan notes) were not re-emitted and no new warnings appear in `Apps/macOS` / `PhotosCore`.
Only dep-scan informational lines (`Explicit dependency on target ...`) present.

## 3. `swift test --package-path native-apple/PhotosCore` — PASS
`Test run with 158 tests in 21 suites passed` in 6.4 s (log: `/tmp/heirloom-perf/test.log`).
Matches WP1-REPORT.md claim exactly (158/21, incl. `[perf][WP1]` budgets).

## 4. `make test-macos-ui` (tests self-pass `--fixture-seed`) — SAME 3 PRE-EXISTING FAILURES, no regression
`** TEST FAILED **` with exactly the WP0-baseline set (log: `/tmp/heirloom-perf/uitest.log`):
- `MacSmokeTests.swift:24 testSidebarAndGridRender` — `sidebar renders` timeout
- `MacSmokeTests.swift:60 testKeyboardSelectionAndMoveTargets` — XCTAssertTrue failed
- `MacSmokeTests.swift:89 testLibrarySwitcherFiltersGrid` — XCTAssertTrue failed
Identical test names, same failure mode (sidebar never renders in this environment, per WP0 open
issue #1). No new failures. (Note: `make` exits 65; the `EXIT=0` seen at capture time was the
`tail` pipe, not xcodebuild.)

## 5. Static guards — BASELINE RECORDED (WP2/WP3 own these; not a Wave 1 failure)
- `assetsById`: MacSearchView.swift (25,149,168,244,261), MacGridView.swift (23,41,164,342,509,511,578,616,632), MacMainWindow.swift (257,518,677)
- `allRowIds`: MacGridView.swift:27, MacMainWindow.swift:625,661,671
- `displayedSections` (+`displayedRowIds`): MacMainWindow.swift:256,258,502,513
- `borderColor = nil`: MacGridView.swift:302 — R10 black-border bug still present (owned by WP3)

## 6. Installed bundle — PASS
`/Applications/Heirloom-macOS.app/Contents/MacOS/` contains only `Heirloom-macOS` (no `*.debug.dylib`).
`codesign -dv` → `TeamIdentifier=599Z443923`. Bundle/device binary stamped Sep 16 10:17:27, i.e.
installed from this tip (10:15) by the orchestrator.

## Verdict: GATE 1 PASS
Builds green, PhotosCore 158/21 green, UI tests show only the 3 documented pre-existing failures,
bundle is a clean Release install with the right team. No regressions vs WP0/WP1 reports.
Follow-ups for later gates (not Gate 1 blockers): sidebar-never-renders UI environment issue (WP2/WP4
triage), `borderColor = nil` + loader statics above (WP2/WP3), uncommitted Makefile iOS diff.
