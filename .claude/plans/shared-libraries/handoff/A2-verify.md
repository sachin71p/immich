# A2 verify — results (2026-09-15)

1. `native-apple/scripts/verify.sh core` → KNOWN (same env failure as A0-verify)
`error: 'photoscore': Invalid manifest ... sandbox-exec: sandbox_apply: Operation not permitted`
SwiftPM inner sandbox vs agent sandbox; no project test ran. Self-check instead:
2. `swift build --disable-sandbox` (PhotosCore) → PASS (`Build complete!`, exit 0)
3. `swift test --disable-sandbox` (PhotosCore) → PASS (55/55 in 9 suites, incl. 26 new `[A2-*]`; 29 A0/A1 intact)
4. Xcode-toolchain apple tier (`verify.sh ios/mac`: xcodegen + xcodebuild) → NOT RUN (`xcodegen` not on PATH; never PASS per brief)
5. `scripts/fork-test/run.sh coverage` → FAIL (pre-existing, not A2):
`MISSING tests for done-phase cases: R16-04(S6), R12-01(S7), R12-02(S7), R13-01(S7), R13-02(S7), R13-03(S7), R13-04(S7), SY-01..SY-06(S6), W-01(S8a), W-02(S8a), W-09(S8a)`
A2 gap: `coverage.ts` has no A2 case ids at all (done phases list ends at A1); no A2-* cases in matrix yet.
