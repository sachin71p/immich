# Heirloom Server AI — Implementation Plan (server, DB, admin + user web UI)

Status: READY TO EXECUTE · 2026-09-18 · Author: Opus (planning session)
Parent design (read §0, §2–§7, §10–§12 only; do NOT edit it): `.claude/plans/heirloom-on-device-ai/PLAN.md`
Conventions recon: [recon-conventions.md](recon-conventions.md) — some points are unverified; S0 confirms them.
Repo: `/Users/spatel/workspace/github/projects/immich` (Immich fork "Heirloom"). Base branch:
`feat/shared-libraries`. Work branch: `feat/server-ai` (create from base).

---

## 0. Goal & scope

Server-first AI on the homelab GPU (NVIDIA RTX A4500, 20 GB, Ampere — no FP8), plus the admin and
user web UI to configure it and see its results.

**In scope**
1. DB schema + migrations for analysis results, processed-by tracking, Apple metadata, trips,
   events, new memory types.
2. New analysis pipelines as server jobs:
   - **Describe** — a vision-language model (VLM) behind an OpenAI-compatible API (vLLM) writes a
     caption, kind (receipt / ID / handwriting…), utility flag, tags, event and quality per asset.
   - **Fingerprint** — CPU: perceptual hash, QR/barcodes, sharpness.
   - **Transcribe** — video speech via an OpenAI-compatible transcription API.
   - **Sound tags** — optional, P2.
3. Endpoints for the native apps: Apple library metadata, device registration, optional Apple
   signals, light device job queue.
4. Smart collections (iOS Photos Utilities + Media Types), Trips, new Memory types, titles by the VLM.
5. Admin web UI: model selection, new ML sections, routing, trips/memories settings, new queue
   cards, an Analysis status page.
6. User web UI:
   - Collections page (Utilities + Media Types with counts)
   - Trips pages
   - AI section in the asset detail panel
   - caption/tag search filters
   - new memory types in the memory lane
7. Compose override for the new GPU services. **Files only — no deployment.**

**Out of scope**
- Native iOS/macOS client changes. The OpenAPI spec is regenerated so the Swift client can pick
  it up later.
- Editing (§13 of the parent plan).
- Device-side analysis.
- Deploying to the homelab. Deployment is gated by the existing S2/S10 deploy gates.
- The model bake-off (WP0 of the parent plan) — this plan makes models *selectable*; the owner
  picks them.

## 1. Ground rules for every agent

- **Match surrounding code:** naming, comment density, file layout, the `// fork:` marker comments
  used elsewhere in the fork, i18n keys in `i18n/en.json` only.
- **Generated artifacts are regenerated, never hand-edited:**
  - migrations: `pnpm run migrations:generate` in `server/`
  - OpenAPI spec + TS SDK: the repo's `open-api` sync target / `pnpm run api:sync`
  - SQL query docs: `make sql` or the equivalent script
  S0 confirms the exact commands.
- **Hotspot files** are edited only by the WP that owns them in the table below:
  `server/src/enum.ts`, `server/src/dtos/config.dto.ts` (and the defaults file),
  `server/src/schema/index.ts`, `i18n/en.json`, `open-api/*`, `web/src/lib/components/shared-components/side-bar/*`.
  All enums, queues and config keys for the whole plan are added up front in S1/S2, so later WPs
  mostly add new files. Later WPs may append **i18n keys** only while no other web WP runs in
  parallel.
- **Access control:** every new endpoint uses the fork's `requireAccess` / `checkAccess`
  (`server/src/utils/access.ts`) with an appropriate Permission. Shared-library assets follow the
  same rules as other asset reads/edits. Admin-only endpoints use the existing admin guard.
- **Tests with every WP:**
  - unit specs (`newTestService` pattern)
  - medium tests for new repositories/SQL
  - web component tests where the surrounding folder has them
- **Definition of done for every WP:** server `pnpm run check`/lint/unit/medium pass (web too if
  touched); generated files are in sync; one commit per WP on `feat/server-ai` with message
  `feat(server-ai): <WP id> <summary>`.
- **Never** push, open PRs, deploy, touch the homelab, or edit the parent plan without the owner's
  explicit OK.

---

## 2. Contracts (source of truth for all WPs)

### 2.1 Enums (S1 adds all of them)
```
AnalysisProcessor   = 'server' | 'ios' | 'macos'
AnalysisCapability  = 'clip' | 'face' | 'ocr' | 'describe' | 'fingerprint' | 'transcribe'
                    | 'sound' | 'apple-signals' | 'render'
AssetKind           = 'photo' | 'screenshot' | 'document' | 'receipt' | 'id_document'
                    | 'handwriting' | 'illustration' | 'whiteboard' | 'menu' | 'other'
AssetEventKind      = 'viewed' | 'edited' | 'shared'
AnalysisJobStatus   = 'pending' | 'leased' | 'done' | 'failed'
MemoryType (+)      = 'trip' | 'person' | 'pets' | 'year_review' | 'celebration' | 'place'
QueueName (+)       = AssetDescribe, AssetFingerprint, VideoTranscribe, SoundTagging, Trips
JobName (+)         = AssetDescribeQueueAll, AssetDescribe,
                      AssetFingerprintQueueAll, AssetFingerprint,
                      VideoTranscribeQueueAll, VideoTranscribe,
                      SoundTaggingQueueAll, SoundTagging,
                      TripDetectQueueAll (per user), TripDetect, TripTitleGenerate,
                      AnalysisLeaseCleanup
```
Queue display names/descriptions get i18n keys (S2).

### 2.2 Schema (S1)
```
asset (+)
  analysisProcessor     analysis_processor NULL
  analysisDeviceId      uuid NULL → analysis_device.id ON DELETE SET NULL
  analysisCompletedAt   timestamptz NULL
  appleMetadata         jsonb NULL
      { mediaSubtypes: string[], burstIdentifier?, representsBurst?, sourceType?,
        playbackStyle?, isFavorite?, isHidden?, hasAdjustments?, captureDeviceModel?,
        localIdentifier?, cloudIdentifier? }

asset_job_status (+)  describedAt, fingerprintedAt, transcribedAt, soundTaggedAt  timestamptz NULL

analysis_device   id uuid PK, userId FK, platform ('ios'|'macos'), name, model, osVersion,
                  appVersion, capabilities jsonb, createdAt, lastSeenAt
analysis_run      assetId FK, capability analysis_capability, processor, deviceId NULL,
                  modelName, modelVersion NULL, status ('done'|'failed'), error NULL,
                  durationMs NULL, processedAt           PK(assetId, capability)
analysis_job      id uuid PK, deviceId FK, assetId FK, capability, payload jsonb,
                  status analysis_job_status, leaseExpiresAt NULL, attempts int,
                  result jsonb NULL, createdAt, updatedAt   idx(deviceId,status)

asset_description assetId PK FK, caption text, kind asset_kind, isUtility bool, event text NULL,
                  peopleCount smallint NULL, quality smallint NULL (1–10), hasText bool,
                  raw jsonb, modelName, promptVersion smallint, updatedAt
                  GIN trigram index on caption (pg_trgm — check it's enabled; if not, add it
                  in the migration)
asset_label       assetId FK, label text, score real, source ('describe'|'sound'|'apple'),
                  PK(assetId, source, label); idx(label)
asset_quality     assetId PK FK, sharpness real NULL, vlmQuality smallint NULL,
                  appleAesthetic real NULL, appleIsUtility bool NULL, lensSmudge real NULL
asset_fingerprint assetId PK FK, dhash bigint, barcodes jsonb   -- [{format, text}]
asset_transcript  assetId PK FK, language text, text text, segments jsonb, modelName, updatedAt
                  GIN trigram index on text
asset_event       id bigserial PK, assetId FK, userId FK, kind asset_event_kind, createdAt
                  idx(userId, kind, createdAt desc)

trip              id uuid PK, ownerId FK, title text, subtitle text, titleSource
                  ('template'|'vlm'|'user'), startAt, endAt, places jsonb
                  [{country, state, city}], centroid (lat/lng reals), coverAssetId NULL,
                  isHidden bool, createdAt, updatedAt, updateId (sync pattern like other tables)
trip_asset        tripId FK, assetId FK, PK(tripId, assetId)

user preference (existing user metadata/preferences mechanism)
  trips.homeLatitude / homeLongitude NULL (inferred when null)
```
All FKs to asset cascade on delete. Add the `updatedAt` / `updateId` triggers the same way the
existing tables do. Anything the native apps will sync later needs an `updateId`: asset_description,
asset_label, trip, trip_asset.

### 2.3 System config (S2)

Extend the existing `machineLearning` block and add new top-level blocks. Keep existing keys and
defaults unchanged.
```
machineLearning.describe:    { enabled: false, url: 'http://heirloom-vlm:8000/v1', apiKey: '',
                               modelName: 'Qwen/Qwen2.5-VL-7B-Instruct-AWQ', maxImageSize: 1024,
                               timeoutSeconds: 120, describeVideos: true, promptVersion: 1 }
machineLearning.transcribe:  { enabled: false, url: 'http://heirloom-speech:8000/v1', apiKey: '',
                               modelName: 'deepdml/faster-whisper-large-v3-turbo-ct2',
                               language: '', maxDurationMinutes: 30 }
machineLearning.soundTagging:{ enabled: false, modelName: 'panns-cnn14', minScore: 0.3 }   -- P2, S6b
machineLearning.fingerprint: { enabled: true, duplicateHammingDistance: 6, barcodes: true }
analysis:                    { processor: { ios: 'server', macos: 'server', other: 'server' },
                               acceptAppleSignals: true, deviceJobLeaseMinutes: 30 }
smartCollections:            { enabled: true }
trips:                       { enabled: true, awayKm: 80, minNights: 1, minAssets: 20,
                               mergeGapHours: 36, generateTitles: true }
memories (+):                { types: { trip, person, pets, yearReview, celebration, place: true } }
job (+):                     concurrency for the 5 new queues
                             (describe 2, fingerprint 4, transcribe 1, soundTagging 1, trips 1)
```
- `analysis.processor` accepts only `'server'` in v1. The other values validate but are rejected
  with a clear message; the admin UI shows them disabled with "requires device offload (not
  available yet)".
- Changing `machineLearning.clip.modelName` must keep the existing dimension-resize /
  embedding-clear behaviour (SigLIP2 SO400M = 1152-d). Verify it works for a 512 → 1152 change in
  a medium test.

### 2.4 Describe (VLM) contract (S4)

- **Transport.** `POST {url}/chat/completions`, OpenAI-compatible; works with vLLM, Ollama and
  llama.cpp.
- **Request.**
  - Input image: the asset's **preview** file, resized to `maxImageSize` long edge with `sharp`,
    sent as a JPEG data URL. Videos use their preview/poster frame when `describeVideos`.
  - Output format: `response_format: { type: "json_schema", json_schema: { name: "asset_description", strict: true, schema } }`
  - `temperature: 0`
- **System prompt v1** (store as a versioned constant; bump `promptVersion` when it changes):
  > You catalogue a family photo library. Describe the image factually. Never guess names of people.
  > Choose `kind` for what the image is (photo = a normal camera photo of a scene or people).
  > `is_utility` is true for images kept for information rather than memories (screenshots,
  > documents, receipts, whiteboards, menus, parking signs, product labels).
  > `quality` rates the photo as a keepsake from 1 (unusable: blurred, accidental) to 10 (excellent).
  > `tags`: 3–12 lowercase English nouns or short noun phrases for things, places, activities.
  > `event`: the occasion if clearly visible, else "none".
- **JSON schema.**
  ```
  caption: string ≤ 200 chars
  kind: AssetKind
  is_utility: boolean
  quality: integer 1–10
  tags: string[] (maxItems 12)
  event: "none" | "birthday" | "wedding" | "holiday" | "graduation" | "party" | "concert"
       | "sports" | "religious" | "festival" | "trip" | "other"
  people_count: integer ≥ 0
  has_text: boolean
  ```
- **Storing results.**
  - Validate with the DTO/validator style the repo uses.
  - Upsert `asset_description` (raw JSON kept) and `asset_label` (source `describe`, score 1.0);
    `asset_quality.vlmQuality` = quality.
  - `analysis_run(capability='describe', processor='server', modelName)`; set
    `asset_job_status.describedAt`.
  - Set `asset.analysisProcessor = 'server'` and `analysisCompletedAt` once clip + face + describe
    are all done (helper shared by all pipelines).
- **Scheduling.**
  - Enqueue after thumbnail generation (same hook the smart-search job uses).
  - `QueueAll` supports force/missing like the other queues.
  - Skip trashed/offline assets and assets without a preview.
- **Failure handling.** Record a failed `analysis_run` with the error. Retry with the queue's normal
  backoff. HTTP 400 from a malformed model output → mark failed, no retry storm.
- **Test connection.** Admin endpoint `POST /admin/analysis/describe/test` sends a bundled 64×64
  test image and returns the parsed result or the error. The settings UI uses it.
- **Titles.** `generateTitle(images ≤ 6, context)` → `{ title ≤ 40 chars, subtitle ≤ 60 chars }`,
  same endpoint, separate prompt constant.

### 2.5 Fingerprint contract (S5, CPU in the microservices worker)
- **dHash:** 64-bit difference hash from the preview (grayscale 9×8 via sharp) → `asset_fingerprint.dhash`.
- **Barcodes:** `zxing-wasm` (MIT, zxing-cpp) on the preview, then a retry at full resolution if the
  image has text/document kind → `barcodes`.
- **Sharpness:** variance of the Laplacian on a 512 px grayscale → `asset_quality.sharpness`.
- **Duplicates:** after fingerprinting, assets owned by the same user with Hamming ≤
  `duplicateHammingDistance` join or create the same `duplicateId` group. Reuse the existing
  duplicate service's grouping helper so SigLIP2-distance and pHash groups merge rather than
  compete. Medium test: two re-encodes of one image end up in one group.

### 2.6 Transcribe contract (S6)
- **Scope:** videos only, with an audio stream and duration ≤ `maxDurationMinutes`.
- **Audio extraction:** ffmpeg (already in the server image) → 16 kHz mono WAV/FLAC temp file.
- **Request:** `POST {url}/audio/transcriptions` (OpenAI-compatible; `speaches` / faster-whisper
  server) with `response_format=verbose_json`, `model`, and optional `language`.
- **Store:** `asset_transcript`, `analysis_run`, `transcribedAt`. Empty/no-speech result → store
  empty text (so it is not retried).
- **S6b (P2, optional):** a sound-tagging task in `machine-learning/` (new ModelTask using a PANNs
  CNN14 ONNX model) → `asset_label` with source `sound`. Only do it after S6 passes; can be dropped.

### 2.7 Device-facing API (S3)
| Method & path | Body / result | Notes |
|---|---|---|
| upload DTO (+ optional `appleMetadata` JSON field) | — | multipart field, validated, stored on `asset.appleMetadata` |
| `PUT /assets/:id/apple-metadata` | `AppleMetadataDto` | owner/editor access |
| `POST /analysis/devices` | `{platform, name, model, osVersion, appVersion, capabilities}` → `{id}` | idempotent per (user, name, platform); updates `lastSeenAt` |
| `POST /analysis/signals` | `[{assetId, deviceId, appleAesthetic?, appleIsUtility?, lensSmudge?, documentParagraphs?, documentTables?}]` ≤ 100 | writes `asset_quality` / `asset_label(source apple)`, `analysis_run(capability 'apple-signals', processor from device platform)`; rejected when `acceptAppleSignals=false` |
| `GET /analysis/jobs?deviceId&capabilities&limit` | leases pending `analysis_job` rows (render / apple-signals) | lease = `deviceJobLeaseMinutes`; `AnalysisLeaseCleanup` job returns expired leases |
| `POST /analysis/jobs/:id` | `{status: 'done'|'failed', result?, error?}` | |
| `GET /analysis/stats` (admin) | per capability: done / failed / missing, by processor, by model | powers the admin Analysis page |
| `POST /analysis/reprocess` (admin) | `{capability, scope: 'all'|'failed'|'model', modelName?}` | queues jobs |
| `GET /assets/:id/analysis` | description, labels, quality, fingerprint barcodes, transcript (truncated), appleMetadata, analysis_run rows (+ device name) | the detail panel uses it |
| `POST /assets/:id/events` | `{kind}` | powers Recently Viewed / Edited / Shared; the web viewer calls `viewed` (debounced, once per asset per session); edit/share code paths call the service directly |

### 2.8 Smart collections (S7)
- **Registry.** Code-defined collection definitions. Each has `id`, `section` (`utilities` |
  `mediaTypes`), i18n key, icon (mdi), and a Kysely predicate builder over asset + joins.
  **Evaluated at query time**: no membership table, always fresh.
- **Endpoints.**
  - `GET /collections` → `[{id, section, count}]`. Counts per user are cached for 5 minutes and
    invalidated on asset upload/delete.
  - `GET /collections/:id/assets?cursor&size` → paged assets, newest first, same DTO as search
    results.
  - Must respect the visibility rules the timeline uses (archived/hidden/locked/trash) and include
    shared-library assets the user can see.
- **Utilities.**

  | Collection | Rule |
  |---|---|
  | Favorites | isFavorite |
  | Hidden | hidden/locked visibility (link to the existing locked view if it requires PIN) |
  | Recently Deleted | trash (link to the existing trash) |
  | Duplicates | assets with a duplicateId shared by ≥ 2 visible assets (link to the existing duplicates utility) |
  | Captured by Me | EXIF make/model ∈ models of the user's `analysis_device` rows, or `appleMetadata.sourceType = 'userLibrary'` with camera EXIF |
  | Identity Documents | kind = id_document |
  | Receipts | kind = receipt |
  | Handwriting | kind = handwriting |
  | Illustrations | kind = illustration and no camera make |
  | QR Codes | barcodes contains format QR_CODE |
  | Recently Saved | no camera make and createdAt within 30 days (or appleMetadata source says "saved"), not a screenshot |
  | Recently Viewed / Edited / Shared | `asset_event` (edited also = has asset_edit or an edit recipe) within 30 days |
  | Documents | kind ∈ {document, receipt, id_document, whiteboard, menu} |
  | Imports | uploads whose `deviceId` is WEB/CLI or from an external library, last 30 days |
  | Map | has GPS (link to the existing map) |

- **Media Types.** `appleMetadata.mediaSubtypes` when present, else the EXIF/QuickTime fallback.
  S0 verifies which EXIF fields the fork stores.

  | Collection | Rule |
  |---|---|
  | Videos | type video |
  | Selfies | subtype selfie or lensModel ILIKE '%front%' |
  | Live Photos | livePhotoVideoId not null |
  | Portrait | photoDepthEffect or Apple portrait EXIF marker |
  | Slo-mo | videoHighFrameRate or fps ≥ 100 |
  | Cinematic | videoCinematic |
  | Bursts | burstIdentifier present (grouped count = number of bursts) |
  | Screenshots | photoScreenshot or kind = screenshot or (no camera make + PNG + UserComment 'Screenshot') |
  | Screen Recordings | subtype or (video + no camera make + screen-size dims) |
  | RAW | RAW mime/extension |
  | Panoramas | photoPanorama or aspect ≥ 2.5 with camera make |
  | Time-lapse | videoTimelapse |
  | Spatial | spatialMedia |
  | Long Exposure | playbackStyle / subtype |

  A collection with count 0 is still returned; the UI hides empty ones except the always-visible
  set (Favorites, Hidden, Recently Deleted, Duplicates).

### 2.9 Trips & Memories (S8)
- **TripDetect** (per user; nightly via the existing nightly-tasks hook, plus a debounced run 10
  min after upload bursts):
  1. **Home** = user preference, else the most frequent ~1 km grid cell among photos taken between
     20:00 and 07:00 local time over the last 24 months.
  2. **Away** = GPS assets further than `awayKm` from home. Group consecutive away assets into
     trips, split when a home-located asset appears for more than 12 h or the gap exceeds
     `mergeGapHours`. Keep a trip if it spans at least `minNights` nights or has at least
     `minAssets` assets.
  3. **Membership** = all of the user's assets (GPS or not) captured inside the trip's time window
     by the same devices.
  4. **Places** come from the existing reverse-geocoded EXIF (country / state / city). Template
     title:
     - one state or country → that name;
     - two → "A & B";
     - more → the country name, or "A, B & more".
     Subtitle = the date range in the user's locale, e.g. "APR 6–19, 2026".
  5. **Cover** = the highest vlmQuality non-utility photo, preferring ones with faces.
  6. **Idempotent rebuilds:** match existing trips by overlap ≥ 50% and keep their id, title and
     `titleSource = 'user'` edits.
  7. **Titles:** `TripTitleGenerate` (when `trips.generateTitles` and describe is enabled) sends the
     cover + 5 top photos + places + dates + named people to `generateTitle`. Replace only
     `titleSource = 'template'` titles.
- **Trips API.**
  - `GET /trips?year` → list with cover + counts.
  - `GET /trips/:id` → the trip.
  - `GET /trips/:id/assets` → paged assets.
  - `PATCH /trips/:id {title?, subtitle?, isHidden?}` → sets `titleSource='user'`.
  - `POST /trips/rebuild` → the current user.
  - `GET /trips/years` → segment control values.
- **Memories.** Extend the existing memory generation for the new MemoryTypes, each toggleable in
  config. The `memory.data` JSON carries the title/subtitle and a `sourceId` (e.g. tripId).
  - **trip:** anniversaries of trips at least 1 year old, and just-finished trips (within 3 days).
  - **person:** a named person with at least 15 good photos in one month.
  - **pets:** labels cat/dog, at least 20 photos in a year.
  - **year_review:** in January, the best 30 of the previous year, spread across months.
  - **celebration:** `asset_description.event` ∈ {birthday, wedding, holiday, graduation, party}
    clusters within 1 day.
  - **place:** the same non-home city in at least 3 different years.
- **Curation for all types:**
  - drop is_utility, screenshots and documents;
  - collapse each duplicateId / burst to its best asset (vlmQuality, then sharpness);
  - cap at 30 assets, spread across time.
- **Existing on_this_day memories** get the same curation. Keep their current behaviour when
  describe is disabled.

### 2.10 Web UI (S9 user, S10 admin) — follow existing component patterns
**User**
- **Sidebar:** "Collections" and "Trips" entries, placed next to Explore / Places.
- **`/collections`:** two grouped lists like the iOS screenshots.
  - Utilities and Media Types sections.
  - Each row: mdi icon, label, count right-aligned.
  - Rows link to the existing pages where they exist (favorites, trash, locked, duplicates, map);
    otherwise to `/collections/[id]`, a paged gallery using the same grid/viewer components as
    search results.
- **`/trips`:**
  - segmented control "All / <years>";
  - large cover cards with title (bold, bottom-left over the image) and a date subtitle — mirror
    the iOS screenshot;
  - `/trips/[id]` gallery with inline title edit and a "hide trip" action.
- **Asset detail panel — new "AI" section**, collapsed by default:
  - caption, kind badge, tag chips (each links to search with that tag), quality stars (1–10 →
    5 stars);
  - QR/barcode payloads (URLs rendered as links, with `rel="noopener noreferrer nofollow"`);
  - transcript for videos (expandable);
  - Apple facts (Live / Portrait / Burst / Cinematic badges);
  - "Processed by" per capability: processor icon, device name, model, date.
  - Data from `GET /assets/:id/analysis`.
- **Search:** add "Caption / transcript contains" and "Tags" filters to the search filter panel.
  Server side, extend metadata search with `captionQuery` (trigram ILIKE over caption + transcript)
  and `labels[]`. Smart search keeps working as today.
- **Memory lane:** new memory types render with their stored title/subtitle.
- **Viewer:** call `POST /assets/:id/events {kind:'viewed'}` debounced (≥ 2 s on screen, once per
  asset per session).

**Admin**
- **System settings → Machine Learning:**
  - Replace the free-text CLIP / face / OCR model inputs with a select of the models the fork's
    ML service supports, plus a "Custom…" option that keeps free text. The CLIP options include
    all SigLIP2 variants; each option shows its embedding dimension. Show a warning that changing
    the CLIP model re-indexes search.
  - New subsections, each with an enable toggle, URL, API key, model, limits, and a
    **Test connection** button for describe and transcribe:
    - "Vision-language descriptions"
    - "Speech transcription"
    - "Fingerprints & barcodes"
    - "Sound tagging" (P2 — hidden unless S6b is done)
- **New settings section "Analysis":** processor per origin (iPhone / Mac / other). Only
  "Server" is selectable; the others are disabled with explanatory text. Plus an
  "Accept Apple on-device signals" toggle.
- **New settings section "Trips & Memories":** trip thresholds, generate titles, and a toggle per
  memory type.
- **Queues page:** cards for AssetDescribe, AssetFingerprint, VideoTranscribe, SoundTagging, Trips,
  each with All / Missing / Pause like existing cards. Their concurrency lives in Job settings.
- **New admin page "Analysis"** (`/admin/analysis`, linked in the admin sidebar):
  - a table per capability: done / missing / failed, split by processor (server / iPhone / Mac)
    and by model;
  - a "Reprocess" action per row (all / failed / not-current-model);
  - registered devices with last seen.
  - Data from `GET /analysis/stats`.
- **i18n:** all new strings in `i18n/en.json`.

### 2.11 Compose override (S11 — files only)
`docker/docker-compose.ai.yml`, used with `-f docker-compose.yml -f docker-compose.ai.yml`:
- **heirloom-vlm:**
  - image `vllm/vllm-openai:<pinned version>`
  - args: `--model ${VLM_MODEL}`, `--quantization awq`, `--max-model-len 8192`,
    `--gpu-memory-utilization 0.40`, `--limit-mm-per-prompt '{"image":6}'`
  - NVIDIA device reservation and an HF cache volume, on the internal network only.
- **heirloom-speech:**
  - `speaches` CUDA image (pinned; verify the current image name) with the whisper model preloaded
  - on the internal network only.
- **Server env:** document `IMMICH_…` defaults pointing at those hostnames.
- **Comments:** explain that the A4500 is shared with immich-ml and NVENC, and why the memory caps
  are set as they are.
- **Also:** a README snippet in the same folder (short).

---

## 3. Work packages

| WP | Scope | Agent (model) | Depends | Parallel with |
|---|---|---|---|---|
| **S0** | Verify recon-conventions.md (config validation style, config defaults file, migration/SQL/OpenAPI commands, duplicates/utilities web routes, DetailPanel path, AssetFileType values, pg_trgm presence, EXIF fields for lensModel/fps, where the upload DTO lives, nightly-tasks hook, user preferences mechanism, how the Swift OpenAPI client consumes the spec) → write `recon-verified.md` | scout (haiku) | — | — |
| **S1** | All enums/queues/job names (§2.1), schema tables + columns (§2.2), migration, repository skeletons (AnalysisRepository, DescribeRepository = VLM HTTP client, TripRepository, CollectionRepository) with medium tests for the DDL | implementer (sonnet) | S0 | — |
| **S2** | Config (§2.3) DTO + defaults + validation + unit tests; admin settings UI for ML model selects, new ML subsections, Analysis + Trips & Memories sections; queue i18n keys; OpenAPI + SDK regen | implementer (sonnet) | S1 | — |
| **S3** | Device-facing API (§2.7): apple metadata on upload + PUT, devices, signals, device job queue + lease cleanup job, events endpoint, `/assets/:id/analysis`, stats, reprocess; processed-by helper; access control; unit + medium + e2e tests | implementer (sonnet) | S2 | S4 |
| **S4** | Describe pipeline (§2.4) + test-connection + generateTitle; fake OpenAI-compatible server for tests | implementer (sonnet) | S2 | S3, S5 |
| **S5** | Fingerprint pipeline + pHash duplicate merge (§2.5) | implementer (sonnet) | S2 | S4 |
| **S6** | Transcribe pipeline (§2.6); S6b sound tagging (optional, python) | implementer (sonnet) | S2 | after S4/S5 finish (touches the same queue wiring) |
| **S7** | Smart collections registry + endpoints + count cache (§2.8), caption/label search filters | implementer (sonnet) | S3, S4, S5 | — |
| **S8** | TripDetect, Trips API, TripTitleGenerate, new memory types + curation (§2.9) | implementer (sonnet); Opus orchestrator reviews heuristics against §2.9 | S4, S7 | — |
| **S9** | User web UI (§2.10 user) | implementer (sonnet) | S7, S8 | S10 |
| **S10** | Admin web UI: queue cards, Analysis page, remaining admin bits not done in S2 | implementer (sonnet) | S3 | S9 (i18n: append-only, orchestrator merges) |
| **S11** | Compose override + README (§2.11) | implementer (sonnet) | S4, S6 | anything |
| **S12** | Full verification: server check/lint/unit/medium, web check/lint/unit, e2e subset, OpenAPI/SQL drift check, migration up/down on a scratch DB | verifier (sonnet) | all | — |
| **S13** | Docs: admin guide page for the new settings/pages (docs site style), CHANGELOG-style summary in the plan folder, commit messages | scribe (sonnet) | S12 | — |

**Verification after each WP:** a `verifier` run of that WP's test scope. The orchestrator reads
the compressed report and decides the next step.

**Parallel work rule:** WPs listed as parallel may run at the same time only if they don't touch
the same files. Hotspot files (§1) belong to S1/S2; if a later WP needs a hotspot change, it
returns the change to the orchestrator instead of editing the file itself.

## 4. Acceptance checklist (the orchestrator ticks these in `PROGRESS.md`)
- [ ] Migrations generate cleanly, apply to a fresh DB and to a copy of the current fork schema;
      revert works.
- [ ] With describe enabled against the fake VLM, an uploaded image gets asset_description +
      labels + analysis_run, and processed-by = server.
- [ ] Changing the CLIP model to a 1152-d SigLIP2 model resizes and re-queues smart search
      (medium test).
- [ ] Two re-encodes of one photo land in one duplicate group via dHash.
- [ ] A QR screenshot appears in Collections → QR Codes; a receipt-kind asset appears in Receipts.
- [ ] Media Types counts use appleMetadata when present and the EXIF fallback when not.
- [ ] A synthetic GPS fixture (home + 2-state trip over 5 nights) yields exactly one trip titled
      "Alabama & Florida" with the correct date subtitle; a rebuild keeps its id and user title.
- [ ] The trip memory is generated; curation drops utility/duplicate assets.
- [ ] Admin can pick models, enable describe/transcribe, and test the connection; new queue cards
      work; the Analysis page shows per-processor counts.
- [ ] The user sees Collections, Trips, the AI detail section and the new search filters.
- [ ] All new endpoints deny access to other users' assets (e2e), and allow shared-library access
      per S2 rules.
- [ ] OpenAPI spec + TS SDK regenerated; `git diff` of generated files is clean after re-running
      the generators.
- [ ] Nothing deployed; no push without the owner's OK.

## 5. Risks & notes for the orchestrator
- **Upstream mergeability:** prefer new files/modules over rewriting upstream services. Mark fork
  additions to upstream files with `// fork: server-ai`.
- **Heavy queries:** collection counts over large libraries — check `EXPLAIN` in medium tests; add
  indexes (kind, label, dhash) rather than materialising membership.
- **VLM output drift:** always enum-validate; unknown values → `other`, never crash.
- **Keep S8 heuristics simple:** exactly as §2.9. Don't invent extra memory types.
- **Library clones:** the owner's real data will be the cloned library on LXC 403. Nothing here
  runs against it — tests use fixtures only.
