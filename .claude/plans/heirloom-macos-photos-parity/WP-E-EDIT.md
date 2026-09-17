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
