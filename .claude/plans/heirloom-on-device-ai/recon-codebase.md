# Heirloom On-Device ML Reconnaissance

**Date:** 2026-09-17  
**Branch:** feat/shared-libraries  
**Scope:** Native Apple apps, server ML pipeline, machine-learning service, existing plans, Collections UI

## 1. Native Apple Apps (iOS & macOS)

### Project Structure
- **Root:** `/native-apple/` (Heirloom.xcodeproj, XcodeGen-based via project.yml)
- **iOS app:** `/native-apple/Apps/iOS/` (SwiftUI)
- **macOS app:** `/native-apple/Apps/macOS/` (SwiftUI)
- **Shared framework:** `/native-apple/Apps/Shared/` (app groups, entitlements)
- **Core library:** `/native-apple/PhotosCore/` (Swift Package, min deployment iOS 27.0, macOS 27.0 — likely typo, should be 17.0/18.0)

### UI Stack & Server Communication
- **UI:** SwiftUI only
- **API Client:** Generated via **Swift OpenAPI Generator** from server OpenAPI spec (packages: swift-openapi-generator, swift-openapi-runtime, swift-openapi-urlsession)
- **Shared Swift Packages:** ImmichAPI, CoreModel, Rules, LocalStore, SyncEngine, Media, Upload, Editing, Search
- **Database:** GRDB (SQLite); image caching via Nuke

### PhotoKit Usage (Backup/Upload)
- **BackupScanner.swift:** PHAsset, PHPhotoLibrary, PHAssetCollection, PHAssetResource, PHAssetResourceManager, PHAssetChangeRequest
  - Reads Photos library with requestAuthorization(for: .readWrite)
  - Fetches smart collections and albums via PHAssetCollection.fetchAssetCollections
  - Stages assets for upload via PHAssetResource + PHAssetResourceManager.writeData
- **Upload job:** BGProcessingTask fallback registered at app launch (BackupScheduler.swift)

### Vision/CoreML/CloudKit Usage
- **Vision framework:** EditRenderer.swift for auto-straighten (horizon detection)
- **VisionKit:** MacOS app for Live Text (MacLiveText.swift, MacViewer.swift)
- **CoreML:** Not found
- **CloudKit:** No capability in entitlements yet (`/native-apple/Apps/Shared/Heirloom.entitlements` contains only keychain-access-groups + app-groups)
- **BGProcessingTask:** Yes, used for background backup scheduling

### Entitlements
- App identifier prefix group: `group.com.immich.heirloom.shared`
- No iCloud/CloudKit, HomeKit, or special capabilities declared yet

---

## 2. Server ML Pipeline

### Services & Tables
**ML Services:**
- `smart-info.service.ts` – CLIP embeddings for smart search
- `search.service.ts` – Search API (faceted, person, places, smart search)
- `duplicate.service.ts` – Duplicate detection

**Key DB Tables:**
- `smart_search` – assetId (FK), embedding (vector, **512-dim**, hnsw index, cosine ops)
- `face_search` – faceId (FK), embedding (vector, **512-dim**, hnsw index, cosine ops)
- `asset_face` – assetId, personGroupId, bbox coords, sourceType (enum: MachineLearning, Manual, etc), isVisible
- `person` / `person_group` – Face clustering & identity
- `asset_ocr` – OCR text extraction (if enabled)
- `memory` / `memory_asset` – Memories with type (JSONB data), memoryAt, seenAt, showAt, hideAt, isSaved
- `asset` – duplicateId field present for duplicate detection; no processedBy/source-device yet
- `asset_exif` – EXIF metadata
- `asset_job_status` – Job tracking

**Schema location:** `/server/src/schema/tables/`, migrations in `/server/src/schema/migrations/`

### ML HTTP Client
- Generated OpenAPI client (Swift on native, TypeScript/JavaScript on server)
- Machine-learning service listens on separate port (default :3003 per config.py)

---

## 3. Machine-Learning Service (Python)

**Location:** `/machine-learning/`

**Default Models (inferred from constants.py):**
- **CLIP:** OpenCLIP (ViT-based family; ViT-B-32__openai, ViT-L-14__openai, etc.) – 512-dim embeddings
- **Facial Recognition:** InSightFace (buffalo_l, buffalo_m, buffalo_s, antelopev2) – 512-dim embeddings
- **OCR:** PaddleOCR (PP-OCRv5 variants, multilingual)

**Config:** `/immich_ml/config.py` – ClipSettings, FacialRecognitionSettings, OcrSettings; preload models, max batch size, device/precision (CUDA, ROCm, OpenVINO, CoreML, CPU)

---

## 4. Existing Plans

**Directory:** `.claude/plans/`

Relevant to on-device ML:
- `heirloom-macos-photos-parity/` – macOS parity with Photos.app; includes Memories, smart collections, Trips, Duplicates
- `heirloom-ios-photos-parity/` – iOS parity; 3 P0 render defects, 4 settings questions open
- `heirloom-ios-ui/` – UI component work (Collections, Utilities, etc.)
- `heirloom-web-v2/` – Web redesign (separate from native)
- `shared-libraries/` – Multi-user shared albums/libraries infrastructure

**No existing on-device ML plan.** On-device folder exists but empty.

---

## 5. Collections UI in iOS

**Collections tab breakdown** (WP4, native-15…18):
- **Memories** – MemoryStory type; backed by server `memory` table; assetIds associated per memory.id
- **Pinned** – User-customizable pinned sections
- **Albums** – User & shared albums
- **People** – Face recognition results (person_group)
- **Shared Albums** – Collaboration albums
- **Shared Libraries** – fork: shared-libraries scope
- **Recent Days** – Timeline grouping
- **Media Types** – Image/video/screenshot/... (UtilityDetails.swift: MediaTypeDetailView)
- **Utilities** – Screenshot, screen recording, etc.
- **Places** – City-based grouping

**No Trips UI found yet** — mentioned in macos-photos-parity plan but not implemented in iOS Collections.

**Data:** CollectionsLoader loads memories, albums, people, libraries via SyncEngine; cover photos fetched on-demand (recent 1 asset per space).

---

## Key Gaps for On-Device ML

1. **No CloudKit capability** – Would need entitlement + CKContainer for iCloud sync
2. **No Vision/CoreML models** – Framework imports exist (EditRenderer, VisionKit) but no ML model loading
3. **No processedBy/source-device tracking** – Asset table lacks field to distinguish on-device vs. server-processed results
4. **No local embedding models** – Would need ONNX/CoreML ports of CLIP/buffalo models
5. **Trips not UI-complete** – Mentioned in parity doc; likely requires geospatial clustering on-device
6. **Memory creation on-device** – Currently server-driven; local generation would need Vision + heuristics

---

## Migration Path Notes

- Smart search embedding dimension: **512** (matches buffalo_l/ViT-B-32)
- Face detection + recognition both 512-dim, separate models
- OCR optional (not found in default startup; requires paddle models)
- Asset table has `duplicateId` column → on-device duplicate detection feasible
- SourceType enum on asset_face allows for device-side face detection mark-up
- Memories are JSONB with flexible schema → can extend with on-device detection metadata
