# GATE Wave 3 — FINAL verdict (Part A + gate3fix re-gate trace)

Branch `perf/heirloom-macos` @ `117d0c577` (WP3+WP4+WP5 merged, then WP3FIX
storm-fix `035d450d8`/`28f4ebba2`, 401-exemption `55db324aa`, merge `deb7f42ed`).
Verifier, read-only source. Prior FAIL report (trace gate3-20260916-123239: 9 hangs /
4.09 s / worst 1.14 s) is superseded by the re-gate below. Raw logs:
`/tmp/heirloom-perf/build-gate3.log`, `test-gate3.log`, `uitest-gate3.log`,
`gate3fix-20260916-131855.trace`, `summary-gate3fix.txt`.

## Part A — build / tests / guards / bundle (unchanged code signal: green)

`make build-macos CONFIGURATION=Release` — **BUILD SUCCEEDED, zero warnings**
(prior established fact, re-quoted; WP3FIX + 401-exemption commits each also
report Release BUILD SUCCEEDED). `swift test --package-path
native-apple/PhotosCore` — **168 tests / 22 suites, ALL PASS** (incl. 9 new
WP3FIX tests + 401-exemption test). Static guards **clean** (one comment-only
hit); Rotate-fix confirmed in source; bundle has no `*.debug.dylib`,
TeamIdentifier `599Z443923`. Pass.

## Part B — re-gate trace (gate3fix-20260916-131855, 150 s, cold launch)

`python3 scripts/heirloom-perf/summarize.py` (full text `summary-gate3fix.txt`).

- **Hangs: 2 total, 0.69 s combined, worst 0.38 s — both Microhang** (02:08.051
  319.59 ms; 02:24.058 375.04 ms). Prior: 9 / 4.09 s / worst 1.14 s.
  Budget check: **0 hangs ≥ 500 ms ✓; 2 microhangs ≤ 2 ✓** (exactly at limit).
- **Signposts (app subsystem): SnapshotBuild [timeline] ×1, 0.050 s.**
  GridLoad / ThumbnailFetch / ThumbnailDecode / Prefetch **did not fire** in this
  recording (exactly one `com.immich.heirloom` signpost event in the whole trace;
  see Note 1). The script's signpost table lumps all 8,211 system intervals as
  "(unnamed)" — it reads column `name`, the export schema uses `signpost-name`
  (harness bug, app data unaffected).
- **Top-5 owned main-thread frames** (3,194 Running samples): deduplicated app
  symbol 354 (11.1%); `MacGridLoader.load` closure 339 (10.6%);
  `MacGridLoader.fetch` 329 (10.3%); `MacGridLoader.timelineSections` 316 (9.9%);
  `MacGridCell.updateHeartBadge` / `MacKeyCollectionView.mouseMoved` 27 each
  (0.8%). Note 2 applies.
- **Log storm: FIXED.** Zero persisted `com.immich.heirloom` lines of any category
  in the 13:18:55–13:21:25 window (prior: 138 404s + 3,210 error-level cancels).
  16 keyword hits in-window are all Apple-framework XPC/network noise, none from
  the app. **No 404-flood** (same id dozens/ms) — no 404 lines at all.
  Cancellations now log at `.debug`, which the log store does not persist, so
  their absence-from-store is expected, not missing evidence; the binding check
  (no error-level cancel/404 spam) passes.
- **Launch→thumbnails:** only datum is SnapshotBuild 50 ms (far inside either
  budget). GridLoad never fired (launch/load began before the recording window
  opened — trace starts mid-quit of the previous instance, relaunch at ~13:19:36),
  so the ≤2.0 s warm / ≤4.0 s empty budget is **not directly measurable** from
  this trace. This machine (owner's Mac, repeated runs today) is assumed
  **warm disk cache, unverified** — treat the launch budget as unevidenced, not met.

Note 1 (for owner): GridLoad wraps the load-task body — its absence plus a single
50 ms SnapshotBuild suggests the load completed before recording or outside the
captured run; consider starting the recording before relaunch next gate.
Note 2: `MacGridLoader.load/fetch/timelineSections` still account for ~31% of
main-thread Running samples combined. No hang ≥ 500 ms resulted this run, but
this is the same code family that produced the 1.8–2.0 s R2 hangs — worth a
follow-up look, not a gate blocker.

## UI

No UI re-run in this gate (no `uitest-gate3fix.log`). Standing state: 13/13 fail
at the pre-existing sidebar-render environmental gate (window titles resolve,
content empty; main-thread runtime warnings noted) — **no code signal, no
regression signal**. UI suite must still be judged on the owner's host.

## Overall verdict: CONDITIONAL PASS

Wave-3 criteria (all grid/selection/viewer budgets + no hang ≥ 1 s on
evidenceable items): every **evidenceable** item passes — 0 hangs ≥ 500 ms,
microhangs at limit (2/2), storm fixed with zero persisted app errors, Part A
green. Conditions / still needs owner hands:
1. Driven grouping/scroll/zoom/selection scenario (§3 B–F) — hang/blank-cell/
   zoom-step budgets need hands-on runs with screenshots.
2. Blank-grid visual confirmation (Gate-2's bug) on the 102k library.
3. Launch→thumbnails budget under a known cache condition (start recording
   before relaunch; optionally clear disk cache for the empty-cache leg).
4. UI suite (`make test-macos-ui`) on the host from a quiet tree.
