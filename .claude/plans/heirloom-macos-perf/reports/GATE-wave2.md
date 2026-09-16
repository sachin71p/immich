# GATE 2 Verdict — Wave 2 (WP2 merged)

Tip verified: `perf/heirloom-macos` @ `9395dd233`. Read-only verification; logs in `/tmp/heirloom-perf/`.

## Per-item results

1. **Release build** — PASS. `make build-macos CONFIGURATION=Release` → `BUILD SUCCEEDED`
   (log: `/tmp/heirloom-perf/build-gate2.log`). Zero `warning:` lines, so no new warnings
   in `Apps/macOS` or `PhotosCore`. No `error:` lines.
2. **PhotosCore tests** — PASS. `swift test --package-path native-apple/PhotosCore` →
   `Test run with 158 tests in 21 suites passed after 7.447 seconds`
   (log: `/tmp/heirloom-perf/test-gate2.log`). No `✘`/failure/error lines
   (the only "failed" hits are the passing A5 test name "...failed rows back off...").
3. **Static guards** — PASS.
   - `grep -rn "assetsById\|allRowIds\|displayedSections\|borderColor = nil" native-apple/Apps/macOS/Sources` → no hits (exit 1).
   - `grep -rn "await reload()" .../MacMainWindow.swift` → 5 hits, all allowed:
     L150 `.task(id: reloadKey)`, L194 new-space sheet, L200 new-album sheet,
     L207 manage-space sheet, L294 error-banner Retry. None in
     toggleFavorite/trash/move/add-to-album (those post `MacAssetChange`, verified by context read).
4. **Bundle** — PASS. `/Applications/Heirloom-macOS.app`: no `*.debug.dylib` anywhere in the
   bundle; `codesign -dvv` → `TeamIdentifier=599Z443923`.
5. **Cold-launch trace** (`gate2-20260916-105832.trace`, already-captured, launch+idle only) — PASS on launch-hang criterion.
   `summarize.py`: **0 hangs, 0.00 s combined, worst 0.00 s** — no hang >= 1 s.
   Main thread 512 Running samples: top owned frames are the WP2 snapshot path —
   `MacGridLoader.load` closure 34.0%, `fetch` 33.8%, `timelineSections` 33.0%,
   then grid item/cell frames (`itemForRepresentedObjectAt` 3.9%, `sizeForItemAt` 2.9%).
   Signposts: 716 unnamed intervals (p50 ~0 s, max 146.6 s = whole-trace span, not a hang).

## Caveat

This trace is launch+idle ONLY (no driven scenario — no computer-use in this harness).
It evidences launch hangs, not the grouping/scroll/select/favorite budgets; those remain for WP7.

## Overall GATE 2 verdict: PASS (with one owner-held item)

Build + tests green, greps clean, no hang >= 1 s in the launch trace.
**Visual blank-grid check U2/U21/U22: NEEDS-OWNER** — hands-on driving is impossible in
this harness; requires the owner to launch the installed app and confirm the grid populates.
