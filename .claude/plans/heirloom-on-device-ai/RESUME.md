# Heirloom on-device AI — resume point (paused 2026-09-17)

## Owner's request (verbatim intent)
- Use iPhone + Mac on-device Apple ML (Neural Engine) to analyze the whole library: duplicates,
  people, smart collections (iOS Photos Utilities + Media Types + Trips), Memories.
- Routing: iPhone-originated photos → processed on iPhone; Mac-uploaded → on Mac; existing /
  web-uploaded → device chosen in settings (ios | macos | heirloom server).
- Asset record stores which device processed its AI (ios/macos/server).
- Results sync/upload to Heirloom server and are written to the Heirloom DB.
- Deliverables: (1) list of all Apple photo/video/AI frameworks + APIs, (2) plan to use them in
  Heirloom iOS + macOS apps, (3) CloudKit feasibility for photo/metadata sync across devices + server.

## Done
- recon-codebase.md — scout (haiku). NOTE: its claim that iOS/macOS 27 deployment targets are a
  "typo" is WRONG; iOS/macOS 27 is the current release. Ignore that note.
- research-apple-frameworks.md — sonnet. Framework catalogue + capability→API table + UNVERIFIED list.
- research-cloudkit.md — sonnet. Verdict: server stays source of truth; CloudKit private DB is not
  usable from the server (per-user web token, 30 min / 2 wk), breaks with multi-Apple-ID families,
  and conflicts with ADP. At most an optional device-to-device side channel.

## Key facts to carry into the plan
- Apps: native-apple/Apps/{iOS,macOS}, shared pkg native-apple/PhotosCore (ImmichAPI via Swift
  OpenAPI Generator, SyncEngine, Upload, Search…). No CloudKit entitlement. No Core ML models yet.
- Server: CLIP 512-d (smart_search), face 512-d (face_search, buffalo_l), asset_face.sourceType,
  asset.duplicateId, asset_ocr, memory tables. No processedBy field yet.
- Vision has NO face-identity embedding → need a Core ML face model. To stay compatible with the
  server, export the same buffalo_l ArcFace + the same CLIP model to Core ML so vectors match the
  server's embedding space (otherwise mixed-provenance vectors aren't comparable). MobileCLIP
  license = research-only → legal check before shipping.
- PhotoKit exposes Media Types via mediaSubtypes/smart albums; Utilities (Duplicates, Receipts,
  Handwriting, QR, IDs, Documents), People, Memories, Trips are private → must rebuild.
- Useful: CalculateImageAestheticsScoresRequest (isUtility), RecognizeDocumentsRequest (iOS 26),
  feature prints, PHPersistentChangeToken, PHCloudIdentifier, BGContinuedProcessingTask,
  PHBackgroundResourceUpload(Job)Extension (static URL-base problem for self-hosted),
  Foundation Models (image input iOS 27) for titles/captions.

## Next step
Opus: read the three reports and write PLAN.md (architecture, DB schema changes incl.
asset.aiProcessedBy + model-version columns, device routing/leases, pipeline per capability,
phased work packages), then send the framework list + plan to the owner.
