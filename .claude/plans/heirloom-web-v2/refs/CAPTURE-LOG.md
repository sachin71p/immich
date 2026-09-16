# WP1 — Reference capture log (screenshots NOT obtained)

No publishable reference screenshots exist. This log records exactly what was tried,
the blocker, the two real measurements salvaged, and the host recipe to finish.

## Status

- Native macOS build: COMPILED from working tree
  (`xcodebuild -project native-apple/Heirloom.xcodeproj -scheme Heirloom-macOS
  -configuration Debug -derivedDataPath /tmp/wp1-dd -skipPackagePluginValidation
  CODE_SIGNING_ALLOWED=NO -jobs 2 build` → EXIT 0, warnings only).
- Fixture launch: binary runs (`--fixture-seed -ApplePersistenceIgnoreState YES`,
  process alive, AppKit runloop healthy per `sample`), but NO main window ever
  materialized in this launch context across 4 attempts (direct exec, `open`,
  `open -n`, rebadged bundle-id copy at `/tmp/wp1shot/HeirloomShot.app`).
- Interaction: impossible from this shell — System Events process control denied
  (`osascript … frontmost …` → `-1719 assistive access`), so no sidebar clicks,
  grouping switches, viewer opens, or dialog captures were possible.
- Appearance toggle for dark capture: NOT attempted (would flip the user's live
  desktop; per-app defaults share the bundle id with the user's running app).
- Probably decisive: the host user is LIVE-debugging the mac app in parallel
  (observed their rebuild script running `pkill -9 -f "Heirloom-macOS"`), which
  reaps same-named fixture processes; further `open`/focus-stealing automation was
  stood down to avoid interfering.

## Salvaged real measurements (window-manager observed, no pixels)

- Library window: 1400×900 @ (164,95), name "Library" — matches
  `.defaultSize(1400, 900)`.
- Settings window: 900×512, name "Heirloom Settings".
- Recorded in `WP1-MEASUREMENTS.md` as [W] provenance.

## Host recipe (lead/owner: mac verifier with UI automation rights)

```bash
cd native-apple && bash scripts/verify.sh mac   # sanctioned path; runs MacSmokeTests
# then, with the fixture app frontmost at 1400x900:
# dark:  screencapture -l<winid> -x refs/library-idle-dark.png        (sidebar Library, Months, zoom 120)
# light: toggle appearance, repeat → refs/library-idle-light.png
# states (XCUITest or manual): selection, Years/Months/All, switcher menu,
#   move/add-album/new-space/new-album/import/camera sheets, viewer, inspector,
#   search idle+results, map, people, memories+player, settings, editor
```

Deterministic seed: `--fixture-seed` (`FixtureSeed`, 8 assets across 2022–2024,
space `Family`, library `Archive`, album `Trip`). Masks: WP1-MEASUREMENTS §8
(+ WP3-VISUAL-MANIFEST.md from Agent C — reconcile before baselining).
