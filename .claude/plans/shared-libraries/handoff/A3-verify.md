# A3 verify — results (2026-09-15)

1. `native-apple/scripts/verify.sh ios` → NOT RUN (env; never PASS per TESTING.md §8)
   - stops before any test: `line 20: xcodegen: command not found` (exit 127)
   - Apple tier needs xcodegen + Xcode on host; sandbox has neither.
2. Docker/socket tiers (M/E/W/G) → NOT RUN (no Docker in sandbox; never PASS per §8).

Attribution: environmental — xcodegen step precedes all
build/test, so no project file ran; neither A3 files
(handoff/A3.md Files-changed) nor concurrent A4 edits under
native-apple/PhotosCore, Apps/Shared, Apps/macOS caused it.
KNOWN (handoff/S0-verify.md): plugin-core wasm `extism-js`
missing — unrelated to A3, not a regression.
Verdict: no A3 test executed; needs host run with Xcode.
