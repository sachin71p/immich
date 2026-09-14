# A8 — Editor engine (Core Image) + iOS/macOS edit UIs

Depends on: A3, A4 · Reads: A0 Architecture+Rules · DECISIONS §4 (who may edit).
Pre-step (scout, ≤40 lines → `handoff/A8-scout.md`): upstream non-destructive editing model — `asset_edit` table,
AssetEditCreate/Delete endpoints, what edit operations it supports, how edited files (`asset_file.isEdited`) are
produced and served, and the `/assets/:id/metadata` key-value API. Orchestrator then confirms the persistence
choice below before implementation.

## Persistence (default, confirm after scout)
- Operations upstream supports (e.g. crop/rotate/mirror) → store as upstream edits so web/Flutter see them.
- Everything else → recipe JSON `fork.editRecipe.v1` in asset metadata KV; client renders full-res and uploads the
  rendered result as the asset's edited file if an endpoint allows; otherwise BLOCKED → orchestrator adds a server
  endpoint (small S-phase addendum). Original is never modified (revert always possible).

## Engine (PhotosCore `Editing`, UI-free, Metal-backed CIContext)
1. Adjust: Auto (`autoAdjustmentFilters`), Exposure, Brilliance (tone-curve + local contrast approximation),
   Highlights, Shadows, Contrast, Brightness, Black Point, Saturation, Vibrance, Warmth, Tint, Sharpness,
   Definition (local contrast), Noise Reduction, Vignette. Parameter ranges −100…100 mapped to filter params.
2. Filters: original LUT presets (Vivid, Vivid Warm, Vivid Cool, Dramatic, Dramatic Warm, Dramatic Cool, Mono,
   Silvertone, Noir *style* names are fine; LUTs must be our own) with intensity.
3. Crop: aspect presets, free, straighten, vertical/horizontal perspective (`CIPerspectiveCorrection`), rotate, flip, auto-straighten (Vision horizon).
4. Portrait: read auxiliary depth/disparity + portrait matte from HEIC originals; aperture + focus point via
   `CIDepthBlurEffect`; disabled when no depth data.
5. Markup: PencilKit on iOS; simple vector markup (pen, shapes, text, arrows) on macOS; flattened into render.
6. Video: trim, mute, rotate/crop via AVFoundation export. Live Photo: key frame choice, mute, trim.
7. Undo/redo stack, copy/paste edits between assets, revert to original, compare (press-and-hold).
8. Renderer: preview-resolution live rendering (60 fps target on sliders), full-resolution export (HEIC/JPEG,
   preserves metadata + HDR where possible).

## UIs
- iOS: Photos-like edit screen (tool tabs: Adjust, Filters, Crop, Portrait, Markup), horizontal dial slider, Done/Cancel.
- macOS: edit mode with right-hand tool panel (Adjust sections with disclosure + sliders, Filters, Crop), keyboard shortcuts.

## Tests
Recipe serialization stability, render determinism (hash of small fixture renders per op), undo/redo, permission
gating via Rules.

Verify: `native-apple/scripts/verify.sh all`.
