# Heirloom macOS Perf Fix — FINAL (Wave 4, all gates)

Branch `perf/heirloom-macos`, tip `de73015fb` (WP6 merge). Base `85b44a101` via
Wave-1 tip `6800aaa8c` (plan + evidence), with an intentional mid-project rebase onto
the peer iOS line (orchestrator halted, owner confirmed, WP3–5 re-planted conflict-free).
Release build installed at `/Applications/Heirloom-macOS.app` from this tip.
No push, no PR (owner didn't ask).

## Before → after (owner's 102k library, Release, real server)

| Measure | Baseline (04-baseline) | Gate 2 | Gate 3 re-gate | Gate 4 warm | Gate 4 empty |
|---|---|---|---|---|---|
| Hangs ≥ 250 ms | 13 | 0 | 2 | 4 | 2 |
| Total hang time | 12.93 s | 0.00 s | 0.69 s | 1.25 s | 1.23 s |
| Worst hang | 2.00 s | — | 0.38 s | 0.36 s | 0.75 s |
| Launch → thumbnails | ~30 s unresponsive, 60 s+ blank | unevidenced | unevidenced | GridLoad 5.51 s | GridLoad 3.90 s |
| SnapshotBuild | n/a | n/a | 0.050 s | ~0.05 s | ≤0.047 s |
| PhotosCore tests | 129 / 18 | 158 / 21 | 168 / 22 | 174 / 24 | 174 / 24 |
| UI tests passing | 0 / 3 | 0 / 3 | 0 / 13 | 3 / 13 | 3 / 13 |

Launch-budget verdict: empty-cache 3.90 s meets ≤4.0 s (narrowly, n=1);
warm 5.51 s misses ≤2.0 s (n=1, fetch-dominated, warm/empty inversion proves server
variance dominates — re-sample under controlled server conditions before judging).
Hang budgets: 0 hangs ≥500 ms met on warm (4 micros vs ≤2 missed by 2);
empty missed by one 749 ms hang coinciding with VisionKit/LiveText frames (n=1, re-sample).
Idle-hang band across all post-fix traces is 2–4 microhangs vs 13 baseline hangs.

## Budget scoreboard (PLAN table)

Met and evidenced: snapshot build ~50 ms (≤60 ms unit budget); geometry init <1 ms;
disk-cache init <5 ms; no full reload on favorite/trash/move (change-center, unit-tested);
cancellation never surfaced; footer/counts O(1); prefetch capped + settled (14 passes,
max 153 ms); decode p95 ≤9 ms; 401 exempt from negative hold; logs clean both legs.
Met narrowly / noisy: empty-cache launch 3.9 s (≤4.0 s).
Missed on n=1: warm launch 5.5 s (≤2.0 s); warm micros 4 (≤2); empty 1 hang ≥500 ms (0).
Needs hands (unevidenced): grouping switch ≤300 ms; select/favorite ≤16 ms/event;
scroll (no hang ≥250 ms, no blank >500 ms); sidebar ≤1 s; zoom ≤100 ms/step;
memory ≤700 MB; all page-render ≤1 s visuals; blank-grid + U-row visual confirms.

## What merged (11 merges + reports)

WP0 logging API + Release install/harness/fixture (GATE-wave1 PASS) →
WP1 snapshot/geometry/pipeline (GATE-wave1) →
WP2 snapshot loader/pane/interim grid (GATE-wave2 machine PASS, blank-grid NEEDS-OWNER) →
WP3 layout/headers/coordinator/cell + WP4 rotate/sheets/toolbar/titles/UI-tests +
WP5 viewer/inspector/rotation/video + Rotate-menu enable (GATE-wave3 CONDITIONAL PASS) →
storm fix (sync-gated reload, prefetch hardening, 404 negative hold, signposts) +
duration ms→s + v4 backfill + harness signpost-name fix (re-gate: 2/0.69 s) →
WP6 People/Memories/Map/Collections/Search/Albums/Duplicates (GATE-wave4 CONDITIONAL PASS).
Build: zero warnings. Bundle: no debug dylib, TeamIdentifier 599Z443923.

## Bugs found beyond the brief (all fixed, all with maintained tests)

1. Prefetch storm (3,210 cancels + 138 404s idle, hang clusters) — sync-gated reload,
   same-window prefetch no-op, 400/402–499 negative hold (10 min), quiet cancels.
2. Duration ms→s unit bug (badges 1000×) — wire conversion + unconditional v4 backfill.
3. `startActiveTimer` 30 s has no caller — diagnosed trigger falsified honestly; gate
   in place (`userInitiated:false`) for whenever wired.
4. summarize.py `name` vs `signpost-name` — named intervals recovered (GridLoad etc.).

## Known gaps / follow-ups (owner-hands first, then code)

1. Driven scenario B–H with screenshots (grouping/scroll/zoom/selection/sidebar/memory).
2. Blank-grid + all U-row visual confirms on the 102k library (05-ui-audit.md statused).
3. Launch re-sample, controlled server, warm + empty legs (settle the 5.5 s question).
4. UI suite on a quiet host (10 gated behind sidebar-render; 3 newly passing).
5. Main-thread runtime warnings in UI runs — attribute (test-harness vs app startup).
6. Empty-run 749 ms VisionKit/LiveText hang — re-sample before calling it code.
7. `startActiveTimer`: wire with `userInitiated:false` or delete the dead code.
8. Peer session state in this checkout: 37 staged iOS/icon paths (theirs, untouched)
   + my pre-rebase backup stash `stash@{0}` (redundant now — safe to drop after review).

## Cost (tiers)

Sonnet implementers: WP0–WP6 slices, storm/duration/harness fixes, all verifications.
Opus (orchestrator): plan review, 4 diff reviews (WP1/WP2/WP3/WP3FIX-spot), all merges,
installs, traces, storm + 401 + timer-falsification diagnoses, FINAL + audit pass.
Two runtime-failure retries (WP1, WP2-full) recovered via pre-sliced delegation;
one self-caused commit sweep caught and unwound same-turn.
