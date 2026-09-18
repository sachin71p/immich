# Apple On-Device ML/Vision Frameworks for Heirloom — Research Report

Compiled 2026-09-17. Covers WWDC 2023–2025 (iOS/macOS 17/18/26 SDK generations) plus what's known
about WWDC 2026 (iOS/macOS 27, in beta as of this writing). Anything not directly confirmed by an
Apple doc/session is flagged **UNVERIFIED**.

---

## 1. Photos / PhotoKit

### 1.1 PHAsset properties relevant to smart-collection classification

`PHAsset` exposes most of what Heirloom needs to replicate iOS Photos' Media Types filters directly,
without re-deriving them via ML:

- **`mediaType`** (`PHAssetMediaType`: `.image`, `.video`, `.audio`, `.unknown`).
- **`mediaSubtypes`** (`PHAssetMediaSubtype`, an `OptionSet`) — this is the single richest signal.
  Confirmed members (Apple docs): `.photoPanorama`, `.photoHDR`, `.photoScreenshot`, `.photoLive`,
  `.photoDepthEffect` (Portrait mode), `.videoStreamed`, `.videoHighFrameRate` (Slo-mo),
  `.videoTimelapse`, `.videoCinematic`, `.spatialMedia`. [`PHAssetMediaSubtype` docs](https://developer.apple.com/documentation/photos/phassetmediasubtype), [`photoScreenshot`](https://developer.apple.com/documentation/photos/phassetmediasubtype/photoscreenshot), [`videoCinematic`](https://developer.apple.com/documentation/photos/phassetmediasubtype/videocinematic).
  Note: there have been developer-forum reports that `.photoHDR` reliably returns `false` on modern
  Gain-Map HDR photos — Apple appears to have stopped setting this flag for the new ISO-gain-map HDR
  pipeline, so don't rely on it for "HDR" detection; read the Gain Map auxiliary data instead (§1.6/§9.2). UNVERIFIED whether this is intentional or a bug — see [forum thread](https://developer.apple.com/forums/thread/806595).
- **`burstIdentifier` / `representsBurst` / `burstSelectionTypes`** — group and flag "best of burst" picks.
- **`sourceType`** (`.typeUserLibrary`, `.typeCloudShared`, `.typeiTunesSynced`) — distinguish native
  captures from imports.
- **`isFavorite`**, **`hidden`** — map directly to the Favorites/Hidden Utilities.
- **`playbackStyle`** (`PHAssetPlaybackStyle`: `.image`, `.imageAnimated`, `.livePhoto`, `.video`,
  `.videoLooping` — used to detect Live Photos vs looping GIFs vs normal video without inspecting
  subtypes).
- **`adjustmentFormat`** (via `PHContentEditingInput`, see §1.5) — whether the asset carries edits.
- Depth/portrait matte, RAW, and spatial data are *not* on `PHAsset` itself — they're read from the
  underlying resource via `ImageIO`/`AVFoundation` (see §9).

There is **no public `isDuplicate`, `isReceipt`, `isHandwriting`, `isIdentityDocument`, or `isQRCode`
flag** on `PHAsset`. Those Photos "Utilities" categories are produced by Apple's private on-device
classifiers (see §11) and are not exposed to third-party apps at all — Heirloom must reproduce them
itself with Vision (`CalculateImageAestheticsScoresRequest.isUtility`, `RecognizeDocumentsRequest`,
`VNDetectBarcodesRequest`, text-density heuristics, etc. — see §3).

### 1.2 PHAssetCollectionSubtype — which Utilities/Media-Type albums are public

`PHAssetCollectionSubtype` (raw values from the public header) confirms exactly which smart albums
Apple exposes to third parties:

| Subtype | Raw value | Exposed publicly? |
|---|---|---|
| `smartAlbumGeneric` | 200 | yes |
| `smartAlbumPanoramas` | 201 | yes |
| `smartAlbumVideos` | 202 | yes |
| `smartAlbumFavorites` | 203 | yes |
| `smartAlbumTimelapses` | 204 | yes |
| `smartAlbumAllHidden` | 205 | yes |
| `smartAlbumRecentlyAdded` | 206 | yes |
| `smartAlbumBursts` | 207 | yes |
| `smartAlbumSlomoVideos` | 208 | yes |
| `smartAlbumUserLibrary` | 209 | yes |
| `smartAlbumSelfPortraits` | 210 | yes (selfies) |
| `smartAlbumScreenshots` | 211 | yes |
| `smartAlbumDepthEffect` | 212 | yes (Portrait mode) |
| `smartAlbumLivePhotos` | 213 | yes |
| `smartAlbumAnimated` | 214 | yes (GIFs) |
| `smartAlbumLongExposures` | 215 | yes |
| `smartAlbumUnableToUpload` | 216 | yes |
| `smartAlbumRAW` | 217 | yes |
| `smartAlbumCinematic` | 218 | yes |
| `smartAlbumSpatial` | 219 | yes |

Sources: [`smartAlbumScreenshots`](https://developer.apple.com/documentation/photos/phassetcollectionsubtype/smartalbumscreenshots), [`smartAlbumUserLibrary`](https://developer.apple.com/documentation/photos/phassetcollectionsubtype/smartalbumuserlibrary), [`smartAlbumTimelapses`](https://developer.apple.com/documentation/photos/phassetcollectionsubtype/smartalbumtimelapses), enum raw values corroborated against public header dumps.

**Confirmed absent from `PHAssetCollectionSubtype`** (i.e., NOT public — these iOS 17+ Photos
"Utilities" categories exist only inside Apple's own app, backed by private on-device models):
**Duplicates**, **Receipts**, **Handwriting**, **Illustrations**, **QR Codes**, **Identity
Documents**, **Documents**, **Imports**, **Recently Saved / Viewed / Edited / Shared**, **Map** view,
**Captured by Me** (this one is derivable — see §1.2.1), **Trips**, **Memories**, and the People/Faces
groupings (`albumSyncedFaces`, raw value 4, exists but is populated by *device-synced* face albums
from very old iPhoto/Aperture-style syncing, not Apple's modern on-device People feature — it is
effectively vestigial today). Heirloom must build equivalents for all of the "Utilities" list itself.

- **1.2.1 "Captured by Me"**: derivable from `sourceType == .typeUserLibrary` combined with
  `PHAsset.creationDate`/absence of `PHCloudIdentifier` importedFrom markers — no direct flag, but
  functionally reconstructible from asset origin (UNVERIFIED exact heuristic Apple uses internally).

### 1.3 PHPersistentChangeToken / fetchPersistentChanges — incremental sync

Introduced in iOS 16 / WWDC22 specifically to let third-party sync apps (photo backup tools) avoid
full-library re-diffs:

- `PHPersistentChangeToken` — an opaque, `NSSecureCoding`-compliant token you persist to disk between
  launches. [Docs](https://developer.apple.com/documentation/photos/phpersistentchangetoken)
- `PHPhotoLibrary.shared().fetchPersistentChanges(since:)` returns a `PHPersistentChangeFetchResult`
  you iterate for `PHPersistentChange` (per-batch inserts/updates/deletes of `PHObject`, with a new
  `changeToken` you save for next time). This works **even across app relaunches and device reboots**,
  unlike the older `PHChange` observer which only fires live while the app runs.
- Session: [Discover PhotoKit change history (WWDC22, session 10132)](https://developer.apple.com/videos/play/wwdc2022/10132/).
- Practical notes from a third-party implementer: [Querying the iOS Photo Library](https://ikyle.me/blog/2025/querying-the-ios-photo-library).
- **Min OS**: iOS 16 / macOS 13. This is the correct primitive for Heirloom's background sync engine
  (far better than polling `fetchAssets` diffs).

### 1.4 PHCloudIdentifier — cross-device identity

- `PHCloudIdentifier` (iOS 15+ / macOS 12+) is a stable identifier for an asset that syncs via iCloud
  Photos, valid across every device signed into the same iCloud Photo Library — unlike
  `localIdentifier`, which can change (e.g., after a device restore/transfer).
  [Docs](https://developer.apple.com/documentation/photos/phcloudidentifier)
- `PHCloudIdentifierMapping` is the result wrapper `PHPhotoLibrary` returns when you batch-convert
  between `localIdentifier` and `PHCloudIdentifier` (`cloudIdentifierMappings(forLocalIdentifiers:)`
  and the inverse). [Docs](https://developer.apple.com/documentation/photokit/phcloudidentifiermapping)
- Session: [Improve access to Photos in your app (WWDC21, 10046)](https://developer.apple.com/videos/play/wwdc2021/10046/).
- Use for Heirloom: dedupe the *same* asset seen from iPhone + iPad + Mac before it's uploaded twice,
  and to reconcile a server-side asset back to "this local PHAsset" after an iCloud restore changes
  local identifiers.

### 1.5 PHContentEditingInput / Output, PHAssetResource(Manager), PHAdjustmentData

- **`PHContentEditingInput`**: gives your extension/app access to the *original, unadjusted* image or
  video data plus (if a Live Photo) the paired video, plus any existing `PHAdjustmentData`.
  [Docs](https://developer.apple.com/documentation/photos/phcontenteditinginput)
- **`PHContentEditingOutput`**: where you write back a new rendered version plus new
  `PHAdjustmentData` describing what changed, so Photos can revert/reapply your edit later.
  [Docs](https://developer.apple.com/documentation/photos/phcontenteditingoutput)
- **`PHAdjustmentData`**: opaque blob (formatIdentifier + version + your own data) describing an
  edit, non-destructively layered over the original. [Docs](https://developer.apple.com/documentation/photos/phadjustmentdata)
- **`PHAssetResource`** / **`PHAssetResourceManager`** (iOS 9+): the lower-level API to enumerate and
  read the *actual bytes* backing an asset — original file, current (edited) file, adjustment data,
  alternate (e.g. the video half of a Live Photo), full-size render, or the paired
  photo/video of a Live Photo — independent of the `PHContentEditingInput` workflow. This is what
  Heirloom's uploader should use to pull true originals (including RAW/HEIC/ProRAW bytes) off-device
  for server-side processing, since it exposes `PHAssetResourceType` (`.photo`, `.video`,
  `.audio`, `.alternatePhoto`, `.fullSizePhoto`, `.adjustmentData`, `.adjustmentBasePhoto`, `.pairedVideo`, etc.).

### 1.6 PHImageManager / PHCachingImageManager

Standard thumbnail/full-image request API (`requestImage`, `requestImageDataAndOrientation`,
`requestAVAsset`, `requestPlayerItem`). `PHCachingImageManager` adds `startCachingImages` /
`stopCachingImages` to pre-warm thumbnails for scroll performance. Nothing new here since early
PhotoKit; still the correct API for a fast on-device grid. `requestImageDataAndOrientation(for:options:resultHandler:)`
is the path to get raw HEIC/JPEG bytes (with `PHImageRequestOptions.isNetworkAccessAllowed` for
iCloud-only originals) — the practical route to feed Vision requests without going through
`PHContentEditingInput` machinery.

### 1.7 Limited Library access

`PHAuthorizationStatus.limited` (iOS 14+): user grants access to a hand-picked subset. Key behaviors:
- `PHPickerViewController` is **not** restricted by limited-library mode — it shows the *entire*
  system photo library regardless of the app's granted subset, since picks happen out-of-process.
  But `PHAsset` fetches in your app process still only return the limited subset.
- `PHPhotoLibrary.shared().presentLimitedLibraryPicker(from:)` lets the user add more assets to the
  granted subset without leaving your UI.
- Selections made via `PHPickerViewController` are **not automatically added** to the limited-access
  grant; you get the bytes via `NSItemProvider`, but the asset does not become fetchable by your app.
- Sources: [Handle the Limited Photos Library (WWDC20 notes)](https://mackuba.eu/notes/wwdc20/handle-the-limited-photos-library/), [forum thread on picker + limited access](https://forums.developer.apple.com/forums/thread/759040).
- Design implication for Heirloom: full-library background sync **requires** full access
  (`.authorized`); limited mode is workable only for a manual "pick what to back up" flow.

### 1.8 Background resource upload — iOS 26.1 (new, confirm before relying on it)

Apple added a genuine **system-managed background upload extension for PhotoKit in iOS 26.1** (not
26.0) aimed exactly at apps like Heirloom/Immich:
- Extension point: `com.apple.photos.background-upload`, backed by the
  **`PHBackgroundResourceUploadExtension`** protocol. [Docs stub](https://developer.apple.com/documentation/photos/phbackgroundresourceuploadextension?changes=_1)
- The system, not your app, decides *when* to invoke your extension (network/power/thermal aware),
  and keeps a Live-Activity-style progress surface so backups continue reliably even when your app is
  suspended or the device is locked — solving the single biggest pain point of iOS photo-backup apps
  today (background execution time limits).
- Immich's own community is already tracking this for the iOS app: [Immich discussion #23358](https://github.com/immich-app/immich/discussions/23358), [#23583](https://github.com/immich-app/immich/discussions/23583), [#23585](https://github.com/immich-app/immich/discussions/23585).
- Coverage: [9to5Mac](https://9to5mac.com/2025/10/24/ios-26-1-third-party-photos-backup-background/), [Neowin](https://www.neowin.net/news/apple-quietly-opens-up-background-photo-backups-to-third-party-apps-with-ios-261/).
- **Status as of this report: was still in beta/evolving through the iOS 26.1 betas.** Confirm current
  shape against the shipped 26.1 SDK before committing Heirloom's sync architecture to it — this is
  the single highest-leverage new PhotoKit capability for Heirloom and merits its own follow-up spike.
  **UNVERIFIED**: exact extension lifecycle/entitlements/App Store review posture at GA.

### 1.9 Does Apple expose its own People/Faces, scene labels, Memories, Trips, or captions?

**No, on every count.** Apple's People/Faces recognition (`mediaanalysisd`), scene/object labeling
used inside Memories, trip detection, and auto-generated captions are all produced by **private**
frameworks/daemons (§11) and are not surfaced through PhotoKit, Vision, or any other public API.
`PHPerson` **does not exist** as a public PhotoKit class (there is no such type in current or
historical public headers — the closest historical artifact is `albumSyncedFaces`, a *legacy iPhoto
face-album sync* subtype, not the modern People feature). The "moment" concept
(`PHCollectionList` fetched via the old `.momentList`/`.moment` type) is explicitly **deprecated** —
Apple's guidance is to use `PHCollectionList`/`PHAssetCollection` fetches directly rather than the
Moments abstraction. [PhotoKit deprecated errors](https://developer.apple.com/documentation/photokit/deprecated-errors). Net effect for Heirloom: **all** face clustering, scene
classification, trip/Memory generation, and captioning must be built by Heirloom itself using Vision +
Core ML + Foundation Models — none of it can be read from Apple's own analysis.

---

## 2. PhotosUI

- **`PhotosPicker`** (SwiftUI, iOS 16+) / **`PHPickerViewController`** (UIKit, iOS 14+): out-of-process
  picker UI — the host app never sees library contents the user didn't pick, no permission prompt
  needed for basic single/multi-select. Supports `PHPickerFilter` (`.images`, `.videos`, `.livePhotos`,
  `.depthEffectPhotos`, `.panoramas`, `.screenshots`, `.slomoVideos`, `.cinematicVideos`, `.spatialMedia` — [`spatialMedia` filter doc](https://developer.apple.com/documentation/photosui/phpickerfilter-swift.struct/spatialmedia)) to pre-scope selection to a media
  subtype — useful for a "back up my Live Photos only" style flow.
- **iOS 17+ embedded/inline picker**: `PhotosPicker`/`PHPickerViewController` gained an embedded
  presentation style (inline in your own view hierarchy rather than a sheet) — useful for a
  Heirloom "select photos to share" composer.
  [Meet the new Photos picker (WWDC20, 10652)](https://developer.apple.com/videos/play/wwdc2020/10652/) is the original session; embedded style and richer filtering were extended in subsequent years — **UNVERIFIED** exact WWDC session number for the iOS 17 embedded-picker enhancement; verify against the PhotosUI "Updates" doc page before citing a specific session in a spec.
- **`PHLivePhotoView`**: UIKit/SwiftUI-bridgeable view for full-fidelity Live Photo playback
  (contextual "press and hold" motion), independent of `AVPlayer`.
- **Photo editing extensions** (`PHContentEditingController` + Info.plist `PHEditingExtension`
  service) let a companion app edit a photo in-place from within Photos.app — not core to Heirloom's
  sync pipeline but relevant if Heirloom ever wants a "edit in Heirloom" affordance from Apple Photos.

---

## 3. Vision framework

iOS 18/macOS 15 introduced a **parallel, Swift-native, async/await request API** alongside every
legacy `VN*Request`/`VN*Observation` Objective-C-compatible type (e.g. legacy
`VNGenerateImageFeaturePrintRequest` ↔ new `GenerateImageFeaturePrintRequest`). The legacy API is not
deprecated and both interoperate; new capabilities (aesthetics, lens smudge, document recognition)
ship Swift-only. [Discover Swift enhancements in the Vision framework (WWDC24, 10163)](https://developer.apple.com/videos/play/wwdc2024/10163/).

### 3.1 Face analysis
| Legacy | Swift (iOS18+) | What it does | Min OS | Notes |
|---|---|---|---|---|
| `VNDetectFaceRectanglesRequest` | `DetectFaceRectanglesRequest` | Face bounding boxes | iOS 11 | ANE-accelerated |
| `VNDetectFaceLandmarksRequest` | `DetectFaceLandmarksRequest` | 65-76 point landmarks (eyes, brows, nose, lips, face contour) | iOS 11 | |
| `VNDetectFaceCaptureQualityRequest` | `DetectFaceCaptureQualityRequest` | Single float "how good is this face capture" combining exposure, blur, pose, expression | iOS 13 | Ideal signal for Heirloom's "best shot of this person" selection. [Docs](https://developer.apple.com/documentation/vision/vndetectfacecapturequalityrequest?language=objc) |

**Vision does NOT provide face-identity embeddings.** There is no `VN*` request that returns a
vector suitable for "is this the same person." `VNFaceObservation`/`VNFaceLandmarks2D` give geometry
only. Confirmed by the absence of any identity/embedding output type across the whole Vision face
API surface, and corroborated by community consensus (e.g. [face-recognition-in-ARKit implementations](https://github.com/NovatecConsulting/FaceRecognition-in-ARKit) that bolt on a
separate Core ML model because Vision has nothing). **Options for Heirloom's face
clustering**:
1. Convert a face-embedding model (e.g. ArcFace, which outputs a 512-D vector; [ArcFace explainer](https://arxiv.org/pdf/2604.09127)) to Core ML with `coremltools`, run it on 112×112 aligned
   face crops (align using Vision's landmarks first), then cluster embeddings yourself (cosine
   distance + HDBSCAN/agglomerative clustering). This mirrors what Apple's own 2021 paper describes
   doing internally (§12) — Apple never exposed that model publicly, so Heirloom has to bring its own.
2. `VNGenerateImageFeaturePrintRequest` on a face crop is a documented **weak substitute** — it's a
   general-purpose scene/object feature print, not face-specialized, so same-person recall is
   materially worse than a dedicated face embedding, though it's "free" (no extra model to ship).
3. No first-party Apple framework closes this gap as of iOS 26 / WWDC 2026 — this remains the single
   biggest "bring your own model" requirement for Heirloom's People feature.

### 3.2 Body / pose / animals
- `VNDetectHumanRectanglesRequest` — person bounding boxes (fast, e.g. for burst dedup / "has people" filter).
- `VNDetectHumanBodyPoseRequest` / Swift `DetectHumanBodyPoseRequest` — 2D, ~19-joint skeleton.
- `VNDetectHumanBodyPose3DRequest` (iOS 17+) — 17 joints in **3D**, camera-relative; uses `AVDepthData`
  when present but does **not require LiDAR**. [Docs](https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest), [guide](https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images). Introduced at WWDC23 ("new Vision framework with 3D
  Detection").
- `VNDetectAnimalBodyPoseRequest` — animal skeleton pose (dogs/cats). Detailed joint taxonomy not
  independently confirmed in this pass — **UNVERIFIED** exact joint count; check current doc page.
- `VNRecognizeAnimalsRequest` — animal identification (cats/dogs, plus additional species added over
  releases). Distinct from the general `VNClassifyImageRequest` scene/object classifier below.
- `VNDetectHumanHandPoseRequest` — 21-point hand skeleton (not searched this pass, existing since
  iOS 14 — carried over from prior knowledge, **flagging for spot-check** since not directly
  re-verified in this session).

### 3.3 Whole-image classification & similarity
- **`VNClassifyImageRequest`** — Apple's built-in general-purpose multi-label image classifier.
  Community-compiled lists put the **`VNClassifyImageRequestRevision1`** taxonomy at **1303 labels**
  (matches the task's "~1300+" figure). [Discussion](https://medium.com/@kamil.tustanowski/image-classification-using-the-vision-framework-3cac0ab6f399). Output: array of `VNClassificationObservation` (identifier string
  + confidence). This is the direct API for Heirloom's "scene/object classification" requirement
  (beach, dog, food, sunset, document, etc.) — no custom model needed for a first pass.
- **`VNGenerateImageFeaturePrintRequest`** / Swift `GenerateImageFeaturePrintRequest` — produces a
  `VNFeaturePrintObservation` (a fixed-length float vector) usable for near-duplicate/similarity via
  `computeDistance(_:to:)` (returns a float; smaller = more similar). Multiple revisions exist
  (`VNGenerateImageFeaturePrintRequestRevision1`, `...Revision2`) with different underlying models —
  **you must pin a revision** if you persist feature prints server-side, since prints from different
  revisions aren't comparable. A commonly cited practical cutoff for "likely duplicate" is a distance
  in the **0.4–0.6** range (empirical, not an Apple-documented threshold — treat as a starting point,
  tune against Heirloom's own corpus). [Docs](https://developer.apple.com/documentation/vision/generateimagefeatureprintrequest), [distance-based dedup writeup](https://medium.com/@MWM.io/apples-vision-framework-exploring-advanced-image-similarity-techniques-f7bb7d008763). **UNVERIFIED**: exact `elementCount`/`elementType` per revision — Apple's
  reference page for `VNFeaturePrintObservation` should be checked directly in Xcode docs before
  hard-coding a dimensionality in a spec (older Apple sample code and blog posts cite 2048 for
  Revision1; do not treat that as confirmed without checking the live doc).
- **`CalculateImageAestheticsScoresRequest`** (iOS 18+) — direct hit for Heirloom's "best shot" /
  quality-ranking requirement. Produces `ImageAestheticsScoresObservation` with:
  - `overallScore: Float` in **[-1, 1]** (higher = more aesthetically pleasing).
  - **`isUtility: Bool`** — true for well-exposed/sharp-but-unmemorable images: screenshots,
    receipts, whiteboard photos, documents. **This flag is exactly the signal Heirloom needs to
    separate "real photos" from "utility captures"** when building the Screenshots/Receipts/Documents
    smart collections, without having to hand-roll that heuristic. [Docs](https://developer.apple.com/documentation/vision/calculateimageaestheticsscoresrequest), [tutorial](https://www.createwithswift.com/scoring-the-aesthetics-of-an-image-with-the-vision-framework/).
  - Does **not run in Simulator** — device-only (ANE/GPU dependent). Test on real hardware.

### 3.4 Saliency, horizon, segmentation, masks
- `VNGenerateAttentionBasedSaliencyImageRequest` — heat map of where a viewer's eye would land
  (mirrors Photos' auto-crop/thumbnail-region logic). [Docs](https://developer.apple.com/documentation/vision/vngenerateattentionbasedsaliencyimagerequest)
- `VNGenerateObjectnessBasedSaliencyImageRequest` — heat map of "likely to be an object," used
  upstream of subject-lifting/instance segmentation. [Docs](https://developer.apple.com/documentation/vision/vngenerateobjectnessbasedsaliencyimagerequest)
- `VNDetectHorizonRequest` — returns the horizon line angle (auto-level correction signal).
- `VNGeneratePersonSegmentationRequest` — a single alpha matte for "all people" in frame (fast, coarse).
- `VNGenerateForegroundInstanceMaskRequest` (iOS 17+, "Lift Subject") — **class-agnostic** instance
  segmentation: any foreground subject (person, pet, object) gets its own instance index in a single
  mask (index 0 = background, 1..N = each instance); not simulator-runnable (device only — no CPU
  fallback). [Docs](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest), background at [WWDC23 "Lift subjects from images"](https://developer.apple.com/videos/play/wwdc2023/10176/).
- `VNGeneratePersonInstanceMaskRequest` — the person-specific sibling that gives per-person instance
  indices instead of one blended mask (useful for multi-person photos where you want each person's
  mask separately, e.g. to run face-capture-quality per detected instance).

### 3.5 Tracking / motion
- `VNTrackObjectRequest` — stateful frame-to-frame object tracker seeded by a bounding box (video use:
  tracking a subject across a burst/video for stabilized thumbnail selection).
- `VNTrackOpticalFlowRequest` — dense optical flow field between two frames.
- `VNDetectTrajectoriesRequest` — fits parabolic trajectories across a frame sequence (e.g. a thrown
  ball) — niche for Heirloom, potentially useful for sports/action-shot highlight detection in videos.
- Image registration: `VNTranslationalImageRegistrationRequest` /
  `VNHomographicImageRegistrationRequest` — align two images (e.g. bracket/HDR merge inputs, or
  aligning burst frames before diffing for "which frame is sharpest").

### 3.6 Text, barcodes, documents, contours
- `VNRecognizeTextRequest` — OCR. Now on **Revision 3**, which is the same recognizer that powers
  system Live Text; supports a large, growing language list (`supportedRecognitionLanguages`),
  including Japanese/Korean added in a recent revision. [Reference](https://developer.apple.com/videos/play/wwdc2022/10024/) (WWDC22 "What's new in Vision").
- **`RecognizeDocumentsRequest`** (iOS 26 / WWDC25, new) — the big upgrade for Heirloom's
  Documents/Receipts/Handwriting/Identity-Documents smart collections: goes beyond flat OCR to return
  a **hierarchical `DocumentObservation`** — paragraphs, detected **tables (rows + columns)**, lists,
  and structured data (e.g. phone numbers), plus embedded barcode detection, in a single pass, across
  26 languages. [Docs](https://developer.apple.com/documentation/vision/recognizedocumentsrequest), session [Read documents using the Vision framework (WWDC25, 272)](https://developer.apple.com/videos/play/wwdc2025/272/). This is
  the correct building block for a "Receipts" or "Documents" classifier (structured content density +
  table/paragraph presence rather than a generic scene label).
- `VNDetectBarcodesRequest` — barcode/QR. `VNDetectBarcodesRequestRevision3` uses an ML-based decoder
  (prior revisions were classical CV). Query `VNDetectBarcodesRequest.supportedSymbologies` at
  runtime; confirmed symbologies include QR, Aztec, PDF417, Data Matrix, Code 128/39, EAN-13, ITF14,
  GS1 DataBar, UPC-E, and more. [Overview](https://www.createwithswift.com/reading-qr-codes-and-barcodes-with-the-vision-framework/). Direct hit for the "QR Codes" Utility collection.
- `VNDetectContoursRequest` — edge/contour extraction (single image), useful as a pre-pass for
  document-edge detection or line-art/illustration classification.

### 3.7 iOS 26 additions specific to capture quality
- **`DetectLensSmudgeRequest`** (iOS 26 / WWDC25) — returns a confidence score for "this image/frame
  was shot through a smudged lens." [Docs](https://developer.apple.com/documentation/vision/detectlenssmudgerequest). Primarily a *capture-time* UX signal (real-time camera
  feedback), but also useful for Heirloom as a "hazy/low quality capture" downgrade signal when
  ranking a burst or computing "best shot," and could plausibly seed a future "blurry photos" cleanup
  Utility album (Apple Photos doesn't expose one publicly, but the raw signal is now available).

### 3.8 Platform availability summary for Vision
Vision (both legacy and Swift APIs) ships on **iOS, iPadOS, macOS, tvOS, and visionOS** — it is not
iOS-only. Model-heavy requests (aesthetics, foreground-instance-mask, lens smudge) generally require
a real Neural Engine and are documented as unavailable/degraded in Simulator; run device tests for
anything that gates a Heirloom pipeline decision.

---

## 4. VisionKit

- **`ImageAnalyzer`** — the entry point that runs Apple's Live Text + subject + barcode analysis over
  a still image, producing an `ImageAnalysis` result. [Docs](https://developer.apple.com/documentation/visionkit/imageanalyzer)
- **`ImageAnalysisInteraction`** — a `UIInteraction`/gesture-recognizer-like object you attach to an
  `UIImageView`/`NSImageView` to get free, Apple-styled UI for: text selection & copy (Live Text),
  QR/barcode tap-to-open, and **subject lifting** (long-press-drag a subject out of the photo).
  Interaction types are configurable via `preferredInteractionTypes` (`.automatic` includes all
  three). [Docs](https://developer.apple.com/documentation/visionkit/imageanalysisinteraction). Session: [Lift subjects from images in your app (WWDC23, 10176)](https://developer.apple.com/videos/play/wwdc2023/10176/).
- **`DataScannerViewController`** (iOS 16+) — live camera-feed scanner for text/machine-readable
  codes, real-time (distinct from the still-image `ImageAnalyzer` path). [Docs](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller). Relevant to Heirloom
  only if it ever adds a "scan a document/QR directly into your library" capture mode.
- VisionKit's subject-lifting UI is a thin, ready-made wrapper over the same
  `VNGenerateForegroundInstanceMaskRequest` from §3.4 — use VisionKit when you want the interactive
  drag-to-lift UX for free; use raw Vision when you need the mask data programmatically (e.g. batch
  server-side asset processing has no UI at all).
- Visual Look Up (identifying landmarks/plants/pets from a photo) is surfaced through this same
  `ImageAnalysisInteraction` pathway in Apple's own apps, but **the underlying knowledge-graph lookup
  itself is not a public API** — you get the interaction affordance, not raw "this is the Eiffel
  Tower" data. **UNVERIFIED** whether any structured result is exposed to third parties versus purely
  a system UI hand-off; treat as private-server-backed and out of scope for offline/self-hosted use.

---

## 5. Core ML, MLX, Create ML

### 5.1 Core ML core runtime
- Executes ML-Program/`mlpackage` models across CPU/GPU/**ANE**, with an automatic compute-unit
  scheduler (`MLComputeUnits.all/.cpuAndNeuralEngine/...`).
- **`MLTensor`** (iOS 18/macOS 15, WWDC24) — a new Swift type mirroring NumPy/PyTorch-style tensor
  ops, letting you compose pre/post-processing (e.g. softmax, top-k, normalization) directly against
  Core ML outputs without hand-writing Accelerate/vDSP glue. [Deploy ML/AI models on-device with Core ML (WWDC24, 10161)](https://developer.apple.com/videos/play/wwdc2024/10161/).
- **Stateful models** (iOS 18/macOS 15) — a model can declare `state` inputs Core ML persists and
  updates in place across calls, avoiding the overhead of re-passing KV-cache-style state every
  inference. Directly relevant if Heirloom ever runs a transformer-based embedding/caption model
  on-device with autoregressive decoding. [coremltools guide](https://apple.github.io/coremltools/docs-guides/source/stateful-models.html), [Bring your ML/AI models to Apple silicon (WWDC24, 10159)](https://developer.apple.com/videos/play/wwdc2024/10159/).
- `coremltools` (Python) remains the conversion path from PyTorch/TensorFlow/ONNX models (e.g. a
  face-embedding network or a captioning model) into `.mlpackage`.
- **WWDC 2026 note**: multiple outlets report Apple introducing a **"Core AI"** framework, pitched as
  a successor/complement to Core ML aimed specifically at running larger multimodal/LLM-class models
  on-device, expected to coexist with Core ML rather than replace it immediately.
  [AppleInsider](https://appleinsider.com/articles/26/03/01/wwdc-2026-to-introduce-core-ai-as-replacement-for-core-ml), [WWDC26 recap](https://appcircle.io/blog/wwdc-2026-recap-for-developers). **UNVERIFIED / early**: this is third-party
  reporting on a pre-release framework; re-check the official `developer.apple.com/documentation`
  index once iOS 27/macOS 27 SDKs are GA before designing around it.

### 5.2 MobileCLIP / MobileCLIP2 (Apple's own CLIP) — for CLIP-compatible on-device embeddings
This is the most important finding for Heirloom's "smart search" parity with the server's CLIP index:
- Apple Research publishes **MobileCLIP** (CVPR 2024) and **MobileCLIP2** (TMLR, Aug 2025) at
  [apple/ml-mobileclip](https://github.com/apple/ml-mobileclip), with **Core ML exports of both image
  and text encoders already provided** on Hugging Face
  ([apple/coreml-mobileclip](https://huggingface.co/apple/coreml-mobileclip)). MobileCLIP-S0 is
  reported ~4.8x faster and ~2.8x smaller than OpenAI ViT-B/16 at comparable zero-shot accuracy.
  [Paper](https://arxiv.org/html/2311.17049v2).
- **Licensing caveat (important for a commercial/self-hosted product like Heirloom):** the Core ML
  model weights are released under Apple's **"Apple Machine Learning Research Model" license**
  (surfaced on Hugging Face as `apple-ascl`), which Apple's own `LICENSE_MODELS` text describes as
  for **"the sole purpose of scientific research of artificial intelligence and machine-learning
  technology"** — i.e., a research license, not an unrestricted commercial-use grant. **Flag this for
  legal review before shipping MobileCLIP weights inside Heirloom** — either get explicit clarification
  that this covers Heirloom's use case, fine-tune/retrain your own encoder with compatible license
  terms, or use a differently-licensed CLIP variant and re-derive embeddings server-side to keep
  vector space compatibility. [ml-mobileclip LICENSE](https://github.com/apple/ml-mobileclip/blob/main/LICENSE), [LICENSE_MODELS](https://github.com/apple/ml-mobileclip/blob/main/LICENSE_MODELS).
- Practically: if license terms work out, running MobileCLIP's *image* encoder on-device via Core ML
  (ANE-accelerated) lets Heirloom compute a CLIP-space embedding client-side and upload only the
  vector (small, privacy-friendlier, saves bandwidth) — **provided the self-hosted server's existing
  CLIP index uses a compatible/matching model+checkpoint**, since CLIP embedding spaces are not
  interchangeable across differently-trained encoders. Immich's server today typically uses
  OpenCLIP/other checkpoints — **verify checkpoint compatibility before assuming plug-and-play**
  (this needs a follow-up check against Immich's current ML service config, not just Apple docs).

### 5.3 MLX / MLX Swift (Mac-focused)
- Open-source (`ml-explore/mlx`, `ml-explore/mlx-swift`) array framework built around Apple Silicon's
  unified memory, with a lazy-graph execution model (NumPy/PyTorch-like ergonomics).
  [mlx-swift](https://github.com/ml-explore/mlx-swift), [Apple Open Source page](https://opensource.apple.com/projects/mlx/).
- WWDC25 sessions: [Get started with MLX for Apple silicon (315)](https://developer.apple.com/videos/play/wwdc2025/315/), [Explore LLMs on Apple silicon with MLX (298)](https://developer.apple.com/videos/play/wwdc2025/298/).
- Positioned for **Mac-side** heavier workloads (larger LLMs, fine-tuning, research-y inference) —
  not currently the recommended path for routine iPhone photo-analysis pipelines, where Core ML +
  Vision's ANE path is both officially sanctioned and lighter-weight. For Heirloom's **macOS app**,
  MLX is a credible option if you want to run a larger on-device captioning/tagging LLM locally rather
  than relying on Foundation Models' capped ~3B model.

### 5.4 Create ML / Create ML Components
Not directly re-verified this session (no dedicated search pass) — Create ML remains Apple's
no-code/low-code **training** tool (image classifiers, sound classifiers, recommenders, tabular
models) exported to Core ML, and Create ML Components is the programmatic Swift training-pipeline
API for custom transforms. Relevant to Heirloom only if you want to **train a small custom classifier**
(e.g. a Heirloom-specific "identity document" detector) on a labeled Heirloom dataset rather than
inferring one from Vision's generic outputs — flagged as a build option, not further researched here.

---

## 6. Foundation Models framework (on-device LLM)

- **Framework**: `import FoundationModels`. Ships iOS 26 / iPadOS 26 / macOS 26 (WWDC25, session
  [Meet the Foundation Models framework (286)](https://developer.apple.com/videos/play/wwdc2025/286/); [Apple Newsroom announcement](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)).
- **Model**: the on-device ~3B-parameter LLM that also powers system Apple Intelligence features.
  Runs **only on Apple-Intelligence-eligible devices with Apple Intelligence turned on** — this is a
  hard availability gate Heirloom must check (`SystemLanguageModel.availability`) and degrade
  gracefully on unsupported hardware/regions.
- **Guided generation**: `@Generable` + `@Guide` macros let you declare a target Swift type (e.g. a
  `struct TripTitle { @Guide(...) var title: String; var moodTags: [String] }`) and get **constrained
  decoding** — the model is token-masked so it structurally cannot emit invalid output for that
  schema (compile-time schema, not prompt-engineered JSON hoping the model complies).
  [Explainer](https://dev.to/iniyarajan86/foundation-models-guided-generation-with-apples-ios-26-framework-2m09).
- **Tool calling**: apps can register Swift "tools" the model can invoke mid-generation (function
  calling), which is how Apple recommends grounding generations in live app data.
- **Image input**: **not available at iOS 26 GA.** Multimodal prompt *attachments* (accepting
  `UIImage`/`NSImage`/`CGImage`/`CIImage`/pixel buffers/file URLs) were added in the **iOS 27 /
  WWDC 2026** generation — described as "a natural extension of existing prompt builders," with
  Vision-framework tools (OCR, barcode reading) exposed for the model to call directly, all on-device.
  [WWDC26 session: What's new in the Foundation Models framework (241)](https://developer.apple.com/videos/play/wwdc2026/241/), [deep dive](https://swiftwithmajid.com/2026/09/01/building-ai-features-using-foundation-models-multimodal-input/), [blog](https://blakecrosley.com/blog/foundation-models-image-input-ios-27). **Bottom line for Heirloom**: today (iOS 26), Foundation
  Models is **text-only** — perfectly suited to *titling/summarizing* a Memory or Trip from structured
  metadata you assembled from Vision/location data, but it **cannot itself look at a photo**. On
  iOS 27+ (once GA), it can additionally take photos as input directly, narrowing the gap with
  server-side captioning.
- **WWDC 2026 additions** beyond image input: free Private-Cloud-Compute-hosted Foundation Models
  access for developers under 2M first-time downloads (removes the on-device-only constraint for
  smaller apps, at the cost of a network round-trip and giving up the "fully local" privacy story),
  ability to call third-party hosted models (Claude, Gemini) through the same Swift API, and a
  "Dynamic Profiles" system for multi-agent workflows. [Recap](https://dev.to/hariharanjagan/whats-new-in-apples-foundation-models-framework-at-wwdc-2026-5227), [WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/).
- **Heirloom use cases**: Memory/Trip titles and one-line summaries from structured inputs (place
  names, date range, dominant scene labels, person names if the user has labeled them), on-device and
  free of per-call API cost, no data leaves the device (as long as you don't opt into the new
  PCC-hosted path). Given the current text-only constraint, feed it your Vision-derived labels/OCR
  text/geocoded place names rather than expecting it to interpret the pixels itself.

### 6.1 Adjacent Apple Intelligence surfaces (lower priority for Heirloom, noted for completeness)
- **Image Playground / `ImageCreator`** — on-device generative image creation API; not relevant to
  analyzing existing photos.
- **Writing Tools** — system-wide text rewrite/proofread/summarize UI surface; could theoretically be
  invoked on caption text fields but isn't a distinct API Heirloom would call directly.
- **App Intents + Visual Intelligence / Spotlight**: WWDC25/26 pushed App Intents toward
  "entity/intent schemas" that let system surfaces (Spotlight semantic index, Visual Intelligence
  camera search, Siri) query and act on your app's content via natural language, plus new **View
  Annotations** mapping visible UI to entities Siri can reference conversationally.
  [Explore new advances in App Intents (WWDC25, 275)](https://developer.apple.com/videos/play/wwdc2025/275/), [Get to know App Intents (WWDC25, 244)](https://developer.apple.com/videos/play/wwdc2025/244/), [Best practices for visual intelligence (WWDC26, 297)](https://developer.apple.com/videos/play/wwdc2026/297/). Longer-term opportunity: expose Heirloom's people/places/albums as App
  Intents entities so Siri/Spotlight/Visual Intelligence can search a user's Heirloom library the way
  they can search Apple Photos today — a larger, separate integration project, not core to the
  on-device analysis pipeline.

---

## 7. Natural Language, Translation, Speech, Sound Analysis

### 7.1 Natural Language — `NLContextualEmbedding`
- Modern (BERT-style transformer) contextual text embedding model, superseding the older
  `NLEmbedding` (static word vectors with no context-sensitivity).
- Produces a **per-token** embedding sequence (not a single pooled sentence vector out of the box) —
  reported dimensionality **512**, sequence length **256 tokens**; you pool tokens yourself (mean/CLS)
  if you want one vector per caption/OCR block. [Docs](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding), [analysis](https://www.callstack.com/blog/on-device-ai-introducing-apple-embeddings-in-react-native). **UNVERIFIED**: exact
  dimensionality/sequence-length figures are drawn from third-party technical analysis rather than the
  primary Apple doc page content itself (WebFetch could not retrieve full page body this session) —
  confirm against the live doc before hard-coding into a spec.
- Use for Heirloom: embedding OCR'd/Live-Text text, captions, or place names for on-device semantic
  text search that doesn't require network calls — a complement to, not a replacement for, image-CLIP
  search.
- Older `NLEmbedding.sentenceEmbedding(for:)` / `sentenceEmbedding(for:revision:)` APIs still exist
  for simpler, lower-fidelity sentence vectors. [Docs](https://developer.apple.com/documentation/naturallanguage/nlembedding/sentenceembedding(for:revision:)).

### 7.2 Translation framework (iOS 18+)
- `import Translation`. `TranslationSession` performs on-device translation between a language pair;
  obtained via the SwiftUI `.translationTask(_:action:)` view modifier.
  [Docs](https://developer.apple.com/documentation/translation/translationsession). All translation happens **on-device**; Apple states it
  collects only usage/performance metrics, not content. [Overview](https://www.createwithswift.com/using-the-translation-framework-for-language-to-language-translation/).
- Use for Heirloom: translating OCR'd text (receipts, signs, documents) or user-facing metadata
  without a server round-trip — nice complement to `RecognizeDocumentsRequest`.

### 7.3 Speech — `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26, WWDC25)
- New modular API (`import Speech`) distinct from the legacy `SFSpeechRecognizer`. `SpeechAnalyzer`
  is the session/coordinator object; you attach modules (e.g. `SpeechTranscriber`) that process audio
  from the point they're attached; modules can be swapped mid-session.
  [Docs](https://developer.apple.com/documentation/speech/speechanalyzer), [Bring advanced speech-to-text to your app (WWDC25, 277)](https://developer.apple.com/videos/play/wwdc2025/277/).
- New underlying speech-to-text **model** is explicitly positioned as better for **long-form,
  distant audio** (lectures, meetings) than the prior on-device model — directly applicable to
  transcribing Heirloom video audio tracks for search/captioning.
- Available across "all platforms but watchOS," with hardware caveats. **UNVERIFIED** exact minimum
  chip/RAM gate — check current doc page for the specific hardware table before finalizing a minimum
  supported device list.

### 7.4 Sound Analysis — `SNClassifySoundRequest`
- Built-in classifier trained on **300+ sound classes** (per Apple's own developer materials — animal
  sounds, human sounds like laughter/applause, etc.), returning multiple labels with independent
  confidence scores per analysis window (multi-label, not single-label). [Docs](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest), [challenge writeup](https://developer.apple.com/news/?id=zl9wxkjd).
- Custom classes are supported by supplying your own Core ML sound-classifier model to the same
  request type.
- Use for Heirloom: tagging video assets by audio content (e.g. "has singing," "has laughter," "has
  fireworks/crowd noise") as an additional Memories/highlight-reel signal alongside visual analysis.

---

## 8. Core Image, ImageIO, AVFoundation, Metal/MPS, Accelerate

### 8.1 Core Image
- `CIRAWFilter` — the modern RAW pipeline (superseding the older `CIFilter(imageURL:options:)`
  RAW-category filters), exposing ~20 calibrated properties (exposure, white balance, sharpness,
  noise reduction, boost, etc.) so Heirloom can render a consistent preview from ProRAW/RAW originals
  without shelling out to a third-party RAW decoder. [Docs](https://developer.apple.com/documentation/coreimage/cirawfilter). Apple's WWDC26 session
  ["Enhance RAW image processing with Core Image" (305)](https://developer.apple.com/videos/play/wwdc2026/305/) indicates continued investment here for
  2026 — check its content once available for anything new relevant to server-quality RAW rendering.
- Auto-enhance (`CIImage.autoAdjustmentFilters(options:)`) analyzes histogram, face regions, and
  metadata to propose a filter chain — a reasonable cheap "auto-fix" baseline distinct from Heirloom's
  own aesthetics-driven ranking.
- Core Image's RAW pipeline is explicitly documented as ANE-accelerated ("v9... using the Apple
  Neural Engine for optimal performance" per Apple's own session framing) — worth using over a
  hand-rolled decoder purely for the free hardware acceleration.

### 8.2 ImageIO — HDR gain maps, depth/portrait mattes
- `CGImageSourceCopyAuxiliaryDataInfoAtIndex` reads auxiliary payloads embedded alongside the main
  image in HEIC/JPEG containers. [Docs](https://developer.apple.com/documentation/imageio/cgimagesourcecopyauxiliarydatainfoatindex(_:_:_:)).
- Confirmed auxiliary data type keys: `kCGImageAuxiliaryDataTypeDepth`, `...TypeDisparity`,
  `...TypePortraitEffectsMatte`, and for HDR, **`kCGImageAuxiliaryDataTypeHDRGainMap`** (legacy Apple
  gain-map format) vs. **`kCGImageAuxiliaryDataTypeISOGainMap`** for the newer ISO 21496-1 standard
  gain-map format that current iPhones actually write — **use the ISO key for new captures**, fall
  back to the legacy key for older assets. [`kCGImageAuxiliaryDataTypeHDRGainMap` docs](https://developer.apple.com/documentation/imageio/kcgimageauxiliarydatatypehdrgainmap), [`kCGImageAuxiliaryDataTypeDepth` docs](https://developer.apple.com/documentation/imageio/kcgimageauxiliarydatatypedepth), [practical write-up on gain-map pitfalls](https://juniperphoton.substack.com/p/pitfalls-and-workarounds-when-dealing).
- This is the correct, direct way for Heirloom to detect **Portrait-mode depth data** and **HDR
  gain-map presence** (feeding "Portrait" / "HDR" smart-collection logic) rather than trusting
  `PHAsset.mediaSubtypes.photoHDR`, which per §1.1 appears unreliable on modern captures.
- General `CGImageSourceCopyPropertiesAtIndex` still remains the path for EXIF/TIFF/GPS/maker-note
  metadata (capture device, lens, exposure, GPS coordinates) — foundational for Heirloom's per-asset
  metadata extraction pipeline, unaffected by any of the AI-framework changes covered above.

### 8.3 AVFoundation
- `AVAssetImageGenerator` — extracts still keyframes from video (thumbnail generation,
  representative-frame selection for a Memory/highlight). [Docs](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator).
- **Spatial video / MV-HEVC** (iOS 17.2+/macOS 14.2+ APIs): spatial video stores **two tagged camera
  views** (left/right) multiplexed in one HEVC track. Reading both views requires configuring
  `AVAssetReaderTrackOutput` explicitly to request the `taggedBuffers` array — by default you only get
  the primary (single) view. [Deep dive](https://www.finnvoorhees.com/words/reading-and-writing-spatial-video-with-avfoundation/), [Apple guide: Converting side-by-side 3D video to MV-HEVC](https://developer.apple.com/documentation/AVFoundation/converting-side-by-side-3d-video-to-multiview-hevc-and-spatial-video). Relevant for Heirloom's
  "Spatial" media-type smart collection and for correctly generating a 2D preview thumbnail from
  spatial captures (must pick one eye, not decode both).
  Apple Immersive Video itself (visionOS-captured 4320×4320/eye @ 90fps content) is handled by a
  separate **ImmersiveMediaSupport** framework for its metadata — out of scope for iPhone/Mac capture
  but worth knowing exists if Heirloom ever ingests Vision Pro content. [WWDC25 session 403](https://developer.apple.com/videos/play/wwdc2025/403/).
- `AVAssetReader` remains the low-level frame/sample-buffer access API underlying all of the above —
  standard, unchanged in recent SDKs beyond the tagged-buffer addition for spatial video.

### 8.4 Metal / MPS / MPSGraph, Accelerate
Not independently re-searched this session (stable, well-documented APIs; no material WWDC
2023–2026 changes specific to Heirloom's use case surfaced in the searches performed). For
completeness: **Metal Performance Shaders (MPS)** and **MPSGraph** provide GPU-accelerated compute
graphs usable as a fallback/complement to Core ML for custom numerical pipelines (e.g. a hand-rolled
similarity search or histogram computation at scale); **Accelerate**'s `vDSP`/`BNNS` sub-frameworks
give CPU-vectorized primitives (fast dot-product/cosine-distance/Hamming-distance kernels) that are
the right tool for scoring thousands of on-device feature-print/embedding comparisons (e.g. local
duplicate clustering across a whole library) without round-tripping through Core ML for a simple
distance calculation. Recommend a dedicated follow-up pass if/when Heirloom's on-device dedup engine
design needs exact API signatures.

---

## 9. Location, Weather, Calendar, Contacts, Background execution, Thermal state

- **`CLGeocoder`** (Core Location) — on-device-first reverse geocoding (coordinate → place
  name/locality/country), the base primitive for Trip place-naming. [Docs](https://developer.apple.com/documentation/corelocation/clgeocoder). Developer-forum reports note
  inconsistencies between what Apple Maps itself shows and what `CLGeocoder`/`MKLocalSearch` return
  for POIs at the same coordinate — treat POI-level place names as best-effort, not authoritative.
  [Forum thread](https://developer.apple.com/forums/thread/781634).
- **`MKLocalSearch`** (MapKit) — point-of-interest search around a coordinate/region; the practical
  way to answer "what venue was this photo taken at" beyond a bare locality name, for Trip/Memory
  narration.
- **WeatherKit** — historical/current/predictive weather for a coordinate+date, useful for enriching
  Trip/Memory captions ("sunny day in Lisbon"). Free tier: **500,000 requests/month** included with
  an Apple Developer Program membership; paid tiers available beyond that.
  [Docs](https://developer.apple.com/documentation/weatherkit/) / [REST API docs](https://developer.apple.com/documentation/weatherkitrestapi). **Caveat found in developer forums**: at least one
  reported constraint limits a *historical* query window to **10 days per request** regardless of the
  requested start/end date span, and historical coverage reportedly only extends back to
  **around August 2021** for some data categories — both are forum reports, not confirmed by the
  primary WeatherKit doc page in this pass. **UNVERIFIED — treat as a real risk for a "weather at the
  time of decade-old photos" feature** and validate directly against the current WeatherKit REST API
  reference before depending on deep historical lookback. [Forum: 10-day limit](https://developer.apple.com/forums/thread/721786), [forum: historical availability](https://developer.apple.com/forums/thread/747160).
- **EventKit** — read calendar events (`EKEventStore`) to correlate a photo's timestamp/location with
  a named calendar event ("Sarah's Wedding", "Tokyo trip") for higher-quality Memory/Trip titles than
  geocoding alone can produce — standard API, unchanged in recent SDKs relative to this use case.
- **Contacts** — `CNContactStore` lets Heirloom let the user attach a real name (and photo, for a
  reference embedding) to a detected face cluster, matching Apple Photos' own People-naming UX;
  standard, stable API.
- **Background Tasks**:
  - `BGProcessingTask` (existing) — deferred, system-scheduled long-running background work; supports
    `requiresExternalPower` and `requiresNetworkConnectivity` constraints — the right primitive for
    "run the on-device analysis pipeline overnight while charging."
  - **`BGContinuedProcessingTask`** (new, iOS 26/iPadOS 26, WWDC25 session
    [Finish tasks in the background (227)](https://developer.apple.com/videos/play/wwdc2025/227/)) — a *different* model: a user-initiated,
    foreground-started task (e.g. tap "Analyze Library Now") that the system keeps alive into the
    background with a visible, cancellable system UI (Apple's own example: the Journal app's export
    flow). Unlike `BGProcessingTask`/`BGAppRefreshTask`, which are silent and system-scheduled at the
    system's discretion, this is for tasks with an explicit, user-visible start and progress — a good
    fit for a Heirloom "analyze now" button distinct from its passive overnight sync. [Docs](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask).
  - **UNVERIFIED** in this pass: `BGProcessingTask.requiresExternalPower`'s exact availability/OS
    version and any WWDC 2025/2026 changes to `BGProcessingTask` itself beyond the new sibling API —
    the search results didn't surface confirmation either way; treat the existing (pre-26) contract as
    unchanged unless proven otherwise.
- **`ProcessInfo`** — `thermalState` (`.nominal`/`.fair`/`.serious`/`.critical`) and
  `isLowPowerModeEnabled` remain the standard signals for throttling/pausing an on-device analysis
  pipeline gracefully; not independently re-searched this session (stable, long-standing API with no
  material recent changes surfaced).

---

## 10. Private frameworks Apple Photos uses internally

These are **not usable in an App Store app** (no public headers/entitlements) — listed so Heirloom's
team understands what Apple's own pipeline looks like and can pick the closest public substitute:

| Private component | What it does (from process/forensic observation) | Closest public substitute for Heirloom |
|---|---|---|
| `photoanalysisd` | Background daemon that runs Photos' analysis passes (Memories generation, People/scene recognition orchestration) when the device is idle/charging | `BGProcessingTask` + Vision/Core ML, scheduled by Heirloom itself |
| `mediaanalysisd` | Runs the actual on-device ML inference for face recognition and Spotlight-relevant media indexing | Vision (`DetectFaceRectanglesRequest`/`DetectFaceLandmarksRequest`) + a custom face-embedding Core ML model (§3.1) |
| `photolibraryd` | Core Photos-library management daemon (asset storage, sync state) | PhotoKit (`PHPhotoLibrary`, `PHAsset`) is the public front door to this |
| "PhotosGraph" (`photosgraph.graphdb`, observed in system logs) | Apple's internal knowledge-graph store correlating people/places/events/moments for Memories | No public equivalent — Heirloom must build its own graph/DB (e.g. server-side relational model linking people, places, trips, events) |
| "PhotosIntelligence" / "MediaAnalysis"/"CoreKnowledge"/"VisionCore"/"Espresso" (named in the task prompt) | Apple's internal ML-inference stack naming (Espresso is Apple's historically-known internal neural-net inference engine, predates/underlies Core ML in some contexts) | **UNVERIFIED** — this session's searches did not turn up independent, current confirmation of "PhotosIntelligence," "CoreKnowledge," or "VisionCore" as distinctly named internal frameworks (vs. being informal/inferred names); do not cite these as confirmed framework names without further reverse-engineering-community sourcing (e.g. a jailbreak-community dyld shared-cache framework listing) if precision matters for a document going outside the team. Core ML / Vision are the safe public-facing terms to use in any external-facing Heirloom documentation. |

General takeaway: Apple's own Photos app is not using any secret *capability* Heirloom lacks access
to — it's using the **same class of models** (face embeddings + clustering, scene classifiers, LLM
summarization) that Heirloom can approximate with Vision + a custom Core ML face model + Foundation
Models, just wired together with private orchestration and a proprietary knowledge-graph store that
Heirloom will need to build its own version of (this is core, expected product work, not a
gap Apple could hand over).

---

## 11. How Apple Photos builds Memories and Trips (published research + observed behavior)

- **People recognition**: Apple's own 2021 ML-research post, ["Recognizing People in Photos Through
  Private On-Device Machine Learning"](https://machinelearning.apple.com/research/recognizing-people-photos), describes the iOS 15-era pipeline: detect faces *and upper bodies*
  on-device, encode each into a compact embedding, and **cluster** similar embeddings into likely
  identities — explicitly designed to keep matching people whose face isn't visible (turned away,
  occluded) by falling back to body/clothing embedding similarity. All computation is on-device; nothing
  is uploaded for training. This is the direct blueprint for Heirloom's own face+body clustering
  design (§3.1) — same conceptual pipeline (detect → embed → cluster), different (must self-supply)
  models. [Additional summaries](https://www.louisbouchard.ai/how-apple-photos-recognizes-people/), [MarkTechPost coverage](https://www.marktechpost.com/2021/07/28/apple-explains-its-new-on-device-machine-learning-methods-to-recognize-people-in-photos-with-extreme-poses-accessories-correctly-or-even-occluded-faces/).
- **Trips**: Apple has not published a research paper on trip-detection specifically; Apple Support
  documentation ([Find your travel photos on iPhone](https://support.apple.com/guide/iphone/find-your-travel-photos-and-videos-iph7cce5d7a2/ios), [on Mac](https://support.apple.com/guide/photos/find-your-travel-photos-and-videos-phtacde28864/mac)) only describes the
  user-facing behavior: Photos groups travel photos/videos into automatically-detected Trip
  collections **based on location data**. User-reported behavior (not an Apple spec) on Apple's own
  community forums indicates the underlying heuristic is essentially **away-from-home location
  clustering over a contiguous time window**, with known rough edges: it does not distinguish a
  *former* home address from "away," long road trips can get fragmented into separate trips per
  stopover rather than one trip, and it can be noisy for people who move frequently.
  [Community thread](https://discussions.apple.com/thread/255713589). For Heirloom's own Trip-detection design,
  the practical algorithm to replicate is: (1) establish a "home" cluster from the density of
  low-movement location samples over time, (2) segment the timeline into contiguous
  away-from-home intervals above a minimum distance/duration threshold, (3) merge/split intervals
  using a gap-tolerance window (to avoid fragmenting one trip with several stops), (4) name each
  segment via `CLGeocoder`/`MKLocalSearch` reverse geocoding of its centroid/hull, optionally refined
  with `EventKit` calendar-event overlap and Foundation-Models-generated titles.
- **Memories** more broadly (curated, mixed-theme collections, not just trips) are understood (from
  Apple's own feature descriptions, not a published algorithm) to combine: scene/object classification
  clustering (holidays, pets, specific people, recurring anniversaries/"this day"), the
  aesthetics/quality signal to pick which photos actually make the cut, and templated
  narrative/music generation. No Apple research paper covers the full Memories pipeline end-to-end;
  the People paper (above) is the only piece Apple has formally published. Treat the rest of
  Memories' design as informed inference from observed app behavior, not documented fact —
  **UNVERIFIED** beyond what's stated here.

---

## 12. Capability → best public API summary table

| Heirloom capability | Best public API | Min OS | Platforms | Notes / limits |
|---|---|---|---|---|
| Media-type classification (screenshot, live, portrait, cinematic, spatial, slo-mo, panorama, RAW, burst) | `PHAsset.mediaSubtypes` (`PHAssetMediaSubtype`) + `PHAssetCollectionSubtype` smart albums | iOS 8+ (subtypes vary by year; spatial/cinematic iOS 17+) | iOS, iPadOS, macOS (Catalyst/PhotoKit-on-Mac) | `.photoHDR` unreliable on modern gain-map HDR — verify via ImageIO instead |
| Favorites / Hidden | `PHAsset.isFavorite` / `.hidden` | iOS 8 / iOS 8 | iOS, macOS | Direct 1:1 |
| Incremental library sync | `PHPersistentChangeToken` + `fetchPersistentChanges(since:)` | iOS 16 / macOS 13 | iOS, iPadOS, macOS | Survives relaunch/reboot, unlike live `PHChange` |
| Cross-device asset identity | `PHCloudIdentifier` | iOS 15 / macOS 12 | iOS, macOS | Requires iCloud Photos on |
| Background photo backup (system-managed) | `PHBackgroundResourceUploadExtension` | iOS 26.1 (beta at time of writing) | iOS | Verify GA shape before architecting around it |
| Near-duplicate detection | `GenerateImageFeaturePrintRequest` / `VNGenerateImageFeaturePrintRequest` + distance | iOS 13+ (Swift API iOS 18+) | iOS, iPadOS, macOS, tvOS, visionOS | Pin a revision; ~0.4–0.6 distance is an empirical (not Apple-documented) similarity cutoff |
| Scene/object classification | `VNClassifyImageRequest` | iOS 12.1+ | iOS, iPadOS, macOS, tvOS, visionOS | ~1303-label taxonomy (Revision1) |
| Face detection/landmarks/quality | `DetectFaceRectanglesRequest` / `DetectFaceLandmarksRequest` / `DetectFaceCaptureQualityRequest` | iOS 11 / 11 / 13 | iOS, iPadOS, macOS, tvOS, visionOS | No identity output — see next row |
| Face identity / person clustering | **No Apple API** — bring your own Core ML face-embedding model (e.g. ArcFace via coremltools) on Vision-aligned face crops | n/a | n/a | Biggest custom-build gap in the whole stack |
| Aesthetics / "best shot" / utility-photo flag | `CalculateImageAestheticsScoresRequest` | iOS 18 | iOS, iPadOS, macOS | `isUtility` directly flags screenshot/receipt/document-like captures; device-only, no Simulator |
| Documents / receipts / handwriting / tables | `RecognizeDocumentsRequest` | iOS 26 | iOS, iPadOS, macOS | Structured paragraphs/tables/lists/barcodes in one pass, 26 languages |
| OCR (plain text) | `VNRecognizeTextRequest` (Revision 3) | iOS 13+ (Rev3 iOS 16+) | iOS, iPadOS, macOS, tvOS, visionOS | Same recognizer as system Live Text |
| QR / barcodes | `VNDetectBarcodesRequest` (Revision 3 = ML-based) | iOS 11+ (Rev3 iOS 15+) | iOS, iPadOS, macOS, tvOS, visionOS | Query `supportedSymbologies` at runtime |
| Subject lifting / instance segmentation | `VNGenerateForegroundInstanceMaskRequest`, or VisionKit `ImageAnalysisInteraction` for the interactive UI | iOS 17 | iOS, iPadOS, macOS | Device-only, no CPU/Simulator fallback |
| Person-only segmentation | `VNGeneratePersonSegmentationRequest` / `VNGeneratePersonInstanceMaskRequest` | iOS 15 / iOS 17 | iOS, iPadOS, macOS | |
| 2D/3D body pose | `DetectHumanBodyPoseRequest` / `VNDetectHumanBodyPose3DRequest` | iOS 14 / iOS 17 | iOS, iPadOS, macOS, tvOS | 3D works without LiDAR |
| Animal detection/pose | `VNRecognizeAnimalsRequest` / `VNDetectAnimalBodyPoseRequest` | iOS 13 / iOS 17 | iOS, iPadOS, macOS, tvOS, visionOS | |
| Lens-smudge / hazy capture flag | `DetectLensSmudgeRequest` | iOS 26 | iOS, iPadOS, macOS | New — repurpose for "blurry/hazy" quality signal |
| CLIP-space embedding on-device | Apple **MobileCLIP/MobileCLIP2** Core ML export | n/a (Core ML, any recent iOS/macOS) | iOS, iPadOS, macOS | **License is research-only (`apple-ascl`) — legal review required before shipping**; verify checkpoint compatibility with server's CLIP index |
| Text/caption embeddings on-device | `NLContextualEmbedding` | iOS 17+ (verify) | iOS, iPadOS, macOS | Per-token output; pool yourself for a sentence vector |
| On-device translation | `Translation` / `TranslationSession` | iOS 18 | iOS, iPadOS, macOS | Fully on-device |
| Video/audio speech transcription | `SpeechAnalyzer` + `SpeechTranscriber` | iOS 26 | iOS, iPadOS, macOS (not watchOS) | Better long-form/distant-audio model than legacy `SFSpeechRecognizer` |
| Video sound tagging (laughter, music, etc.) | `SNClassifySoundRequest` | iOS 13+ | iOS, iPadOS, macOS, tvOS, watchOS | 300+ built-in classes, multi-label |
| RAW rendering / auto-enhance | `CIRAWFilter` / `autoAdjustmentFilters` | iOS 10+ (RAW filter revisions ongoing incl. WWDC26) | iOS, iPadOS, macOS | ANE-accelerated |
| HDR gain map / depth / portrait matte extraction | `CGImageSourceCopyAuxiliaryDataInfoAtIndex` + `kCGImageAuxiliaryDataType*` keys | iOS 11+ (ISO gain map key newer) | iOS, iPadOS, macOS, tvOS | Use ISO gain-map key for current captures, legacy key as fallback |
| Spatial video (MV-HEVC) frame access | `AVAssetReaderTrackOutput` with `taggedBuffers` | iOS 17.2 / macOS 14.2 | iOS, iPadOS, macOS | Must explicitly request tagged buffers for both eyes |
| Memory/Trip title & summary generation | `FoundationModels` (`@Generable`/`@Guide`) | iOS 26 | iOS, iPadOS, macOS | Text-only until iOS 27 (image attachments new in 27); Apple-Intelligence-eligible devices only |
| Reverse geocoding / trip place naming | `CLGeocoder`, `MKLocalSearch` | iOS 5+ / iOS 6+ | iOS, iPadOS, macOS | POI coverage can be inconsistent with Apple Maps itself |
| Historical weather for Memories | `WeatherKit` | iOS 16+ | iOS, iPadOS, macOS, watchOS, tvOS | 500K free requests/mo; **historical lookback window/depth unverified — check before relying on old-photo weather** |
| Overnight/charging background analysis | `BGProcessingTask` (`requiresExternalPower`) | iOS 13+ | iOS, iPadOS | System-scheduled, silent |
| User-initiated "analyze now" with visible progress | `BGContinuedProcessingTask` | iOS 26 | iOS, iPadOS | New; foreground-started, system-continued |

---

## 13. Summary of UNVERIFIED items requiring direct doc/device confirmation before Heirloom design lock

1. Exact `VNFeaturePrintObservation` `elementCount`/`elementType` per feature-print request revision.
2. `VNDetectAnimalBodyPoseRequest` joint count/taxonomy.
3. `NLContextualEmbedding` exact dimensionality (512) and sequence length (256) — third-party sourced.
4. `SpeechAnalyzer`/`SpeechTranscriber` exact minimum hardware requirements.
5. `BGProcessingTask.requiresExternalPower` current OS-version gate and any 2025/2026 changes.
6. WeatherKit historical query window (10-day-per-request cap) and lookback depth (~Aug 2021 origin) — both forum-sourced, not confirmed on the primary WeatherKit doc page this session.
7. `PHBackgroundResourceUploadExtension` final shape/entitlements at iOS 26.1 GA (was beta/evolving at last check).
8. Existence/naming precision of "PhotosIntelligence"/"CoreKnowledge"/"VisionCore" as literal internal Apple framework names (vs. informal/inferred labels).
9. Apple's WWDC 2026 "Core AI" framework's actual scope/relationship to Core ML — based on early third-party reporting on a pre-GA SDK.
10. Whether MobileCLIP's Apple Machine Learning Research Model license permits Heirloom's commercial self-hosted use case — needs explicit legal review, not just a license-name lookup.
11. Immich server's current CLIP checkpoint/architecture, to confirm (or rule out) embedding-space compatibility with an on-device MobileCLIP encoder.
