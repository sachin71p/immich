# WP-E — Edit mode parity

Read first: `PLAN.md` (§0, §1 E-rows, §2.4, §3) and `EVIDENCE.md` ("Edit mode" under Photos and Heirloom).
Photos reference: `evidence/photos-screens/12-…16-*.png` and `evidence/video/FULL-photos-photo-edit.mp4`.

Current code:
- `native-apple/Apps/macOS/Sources/MacEditView.swift`: a sheet with an HSplitView; tabs
  .adjust/.filters/.crop/.portrait/.markup/.video.
- Storage: `EditPersistence` (`/edits` endpoint + recipe KV) in `PhotosCore/Sources/Editing`.

**Safety:** while testing on the owner's library, never press Done on a real asset. Use the fixture
library, or Cancel.

## Steps

1. **P0 (E1).**
   - Edit opens on the first click and on Return (listen for WP-V's notification name
     `HeirloomViewer.openEdit`; define it in your files if WP-V hasn't yet, and tell the orchestrator).
   - Escape = Cancel, with a "Discard changes?" confirmation when the recipe is dirty.
   - Fix the Markup panel clipping.
2. **Edit mode shell (E2, E7).**
   - `MacEditModeView` replaces the main window content, collapses the sidebar (restore it on exit) and
     sets the dark appearance on the window.
   - Top bar: zoom slider; Revert to Original (only when edited); before/after button; centred
     Adjust | Styles | Crop | Tools segmented control; right side "…" (Markup, Edit With ›), Favorite,
     Rotate, Auto Enhance, yellow **Done**.
   - Canvas: Metal-backed `CIContext` render (MTKView or `CAMetalLayer`) with zoom/pan. Render time
     ≤ 16 ms per slider tick on the 2048 px proxy.
   - **Loading:** show the preview proxy at once (the viewer's current image). Fetch the original in the
     background with a bottom-right spinner (as Photos does for iCloud). Once it arrives, re-render;
     export uses the original only. Done is disabled until the original has loaded, with a tooltip saying
     why.
   - Add signpost `Edit.Open` (≤ 300 ms to chrome + proxy).
3. **Adjust (E4).**
   - Section component: header row (chevron, icon, title, AUTO, reset, enable toggle); filmstrip smart
     slider (render 5–7 downsampled strength previews once per section, off-main); **Options ›**
     disclosure with fine sliders.
   - **Sections:**
     - **Light:** Brilliance, Exposure, Highlights, Shadows, Brightness, Contrast, Black Point.
     - **Color:** Saturation, Vibrance, Cast.
     - **Black & White:** Intensity, Neutrals, Tone, Grain.
     - **White Balance:** Neutral Gray / Skin Tone / Temperature-Tint, with an eyedropper.
     - **Curves:** RGB + per-channel, with black/grey/white pickers.
     - **Levels:** input/output handles.
     - **Definition.**
     - **Selective Color:** 6 hue swatches with Hue / Saturation / Luminance / Range.
     - **Noise Reduction.**
     - **Sharpen:** Intensity / Edges / Falloff.
     - **Vignette:** Strength / Radius / Softness.
     - **Depth** (only with depth data; migrates the old Portrait tab).
     - **Red-Eye** (P2).
   - Map each to CoreImage filters in `PhotosCore/Editing`. Add new recipe keys with defaults, and add
     decoding tests that old recipes still render identically.
   - Reset Adjustments at the bottom.
4. **Styles (E5).**
   - 2D pad (Tone × Color), a Palette value and an Intensity slider.
   - Undertone presets: Standard, Amber, Gold, Rose Gold, Bright, Neutral, Cool Rose.
   - Mood presets: Vibrant, Natural, Luminous, Dramatic, Quiet, Cozy, Ethereal, Muted B&W, Stark B&W.
   - Each preset is a documented CoreImage recipe (tone curve + colour matrix + saturation). Thumbnails
     are rendered off-main from the proxy.
   - Existing filter recipes (Vivid …, Noir) keep rendering. Show them in a "Classic" group only when the
     current recipe uses one.
5. **Crop (E6).**
   - On-image crop rectangle with corner/edge handles, a rule-of-thirds grid while dragging, and drag to
     pan the photo.
   - Straighten, Vertical and Horizontal as horizontal dial rows (−45…45 with detents).
   - Flip; Aspect list (Original, Freeform, Square, 16:9, 4:5, 5:7, 4:3, 3:5, 3:2, Custom… with a
     portrait/landscape toggle); Auto (existing auto-straighten); Reset.
6. **Tools (E8), Markup, compare (E9).**
   - Tools shows only implemented tools. If none are implementable on-device in this WP, hide the tab and
     note it in the report for owner decision.
   - Markup moves to "…" and keeps the existing vector markup.
   - Before/after: press-and-hold `M` or the compare button.
   - ⇧⌘C / ⇧⌘V copy and paste edits.
   - Keys: `A`, `S`, `C`, `T` switch tabs when no text field has focus.
7. **Video edit tab.** Keep the existing video trim, reachable from edit mode when the asset is a video
   (Photos shows a trim bar under the canvas).

## Proof (`reports/WP-E-REPORT.md`)
- Screenshots of every tab and section beside the matching Photos screenshot.
- Recording of opening edit on a non-cached original (spinner, proxy editing, re-render).
- Render timing per slider tick.
- Recipe back-compat tests.
- UI test on the fixture: open edit, change Exposure, Cancel → no change; open, change, Done →
  recipe saved and visible in the viewer.

## Design references (open these before coding)
`DESIGN-REFERENCE.md` pairs: **E1–E5 (plus photos/20-edit-video-adjust.png)**, in `evidence/design/pairs/`. Match the left side (Apple Photos).
Your report must include AFTER captures of the same screens (`scripts/heirloom-parity/pairs.sh` rebuilds
the pairs).

## Regression tests (mandatory; see `TEST-PLAN.md` §2)
Implement every test listed for **E1–E9** in TEST-PLAN §2, in files under `Apps/macOS/Tests/<Area>/`,
`Apps/macOS/UITests/<Area>/` and/or `PhotosCore/Tests`.
- **Red first:** run each new test on base `9b9bb7f2e` (or on your branch before the fix) and record
  the failure, then fix and record the pass.
- Use `AXIDs` identifiers, the fixture library (`-HeirloomFixture`), `SyntheticEvents` for trackpad
  phases, and `GestureInputs` controllers for pinch and smart zoom. All of these come from WP-T.
- Report table: `ID | test(s) | red on base | green now | notes`. Only rows marked **H** in TEST-PLAN
  may lack an automated test.

## Owner decisions (Final — accepted 2026-09-18)

- **D1 — Selective Color scope: FULL 6-swatch control required for Gate 1.** Owner rejected
  the Vibrance/Cast macro. Requires 6 hue swatches × Hue/Saturation/Luminance/Range, new
  recipe keys, and renderer support before Gate 1 sign-off.
- **D2 — Curves scope: FULL RGB + per-channel curve editor with pickers required for Gate 1.**
  Owner rejected the Highlights/Shadows/Contrast macro (same bar as D1; a non-curve
  "Curves" risks rejection at verdict). Requires custom curve canvas, point dragging,
  per-channel state, and new recipe keys.
- **D3 — Levels scope: REAL input/output handles required for Gate 1.** Owner rejected the
  Black Point/Brightness/Contrast macro. Two dual-thumb sliders (input black/white,
  output black/white) over existing keys — no canvas work.
- **D4 — Red-Eye: REQUIRED for Gate 1 despite the P2 marking.** Owner overrode the
  deferral recommendation. Requires tap-to-select eye regions, desaturation correction,
  and new recipe keys. Note: combined with D1–D3, Gate 1 now carries four full builds.
- **D5 — Tools tab: KEEP visible with the placeholder note.** Owner overrode the
  hide-tab recommendation (and the spec's hide-if-empty clause). The "No retouch tools
  are available on-device yet." panel stays for Gate 1.
- **D6 — Done-save semantics: DONE VERSIONS.** Each Done persists a new recipe version,
  keeping prior recipes restorable; Cancel discards the in-progress edit. Version
  storage shape and retention limit are implementation detail, but old versions must
  keep rendering identically as new keys land (D1–D4).
- **D6a — Version store: PERSISTED PER-ASSET STACK, CAP 10, WITH HISTORY TIMESTAMP
  LIST.** Tap-to-restore appends a new version (never overwrites). Recipes are ~1KB
  JSON so the cap bounds worst-case storage. Rejected the two-slot fallback (one
  level of "oops" is not restorable history).

## Implementation briefs (Final — from D1–D6a; build order D3, D1, D2, D4, D6a; D5 needs no work)

- **D3 Levels (first):** two dual-thumb sliders (input black/white, output black/white).
  New dedicated keys `levelsInBlack/levelsInWhite/levelsOutBlack/levelsOutWhite`
  (decouple from the Light section's shared keys); renderer applies a true levels
  transform; section enable/reset owns the four keys. Tests: unit (levels math,
  clamping/order invariants) + UI (handles drag, Done persists, viewer shows it).
- **D1 Selective Color:** 6 hue swatches × Hue/Saturation/Luminance/Range. New
  per-hue keys; swatch picker UI; CoreImage hue-range adjustment in the renderer.
  Tests: unit (per-hue isolation, key defaults) + UI (swatch select, sliders move).
- **D2 Curves:** RGB + per-channel curve canvas with point dragging and
  black/grey/white pickers. New point-array keys; tone-curve renderer path.
  Tests: unit (curve evaluation, monotonicity) + UI (add/drag point, pickers set).
- **D4 Red-Eye:** tap-to-select eye regions + desaturation correction. New region
  keys; renderer spot correction. Tests: unit + UI (tap places correction).
- **D5 Tools tab:** no work — placeholder panel stays per owner override.
- **D6/D6a Versions:** per-asset persisted stack (cap 10) beside the single-slot
  recipe store; History timestamp list UI; tap-to-restore appends. Old versions
  must decode and render identically as D1–D4 keys land. Tests: unit (cap prune
  order, restore-appends, back-compat decode) + UI (History lists, restore works).
- **Estimate impact:** D1–D4 + D6a are four full builds plus a version store —
  roughly double the macro-based E scope. D3 first to validate the keys → UI →
  renderer → tests pattern the siblings follow.
