# Heirloom On-Device AI — Plan

Status: DRAFT for owner review · 2026-09-17, editing §13 added 2026-09-18 · Author: Opus (main session)
Inputs: [research-apple-frameworks.md](research-apple-frameworks.md) · [research-cloudkit.md](research-cloudkit.md) · [recon-codebase.md](recon-codebase.md) · [research-editing.md](research-editing.md) · [recon-editing.md](recon-editing.md)

---

## 0. TL;DR

- **Devices extract, server aggregates.** iPhone and Mac run Apple Vision + Core ML on the
  Neural Engine and upload *per-asset features* (CLIP vector, face boxes + face vectors, labels,
  OCR, aesthetics, document/QR flags, video audio tags). The server does everything that needs
  the *whole library*: face clustering into People, duplicate grouping, smart-collection
  membership, Trips, Memories.
- **Same models everywhere → one vector space.** Convert the server's own models (OpenAI CLIP
  ViT-B/32 and InsightFace buffalo_l) to Core ML so a vector from an iPhone, a Mac and the server
  are interchangeable. Then the server's existing duplicate detection, smart search and face
  clustering keep working unchanged no matter who processed an asset. Apple-only signals
  (aesthetics, `isUtility`, scene labels, document structure) are *additive* on top.
- **Routing:** iPhone-origin assets → iPhone; Mac-origin → Mac; everything else (web/CLI/
  existing library/shared) → the processor chosen in settings (`ios` | `macos` | `server`).
  Every asset records `analysisProcessor` + `analysisDeviceId`, and a per-capability history table
  records exactly which device/model produced each result.
- **Devices never download originals for analysis** — local PHAsset pixels on the origin device,
  or the server's ~1440px preview for assigned non-local assets (consistent with the
  "no full originals" rule).
- **CloudKit: no.** The server cannot durably reach a user's private CloudKit DB (30-min / 2-week
  per-user web tokens only), it breaks for family members on different Apple IDs, ADP can make it
  unreadable, and iCloud Photos already moves photos between one person's devices. Heirloom server
  stays the single source of truth; APNs sent by the server provides the push. (§9)
- **Foundation Models** (on-device LLM) writes Trip/Memory titles and captions on Apple
  Intelligence devices; server provides a template fallback.
- **Editing (§13):** extend the existing non-destructive `EditRecipe` editor. Apple devices are the
  only renderers (no Core Image on Linux) and upload the rendered result as the asset's *edited
  rendition*. Build Apple's exact public pipelines first (RAW 9, HDR gain maps, Portrait depth,
  Cinematic focus + Audio Mix, Live Photo, video), then close approximations (sliders, filters as
  LUTs, curves/levels/selective color), then our own Neural Engine tools (Clean Up, Retouch, smart
  crop, subject masks, "make it warmer" edits). Not reproducible with public APIs: Portrait Lighting,
  re-editing Apple's Photographic Styles, Spatial Scenes, Reframe/Extend.

---

## 1. Apple framework catalogue (condensed — full detail + citations in research-apple-frameworks.md)

### 1.1 Library, access, background
| Framework / API | Use in Heirloom | OS |
|---|---|---|
| **PhotoKit** `PHAsset` (`mediaSubtypes`, `burstIdentifier`, `representsBurst`, `sourceType`, `isFavorite`, `hidden`, `playbackStyle`) | Media Types + Favorites/Hidden for iPhone/Mac-origin assets, no ML needed | iOS 8+ |
| `PHAssetCollectionSubtype` smart albums 200–219 | Public: Videos, Selfies, Live, Portrait, Slo-mo, Time-lapse, Bursts, Screenshots, Panoramas, Long Exposure, Animated, RAW, Cinematic, Spatial, Favorites, Hidden, Recently Added. **Not public:** Duplicates, Receipts, Handwriting, Illustrations, QR, Identity Docs, Documents, Imports, Recently Saved/Viewed/Edited/Shared, People, Trips, Memories | — |
| `PHPersistentChangeToken` / `fetchPersistentChanges(since:)` | Incremental "what's new/changed since last analysis" that survives relaunch | iOS 16 / macOS 13 |
| `PHCloudIdentifier` | Same asset seen on iPhone *and* Mac (iCloud Photos) → process once | iOS 15 / macOS 12 |
| `PHImageManager` / `PHCachingImageManager`, `PHAssetResourceManager` | Pull analysis-size pixels (≈512–1024px) from local library | — |
| `PHBackgroundResourceUploadJobExtension` (iOS 27; 26.1 predecessor deprecated) | System-managed background *upload* — separate track, blocked by static `BackgroundUploadURLBase` for self-hosted URLs | iOS 26.1+ |
| **PhotosUI** `PhotosPicker`, `PHLivePhotoView`, editing extensions | Existing UI concerns, not analysis | — |
| **BackgroundTasks** `BGProcessingTask` (`requiresExternalPower`) | Silent overnight analysis while charging | iOS 13+ |
| `BGContinuedProcessingTask` | User-tapped "Analyze library now" with system progress UI | iOS 26+ |
| `ProcessInfo.thermalState`, `isLowPowerModeEnabled` | Throttle / pause | — |
| macOS `SMAppService` (login item / agent) | Mac analysis agent while plugged in & idle | macOS 13+ |

### 1.2 On-device AI (Neural Engine)
| Framework / API | Output | Heirloom use | OS |
|---|---|---|---|
| **Vision** `GenerateImageFeaturePrintRequest` | float vector + `distance` (pin revision) | Near-duplicate / "similar photos" refinement, burst grouping | iOS 13 (Swift 18) |
| `ClassifyImageRequest` | ~1,303 scene/object labels + confidence | Scene labels → search facets, Illustrations/Documents/Receipts signals, memory themes | iOS 13 |
| `CalculateImageAestheticsScoresRequest` | `overallScore` [-1,1], `isUtility` | "Best shot", Memory curation, key photo; `isUtility` separates screenshots/receipts/docs from real photos | iOS 18 |
| `DetectFaceRectanglesRequest` / `DetectFaceLandmarksRequest` / `DetectFaceCaptureQualityRequest` | boxes, landmarks, quality | Face crops + alignment; best face for person cover | iOS 11/13 |
| *(no Apple face-identity API)* → **Core ML ArcFace** (buffalo_l `w600k_r50`) | 512-d face vector | People clustering (server) | Core ML |
| `RecognizeTextRequest` (rev 3) | lines + boxes | OCR → existing `asset_ocr` + search | iOS 13 |
| `RecognizeDocumentsRequest` | paragraphs, tables, lists, barcodes | Documents / Receipts / Identity Documents / Handwriting signals | iOS 26 |
| `DetectBarcodesRequest` | payload + symbology | QR Codes utility | iOS 11 |
| `RecognizeAnimalsRequest`, `DetectHumanRectanglesRequest`, body pose 2D/3D | animals, people boxes | Pets memories, "people present without face" | iOS 13/17 |
| Saliency (attention/objectness), `DetectHorizonRequest` | heat map, angle | Smart crop for Memory covers, auto-straighten (already used in Editing) | iOS 13 |
| `GenerateForegroundInstanceMaskRequest`, person segmentation | masks | Memory cover/title effects, later | iOS 17 |
| `DetectLensSmudgeRequest` | confidence | Quality penalty in best-shot ranking | iOS 26 |
| **VisionKit** `ImageAnalyzer` / `ImageAnalysisInteraction` | Live Text, subject lift UI | Viewer UX (already on macOS) — not the batch pipeline | iOS 16 |
| **Core ML** (+ `MLTensor`, ML Program) | — | Runs CLIP ViT-B/32 image encoder + text encoder, ArcFace, SCRFD | iOS 15+ |
| "Core AI" (WWDC26) | — | UNVERIFIED — track; no dependency | iOS 27 |
| **Foundation Models** (`@Generable`, tools; image input in 27) | structured text | Trip/Memory titles, subtitles, captions; iOS 27 image-attached captioning | iOS 26 |
| **Natural Language** `NLContextualEmbedding`, `NLTagger` | token vectors, entities | Optional: OCR/caption text search, language ID | iOS 17 |
| **Translation** | on-device translation | Optional: translate OCR text | iOS 18 |
| **Speech** `SpeechAnalyzer` / `SpeechTranscriber` | transcript | Opt-in: searchable video speech | iOS 26 |
| **SoundAnalysis** `SNClassifySoundRequest` | ~300 sound classes | Video tags (laughter, music, fireworks, applause) → Memories | iOS 13 |
| **Create ML** | custom classifier | Fallback for Identity Documents / Handwriting if Vision signals are weak | — |
| **MLX Swift** | — | Mac-only option for larger models later; not v1 | macOS |

### 1.3 Media processing & context
| Framework | Heirloom use |
|---|---|
| **ImageIO** | EXIF/GPS/maker notes; aux data: depth, portrait matte, ISO gain map (HDR) — Portrait/HDR truth instead of flaky `.photoHDR` |
| **Core Image** | `CIRAWFilter` for RAW preview; resize/normalize tensors for Core ML; auto-enhance |
| **AVFoundation** | `AVAssetImageGenerator` keyframes for video CLIP/faces; `AVAssetReader` audio for SoundAnalysis/Speech; MV-HEVC spatial (pick one eye) |
| **Accelerate** (vDSP/BNNS) | Fast cosine/L2 for local dedup of a batch before upload |
| **Metal / MPS / MPSGraph** | Only if a model needs custom GPU pre-processing; not v1 |
| **Core Location / MapKit** `CLGeocoder`, `MKLocalSearch` | POI names for Trip/Memory titles (server already has city-level reverse geocode) |
| **EventKit** | Opt-in: calendar event names for Memory titles ("Maya's birthday") |
| **Contacts** | Name a person cluster from a contact |
| **WeatherKit** | Optional flavour; historical depth UNVERIFIED — not v1 |
| **App Intents / Spotlight** | Later: expose People/Places/Trips to Siri & Spotlight |

### 1.4 What Apple Photos uses privately (not usable)
`photoanalysisd`, `mediaanalysisd`, PhotosGraph knowledge graph (others named in prompt UNVERIFIED).
Apple's People pipeline (published 2021): detect face + upper body → embed → cluster. Heirloom
reproduces it with public Vision + its own Core ML face model; the knowledge graph becomes
Heirloom's Postgres tables.

---

## 2. Architecture

```
 iPhone (origin: ios)                Mac (origin: macos)             Heirloom server
 ┌──────────────────────┐            ┌──────────────────────┐        ┌─────────────────────────────┐
 │ PHAsset (local px)   │            │ PHAsset (local px)   │        │ assets + previews           │
 │   or server preview  │            │   or server preview  │        │                             │
 │ PhotosCore/Analysis  │            │ PhotosCore/Analysis  │        │ Analysis API                │
 │  Vision + Core ML    │──results──▶│  (same package)      │─results▶│  • work queue + leases      │
 │  (ANE)               │  (REST)    │  login-item agent    │ (REST) │  • results ingest           │
 │ BGProcessingTask /   │◀─work──────│                      │◀─work──│ Aggregators (jobs)          │
 │ BGContinuedProcessing│            │                      │        │  • face clustering (People) │
 └──────────────────────┘            └──────────────────────┘        │  • duplicate groups         │
          ▲  Foundation Models title jobs (Apple Intelligence devices) │  • smart-collection rules   │
          └──────────────────────────────────────────────────────────│  • trips / memories         │
                                                                     │ Fallback ML (python) when   │
                                                                     │  processor = server/timeout │
                                                                     └─────────────────────────────┘
```

### 2.1 Division of labour
| Work | Where | Why |
|---|---|---|
| CLIP image vector, face detect + face vector, OCR | Any processor (device or server) | Same models → comparable results |
| Aesthetics, `isUtility`, scene labels, document structure, QR, animals, lens smudge, feature print, sound tags | Devices only | Apple-only APIs; server has no equivalent (server gets CLIP zero-shot fallback for the few that feed collections, §5) |
| Face clustering → People | Server | Needs all faces across the library (existing Immich job, unchanged) |
| Duplicate groups | Server | Existing CLIP-distance job; devices add a feature-print "confirm" signal |
| Smart-collection membership | Server rules over stored signals | One definition, all clients agree |
| Trips, Memories (selection) | Server | Whole-library + time + GPS |
| Trip/Memory titles & captions | Device (Foundation Models) → server fallback template | LLM is on-device only |

### 2.2 Model manifest = the compatibility contract
Server exposes `GET /analysis/manifest`: for each capability, the server's configured model
(`clip: ViT-B-32__openai, dim 512`; `face: buffalo_l, dim 512`; `ocr: …`) plus the minimum
device-model version it accepts. A device uploads a vector **only** if it ships a Core ML
conversion of that exact model; otherwise it uploads only Apple-native signals and leaves that
capability to the server. If the admin switches the CLIP model, device vectors stop being accepted
and the existing re-index job regenerates them (server or re-queued to devices).

Model licences: OpenAI CLIP weights = MIT ✅. InsightFace buffalo_l = non-commercial research
licence — same terms Immich already runs under for personal self-hosting; acceptable for a
personal homelab, flag if Heirloom is ever distributed commercially. MobileCLIP = research-only
and a *different* vector space → **not used**.

---

## 3. Routing — which device processes which asset

### 3.1 Rules
1. Asset uploaded by the iOS app (asset has `deviceId` of a registered iOS device) → that iOS
   device (the "origin device").
2. Asset uploaded by the macOS app → that Mac.
3. Everything else (web upload, CLI, external library, pre-existing library, partner/shared) →
   `defaultProcessor` setting: `ios` | `macos` | `server` (+ which device if several).
4. Fallback: if an assigned device has not completed an asset within `deviceTimeout` (default 7
   days) the server either re-assigns to `defaultProcessor` or processes it itself
   (`fallbackToServer`, default on). Prevents a lost iPhone from stalling the library forever.
5. Per-capability override (advanced): e.g. `clip: server` if the owner wants the server GPU to do
   vectors while devices do Apple-only signals.

### 3.2 Work queue & leases (server-side, not CloudKit)
- `GET /analysis/work?limit=50` → assets assigned to the calling device and not leased;
  returns `assetId`, `deviceAssetId` (local PHAsset id if origin), `checksum`, preview URL,
  required capabilities, manifest version.
- Lease row per asset (`expiresAt` = now + 30 min, renewed per batch). Expired leases return to
  the pool. Assets with a live device lease are skipped by the server's own ML jobs.
- Origin device resolves `deviceAssetId` → PHAsset (via `PHCloudIdentifier` if local id changed);
  if not found locally, falls back to the server preview.

### 3.3 Where the server must stop doing its own ML
Server ML jobs (smart search, face detection, OCR) check `resolveProcessor(asset)`; if it's a
device and the device hasn't timed out → skip and let the device do it. `asset_job_status`
timestamps are set by the ingest endpoint so existing "missing" queues don't re-enqueue.

---

## 4. Server data model changes (kysely schema in `server/src/schema/tables/`)

```
enum analysis_processor  = 'server' | 'ios' | 'macos'

asset (+)
  analysisProcessor        analysis_processor NULL   -- who produced the primary analysis (owner's "which device" field)
  analysisDeviceId         text NULL                  -- registered device id (null for server)
  analysisCompletedAt      timestamptz NULL

analysis_device                                       -- registered processors
  id, userId, platform ('ios'|'macos'), name, model ("iPhone 17 Pro"), osVersion,
  appVersion, capabilities jsonb (models/versions, appleIntelligence bool), lastSeenAt

analysis_run                                          -- one row per asset × capability (audit + re-run)
  assetId, capability ('clip'|'face'|'ocr'|'labels'|'aesthetics'|'document'|'barcode'|
                       'featureprint'|'sound'|'speech'|'caption'),
  processor, deviceId, modelName, modelVersion, processedAt, durationMs, status, error
  PK(assetId, capability)

analysis_lease   assetId PK, deviceId, expiresAt

asset_label      assetId, label, score real, source ('vision-classify'|'clip-zeroshot'|'sound'),
                 PK(assetId, label, source)                   -- scene/object/sound tags
asset_quality    assetId PK, aestheticScore real, isUtility bool, faceQualityMax real,
                 lensSmudge real, sharpness real NULL
asset_document   assetId PK, kind ('document'|'receipt'|'id'|'handwriting'|'illustration'|'qr'|null),
                 kindScore real, paragraphCount, tableCount, barcodes jsonb, docText text
asset_feature_print  assetId PK, revision smallint, embedding vector(N)   -- N fixed per revision (WP0)

existing, reused as-is:
  smart_search (512-d CLIP)       ← device vectors when manifest matches
  asset_face (+ sourceType stays MachineLearning), face_search (512-d)
  asset_ocr                        ← device OCR lines
  memory / memory_asset            ← new memory types (§7)
  asset.duplicateId                ← server duplicate job

trip        id, ownerId, title, subtitle, startAt, endAt, centroid, places jsonb,
            coverAssetId, titleSource ('template'|'foundation-models'), titleDeviceId
trip_asset  tripId, assetId

system/user config
  analysis.defaultProcessor, analysis.defaultDeviceId, analysis.deviceTimeoutDays,
  analysis.fallbackToServer, analysis.capabilityOverrides, trips.homeLocation (user), …
```

Access control: every analysis endpoint must enforce the fork's S2 access-control rules — a device
may only submit results for assets its user owns (or shared-library assets where the user has
edit rights). Ties into the existing deploy gate.

### 4.1 API (OpenAPI → regenerates `ImmichAPI` Swift client)
| Endpoint | Purpose |
|---|---|
| `POST /analysis/devices` / `PUT …/{id}` | Register device + capabilities (heartbeat) |
| `GET /analysis/manifest` | Server model contract (§2.2) |
| `GET /analysis/work` | Pull assigned assets + take leases |
| `POST /analysis/results` | Batch ingest (≤50 assets): vectors, faces, OCR, labels, quality, document, sound, feature print; per-capability model ids |
| `POST /analysis/leases/release` | Give back unfinished leases on suspend |
| `GET /analysis/title-jobs` / `POST …/{id}` | Foundation Models title/caption jobs for trips/memories |
| `GET /analysis/stats` | Per-processor progress for settings UI |
| `POST /analysis/reprocess` | Re-queue assets (by processor/device/capability/model) |

Ingest writes in one transaction per asset, upserts `analysis_run`, sets `asset.analysis*`,
stamps `asset_job_status`, then queues server aggregators: `FacialRecognition` (clustering),
`DuplicateDetection`, `SmartCollectionEvaluate`, and debounced `TripDetect` / `MemoryGenerate`.

---

## 5. Smart collections — signal → rule

Membership is computed on the server from stored signals (materialised in a
`asset_collection_membership` view/table or evaluated by the existing search filters).
Sources: **PK** = PhotoKit on origin device · **EXIF** = server metadata (works for every asset) ·
**V** = Vision on device · **S** = server state/events · **C** = CLIP zero-shot on server (fallback
for non-device assets).

### Utilities
| Collection | Rule | Sources |
|---|---|---|
| Favorites / Hidden / Recently Deleted | existing `isFavorite`, locked folder/`visibility`, trash | S (+PK sync of favorite/hidden on upload) |
| Duplicates | `duplicateId` groups (CLIP distance) confirmed by feature-print distance when both present | S + V |
| Captured by Me | EXIF make/model matches one of the user's registered devices, or PK `sourceType == userLibrary` and camera EXIF present | EXIF + PK |
| Identity Documents | `asset_document.kind='id'` (document request + ID-like label/text heuristics: MRZ `<<<`, "passport", DOB fields) | V (+C) |
| Receipts | `kind='receipt'` (classify label receipt + totals/currency lines + table) | V (+C) |
| Handwriting | `kind='handwriting'` (UNVERIFIED Vision signal → Create ML fallback) | V |
| Illustrations | classify labels drawing/illustration/cartoon, `isUtility`, no camera EXIF | V (+C) |
| QR Codes | `barcodes` contains QR | V |
| Recently Saved | assets whose origin is "saved from another app" (no camera EXIF, PK `sourceType`, filename patterns) added in last 30 days | PK + EXIF |
| Recently Viewed / Edited / Shared | new `asset_event` log (viewed, edited in Heirloom editor, shared-link/album add) — not ML | S |
| Documents | `kind in (document, receipt, id)` or `isUtility && paragraphCount>0` | V |
| Imports | upload batches from web/CLI/external library (group by upload session) | S |
| Map | existing GPS | EXIF |

### Media Types (device PhotoKit is authoritative for its own assets; EXIF fallback for all others)
| Collection | PhotoKit | EXIF / file fallback |
|---|---|---|
| Videos | `mediaType == .video` | mime type |
| Selfies | smart album SelfPortraits | lens model contains "front" |
| Live Photos | `.photoLive` | existing `livePhotoVideoId` |
| Portrait | `.photoDepthEffect` | ImageIO depth / portrait-matte aux data (device) or Apple maker note |
| Slo-mo | `.videoHighFrameRate` | fps ≥ 120 |
| Cinematic | `.videoCinematic` | Apple QuickTime metadata (verify key in WP0) |
| Bursts | `burstIdentifier` | Apple maker note BurstUUID |
| Screenshots | `.photoScreenshot` | no camera EXIF + screen-resolution + UserComment "Screenshot" |
| Screen Recordings | `.videoScreenRecording`? UNVERIFIED | no camera, screen resolution video |
| RAW | resource type / smart album RAW | file extension / mime |
| Panoramas, Time-lapse, Spatial, Long Exposure | subtypes | aspect ratio / metadata |

Implementation: on upload (existing `Upload` package) the app already has the PHAsset → send
`mediaSubtypes`, `burstIdentifier`, `sourceType`, `playbackStyle` as upload metadata into a new
`asset_apple_metadata` jsonb column. Cheap, no ML, lights up most of Media Types immediately.

---

## 6. People (faces)

1. Device: Vision `DetectFaceRectanglesRequest` → for exact parity with the server's alignment,
   run the converted **SCRFD (det_10g)** detector too, OR derive the 5 alignment points from Vision
   landmarks — WP0 measures both; pick whichever keeps cosine(device, server) ≥ 0.95 on the same
   face.
2. Align to 112×112, run ArcFace Core ML → 512-d vector; attach `DetectFaceCaptureQualityRequest`
   score and bounding box (normalised to the asset's original dimensions/orientation).
3. Upload to `asset_face` + `face_search`; server's existing incremental clustering assigns
   `personId`. Face quality picks the person's cover face.
4. Naming: app offers Contacts picker (`CNContactPickerViewController`) → sets person name;
   birthday from contact enables "birthday" memories.
5. Later (optional): Apple's paper also clusters **upper bodies** to catch turned-away faces —
   body-crop feature print as a within-event linker. Not v1.

## 7. Trips & Memories

### Trips (server job `TripDetect`, runs nightly + after ingest bursts)
1. Home: user setting, else infer = most frequent GPS cluster of night-time photos over the last
   12 months (DBSCAN, 1 km).
2. Take GPS-tagged assets ordered by time; mark "away" when > `awayKm` (default 80 km) from home.
3. Segment contiguous away runs; merge gaps ≤ 36 h and returns home < 12 h; require ≥ 1 night or
   ≥ `minAssets` (default 20).
4. Include non-GPS assets captured inside the window by the user's devices.
5. Place set = reverse-geocoded states/countries (server already has local geodata) → template
   title: 1 region "Florida", 2 "Alabama & Florida", 3+ "Southeast US" / country; subtitle
   = date range ("APR 6–19, 2026" as in the screenshot).
6. Cover = highest `aestheticScore` non-utility photo with faces preferred.
7. Title job enqueued → an Apple-Intelligence device calls Foundation Models with a `@Generable`
   `TripTitle { title, subtitle }` given places, POIs (`MKLocalSearch`), dates, top labels, people
   names; server keeps the template if no device answers. User edits always win.
UI: Trips screen with All / year segments (matches screenshot) in iOS & macOS Collections.

### Memories (extend existing `memory` table types; server job `MemoryGenerate`)
| Type | Selection |
|---|---|
| On this day (exists) | + curate with `aestheticScore`, drop `isUtility`, dedupe by `duplicateId`/burst |
| Trip | each trip ≥ 1 year old, or just-finished trip |
| Person / "Together" | person (or pair) with many high-quality photos in a period |
| Pets | `RecognizeAnimals` labels cat/dog over time |
| Year / season in review | top-N by aesthetics per month, diversity via CLIP clustering |
| Celebrations | labels (cake, fireworks, Christmas tree…) + sound tags (singing, applause) + calendar (opt-in) |
| Place | home-city repeated location outside trips (e.g. a beach you visit every summer) |
Curation for all: drop `isUtility`, drop screenshots/docs, collapse duplicates/bursts to the best
shot, limit N, spread across time. Titles via the same Foundation Models job path.

---

## 8. Device pipeline (new `PhotosCore/Sources/Analysis` package)

```
AnalysisCoordinator
  ├─ WorkSource        pull /analysis/work (+ local PHPersistentChangeToken for new captures)
  ├─ PixelProvider     PHImageManager (local) | Nuke fetch of server preview (remote); ~1024px, sRGB
  ├─ Analyzers         (each: capability, modelId, version, `analyze(CGImage) async throws -> Result`)
  │    ClipImageAnalyzer (Core ML), FaceAnalyzer (Vision + Core ML), OCRAnalyzer, DocumentAnalyzer,
  │    ClassifyAnalyzer, AestheticsAnalyzer, BarcodeAnalyzer, FeaturePrintAnalyzer,
  │    VideoAnalyzer (AVAssetImageGenerator keyframes → image analyzers; SoundAnalysis; Speech opt-in)
  ├─ ResultStore       GRDB table of pending results (survives suspension)
  ├─ Uploader          batch POST /analysis/results, retries, releases leases
  └─ Governor          thermal state, low-power, battery/charging, user "only while charging"
```
- One `VNImageRequestHandler` per image, all Vision requests in a single `perform` to share decode.
- Core ML models compiled `.mlmodelc`, `computeUnits = .cpuAndNeuralEngine`; loaded once per run.
- Models shipped via on-demand download from the Heirloom server (`/analysis/models/{id}`) rather
  than bundled, keeping the app small and letting the manifest drive versions (~150 MB CLIP-B/32
  fp16 + ~170 MB ArcFace r50 fp16 — WP0 to try int8 palettisation).
- **iOS scheduling:** `BGProcessingTask` (`requiresExternalPower`, network) nightly; foreground
  opportunistic batches while the app is open and cool; `BGContinuedProcessingTask` for
  "Analyze now" with progress. New iPhone captures are analysed from local pixels *before or at*
  upload time so the server never runs its own ML for them.
- **macOS:** `SMAppService` login-item agent sharing the App Group container; runs while on AC and
  idle; also processes `defaultProcessor = macos` assets from server previews — the Mac is the
  natural choice for the existing library backlog.
- **tvOS:** consumer only (no analysis, no durable storage).

---

## 9. CloudKit — decision

**Do not use CloudKit for photos or metadata.** Evidence (research-cloudkit.md):
- Server-to-server keys only reach the *public* DB; a user's private DB needs a per-user
  `ckWebAuthToken` (30 min, max 2 weeks) → no durable server integration; no server-side push.
- ADP can make fields/assets cryptographically unreadable to anything but the user's devices.
- Private DB is per-Apple-ID → breaks for family members sharing one Heirloom library.
- Originals: iCloud Photos + `PHCloudIdentifier` already sync a person's own devices; CKAsset
  copies would double-bill iCloud quota and contradict the budgeted-cache rule.
- Constraints: 1 MB records, 250-record batches, no unique constraints in SwiftData/CK mirroring.

**Instead:** server = source of truth; device↔device coordination through server leases (§3.2);
change notification via APNs sent by the Heirloom server (own `.p8` key) + existing sync/WebSocket.
**Allowed, optional:** `NSUbiquitousKeyValueStore` for a handful of per-user UI preferences.

Background *upload* (`PHBackgroundResourceUploadJobExtension`) is the right future transport but
needs a static `BackgroundUploadURLBase` — track as a separate spike (relay domain vs. wait for the
Immich community pattern); not part of this program.

---

## 10. Work packages

| WP | Scope | Owner tier | Depends |
|---|---|---|---|
| **WP0 Spikes & verification** | (a) convert CLIP ViT-B/32 image+text and buffalo_l (SCRFD+ArcFace) to Core ML; parity harness vs server ML on 300 assets: CLIP cosine ≥ 0.99, face cosine ≥ 0.95, same clusters; (b) iPhone/Mac throughput + thermals (target ≥ 5 assets/s Mac, ≥ 1.5/s iPhone plugged in); (c) confirm: feature-print dims per revision, handwriting signal, ID-doc heuristics, screen-recording subtype, cinematic metadata key; (d) confirm server CLIP model/dim + duplicate threshold in fork config | Opus designs harness; implementer (Sonnet) builds; Opus judges numbers | — |
| **WP1 Server schema + API** | migrations (§4), analysis module (devices, manifest, work/leases, results ingest, stats, reprocess), job gating (§3.3), S2 access checks, OpenAPI regen | implementer | WP0d |
| **WP2 PhotosCore Analysis package** | coordinator, pixel provider, analyzers, GRDB result store, uploader, governor, model downloader | implementer | WP0a, WP1 API |
| **WP3 iOS integration** | device registration, BG tasks, Analyze-now, origin analysis at capture/upload, Apple metadata on upload (§5) | implementer | WP2 |
| **WP4 macOS agent** | login item, AC/idle governor, backlog processing from previews | implementer | WP2 |
| **WP5 Smart collections** | server rules + endpoints, `asset_event` log, iOS/macOS Utilities & Media Types wiring (replace current placeholders) | implementer; Opus reviews rules | WP1, WP3 |
| **WP6 Duplicates review UI** | group view, keep-best (aesthetics), merge metadata, trash others (+ optional delete local copy via `PHAssetChangeRequest`) | implementer | WP5 |
| **WP7 People** | face ingest → clustering, Contacts naming, cover by quality | implementer; Opus reviews parity | WP0a, WP2 |
| **WP8 Trips + Memories** | TripDetect, memory types, curation, Foundation Models title jobs, Trips UI | Opus designs heuristics; implementer | WP5, WP7 |
| **WP9 Video** | keyframes, sound tags, opt-in transcripts | implementer | WP2 |
| **WP10 Settings & admin** | processor routing UI (user + admin), per-processor stats, reprocess actions, "processed by" in asset info panel | implementer | WP1 |
| **WP11 Verification** | server unit/e2e for ingest & routing; device tests on real hardware (Vision aesthetics/instance masks don't run in Simulator) | verifier | each WP |

Suggested order: WP0 → WP1 → WP2 → (WP3 ∥ WP4 ∥ WP10) → WP5 → WP7 → WP6 → WP8 → WP9.

---

## 11. Decisions for the owner (recommended default in **bold**)

1. Default processor for existing + web-uploaded assets: **macos** (your Mac, while plugged in) | ios | server.
2. Fallback when an assigned device is silent for 7 days: **server processes it** | reassign | wait.
3. Ship InsightFace buffalo_l on devices (same non-commercial licence Immich uses) for face parity: **yes** | use a permissively licensed face model and re-embed server-side too.
4. Model delivery: **download from your Heirloom server on demand** | bundle in app.
5. Opt-in extras: video speech transcripts (off), calendar titles via EventKit (off), Foundation Models titles (**on** where available).
6. Trip threshold: **80 km from home, ≥ 1 night** — or set Home explicitly.
7. Model choice (see §2.2 — ViT-B/32 + buffalo_l were placeholders = server defaults):
   search → **ViT-B-16-SigLIP2__webli** (Apache-2.0, 768-d, big recall gain, fits iPhone ANE);
   faces → WP0 bake-off on the owner's own labelled faces: buffalo_l vs antelopev2 vs AdaFace IR-101
   (MIT). Whatever wins is set on the server first, then converted for devices.
8. Where an edited version lives: **a rendition file on the same asset** (one timeline item;
   Revert = drop it) | keep today's "rendered copy uploaded as a new asset".
9. Import edits you make in Apple Photos into Heirloom (as a rendition; Apple's recipe is private):
   **yes**.
10. Write Heirloom edits back into Apple Photos for iPhone-origin photos (revertible there):
    **off by default, per-edit "Also save to Photos"**.
11. Clean Up engine: **LaMa (Apache-2.0) converted to Core ML** — approve bundling/downloading a
    ~200 MB model.

## 12. Risks
- Face-alignment drift between Vision landmarks and SCRFD → mixed clusters. Mitigated by WP0 gate.
- Apple-only signals missing on server-processed assets → collections like Receipts are weaker for
  those; CLIP zero-shot fallback + recommending `macos` as default processor.
- Device backlog on first run (tens of thousands of assets) — Mac first, iPhone only new captures
  unless the user chooses otherwise.
- iOS background time is scarce; the plugged-in overnight window is the main budget.
- Admin changing the server CLIP model invalidates device vectors — manifest check + re-queue.

---

## 13. Editing with native frameworks & the Neural Engine

Detail + citations: [research-editing.md](research-editing.md). Current state: [recon-editing.md](recon-editing.md).
Existing specs this builds on (do not duplicate): `heirloom-macos-photos-parity/WP-E-EDIT.md` (Mac
editor UI), `heirloom-ios-photos-parity/PLAN.md` (iOS editor gaps E1–E7 and P0 defects F1/F3).

### 13.1 What already exists
- `PhotosCore/Sources/Editing`: non-destructive `EditRecipe` (Adjust ×16 sliders + auto, Style,
  Crop incl. straighten/perspective/flip/aspect, Portrait aperture + focus, Markup, Video
  trim/mute/rotate/Live key frame), Core Image + Metal `EditRenderer`, Vision horizon auto-straighten,
  iOS Photo Editing Extension target.
- Persistence: crop / 90° rotate / mirror → server `asset_edit` table (server renders these);
  everything else → recipe in metadata KV `fork.editRecipe.v1` + full-res render uploaded as a
  **new asset**.
- Web: crop / rotate / mirror only.
- **Blocker:** iOS editor black canvas (F1) and video editor stall (F3) — must be fixed first
  (owned by the iOS parity plan).

### 13.2 Principles
1. **Apple devices are the renderers.** No Core Image on Linux; rebuilding every filter in libvips
   gives visible drift for no gain. The editing device renders full-res and uploads the result.
   The server renders only what it already does exactly (crop / rotate / mirror).
2. **Recipe = abstract, versioned parameters** (already true — sliders are −100…100, not CIFilter
   blobs). Add `recipeVersion` + `rendererVersion`; the uploaded rendition is the source of truth
   for display, so a later renderer change never silently changes an old edit.
3. **Generated pixels are stored, not re-generated.** Clean Up / Retouch / anything ML-generated
   saves its patch (PNG + mask + model id) as a recipe resource, so re-rendering on another device or
   model version gives the same picture.
4. **Heirloom's own viewer isn't limited by PhotoKit.** "Not possible" items that are only about
   flags inside Apple Photos (Live Loop/Bounce/Long Exposure) are recipe fields + Heirloom playback.
5. Edits that must reach Apple Photos go through `PHContentEditingOutput` + `PHAdjustmentData`
   (recipe JSON inside), so Apple Photos can revert and Heirloom can re-open them.

### 13.3 Feature map — Apple Photos → Heirloom

**Tier A — Apple's own public pipeline (exact)**
| Photos feature | API | Heirloom status / work |
|---|---|---|
| RAW / ProRAW editing | `CIRAWFilter` (exposure, boost, local tone map, NR, detail, highlight recovery, lens correction; RAW 9 Neural Engine demosaic/denoise in iOS/macOS 27) | New `RawRecipe`; open RAW originals through CIRAWFilter, sliders feed its linear stage |
| HDR photos (view, edit, keep HDR, Mac "Mute HDR") | `CIImage(.expandToHDR)`, `contentHeadroom`, `toneMapHeadroom`, `CIContext.writeHEIFRepresentation(.hdrGainMapImage, hdrGainMapAsRGB)` | Renderer works in extended range; rendition written with a gain map; `hdrHeadroom` recipe field |
| Portrait depth + change focus | `CIContext.depthBlurEffectFilter(for:disparityImage:portraitEffectsMatte:hairSemanticSegmentation:glassesMatte:gainMap:…)` | Exists (aperture/focus); switch to the newer overload with hair/glasses mattes; hide tab when no depth (E7) |
| Cinematic video: change focus subject, depth | `Cinematic`: `CNAssetInfo`, `CNScript`, `CNDecision`, `CNObjectTracker`, `CNRenderingSession` | New `CinematicRecipe` (serialized script changes — verify `CNScript.Changes` data representation) |
| Audio Mix (iPhone 16+ spatial audio) | `CNAssetSpatialAudioInfo.audioMix(effectIntensity:renderingStyle:)` → `AVAudioMix` | New `audioMix { style, intensity }` in `VideoRecipe` (iOS gap E6) |
| Live Photo edits across all frames, key photo, mute, trim | `PHLivePhotoEditingContext` + `frameProcessor`; AVFoundation for trim/mute | Apply the photo recipe to every frame; key frame exists; verify key-photo write-back for Apple Photos |
| Video adjust / filters / crop / trim / speed / slo-mo ramp | `AVVideoComposition(asset:applyingCIFiltersWithHandler:)`, `AVMutableComposition`, `scaleTimeRange` | Same `EditRenderer` graph per frame; add `speedRamps[]` and filmstrip trim UI (E5); HDR video (HLG/Dolby Vision) preservation spike |
| Straighten, red-eye, white-balance eyedropper | `CIStraightenFilter`, `CIRedEyeCorrection` (+ face landmarks), `CITemperatureAndTint` | Straighten exists; add red-eye tool and WB eyedropper |
| Markup | PencilKit (`PKCanvasView`, `PKDrawing`) | Exists (iOS flattened, macOS vector); store `PKDrawing.dataRepresentation()` so iOS markup stays editable |

**Tier B — close approximations with Core Image (Apple's exact math is private)**
| Photos feature | Approach |
|---|---|
| Exposure, Highlights, Shadows, Contrast, Brightness, Saturation, Vibrance, Warmth/Tint, Sharpness, NR, Vignette | `CIExposureAdjust`, `CIHighlightShadowAdjust`, `CIColorControls`, `CIVibrance`, `CITemperatureAndTint`, `CISharpenLuminance`, `CINoiseReduction`, `CIVignetteEffect` (exists) — **tune the slider curves against Apple Photos** with a reference set (below) |
| Brilliance, Definition, Black Point | Custom Metal local-tone-mapping / clarity kernel (`CIKernel`) instead of chained filters |
| Auto Enhance | `autoAdjustmentFilters` baseline **plus** aesthetics-guided search: render ~8 candidates on a small proxy, score with `CalculateImageAestheticsScoresRequest`, keep the best — mapped back onto the normal sliders so the user can adjust it |
| Filters (Vivid/Warm/Cool, Dramatic/Warm/Cool, Mono, Silvertone, Noir) | Our own 3D LUTs (`CIColorCubeWithColorSpace`) sampled from Apple Photos output on a colour chart + test set; `CIPhotoEffect*` are a different, older set |
| Photographic Styles | Our own Tone × Color pad + Palette (spec'd in WP-E-EDIT); Apple's per-shot style metadata can't be read or re-driven |
| Curves, Levels, Selective Color (Mac) | `CIToneCurve` / custom `CIColorKernel` for 6-range HSL (already spec'd in WP-E-EDIT) |
| Perspective (vertical/horizontal), aspect presets, flip, rotate | Exists (`CIPerspectiveCorrection` + transforms) |
| Live Photo Loop / Bounce / Long Exposure | `LiveRecipe.playbackStyle`: Heirloom player loops / bounces the paired video; Long Exposure = frame-average of the aligned frames (`VNHomographicImageRegistrationRequest` + averaging kernel) rendered to a still. Only the badge inside Apple Photos is impossible |

Fidelity harness (applies to all of Tier B): 50 reference photos edited in Apple Photos at fixed
slider values → export → compare Heirloom renders by ΔE (`CILabDeltaE`) and SSIM; tune until
median ΔE < 3. Also a golden-image test to catch iPhone ↔ Mac render drift.

**Tier C — Heirloom's own Neural Engine tools (no Apple API; Core ML + Vision)**
| Feature | Approach | Priority |
|---|---|---|
| **Clean Up** (tap-to-remove, brush) | Suggest objects with `GenerateForegroundInstanceMaskRequest` / person instance masks; fill with **LaMa** converted to Core ML (512px tiles around the mask, blended back at full res). Patch stored per §13.2-3 | P1 |
| Retouch brush (Mac + iOS) | Same inpainting engine with a small brush mask | P1 |
| Smart crop / auto-straighten suggestions | Horizon angle (exists) + candidate crops scored by saliency + aesthetics | P1 |
| Subject / background adjustments ("brighten the people", "blur the background") | Vision person / foreground instance masks as local-adjustment masks in the recipe (mask regenerated from recipe, cached) | P2 |
| Edit by instruction ("make it warmer and brighter") | Foundation Models `@Generable EditRecipeDelta` with `@Guide` ranges → applied as normal slider values (reviewable) | P2 |
| "Make portrait" on photos without depth | Monocular depth model (Apple's Core ML **Depth Anything V2 Small**, Apache-2.0) → synthetic disparity → the same `depthBlurEffectFilter` | P2 |
| Portrait Lighting look-alikes | Matte + custom relight kernels | P3 / probably skip |
| Extend (outpainting) | Mac-only experiment later (Core ML Stable Diffusion inpainting / MLX); too heavy for iPhone | P3 |

**Not doing (no public API, poor approximation value):** Apple's exact Portrait Lighting,
re-driving Apple Photographic Styles metadata, Spatial Scene conversion (visionOS-only APIs),
Reframe.

### 13.4 Storage & sync changes
- `EditRecipe` v2 (additive, still in `fork.editRecipe.v1`-style KV → bump to `.v2`): `recipeVersion`,
  `rendererVersion`, `raw`, `hdrHeadroom`, `live { playbackStyle, keyFrame, trim, muted }`,
  `video { speedRamps, audioMix, cinematicScript }`, `masks[]` (Vision mask requests by kind +
  params), `patches[]` (resource ids for inpainted areas), `markup.pkDrawing`.
- Recipe resources (patches, PKDrawing, cinematic script) stored as small files linked to the
  asset (new `asset_edit_resource` or asset-file type) rather than inside the JSON.
- **Rendition on the same asset** (decision 8): the device uploads the render as the asset's
  `edited` file; server builds thumbnails/previews from it; Revert deletes it; the timeline shows one
  item. Replaces "upload render as a new asset". Web/server crop-rotate-mirror stays in `asset_edit`,
  applied *on top of* the rendition.
- **Edits made in Apple Photos** (decision 9): `Backup` sees `PHAsset` adjustments via
  `PHPersistentChangeToken`, uploads the current full-size render as the rendition with
  `recipe.source = "apple-photos"` (not re-editable in Heirloom, Revert restores the original).
- **Write-back to Apple Photos** (decision 10): `PHContentEditingOutput` + `PHAdjustmentData`
  (`formatIdentifier = com.heirloom.edit`, recipe JSON). The existing Photo Editing Extension
  uses the same code, so "Edit with Heirloom" inside Apple Photos round-trips.
- Batch: Copy/Paste Edits across many assets queues **render jobs** on the analysis work queue
  (§3.2, new capability `render`), so the Mac agent renders a 200-photo paste in the background.

### 13.5 Performance targets
- Slider tick ≤ 16 ms on a 2048 px proxy (existing WP-E target), full-res export in the background.
- ML tools asynchronous with progress; Clean Up ≤ 1.5 s per mask on iPhone 15 Pro-class, model
  loaded lazily and evicted under memory pressure.
- Video: live preview through `AVPlayerItem.videoComposition`; export with the async
  `AVAssetExportSession.export(to:as:)`.

### 13.6 Editing work packages
| WP | Scope | Owner tier | Depends |
|---|---|---|---|
| **E0** | Fix iOS editor P0s F1/F3 (canvas black, video stall) | Opus diagnoses (cause unknown) | — |
| **E1** | Recipe v2, recipe resources, rendition-on-same-asset (server + clients), Apple Photos edits import, render jobs on the work queue | Opus designs server contract; implementer | E0, WP1 |
| **E2** | Tier A photo: RAW 9, HDR gain-map round trip + Mute HDR, depth-blur overload with mattes, red-eye, WB eyedropper, PKDrawing markup | implementer | E1 |
| **E3** | Tier B fidelity: harness (ΔE/SSIM), slider curve tuning, Brilliance/Definition kernels, 9 LUT filters, aesthetics-guided Auto Enhance; Mac Curves/Levels/Selective Color per WP-E-EDIT | implementer; Opus judges harness results | E1 |
| **E4** | Live Photo: frame-wide edits, key photo, trim/mute, Loop/Bounce playback, Long Exposure render | implementer | E1 |
| **E5** | Video: filmstrip trim, adjust/filters via `AVVideoComposition`, speed + slo-mo ramp, Cinematic focus editing, Audio Mix, HDR video spike | implementer | E1 |
| **E6** | Neural tools: LaMa Core ML conversion + Clean Up/Retouch UI, smart crop, masked adjustments, Foundation Models edit-by-instruction, depth-synthesized portrait | Opus reviews model conversion + quality; implementer | E1, WP0-style model spike |
| **E7** | Apple Photos integration: write-back option, Photo Editing Extension round trip | implementer | E1 |
| **E8** | Verification on real hardware (Neural Engine features don't run in Simulator) + golden images | verifier | each |

Order: E0 → E1 → (E2 ∥ E4 ∥ E7) → E3 → E5 → E6.
