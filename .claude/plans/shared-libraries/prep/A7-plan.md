# A7 plan — Metadata panel, search & filters (iOS + macOS)

Goal: info panel "all metadata", smart + metadata search with chips,
offline LocalStore filters, shared Filter DSL (per phases/A7-metadata-search.md).

Dependency status:
- S7 READY: `GET /assets/:id/exif/full` exists (asset.controller.ts:194);
  extended filters in search.dto.ts (iso/fNumber/focal/fileSize/width/
  extensions/mime/projection/hasLocation/orientation/fps/lensModel).
- A3/A4 READY: ViewerView/ViewerInfoPanel/MiniMap (iOS Viewer.swift),
  MacViewerView/MacInfoPanel, LibraryGrid + MacGridView to reuse.
- PhotosCore GAP: Search.swift is an empty placeholder; exif mirror
  (assetExif in Schema.swift) already has all filter fields.

Work list (targets):
1. `PhotosCore/Sources/Search/FilterDSL.swift` — filter enum + URL-like
   serialization + round-trip tests (new file).
2. `PhotosCore/Sources/Search/SearchAPI.swift` — map DSL → MetadataSearchDto
   / SmartSearchDto params + scope selector (new file).
3. `PhotosCore/Sources/Search/LocalFilters.swift` — GRDB queries over
   assetExif mirror for offline filters (new file).
4. `PhotosCore/Sources/ImmichAPI/` — add exif/full + suggestions client
   (extend generated openapi.yaml usage; cache per asset).
5. `Apps/iOS/Sources/SearchView.swift` — search UI, chips, recent searches,
   results grid reusing LibraryGrid (new file; extend ViewerInfoPanel).
6. `Apps/macOS/Sources/MacSearchView.swift` — same on macOS (new file;
   extend MacInfoPanel).
7. `PhotosCore/Tests/SearchTests.swift` — DSL round-trip, local query
   fixtures, API param mapping (new file).

Acceptance: `bash native-apple/scripts/verify.sh all` green; DSL
round-trip + fixture tests pass; exif/full cached per asset.

Open questions: scope selector values (personal/space/library/all)?
Where do recent searches live (LocalStore userMetadata vs UserDefaults)?
Confirm suggestion chips use server suggestions endpoint as-is.
