# A9 — Photos-like extras (both platforms unless noted)

Depends on: A8 · Reads: A0 Architecture+Rules. Split into sub-dispatches (one implementer each) — they touch
disjoint code: A9.1–A9.4 parallel-safe; A9.5–A9.7 iOS-only, parallel-safe with each other.

- A9.1 Live Photos & video: `PHLivePhoto` from downloaded still + motion files (`PHLivePhotoView` iOS/macOS),
  long-press/hover to play; AVKit player with scrubbing, HDR, streaming from server playback URL.
- A9.2 Live Text & Visual Look Up: VisionKit (`ImageAnalysisInteraction` iOS / `ImageAnalysisOverlayView` macOS)
  on preview/original; subject lift copy.
- A9.3 Memories & For You: upstream memories API → story player (auto-advance, music optional off), "On this day".
- A9.4 Map/Places: MapKit with clustered markers (server map markers respecting scope) + grid of selection.
- A9.5 (iOS) Widgets: memories/favorites widget from LocalStore snapshot (app group).
- A9.6 (iOS) Share extension "Save to <library>" and App Intents/Shortcuts (upload to library, open search).
- A9.7 (iOS) Photo Editing Extension "Get full quality": inside Apple Photos, for an asset whose file carries our
  asset-id marker (XMP/EXIF written by an optional "placeholder" mode), fetch the original from the server and
  return it as the rendered output. Mark as experimental; document limits (shows as Edited, RAW not preserved).

## Tests
Per sub-phase: core logic unit tests + one UI smoke. Verify: `native-apple/scripts/verify.sh all`.
