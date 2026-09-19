# Editing Architecture Reconnaissance

**Date:** 2026-09-18  
**Scope:** native-apple/PhotosCore/Sources/Editing, web/src editor, server/src editing tables & APIs, existing plans  
**Branch:** feat/shared-libraries

---

## 1. Native-Apple Editing Module

### PhotosCore/Sources/Editing — Files & Purpose

| File | Purpose |
|------|---------|
| **EditRecipe.swift** | **Core non-destructive recipe struct** (JSON-codable). Stores: AdjustRecipe, StyleRecipe, CropRecipe, PortraitRecipe, MarkupRecipe, VideoRecipe. Metadata KV key: `fork.editRecipe.v1`. |
| **EditRenderer.swift** | Renders recipes to full-res images; uses **CoreImage, Vision (horizon detection), Metal, ImageIO**; implements CIDepthBlurEffect, CIPerspectiveCorrection, CIToneCurve, CIFilter chains. |
| **EditStyles.swift** | Style presets; CoreImage filter chains (tone × color × saturation parameterization). |
| **EditPersistence.swift** | REST-based persistence protocol; fetches/saves/deletes recipes (metadata KV), clears/applies upstream edits (via `/edits`). |
| **EditAccess.swift** | Access control for editing operations. |
| **EditHistory.swift** | Edit history tracking. |
| **EditMarkup.swift** | Markup (vector annotation) handling. |
| **VideoEdit.swift** | Video-specific trim, mute, rotation, key-frame selection. |
| **UpstreamEdits.swift** | Bridge to server-side /edits endpoint (Crop, Rotate, Mirror). |
| **Editing.swift** | Module entry point. |

### Edit Operations (EditRecipe)

**Non-destructive; original bytes never modified.** Operations split into:

- **Upstream-expressible** (sent to `PUT /assets/:id/edits`): crop rect + quarter-turn rotation + horizontal/vertical flips
- **Client-side only** (recipe KV + rendered full-res re-upload): everything else

#### AdjustRecipe (16 sliders, −100…100)
exposure, brilliance, highlights, shadows, contrast, brightness, blackPoint, saturation, vibrance, warmth, tint, sharpness, definition, noiseReduction, vignette, plus autoEnhance boolean.

#### StyleRecipe
- **Name:** EditStyle enum (preset name)
- **Intensity:** 0–100
- **Neutral:** intensity = 0 or style = .none
- Only names follow Photos-like vocabulary; color science is custom (parameterised Core Image chains)

#### CropRecipe
- **rect:** NormalizedRect (0…1, origin upper-left); nil = full frame
- **straightenDegrees:** −45…45 (free rotation; quarter-turns separate)
- **perspectiveVertical/perspectiveHorizontal:** −100…100 (keystone correction)
- **quarterTurns:** 0…3 (upstream-expressible; maps to rotate angle = quarterTurns × 90)
- **flipHorizontal, flipVertical:** bool
- **aspect:** CropAspect enum (free, 1:1, 3:2, 4:3, 16:9, 9:16)
- **isUpstreamExpressible:** true only if straighten = 0 AND perspective = 0

#### PortraitRecipe
- **aperture:** 1.4…16 (f-stop; larger = less blur)
- **focus:** NormalizedPoint (x, y ∈ 0…1)
- Requires depth/disparity data in source

#### MarkupRecipe
- **elements:** [MacMarkupElement]? (macOS vector; nil on iOS)
- **hasFlattenedInk:** bool (iOS PencilKit flattened into rendered upload)

#### VideoRecipe
- **trimStart, trimEnd:** Double? (seconds from start; nil = full length)
- **muted:** bool
- **quarterTurns:** 0…3 (rotation at export)
- **livePhotoKeyFrame:** Double? (key-frame time for Live Photos)

### Apple Frameworks Used

- **CoreImage** → CIFilter chains (tone curves, color matrices, depth blur, perspective)
- **Vision** → Horizon detection for auto-straighten
- **Metal** → GPU-backed rendering (MTKView / CAMetalLayer)
- **ImageIO** → Image encoding/decoding
- **AVFoundation** → Video trim/mute operations (inferred; VideoRecipe struct)

### iOS Editing Extension

**File:** `/Users/spatel/workspace/github/projects/immich/native-apple/Apps/iOS/Extensions/PhotoEditing/Sources/PhotoEditingExtension.swift`

Purpose: System Photo Editing extension for third-party app editing in Apple Photos.

---

## 2. Web Editor

### Components & Capabilities

**Location:** `/Users/spatel/workspace/github/projects/immich/web/src/lib/components/asset-viewer/editor/`

- **EditorPanel.svelte** — UI container
- **transform-tool/** — Only tool currently implemented: **crop + rotate (90°/180°/270°) + mirror (horizontal/vertical)**

### Edit Manager (web/src/lib/managers/edit/)

- **edit-manager.svelte.ts** — Orchestrates tools; maintains EditActions list (array of crop/rotate/mirror)
- **transform-manager.svelte.ts** — Converts UI state to AssetEditAction.Crop / .Rotate / .Mirror
- Uses SDK type: `AssetEditAction` enum (Crop, Rotate, Mirror only)

**Web editor supports only 3 operations** (all upstream-expressible, server-side only; no recipe KV or full-res render).

---

## 3. Server-Side Editing

### Database

**Table:** `asset_edit` (`/Users/spatel/workspace/github/projects/immich/server/src/schema/tables/asset-edit.table.ts`)

| Column | Type | Notes |
|--------|------|-------|
| **id** | string (generated PK) | |
| **assetId** | string (FK → asset) | CASCADE delete/update |
| **action** | AssetEditAction enum | Crop, Rotate, Mirror |
| **parameters** | jsonb | CropParameters, RotateParameters, or MirrorParameters |
| **sequence** | integer | Multiple edits per asset |
| **updatedAt** | timestamp | Auto-updated |
| **updateId** | string (FK, indexed) | Sync tracking |

**Unique constraint:** (assetId, sequence)

**Triggers:** AfterInsert (asset_edit_insert), AfterDelete (asset_edit_delete, asset_edit_audit), UpdatedAt.

### Server APIs

**Endpoints** (asset.controller.ts):

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/assets/:id/edits` | Retrieve all edits for asset |
| PUT | `/assets/:id/edits` | Apply edits (AssetEditsCreateDto) |
| DELETE | `/assets/:id/edits` | Clear all edits |

### Edit Actions (DTO)

**File:** `/Users/spatel/workspace/github/projects/immich/server/src/dtos/editing.dto.ts`

```typescript
enum AssetEditAction { Crop, Rotate, Mirror }

CropParameters: { x1, y1, x2, y2 }  // pixel coords
RotateParameters: { angle: 90 | 180 | 270 }
MirrorParameters: { axis: 'horizontal' | 'vertical' }
```

---

## 4. Persistence Model

### Architecture Split

**Decided contract** (EditPersistence.swift):

1. **Upstream-expressible ops** (crop rect + quarter-turn + flips) → `PUT /assets/:id/edits` (server table)
2. **Everything else** → metadata KV (recipe + rendered full-res re-upload as NEW asset)

### EditPersistencePayload (Metadata KV)

**Key:** `fork.editRecipe.v1`  
**Value:** JSON object

```json
{
  "format": "fork.editRecipe.v1",
  "sourceAssetId": "...",
  "savedAt": "2026-09-18T...",
  "recipe": { ... },
  "renderedAssetId": "..."?
}
```

### RenderedUpload

When recipe requiresClientRender = true:
- Full-resolution client-side render exported
- Uploaded as NEW asset (original untouched)
- Recipe KV saved separately with renderedAssetId link

---

## 5. Existing Plan Decisions

### iOS Parity Plan (heirloom-ios-photos-parity/PLAN.md)

**P0 defects blocking editing:**
- **F1:** Editor canvas renders black for 45 s+ in Debug & Release (image never arrives)
- **F3:** Video editor black canvas + intermittent chrome stall (chrome never appears until app backgrounded)
- **F3b:** Separate root cause from F1/F3

**P1 UI gaps (§1, tab E1–E7):**
- **E1:** Tab taxonomy differs (Heirloom: Adjust/Filters/Crop/Portrait/Markup vs. Photos: Styles/Live/Adjust/Crop/Tools)
- **E2:** Filters are text-only; Photos shows live thumbnail previews
- **E3:** Plain slider vs. Photos' tick-ruler dial with centre marker
- **E4:** Missing Clean Up / Extend / Reframe tools
- **E5:** Video editor has no trim filmstrip (Photos: frame thumbnails + yellow handles + play button)
- **E6:** No Audio Mix tab for video
- **E7:** Portrait tab is stub ("No depth data"); Photos hides it when not applicable

**Evidence:** Photos editor opens with image visible instantly; video plays immediately; video editor usable in ~8 s including iCloud download.

### macOS Parity Plan (heirloom-macos-photos-parity/WP-E-EDIT.md)

**Detailed spec for macOS editor (WP-E):**

1. **Edit shell:** MacEditModeView, collapses sidebar, dark appearance, top bar with zoom/Revert/before-after/tab control/Markup/Rotate/Auto Enhance/yellow Done button
2. **Canvas:** Metal-backed CIContext (MTKView or CAMetalLayer), ≤16 ms per slider tick on 2048 px proxy, show preview immediately, fetch original in background with spinner
3. **Adjust:** Smart slider filmstrip (5–7 downsampled previews), Options › disclosure; sections: Light (Brilliance, Exposure, Highlights, Shadows, Brightness, Contrast, Black Point) / Color (Saturation, Vibrance, Cast) / Black & White / White Balance / Curves / Levels / Definition / Selective Color / Noise Reduction / Sharpen / Vignette / Depth / Red-Eye (P2)
4. **Styles:** 2D pad (Tone × Color), Palette value, Intensity slider; Undertone & Mood presets with CoreImage recipes
5. **Crop:** On-image handles, rule-of-thirds grid, straighten/perspective/flip dials, aspect list, auto-straighten, reset
6. **Tools:** Only implemented tools shown; hide tab if none implementable
7. **Markup, Compare, Copy/Paste:** Via "…" menu; M key or button for compare; ⇧⌘C/⇧⌘V
8. **Video:** Existing trim bar under canvas

**Key decision:** Render timing target is ≤16 ms per slider tick on 2048 px proxy (Release build).

---

## Summary Table

| Layer | Scope | Status | Persistence |
|-------|-------|--------|-------------|
| **iOS Native** | AdjustRecipe (16 sliders), StyleRecipe, CropRecipe (with straighten/perspective), PortraitRecipe (aperture + focus), MarkupRecipe, VideoRecipe | Implemented (P0 rendering bugs blocking) | Recipe KV + upstream `/edits` |
| **macOS Native** | Same as iOS + detailed UI spec (Adjust sections, 2D style pad, on-image crop, smart sliders) | Design spec drafted; implementation TBD | Recipe KV + upstream `/edits` |
| **Web** | Crop + Rotate (90°/180°/270°) + Mirror only | Transform tool implemented | Server `/edits` table only (no recipe KV) |
| **Server** | AssetEditAction.Crop/Rotate/Mirror | Implemented; asset_edit table + REST APIs | Database table + sync triggers |

---

## Key Findings

1. **Edits are non-destructive:** Original asset bytes never modified. Operations stored as reversible metadata (recipe + server edits).

2. **Split persistence model:** Upstream-expressible ops (crop rect, quarter-turn, flip) → server table. Complex ops (adjustments, styles, perspective, portrait depth, markup) → client-side recipe + rendered upload.

3. **Web editor intentionally limited:** Only transform tool (crop/rotate/mirror); no Adjust, Styles, or Portrait. Design choice to keep server edits lightweight.

4. **iOS rendering defect (P0):** Editor canvas black for 45+ seconds; image data exists (viewer shows it) but editor cannot access. Root cause not yet identified.

5. **macOS spec ready:** Detailed UI design (tabs, smart slider filmstrips, on-image crop, style 2D pad) drafted but not implemented. Render performance target: ≤16 ms per slider on 2048 px proxy.

6. **Apple Frameworks:** CoreImage (filters) + Vision (horizon detect) + Metal (GPU render) + ImageIO (codec).

