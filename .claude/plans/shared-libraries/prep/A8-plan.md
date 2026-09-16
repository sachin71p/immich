# A8 plan — Editor engine (Core Image) + edit UIs

Goal: UI-free editing engine + Photos-like edit UIs on iOS/macOS
(per phases/A8-editor.md). Original never modified; revert always possible.

Dependency status:
- Upstream model CONFIRMED narrow: AssetEditAction = crop/rotate/mirror
  only (editing.dto.ts); KV API exists (`/:id/metadata` GET/PUT/DELETE).
- Persistence default stands: upstream ops → asset edits; everything else
  → recipe JSON `fork.editRecipe.v1` in metadata KV + rendered upload.
  ORCHESTRATOR must confirm before implementation (phase pre-step).
- Media READY: MediaEndpoint supports `edited=true` variants on view/
  download; originalURL preserves verbatim bytes.
- PhotosCore GAP: Editing.swift is an empty placeholder; no recipe,
  renderer, or undo stack exists yet.
- BLOCKED-if: no endpoint accepts rendered full-res upload → needs small
  S-phase addendum (orchestrator decision).

Work list (targets):
1. `PhotosCore/Sources/Editing/Recipe.swift` — recipe model +stable
   serialization v1 + copy/paste (new file).
2. `PhotosCore/Sources/Editing/AdjustEngine.swift` — −100…100 adjust ops
   via Core Image (new file).
3. `PhotosCore/Sources/Editing/LookPresets.swift` — own LUTs + intensity
   (new file; style names only, no Apple LUT copies).
4. `PhotosCore/Sources/Editing/CropEngine.swift` — crop/straighten/
   perspective/rotate/flip + Vision auto-straighten (new file).
5. `PhotosCore/Sources/Editing/PortraitEngine.swift` — depth/matte read,
   CIDepthBlurEffect aperture+focus; disabled without depth (new file).
6. `PhotosCore/Sources/Editing/Renderer.swift` — preview-res live render
   + full-res export (metadata/HDR preserved) (new file).
7. `PhotosCore/Sources/Editing/VideoTrim.swift` — AVFoundation trim/mute/
   rotate + Live Photo key frame (new file).
8. `Apps/iOS/Sources/EditView.swift` — tool tabs + dial slider +
   Done/Cancel + PencilKit markup (new; uses VideoPage/ViewerView).
9. `Apps/macOS/Sources/MacEditView.swift` — right tool panel + shortcuts
   + vector markup (new; uses MacViewerView).
10. `PhotosCore/Tests/EditingTests.swift` — recipe stability, fixture
    render hashes, undo/redo, Rules permission gating (new).

Acceptance: `bash native-apple/scripts/verify.sh all` green; render
determinism hashes pass; revert-to-original works.

Open questions: confirm recipe-vs-upstream split; rendered-upload
endpoint — exists or S-addendum? Markup flatten format (HEIC/JPEG)?
