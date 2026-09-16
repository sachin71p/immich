# A9 plan — Photos-like extras, dependency-ordered

Goal: 7 extras in disjoint sub-dispatches (per phases/A9-extras.md).
A9.1–A9.4 parallel-safe; A9.5–A9.7 iOS-only, parallel-safe.

Dependency status:
- Server READY: memory.controller, map.controller, person/face/tag
  controllers; WireTypes.livePhotoVideoId; MediaEndpoint.videoPlaybackURL
  + livePhotoMotionURL; LocalStore memory/memoryAsset/person/face tables.
- A8 link: only A9.1-video-trim/Live-trim touches A8 VideoTrim; rest need
  A8 only for "edit" entry points, not for build order — sequence A9.4,
  A9.3, A9.2, A9.1 first, A8-dependent polish last.

Order + targets:
1. A9.4 Map FIRST (no A8 need): `Apps/{iOS,macOS}/Sources/*Map*.swift`
   (new) — MapKit clusters from map controller + selection grid.
2. A9.3 Memories (no A8 need): `Apps/*/Sources/*Memor*.swift` (new) —
   story player + "On this day" from memories API + memory tables.
3. A9.2 Live Text (no A8 need): extend ViewerPage/MacViewerView —
   VisionKit ImageAnalysisInteraction / OverlayView + subject lift.
4. A9.1 Live/video (A8-adjacent): extend VideoPage + MacViewerView —
   PHLivePhotoView, AVKit scrub/HDR/stream; trim/mute reuses A8.
5. A9.5 Widgets (iOS): `Apps/iOS/Widgets/*` (new target) — snapshot
   from LocalStore via app group.
6. A9.6 Share+Intents (iOS): `Apps/iOS/{ShareExtension,Intents}/` (new
   targets) — "Save to <library>", upload/open-search intents.
7. A9.7 Photo-editing ext EXPERIMENTAL (iOS): `Apps/iOS/PhotoEditExt/`
   (new target) — asset-id XMP/EXIF marker → fetch original → output.

Acceptance: per sub-phase core unit test + one UI smoke;
`bash native-apple/scripts/verify.sh all` green.

Open questions: A9.7 placeholder-marker format + orchestrator go-ahead
(experimental)? Widget snapshot refresh policy? Map scope = S5 helper?
Music for memories default off — confirm no licensing work.
