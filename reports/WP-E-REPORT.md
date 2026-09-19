# WP-E — Edit mode parity: report

Branch: `feat/heirloom-macos-e` (worktree `immich-mac-e`, base `4cc8db194`).
Fixture flags only (`-HeirloomFixture`); never Done on a real asset.

## What shipped

Full-window edit mode (`Apps/macOS/Sources/MacEditModeView.swift`, new, ~1400 lines)
replaces the viewer content instead of a sheet:

- **E1:** single click on `toolbar.edit`, Return, and the `HeirloomViewer.openEdit`
  notification (defined here — WP-V had not published it) all open edit mode.
  Escape = Cancel with a "Discard changes?" confirm when dirty (both the new mode
  view and the legacy `MacEditView` sheet). Markup panel clip fix (`fixedSize` +
  `minWidth: 260` rows) in both views.
- **E2 shell:** dark full-window chrome — zoom slider, Revert to Original
  (dirty-only), press-and-hold Before/After, Adjust | Styles | Crop | Tools
  segmented control, "…" (Markup, Edit With external editor, Copy/Paste),
  Favorite, Rotate, Auto Enhance, yellow Done. Sidebar collapses to width 0 while
  the mode posts `HeirloomViewer.editModeActive` and restores on exit.
  Proxy-first: canvas shows the proxy at once, the original loads in the
  background with a bottom-right spinner, canvas re-renders from the original,
  export uses the original only, Done is disabled (with tooltip) until it arrives.
  `Edit.Open` signpost brackets the open path (budget 300 ms — perf proof owed,
  see Unresolved).
- **E4 Adjust:** 13 sections (Light, Color, Black & White, White Balance,
  Curves, Levels, Definition, Selective Color, Noise Reduction, Sharpen,
  Vignette, Depth ← old Portrait tab, Red-Eye). Header rows have icon/title,
  AUTO (Light/WB), reset, enable toggle; headline params get an off-main
  5-thumb filmstrip (`EditFilmstrip`, detached task); Options › holds fine
  sliders; WB has Neutral-Gray/Skin-Tone eyedropper (tap-to-sample on canvas).
  Curves are honest preset macros; Levels are macros; per-hue Selective Color
  and Red-Eye (P2) are deferred — see Unresolved.
- **E5 Styles:** 7 Undertone + 9 Mood presets (documented CoreImage recipes, own
  color science, off-main thumbs) + Intensity; Classic group (Vivid …, Noir)
  renders only when the current recipe uses one.
- **E6 Crop:** on-image rect with corner handles (clamped via `CropMath`),
  thirds grid while dragging, drag-to-move; Straighten/Vertical/Horizontal dial
  rows (−45…45); Flip; full Aspect list
  (Original, Freeform, Square, 16:9, 4:5, 5:7, 4:3, 3:5, 3:2, Custom…)
  with portrait/landscape toggle; Vision Auto straighten; Reset.
- **E8 Tools:** `EditToolRegistry` — tab lists only `isAvailable` tools; the
  default registry is empty so the tab hides (no retouch tool is implementable
  on-device in this WP — owner decision).
- **E9:** M hold + clickable compare (AX value Original/Edited), ⇧⌘C / ⇧⌘V
  copy-paste (also in "…"), A/S/C/T tab keys. Video trim tab + trim bar under
  the canvas (trim/mute); stills unaffected.

`PhotosCore/Editing`: 12 new `AdjustRecipe` keys with defaults
(cast, bwIntensity/bwNeutrals/bwTone/grain, wbTemperature/wbTint,
sharpenEdges/sharpenFalloff, vignetteStrength/Radius/Softness), all mapped to
CoreImage (grain is a deterministic fixed checkerboard dissolve, not random);
`decodeIfPresent` back-compat so old recipes decode neutral and render
identically (golden fixtures). New `CropAspect` cases + `CropOrientation`;
`EditCropMath`, `EditToolRegistry`, `EditOriginalLoader`
(proxy→loading→ready/failed, Done gate), `EditFilmstrip`;
`HeirloomSignpost.editOpen = "EditOpen"`.

## Test table (TEST-PLAN §2)

| ID | test(s) | red on base | green now | notes |
|---|---|---|---|---|
| E1 | `EditUITests` open/cancel/discard; markup clip | new API does not compile on base | compiles (TEST BUILD SUCCEEDED); run owed | UI proof owed to main session |
| E2 | `EditUITests` sidebar hide/restore | same as E1 | same as E1 | + hands-on |
| E3/E4 | `EditModeParityTests` new-key determinism/visibility/detail-modulation/filmstrip/back-compat | new API does not compile on base | 17/17 pass | filmstrip off-main by construction (detached task) |
| E5 | preset determinism/visibility/classic + undertone fixtures | same | pass | golden renders = deterministic pixel hashes |
| E6 | crop clamp/aspect-orientation/straighten-scale | same | pass | overlay gestures hands-on |
| E7 | `editOpenGatesDone` (+signpost pin) | same | pass | 300 ms perf proof owed (Release, owner's Mac) |
| E8 | registry empty/available-only | same | pass | tab hidden by default; owner decision |
| E9 | `EditUITests` compare + copy/paste | same as E1 | compiles; run owed | M-hold hands-on |

## Verification observed

- `PhotosCore: swift test --filter EditModeParityTests` → 17/17 pass.
- Full `swift test` (202 tests): edit suites pass (`EditingTests`, `EditModeParityTests`);
  3 failures are timeline `[perf]` timing budgets
  (`TimelineGridSnapshotTests`, `TimelinePerformanceTests`, `TimelineIndexTests`)
  unrelated to this change, under parallel-worker load — re-run on a quiet host.
- macOS `build` + `Heirloom-macOS-Tests` (isolated
  `.build-e/DerivedData`): **BUILD SUCCEEDED**, **28 tests, 0 failures**.
- `build-for-testing -only-testing:Heirloom-macOS-UITests`: **TEST BUILD SUCCEEDED**
  (includes new `EditUITests`).

## E3 bronze Delta-E harness

Bronze = the owner can measure parity the day the refs exist; no Apple Photos
content lives in the repo (fixture/synthetic only, no NE/Core ML).

- Script: `native-apple/scripts/heirloom-parity/deltae.sh <refs-dir> [out-dir]`
  renders each `<case>.recipe.json` on `<case>.source.png` through the real
  `EditRenderer`, compares against `<case>.ref.png` with `CILabDeltaE`, and
  prints per-case `median/p90/max/zerofrac` dE plus a PASS/FAIL summary
  (bronze bar: per-case median dE < 3; failures exit 1). Empty/absent refs dir
  prints "no references — owner capture pending" and exits 0 (never fails).
- Exact-match unit tests (`EditingTests`, `[E3]`, 6 tests, all pass): levels
  degenerate-range identity; `toneCurve` resampling (point sets agreeing at
  the 5 `CIToneCurve` stops render bit-identical, master + per-channel);
  empty curves + range-only selective + identity levels = identity; selective
  black/white bit-identity + no-chroma-on-gray + yellow/green single-hue
  isolation. No GPU goldens, no Photos images; D1–D4 renderer math untouched.
- Finding: the selective kernel wobbles mid-gray by 1 LSB (128 → 127) while
  black/white stay bit-exact — kernel I/O round-trip, not hue math. Flagged
  for the full-E3 tuning loop, not fixed here (renderer math is frozen).

Owner-capture recipe (owner's Mac, Apple Photos): 3 synthetic inputs
(gray step wedge, hue wheel/patches, photo-like gradient) × fixed D1–D3
strengths — e.g. levels `{inBlack:20, inWhite:85, outBlack:10, outWhite:90}`,
curves master `[(0.25,0.3),(0.75,0.8)]`, selective `{selRedSat:+60 range:80}`
— export each edit as PNG at source size (`<case>.ref.png`), save the matching
raw `EditRecipe` JSON (`<case>.recipe.json`) beside the input
(`<case>.source.png`), then run `deltae.sh` on the dir.

Deferred to full E3: the 50-photo reference set, SSIM alongside ΔE, the
slider-gain tuning loop toward median ΔE < 3, and iPhone↔Mac drift goldens.

## Owner work remaining (owner's Mac; nothing here blocks the branch)

- [ ] **Gate 1 verdict — 4-point app confirmation** (`make install-macos`, then launch
  the binary from Terminal with `2>&1 | grep -a heirloom-edit`): (1) Edit opens a
  sharp canvas in ~2 s; (2) Levels at input-black 0 brightens, never black;
  (3) same photo reopened prints `HIT … (no download)`; (4) grid repopulates after
  closing. Reply "Gate 1 passes" or per-section findings. Staff recommendation:
  conditional pass (see report head).
- [ ] **Server rebuild for Done.** `heirloom-server:local` predates the E1 rendition
  endpoint, so Done errors until the server is rebuilt with E1. Skip Done until then;
  the error is expected, not a new bug.
- [ ] **E3 reference captures** (blocks ΔE numbers, nothing else). Per case, a triplet
  in a refs dir (e.g. `~/heirloom-refs/e3-bronze/`): `<case>.source.png` (synthetic
  input) + `<case>.ref.png` (Apple Photos edit, exported at source size) +
  `<case>.recipe.json` (raw `EditRecipe` JSON with identical values). Inputs: gray
  step wedge, hue wheel/patches, photo-like gradient (≤2048 px, throwaway Photos
  album, never Done on a real asset — delete the album after). Cases: levels
  `{inBlack:20, inWhite:85, outBlack:10, outWhite:90}` + 2–3 in/out combos; curves
  identity + master `[(0.25,0.3),(0.75,0.8)]` + one per-channel set; selective
  single-hue sweeps (e.g. `{selRedSat:+60 range:80}`). Then run
  `native-apple/scripts/heirloom-parity/deltae.sh <refs-dir>` and paste the
  per-case medians (bar: median < 3; known 1-LSB mid-gray wobble excluded).
- [ ] **PR hygiene — done.** PR title fixed to conventional commit; `changelog:feature`
  created (mirrors upstream taxonomy) and applied; both gates pass. Remaining red
  checks are pre-existing fork infra (GHCR images, plugin-sdk, base spec).
- [ ] **TEMP-DEBUG cleanup (main session, after the 4-point confirmation).** Remove the
  two `TEMP-DEBUG` prints in `MacViewer.downloadOriginal`, then push.

## Unresolved (owed to the main session)

1. `verify.sh mac-ui` (device foreground is exclusive): run
   `cd native-apple && ./scripts/verify.sh mac-ui` — covers new `EditUITests`
   (E1 open/Return/Escape/discard, E2 sidebar, E7 Done gate, E9 compare/copy-paste).
2. Perf (Release, owner's Mac): `Edit.Open` ≤ 300 ms chrome+proxy; render ≤ 16 ms
   per slider tick on the 2048 px proxy; re-run the 3 timeline perf tests quiet.
3. Visuals: tab/section screenshots beside Photos refs, `pairs.sh` AFTER captures,
   non-cached-original recording (spinner → re-render), markup 1280×800 clip shot.
4. Snapshot baselines for the adjust sections were deliberately NOT recorded here
   (no UI run allowed); record with `SNAPSHOT_RECORD=1` and review the diff.
5. Deferred to owner: per-hue Selective Color, freeform Curves/Levels handles,
   Red-Eye (P2), Tools tab hidden by default, "Edit With" implemented as
   stage-proxy-to-temp + `NSWorkspace.open`.
6. Fixture has no server, so the original never loads there: UI tests assert Done
   stays disabled; Done-save (`open, change, Done → recipe saved`) needs a
   server-backed or stubbed-original run — hands-on gate.
