# WP-T: Test infrastructure (Wave 0, runs before all feature WPs)

Read first: `PLAN.md` §0 and `TEST-PLAN.md` §1 (items T0–T6, T8, T9), which is the spec.
You don't fix product bugs here. You build the harness that the feature WPs write their red-first tests
into.

**Owned files (exclusive):**
- `native-apple/project.yml`: new test targets and scheme test action only.
- `native-apple/Apps/macOS/Tests/**` (new).
- `native-apple/Apps/macOS/UITests/**`.
- `native-apple/Apps/macOS/Sources/AXIDs.swift` (new).
- `native-apple/Apps/macOS/Sources/FixtureSeed.swift`.
- `native-apple/scripts/verify.sh`.
- New `native-apple/scripts/heirloom-parity/**`.

Allowed read-only touches elsewhere:
- Adding `.accessibilityIdentifier(AXIDs.…)` calls is **not** allowed in files owned by other WPs; each
  feature WP adds the identifiers to its own views.
- You publish the constants, and you may tag views in files no WP owns.

## Steps (commit each)
1. **T0 fixture.**
   - Extend `FixtureSeed` so it covers:
     - `-HeirloomFixture small` (2,000 assets) and `large` (102k rows; build them fast via batched inserts,
       under 20 s);
     - synthetic images and videos generated deterministically, no network. Videos are short H.264 clips
       generated with AVAssetWriter at seed time and cached in the fixture dir;
     - live photos, favourites, edited assets, 12 albums, 2 shared libraries, 1 shared album,
       6 named people and 2 unnamed, 3 memories, places with coordinates, and assets tagged "beach";
     - a signed-in fake session with a stub server (URLProtocol) serving thumbnails, originals, video,
       `/search/smart` and `/search/metadata`.
   - `-HeirloomUITestNoAnimation` disables non-essential animations.
   - Make the existing 13 UI tests pass on a quiet host: remove sleeps and flaky label lookups. Record the
     before/after pass counts.
2. **T1 + T2.**
   - Add the `Heirloom-macOS-Tests` hosted unit-test target and the swift-snapshot-testing package
     (test-only).
   - A sample snapshot test of an existing simple view, with a baseline recorded from fixture assets.
   - Add the target to the scheme.
3. **T3.** `AXIDs.swift` with the full identifier list from TEST-PLAN T3, as static functions and
   constants.
4. **T4 + T5 support.** `SyntheticEvents.swift` (scroll with phases, momentum) with its own self-tests:
   the events round-trip their phase and delta values. `MagnifyInput` / `SmartMagnifyInput` value types go
   in a small shared file under `Apps/macOS/Sources/Gestures/GestureInputs.swift`; WP-V and WP-G build
   controllers on them.
5. **T6.**
   - A `HeirloomPerfTests` UI-test class with `measure(metrics:)` scaffolding for launch and for each named
     signpost. Tests for signposts that don't exist yet are marked `XCTSkip("awaiting <WP>")`.
   - Document how to set baselines on the owner's Mac.
6. **T8.** `scripts/heirloom-parity/record.sh`, `framestats.sh` and `pairs.sh`, per TEST-PLAN.
   `framestats.sh` prints changed-frames/s p50 and p10, plus the longest static run during motion.
7. **T9.** `verify.sh` modes `mac-unit`, `mac-ui` and `mac-perf`, plus the existing `core`, `ios`, `mac`.

## Proof (`reports/WP-T-REPORT.md`)
- Pass counts for the UI tests, before and after.
- The new targets building and running.
- A sample snapshot baseline path.
- `framestats.sh` output on `evidence/video/REF-photos-trackpad-swipe.mp4` and
  `CUR-heirloom-trackpad-swipe.mp4`. The expected result is a large difference.
