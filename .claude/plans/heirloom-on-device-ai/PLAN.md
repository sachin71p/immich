# Heirloom On-Device AI — Plan

Status: DRAFT for owner review · 2026-09-17 · editing §13 added and plan re-based to **server-first** (RTX A4500) 2026-09-18 · Author: Opus (main session)
Inputs: [research-apple-frameworks.md](research-apple-frameworks.md) · [research-cloudkit.md](research-cloudkit.md) · [recon-codebase.md](recon-codebase.md) · [research-editing.md](research-editing.md) · [recon-editing.md](recon-editing.md)

---

## 0. TL;DR

- **Server-first (re-based 2026-09-18).** The homelab has an **NVIDIA RTX A4500 (20 GB, Ampere)**.
  With that GPU the server can run *larger* models than an iPhone for almost every analysis, over
  the whole library, with one consistent result. So all photo/video AI runs on the server; the
  iPhone and Mac contribute what **only they have**.
- **Server (GPU):** search vectors (SigLIP2), faces (winner of a bake-off), OCR, and one
  vision-language model (Qwen-VL class, 7–8B, 4-bit) that in a single pass writes a caption,
  document type (receipt / ID / handwriting / illustration…), utility-photo flag and tags. Plus
  Whisper for video speech and an audio tagger for video sounds. The server also does everything
  that needs the whole library: People clustering, duplicate groups, smart collections, Trips,
  Memories and their titles.
- **Devices:** (1) Apple photo-library facts sent with every upload (Live/Portrait/Cinematic/
  Slo-mo/Screenshot flags, bursts, favourite/hidden, "saved from other app"); (2) edits made in
  Apple Photos; (3) all editing and rendering (§13 — Core Image, Cinematic, depth, Neural Engine
  editing tools); (4) optional cheap Apple signals at upload (aesthetics + `isUtility`, document
  structure) stored as *extra* evidence.
- **"Processed by" is kept.** Every asset records `analysisProcessor` (`server` | `ios` | `macos`)
  + device id, and a per-capability history records exactly which processor and model produced
  each result. The routing setting stays so device offload can be switched on later
  (for a GPU-less install); building it is deferred.
- **CloudKit: no** (§9). Server = single source of truth; server-sent APNs for push.
- **Editing (§13):** unchanged by the re-base — Apple devices are the renderers. The GPU adds one
  option: heavy generative edits (Extend) can run on the server.

### Why server-first (owner asked 2026-09-18)
| Analysis | On device | On the A4500 server | Verdict |
|---|---|---|---|
| Search / faces / OCR | same models converted to Core ML | same models natively, and larger ones fit | server ≥ device |
| Scene labels, doc types, utility flag | Apple classifiers (private tuning) | vision-language model + zero-shot search model | close; VLM is more flexible |
| Aesthetics | Apple `CalculateImageAestheticsScoresRequest` | aesthetic head on the search vector | close; Apple signal kept as extra |
| Video speech / sounds | SpeechAnalyzer / ~300 classes | Whisper / 527 AudioSet classes | server better |
| Titles & captions | ~3B on-device LLM, text-only until iOS 27 | 7–8B VLM that *looks at* the photos | server better |
| Library facts, Apple Photos edits, editing render | ✅ only here | ✗ | device-only → devices keep these |
Device-side analysis would have cost: Core ML conversion + parity proofs, cross-device routing and
leases, OS updates silently changing Apple model outputs, uneven coverage, battery/iOS background
limits. None of that buys quality once the GPU exists.

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
| *(no Apple face-identity API)* | — | Faces are embedded on the server GPU (§6) | — |
| `RecognizeTextRequest` (rev 3) | lines + boxes | OCR → existing `asset_ocr` + search | iOS 13 |
| `RecognizeDocumentsRequest` | paragraphs, tables, lists, barcodes | Documents / Receipts / Identity Documents / Handwriting signals | iOS 26 |
| `DetectBarcodesRequest` | payload + symbology | QR Codes utility | iOS 11 |
| `RecognizeAnimalsRequest`, `DetectHumanRectanglesRequest`, body pose 2D/3D | animals, people boxes | Pets memories, "people present without face" | iOS 13/17 |
| Saliency (attention/objectness), `DetectHorizonRequest` | heat map, angle | Smart crop for Memory covers, auto-straighten (already used in Editing) | iOS 13 |
| `GenerateForegroundInstanceMaskRequest`, person segmentation | masks | Memory cover/title effects, later | iOS 17 |
| `DetectLensSmudgeRequest` | confidence | Quality penalty in best-shot ranking | iOS 26 |
| **VisionKit** `ImageAnalyzer` / `ImageAnalysisInteraction` | Live Text, subject lift UI | Viewer UX (already on macOS) — not the batch pipeline | iOS 16 |
| **Core ML** (+ `MLTensor`, ML Program) | — | Editing models (LaMa, depth); device-side search/face models only if the deferred device-offload mode is ever built | iOS 15+ |
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
 iPhone / Mac (Heirloom apps)                       Heirloom server (LXC 403, RTX A4500 20 GB)
 ┌──────────────────────────────┐   upload + apple  ┌──────────────────────────────────────────────┐
 │ PhotoKit: originals, library │ ─────metadata───▶ │ immich-ml (resident on GPU)                  │
 │   facts, Apple Photos edits  │                   │   SigLIP2 search · faces · OCR               │
 │ Optional Apple signals at    │ ─apple signals──▶ │ heirloom-vlm (vLLM, batch, loads on demand)  │
 │   upload (aesthetics, docs)  │                   │   caption · doc kind · utility · tags · titles│
 │ Editor (Core Image, Cinematic│ ─edit rendition─▶ │ heirloom-av (batch): Whisper · audio tags    │
 │   depth, LaMa Clean Up)      │                   │ CPU: pHash · QR (zxing) · EXIF media types   │
 │                              │ ◀─render jobs──── │ Aggregators: People clustering · duplicates  │
 │ tvOS: viewer only            │ ◀──APNs / sync─── │   smart collections · Trips · Memories       │
 └──────────────────────────────┘                   └──────────────────────────────────────────────┘
```

### 2.1 Server ML stack on the A4500
| Service | Model (license) | Approx. VRAM | Runs |
|---|---|---|---|
| immich-ml · search | **ViT-SO400M-16-SigLIP2-384__webli** (Apache-2.0), 1152-d — already in the fork's model list; fallback ViT-L-16-SigLIP2-384 | ~2–2.5 GB fp16 | resident (queries need the text encoder) |
| immich-ml · faces | bake-off winner: antelopev2 / buffalo_l (InsightFace, non-commercial) or AdaFace IR-101 (MIT) | ~0.3–0.6 GB | resident |
| immich-ml · OCR | PP-OCRv5 (Apache-2.0) — already supported | ~0.3 GB | resident |
| **heirloom-vlm** (new) | Qwen-VL 7–8B instruct, 4-bit AWQ (Apache-2.0; exact version picked in WP0 — Qwen3-VL-8B if available, else Qwen2.5-VL-7B) served by vLLM with JSON-schema guided output | ~6–9 GB incl. KV cache (`gpu_memory_utilization` capped) | nightly batch + on new uploads; unloads when idle |
| **heirloom-av** (new) | faster-whisper large-v3-turbo (MIT); PANNs/BEATs AudioSet tagger (MIT) | ~2 GB | videos only, batch |
| aesthetics | small MLP head over the SigLIP2 vector (no extra image pass); head choice/licence checked in WP0 | ~0 | with search job |
| CPU | perceptual hash, zxing-cpp QR (Apache-2.0), EXIF/QuickTime media-type rules | — | on metadata extraction |
All fp16 on Ampere (no FP8). Peak ≈ 13–15 GB with everything loaded, leaving room for NVENC
transcoding. Numbers are estimates — WP0 measures them on the real card.

### 2.2 One VLM pass per photo (structured output)
```json
{ "caption": "Family selfie in front of the USS Alabama battleship on a sunny day",
  "kind": "photo | screenshot | document | receipt | id_document | handwriting | illustration | whiteboard | menu | other",
  "is_utility": false,
  "tags": ["ship","family","selfie","outdoors","sunny"],
  "event": "none | birthday | wedding | holiday | graduation | party | …",
  "people_count": 3 }
```
Enum-constrained decoding (vLLM guided JSON), so outputs are always valid. Videos: one pass on the
poster frame + Whisper transcript. Estimated 1–3 images/s batched → a 50k-photo backlog is roughly
5–14 hours once; new uploads take seconds. The caption is stored and indexed for search alongside
the vector (so "the battleship photo" finds it by words too).

### 2.3 Division of labour
| Work | Where |
|---|---|
| Search vector, faces, OCR, VLM description, aesthetics, pHash, QR, video speech/sounds | Server GPU/CPU |
| Library facts (media subtypes, bursts, favourite/hidden, source), Apple Photos edits | Device, sent with upload |
| Optional Apple signals (`CalculateImageAestheticsScoresRequest`, `RecognizeDocumentsRequest`, lens smudge) | Device at upload, stored with `source = apple` |
| People clustering, duplicate groups, smart collections, Trips, Memories, titles | Server |
| Editing, rendering, Clean Up | Device (§13); Extend can use the server GPU |

---

## 3. Routing & "processed by"

- Setting `analysis.processor` per origin (iPhone uploads / Mac uploads / everything else), values
  `server` | `ios` | `macos`, **default `server` for all**. Only `server` is implemented in v1; the
  device values stay in the schema so an offload mode can be added later without a migration.
- `asset.analysisProcessor` / `analysisDeviceId` record the primary processor; `analysis_run`
  records every capability separately (e.g. `vlm` by server, `apple-aesthetics` by iPhone X).
- **Light device job queue** (kept for editing and Apple-signal backfill, not for core AI):
  `GET /analysis/work?capabilities=render,apple-signals` returns jobs for this device with a
  30-min lease; used for batch Copy/Paste Edits renders (§13.4) and, if enabled, computing Apple
  signals for older assets the device still has locally.
- **Deferred — device offload mode:** full device analysis (Core ML conversions of the server
  models, parity harness, BG processing, Mac agent) — only if a future install has no GPU.

---

## 4. Server data model changes (kysely schema in `server/src/schema/tables/`)

```
enum analysis_processor  = 'server' | 'ios' | 'macos'

asset (+)
  analysisProcessor     analysis_processor NULL   -- owner's "which device processed its AI"
  analysisDeviceId      text NULL
  analysisCompletedAt   timestamptz NULL
  appleMetadata         jsonb NULL                -- mediaSubtypes, burstIdentifier, representsBurst,
                                                  -- sourceType, playbackStyle, isFavorite, hidden,
                                                  -- hasAdjustments, captureDeviceModel

analysis_device   id, userId, platform ('ios'|'macos'), name, model, osVersion, appVersion,
                  capabilities jsonb, lastSeenAt
analysis_run      assetId, capability ('clip'|'face'|'ocr'|'vlm'|'aesthetics'|'phash'|'barcode'|
                  'speech'|'sound'|'apple-aesthetics'|'apple-document'|'render'),
                  processor, deviceId, modelName, modelVersion, processedAt, durationMs,
                  status, error                      PK(assetId, capability)
analysis_lease    jobId PK, assetId, deviceId, capability, expiresAt

asset_description assetId PK, caption text, kind text, isUtility bool, event text, peopleCount int,
                  modelName, modelVersion           -- VLM output; caption GIN/trigram indexed
asset_label       assetId, label, score real, source ('vlm'|'clip-zeroshot'|'sound'|'apple'),
                  PK(assetId, label, source)
asset_quality     assetId PK, aestheticScore real, appleAestheticScore real NULL,
                  appleIsUtility bool NULL, lensSmudge real NULL, faceQualityMax real
asset_document    assetId PK, barcodes jsonb, appleParagraphs int NULL, appleTables int NULL
asset_phash       assetId PK, hash bit(64)
asset_transcript  assetId PK, language, text, segments jsonb, modelName

trip / trip_asset (as before; titleSource 'template' | 'vlm' | 'user')

existing, reused:
  smart_search (dimension becomes 1152 with SigLIP2 SO400M — existing re-index path)
  asset_face / face_search, person (clustering unchanged)
  asset_ocr, memory / memory_asset, asset.duplicateId, asset_job_status (+ vlm/speech timestamps)
```
Access control: all endpoints follow the fork's S2 rules (a device only submits metadata/signals
for assets its user may edit).

### 4.1 API (OpenAPI → regenerates `ImmichAPI` Swift client)
| Endpoint | Purpose |
|---|---|
| upload DTO (+ `appleMetadata`) | Library facts ride on the existing upload call; `PUT /assets/{id}/apple-metadata` for later changes (favourite/hidden/edits) |
| `POST /analysis/devices` | Register device + capabilities |
| `POST /analysis/signals` | Batch Apple signals (optional) |
| `GET /analysis/work` / `POST /analysis/work/{id}` | Render + apple-signal jobs with leases |
| `GET /analysis/stats` | Progress per capability and processor |
| `POST /analysis/reprocess` | Re-queue by capability / model / processor |
Server jobs added: `AssetDescribe` (VLM), `VideoTranscribe`, `VideoSoundTag`, `AssetPHash`,
`SmartCollectionEvaluate`, `TripDetect`, `MemoryGenerate`, `TitleGenerate`.

---

## 5. Smart collections — signal → rule

Membership computed on the server. Sources: **AM** = Apple metadata from upload · **EXIF** =
server metadata · **VLM** = server vision-language pass · **S** = server state/events ·
**A** = optional Apple signal (extra evidence, never required).

### Utilities
| Collection | Rule | Sources |
|---|---|---|
| Favorites / Hidden / Recently Deleted | existing favourite, locked/hidden visibility, trash | S + AM |
| Duplicates | `duplicateId` (SigLIP2 distance) + pHash Hamming ≤ 6 for exact re-encodes | S |
| Captured by Me | camera EXIF make/model matches one of the user's registered devices, or AM `sourceType = userLibrary` with camera EXIF | EXIF + AM |
| Identity Documents | VLM `kind = id_document` (+ MRZ `<<<` in OCR) | VLM + OCR |
| Receipts | VLM `kind = receipt` (+ totals/currency lines in OCR) | VLM + OCR (+A tables) |
| Handwriting | VLM `kind = handwriting` | VLM |
| Illustrations | VLM `kind = illustration` and no camera EXIF | VLM + EXIF |
| QR Codes | zxing finds a QR code | CPU |
| Documents | `kind in (document, receipt, id_document, whiteboard, menu)` | VLM (+A) |
| Recently Saved | no camera EXIF / AM source says saved from another app, added in last 30 days | AM + EXIF |
| Recently Viewed / Edited / Shared | new `asset_event` log — not AI | S |
| Imports | upload sessions from web / CLI / external library | S |
| Map | GPS | EXIF |

### Media Types (AM is authoritative for app uploads; EXIF/QuickTime fallback for everything else)
| Collection | Apple metadata | EXIF / file fallback |
|---|---|---|
| Videos | mediaType video | mime |
| Selfies | SelfPortraits / front camera | lens model contains "front" |
| Live Photos | `.photoLive` | `livePhotoVideoId` |
| Portrait | `.photoDepthEffect` | depth / portrait-matte aux data, Apple maker note |
| Slo-mo | `.videoHighFrameRate` | fps ≥ 120 |
| Cinematic | `.videoCinematic` | Apple QuickTime metadata (key confirmed in WP0) |
| Bursts | `burstIdentifier` | maker note BurstUUID |
| Screenshots | `.photoScreenshot` | no camera EXIF + screen size + "Screenshot" UserComment; VLM `kind = screenshot` |
| Screen Recordings | subtype (verify) | no camera + screen-size video |
| RAW | resource type | extension / mime |
| Panoramas, Time-lapse, Spatial, Long Exposure | subtypes | aspect ratio / metadata |

---

## 6. People (faces)

1. Server detects + embeds faces with the WP0 bake-off winner (buffalo_l vs antelopev2 vs AdaFace
   IR-101) on the owner's own labelled set (~20 people incl. a child at several ages).
2. Existing incremental clustering assigns people; tune max distance / min faces in WP0 with the
   same labelled set (moves quality as much as the model does).
3. Face quality score (detector confidence × size × blur) picks each person's cover.
4. Naming in the apps via Contacts picker; contact birthday feeds birthday memories.
5. Known weakness for every model: babies/young children change fast — expect manual merges.

## 7. Trips & Memories

### Trips (server `TripDetect`, nightly + after ingest bursts)
1. Home = user setting, else the most frequent night-time GPS cluster over 12 months (DBSCAN 1 km).
2. Away when > 80 km from home; segment contiguous away runs; merge gaps ≤ 36 h / home visits
   < 12 h; require ≥ 1 night or ≥ 20 assets.
3. Include non-GPS assets from the user's devices inside the window.
4. Template title from reverse-geocoded regions ("Alabama & Florida"), subtitle = date range
   ("APR 6–19, 2026").
5. Cover = best aesthetic, non-utility photo, faces preferred.
6. `TitleGenerate`: the VLM sees the cover + 6 top photos + places + dates + named people and
   returns `{title, subtitle}`; template kept if it fails. User edits always win.
UI: Trips with All / year segments in iOS & macOS Collections (as in the screenshot).

### Memories (extend `memory` types; server `MemoryGenerate`)
| Type | Selection |
|---|---|
| On this day (exists) | curate: drop utility/screenshots/docs, collapse duplicates + bursts, rank by aesthetics |
| Trip | trips ≥ 1 year old, or just finished |
| Person / Together | person or pair with many good photos in a period |
| Pets | VLM tags cat/dog over time |
| Year / season in review | top aesthetics per month, diversity via vector clustering |
| Celebrations | VLM `event` + sound tags (singing, applause, fireworks) |
| Place | a recurring non-home place outside trips |
Titles via the same `TitleGenerate` job.

---

## 8. Device work (new `PhotosCore/Sources/AppleSignals`, small)

- **Upload path (`Upload` package):** attach `appleMetadata` from the `PHAsset` already in hand;
  watch `PHPersistentChangeToken` for favourite/hidden/edit changes and send
  `PUT /assets/{id}/apple-metadata`; upload Apple Photos edit renders (§13.4).
- **Optional Apple signals at upload** (setting, default on for new uploads only): one
  `ImageRequestHandler` running `CalculateImageAestheticsScoresRequest` +
  `RecognizeDocumentsRequest` (+ `DetectLensSmudgeRequest`) on a ~1024 px image — tens of ms,
  no custom models, no backlog processing unless the owner enables it (then via the light job
  queue while charging).
- **Editing** — §13.
- **tvOS:** viewer only.
- **Deferred:** full device analysis (the previous WP2–WP4 design) — kept in the git history of this
  file for a future GPU-less install.

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

**Instead:** server = source of truth; device jobs through server leases (§3);
change notification via APNs sent by the Heirloom server (own `.p8` key) + existing sync/WebSocket.
**Allowed, optional:** `NSUbiquitousKeyValueStore` for a handful of per-user UI preferences.

Background *upload* (`PHBackgroundResourceUploadJobExtension`) is the right future transport but
needs a static `BackgroundUploadURLBase` — track as a separate spike (relay domain vs. wait for the
Immich community pattern); not part of this program.

---

## 10. Work packages

| WP | Scope | Owner tier | Depends |
|---|---|---|---|
| **WP0 Server model bake-off & capacity** | (a) search: SigLIP2 B/16 vs L/16-384 vs SO400M-16-384 on ~50 of the owner's real queries, recall + query latency; (b) faces: buffalo_l vs antelopev2 vs AdaFace on a labelled set + clustering thresholds; (c) VLM: pick the model, accuracy of `kind`/`is_utility`/`event` on 300 labelled assets, images/s; (d) co-residency: all services + NVENC under load on the A4500; (e) duplicate threshold for the new vectors; (f) confirm Cinematic / screen-recording metadata keys | Opus designs the eval + judges; implementer builds the harness | — |
| **WP1 Server schema + API** | migrations (§4), analysis module (devices, signals, light job queue, stats, reprocess, processed-by), upload DTO `appleMetadata`, S2 checks, OpenAPI regen | implementer | WP0 model choice |
| **WP2 Server ML extensions** | `heirloom-vlm` (vLLM) + `AssetDescribe`; `heirloom-av` (Whisper, sound tags); aesthetics head; pHash; zxing QR; caption + transcript search; switch search model + re-index; Docker Compose/GPU wiring on LXC 403 | implementer; Opus reviews prompts/schema | WP0, WP1 |
| **WP3 Apple metadata + Apple Photos edits** | upload `appleMetadata`, change-token sync of favourite/hidden/edits, edit-render upload | implementer | WP1 |
| **WP4 Apple signals (optional)** | at-upload aesthetics / document structure / lens smudge; opt-in backfill job | implementer | WP1 |
| **WP5 Smart collections** | server rules + endpoints, `asset_event` log, iOS/macOS Utilities & Media Types wiring | implementer; Opus reviews rules | WP2, WP3 |
| **WP6 Duplicates review UI** | groups, keep best (aesthetics), merge metadata, trash others (+ optional delete from iPhone via `PHAssetChangeRequest`) | implementer | WP5 |
| **WP7 People** | model + threshold from WP0, Contacts naming, cover by quality | implementer | WP0, WP2 |
| **WP8 Trips + Memories** | TripDetect, memory types + curation, TitleGenerate, Trips UI | Opus designs heuristics; implementer | WP5, WP7 |
| **WP10 Settings & admin** | processor setting per origin (server-only active), Apple-signals toggle, per-capability stats, reprocess, "processed by" in the asset info panel | implementer | WP1 |
| **WP11 Verification** | server unit/e2e, GPU load test, device tests on real hardware | verifier | each |
| *Deferred* | Device offload mode (Core ML conversions, parity harness, BG analysis, Mac agent) | — | GPU-less install |

Order: WP0 → WP1 → (WP2 ∥ WP3 ∥ WP10) → WP4 → WP5 → WP7 → WP6 → WP8. Editing E0–E8 (§13) runs in
parallel; it only shares WP1's light job queue.

---

## 11. Decisions for the owner (recommended default in **bold**)

1. Where AI runs: **server GPU for all analysis; devices send library facts + Apple Photos edits**
   | device-first as originally planned.
2. Optional Apple signals at upload (aesthetics, document structure): **on for new uploads, no
   backfill** | off | on with backfill while charging.
3. Face model: **decide by WP0 bake-off** (buffalo_l / antelopev2 are non-commercial — fine for a
   personal homelab; AdaFace is MIT).
4. Vision-language model: **Qwen-VL 7–8B 4-bit via vLLM** (Apache-2.0), exact version from WP0 |
   skip VLM and rely on zero-shot search-model labels (weaker documents/receipts/titles).
5. Extras: video speech transcripts **on** (server Whisper), calendar titles via EventKit off.
6. Trip threshold: **80 km from home, ≥ 1 night** — or set Home explicitly.
7. Search model: **ViT-SO400M-16-SigLIP2-384** if WP0 shows query latency is fine, else
   ViT-L-16-SigLIP2-384. One-time full re-index.
8. Where an edited version lives: **a rendition file on the same asset** | today's "rendered copy
   uploaded as a new asset".
9. Import edits you make in Apple Photos into Heirloom (render only): **yes**.
10. Write Heirloom edits back into Apple Photos for iPhone photos: **off by default, per-edit
    "Also save to Photos"**.
11. Clean Up engine: **LaMa (Apache-2.0) on device via Core ML** (~200 MB download).

## 12. Risks
- GPU contention: VLM backlog + transcoding + search queries on one 20 GB card. Mitigate: VLM and
  Whisper as batch services with capped memory, idle unload, run the backlog overnight; search
  models stay resident.
- VLM hallucinated document types → wrong Receipts/IDs. Mitigate: enum-constrained output, OCR
  cross-checks (MRZ, totals), WP0 accuracy gate, user "not a receipt" correction feeds a label.
- Re-index to 1152-d vectors takes the search and duplicate features down briefly — schedule it.
- Children's faces cluster poorly on every model — expect manual merges.
- The server becomes a single point of AI failure; the deferred device-offload mode is the escape hatch.

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
| Extend (outpainting) | Too heavy for iPhone; run on the server GPU (an openly licensed diffusion inpainting model, licence checked first) as an async "Extend" job whose result is stored as a patch | P3 |

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
- Batch: Copy/Paste Edits across many assets queues **render jobs** on the light device job queue
  (§3, capability `render`), so the Mac agent renders a 200-photo paste in the background.

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
