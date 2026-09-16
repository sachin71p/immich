# WP7 — Verification gate (run after every wave)

Read-only for source. Writes `reports/GATE-wave<N>.md`. Parts 1–2 run in a `verifier` subagent.
Parts 3–4 need computer-use on the owner's Mac, so the orchestrator does them.

## 1. Build & tests (verifier)
```bash
cd /Users/spatel/workspace/github/projects/immich
make xcodegen
make build-macos CONFIGURATION=Release 2>&1 | tail -n 300 > /tmp/heirloom-perf/build.log
swift test --package-path native-apple/PhotosCore 2>&1 | tail -n 300 > /tmp/heirloom-perf/test.log
```
- Also run the macOS UI tests with the command recorded in `reports/WP0-REPORT.md`, using
  `--fixture-seed`.
- Report pass/fail, error file:line list, new warnings in `Apps/macOS` / `PhotosCore`, and test counts.
- Check that the static guards return nothing:
  `grep -rn "assetsById\|allRowIds\|displayedSections\|borderColor = nil" native-apple/Apps/macOS/Sources`
- `make install-macos`, then check the bundle has no `*.debug.dylib` and TeamIdentifier `599Z443923`.

## 2. Instruments (verifier + orchestrator)
The orchestrator runs `scripts/heirloom-perf/profile.sh gate<N> 150` and performs the scenario in
§3 A–G during the recording. The verifier runs `summarize.py` and compares against the PLAN budgets,
and against `04-baseline-profile.md` (baseline: 13 hangs, 12.93 s, worst 2.00 s).

## 3. Scripted scenario (orchestrator, computer-use; screenshots at each step saved under `reports/shots/gate<N>/`)
A. Cold launch. Time the window appearing and the first thumbnails appearing (screenshots every 0.5 s
   for 5 s).
B. Library → Years → Months → All Photos → Months, pausing 2 s each. No error banner, headers are
   correct.
C. Drag the scroll bar top → bottom → top over ~5 s, then fling-scroll 20 screens. After stopping, no
   blank cell stays longer than 0.5 s, and no black borders.
D. Single-click 3 items, ⌘-click 2 more, click empty space (deselects), − − + + zoom, and pinch if
   possible.
E. Favorite one photo, then unfavorite it: the heart badge updates instantly and the grid doesn't
   reload (scroll position unchanged).
F. Double-click a photo → ↓ info → → → ← ← (lands on the original) → rotate ×4 → Esc.
G. Sidebar: Favorites, Recently Saved, Map (pan/zoom), People, Memories, Photos, Videos, Live Photos,
   Portrait, Screenshots, the shared library, an album, Collections, Search (type a query + Return).
   Each renders content or a proper empty state within 1 s, with a correct title and no irrelevant
   toolbar items.
H. Open Move… from a selection → Cancel; open again → Escape; open again → ⌘Q quits the app.
   **Never** confirm a move, trash, lock, or album change on the real library.

## 4. Re-audit (orchestrator)
Update `05-ui-audit.md` with a status column (fixed / partially / open / regressed) for U1–U27, and
append any new issues as U28+. Anything open or regressed becomes a follow-up task that names the
responsible WP.

## Gate pass criteria
- Builds and tests are green.
- Budgets met for the WPs merged so far. Wave 1: none. Wave 2: blank-grid fixed and no hang ≥ 1 s.
  Wave 3: all grid, selection and viewer budgets. Wave 4: page budgets.
- No regressions against the previous gate.
