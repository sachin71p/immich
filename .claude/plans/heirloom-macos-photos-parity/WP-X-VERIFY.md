# WP-X — Gate verification (after every wave)

The orchestrator runs this after merging a wave into `feat/heirloom-macos-photos-parity`.

## §1 Build and tests (verifier / Sonnet)
1. `cd native-apple && xcodegen generate` (if `project.yml` changed).
2. `xcodebuild -project Heirloom.xcodeproj -scheme Heirloom-macOS -configuration Release -destination 'platform=macOS' build`:
   zero warnings.
3. `swift test --package-path PhotosCore`, and the macOS UI tests (`MacFunctionalTests`, `MacSmokeTests`,
   plus the new ones).
4. `xcodebuild -scheme Heirloom-iOS -destination 'generic/platform=iOS Simulator' build`: no regressions
   from PhotosCore changes.
5. Report pass/fail counts and the first failing assertion only. Write it to `reports/GATE-<n>-build.md`.

## §2 Install and traces (verifier, then the orchestrator checks)
1. Quiet host: no simulator, no other xcodebuild (`pgrep -lf xcodebuild` must be empty; otherwise wait,
   or ask the owner).
2. `make install-macos` (Release). Confirm there is no `.debug.dylib` in the bundle.
3. Record per PLAN §3, 3 runs each, median:
   - `xcrun xctrace record --template "Animation Hitches" --attach Heirloom-macOS --time-limit 60s` during
     scripted scrolls and viewer paging;
   - the Hangs template for a 5-minute session;
   - signposts via `log stream --predicate 'subsystem == "com.immich.heirloom"'`.
4. Always pass `--time-limit`, and check trace size (`du -sh`) afterwards: a runaway trace reached 250 GB
   on 2026-09-17.

## §3 Hands-on side-by-side (orchestrator, Opus, computer-use)
Photos and Heirloom are both maximized on the same display. For each row in PLAN §1 that the wave closed:
1. Screenshot or record Heirloom and Photos doing the same thing (`screencapture -l<windowid>`; ffmpeg
   avfoundation at 60 fps for motion).
2. Gestures that computer-use cannot synthesize: **ask the owner** to perform the real trackpad swipe,
   pinch, smart-zoom double-tap, grid flick and grid pinch while recording (AskUserQuestion with exact
   steps). Synthetic CGEvents are blocked for this shell (no Accessibility / PostEvent permission), and
   Photos ignores wheel events for paging.
3. Frame-count every clip with the PLAN §3 recipe and put REF vs AFTER numbers in the gate report.
4. Destructive actions only on the fixture library. Cancel every editor on real assets.

## §4 Verdict
`reports/GATE-<n>.md`:
- a table of closed IDs with evidence links;
- budgets met or missed;
- regressions;
- verdict PASS / CONDITIONAL (list the owner decisions needed) / FAIL (list the rework, sent back to the
  same WP agent).

## §5 Test gates (TEST-PLAN §3)
- §1 runs `native-apple/scripts/verify.sh core mac-unit mac-ui`. Any failure is FAIL. Snapshot
  re-recordings must be listed and reviewed by the orchestrator.
- §2 runs `verify.sh mac-perf` against the xcbaseline (median of 3). A regression > 10 % is FAIL.
- Check each WP report's ID → test table.
  - Spot-check 3 "red on base" claims per WP by checking out base in a scratch worktree and running the
    named test.
  - Any P0/P1 ID without a test (other than **H** rows) is FAIL.
- §3 hands-on: rebuild `evidence/design/pairs` with `scripts/heirloom-parity/pairs.sh` and compare every
  pair touched by the wave.
