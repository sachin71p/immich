# WP5 Report — Viewer: paging, rotation, title, inspector, video/live (both slices)

Branch `perf/heirloom-macos-wp5`, worktree `/Users/spatel/workspace/github/projects/immich-wp5`.
Base `ba723d981` (slice 1). No destructive action was run against the real library:
no UI was driven in this session at all (build + package tests only).

## Commits

Slice 1 (prior session, `ba723d981` — summarized from the commit + code):
- `feat(macos): WP5 slice 1 — viewer paging, instant open, preload, keyboard`
  (`MacViewer.swift`, `MacMainWindow.swift` +6): clamped paging through `viewerContext`
  display order (no wrap, affordances disabled at ends, local one-element fallback snapshot);
  instant open (sync memory-cache thumbnail → preview stream → fullsize past 1.5× or when
  window pixels exceed preview, never blanking); neighbor ±2 prefetch 100 ms after settle
  with `cancelPrefetch(keeping:)`; Esc/Space/⌘I/⌘. keyboard handling with viewer focus claim;
  favorite/trash/lock posting `MacAssetChange` and advancing past removed rows.

Slice 2 (this session):
- `031ba97d3` `feat(photoscore): WP5 slice 2 — ExifSummary read-only inspector query`
  (new `PhotosCore/Sources/LocalStore/LocalStore+Exif.swift`).
- `bfb213df4` `feat(macos): WP5 slice 2 — rotation persist+refit, title, mutation posts`
  (`MacViewer.swift`).
- `17d99dfb5` `feat(macos): WP5 slice 2 — Photos-style inspector, inline video, live badge`
  (new `MacInspectorView.swift`, `MacLiveVideo.swift`, regenerated `project.pbxproj` entry).

## What changed (slice 2, items 4,5,6,7,9,10)

- **Item 4 rotation.** `persistRotationIfEnabled()` kept its exact hook name and is now wired to
  the WP4-decided PERSISTABLE path: fetch stored recipe (404 → fresh, other errors abort),
  bump `crop.quarterTurns`, full merged `EditSplitter.split` against the store's width/height
  (no original download), `applyUpstreamEdits` (or `clearUpstreamEdits` when the 4th turn wraps
  to zero), `saveRecipe` preserving `renderedAssetId`, post `MacAssetChange.edited(ids:)`, then
  re-stream preview. Display uses quarter-turn state with a swapped-aspect re-fit scale for
  90°/270° (animated 0.2 s), reset on every page change. Rotate button disabled for videos
  per the WP4 decision (their rotation is a `VideoRecipe` client export).
- **Item 5 title.** Window title is the capture date (`date: .long`); subtitle is time plus
  place (`time · ExifSummary.placeString`). Filename moved to the inspector.
- **Item 6 inspector.** New `MacInspectorView` (⌘I): read-only caption, date/time, camera
  (make/model/lens/ƒ/exposure/ISO/focal), file (dimensions, MP, size, name, kind+HDR badges
  from `MediaFormatInfo.classify`), location place + `MKMapSnapshotter` snapshot cached per
  asset in a static `NSCache` with a composited pin, library/owner + favorite. EXIF comes from
  new `exifSummary(assetId:)` (wraps existing `exif(for:)`; column names match `Schema.swift`
  `v1_assets_exif`). `MacInfoPanel` deleted; only caller was the viewer.
- **Item 7 mutations.** Move sheet completion posts `.removedFromCurrentContexts(moved)` and
  advances when this asset moved out; add-to-album posts `.albumsChanged` — same posts as the
  grid's sheets. Favorite/trash/lock already posted from slice 1. Delete asks for **no**
  confirmation: current behavior is soft-delete (`force: false`) with the server trash, same as
  the grid's delete ("Moved to Recently Deleted.").
- **Item 9 video/live.** `AVPlayerView` `.inline` controls (custom mute bar removed; Trim stays
  as the editor handoff). Player setup is a per-asset task: paging away cancels it, pausing the
  old player; `onDisappear` pauses and releases. LIVE badge moved onto the live-photo page:
  hover bumps a tick that replays the motion hint, long-press still plays full (existing
  `PHLivePhotoView` + press recognizer kept).
- **Item 10 Live Text.** Toggle disables for videos; flipping it on after load re-analyzes the
  displayed (preview-tier) image. Overlay architecture unchanged (`MacLiveText.swift` untouched).

## Test results

- `make build-macos CONFIGURATION=Release`: **BUILD SUCCEEDED** (only the pre-existing
  `SyncEngine missing dependency on Media/Nuke` warnings). Two slice-2 errors were fixed
  along the way: `Duration.hours` → `.seconds(24*3600)`; `MKMapSnapshotter.Snapshot`
  crossing a continuation → composite synchronously, transfer TIFF `Data`.
- `swift test --package-path native-apple/PhotosCore`: **158 tests / 21 suites, all pass**.
- No UI was driven here; per the brief, no move/trash/lock was confirmed on any library.

## Deviations from WP5-VIEWER.md

1. Caption/title are **read-only**, not editable: the server bulk-update DTO accepts a
   description, but `AssetMutations` exposes no description write and WP5 may not edit files
   outside its owned set — reported, not changed. Needs a follow-up (`AssetMutations`
   + local write, owned by whoever owns `SyncEngine`/`LocalStore+Mutations`).
2. **People names omitted**: WP1 reported no per-asset face-name query (only `peopleSummaries`
   + `personThumbnail`), so per the brief's condition the section stays out. The `face` table
   exists in the mirror; a read-only `LocalStore+Faces.swift` could wire this later.
3. The hook name `persistRotationIfEnabled()` matched the code, so no rename to report.
4. No new tests added: owned scope lists source files only, and existing suites cover the
   touched PhotosCore surface (new wrapper has no logic beyond projection).

## Open issues / how WP7 should check

- Hands-on acceptance still needs a host run (Release install, fixture or real library):
  → then ← returns to the same photo; 50-photo fast paging with no blanks; rotation stays
  in bounds and survives a viewer close/reopen (server recipe); inspector shows EXIF for a
  JPEG with EXIF, a map pin for a geotagged photo, and "No description" otherwise; video
  audio stops on page-away; LIVE hint plays on badge hover.
- Known WP4 limitation applies: rotating a source with an existing rendered upload leaves
  the rendered copy stale (link preserved, not re-rendered).
- `MKMapSnapshotter.start` completion is assumed main-thread (Apple documents main-thread
  delivery); compositing runs synchronously inside it, so a background delivery would only
  risk AppKit-off-main drawing, never a data race (only `Data` crosses the continuation).
