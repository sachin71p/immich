# Heirloom macOS vs Apple Photos — captured evidence (2026-09-17)

Machine: owner's MacBook Pro, macOS 27.0 (Darwin 27.0.0), display 1728×1117 pt (3456×2234 px).
Heirloom: `/Applications/Heirloom-macOS.app` (display name "Heirloom", bundle `com.immich.heirloom.macos`),
installed 09:32 from `feat/shared-libraries` @ `9b9bb7f2e`. Library: 80,358 photos + 22,271 videos.
Photos: Apple Photos (macOS 27), iCloud Photos library + Shared Library.

All media is under `evidence/` and is **git-ignored** (it contains the owner's personal photos). Never commit
it, upload it, or paste it into a PR.

## Files

| Path | What |
|---|---|
| `evidence/video/REF-photos-trackpad-swipe.mp4` | **The swipe reference.** Owner's real two-finger swipes in the Photos viewer: slow, fast, partial with snap-back, and reverse |
| `evidence/video/CUR-heirloom-trackpad-swipe.mp4` | Same gestures in Heirloom: hard cuts, no tracking; ends stuck on a video |
| `evidence/video/REF-photos-pinch-zoom-close-open.mp4` | Photos: pinch zoom anchored at the cursor, pan, pinch-in past fit closes to the grid, pinch-out on a grid cell opens it, smart-zoom double-tap |
| `evidence/video/CUR-heirloom-pinch-doubletap.mp4` | Heirloom: pinch and double-tap do nothing |
| `evidence/video/REF-photos-grid-scroll-pinch.mp4` / `CUR-heirloom-grid-scroll-pinch.mp4` | Trackpad scroll, flicks and grid pinch-zoom (owner's hands) |
| `evidence/video/REF-photos-cold-launch.mp4` / `CUR-heirloom-cold-launch.mp4` | Cold launch from `open -a` (at t≈0.5 s in each clip) |
| `evidence/video/FULL-*.mp4` | Full walkthroughs: Heirloom 14 min, Photos 6 min, Photos photo edit |
| `evidence/photos-screens/*.png` | Photos: Library (All Photos / Months / Years / min zoom), search results, Collections, Map, album, edit mode (Adjust, Light options, Styles, Crop, Tools) |
| `evidence/heirloom-screens/*.png` | Heirloom: Library (Months), Years (shows a month grid), Collections (all zero) |
| `evidence/frames/*.png` | Contact sheets and slit-scans derived from the videos |
| `evidence/traces/stuck-library.sample.txt` | `sample` during the 2-minute Library reload stall |
| `evidence/traces/blank-grid.sample.txt` | `sample` while the grid was blank after closing the viewer (app idle) |
| `evidence/traces/heirloom-launch.trace` | Instruments App Launch (5.3 GB; launched via the raw binary, so the window didn't appear; low value) |

Instruments caveat: the Animation Hitches traces for Heirloom came out empty or failed. The kperf lock was
contended by parallel Xcode UI-test sessions (iOS WP2–WP5 worktrees), and one trace ran away to 250 GB and
was deleted. Frame-rate numbers below therefore come from 60 fps screen recordings
(`ffmpeg mpdecimate`: visually changed frames per second). They are approximate. WP-X must re-trace on a
quiet host.

## Measurements (n=1 unless noted)

| Metric | Apple Photos | Heirloom (today) |
|---|---|---|
| Cold launch → thumbnails visible | ~2.9 s (the sidebar and grid appear together) | ~7 s. Sequence: window 0.8 s → **"Connect to server" screen flashes ~1.5 s** → Library chrome with **"0 Photos, 0 Videos"** for ~4 s → spinner → grid |
| Return to Library from another page | instant | **18 s and ~120 s** (n=2). `sample`: GRDB reader in `PhotosLocalStore.timelineRows` (LocalStore+Timeline.swift:241) → `sqlite3_step`, called from `MacGridLoader.timelineSections` (MacGridLoader.swift:320) |
| Media-type / shared-library / shared-album pages | < 1 s | Videos (22 k) ≈ 15–20 s; Screen Recordings (23 items) 5–20 s; Family and a 1-item shared album still spinning at 8 s |
| Grid scroll, changed frames/s during trackpad scroll and flicks | median ≈ 52 (48–60) | median ≈ 22 (5–55); blurred placeholders visible mid-flick; blank gap during grid pinch |
| Viewer swipe | 1:1 tracking, ~95 % of frames change during swipes | 0 tracking frames; hard cut once travel exceeds the threshold |
| Photo edit open | chrome instant; full-quality original ready in ~2.5 s (spinner bottom-right; iCloud download) | modal sheet; the first click on Edit was ignored; ~4 s total |
| Memory footprint | 1.70 GB (running 29 h) | 709 MB (running 45 min) |
| CPU idle | ~1 % | 0 % |

## Interaction reference: what Photos does (from the videos)

1. **Horizontal trackpad swipe in the viewer**
   - The photo follows the fingers 1:1, and the neighbour slides in from the edge with a small white gap.
   - On release it either commits (a flick, or travel past about 50 %) or springs back. The settle is a
     critically damped spring of about 0.3 s.
   - A partial swipe springs back.
   - Direction is natural: two fingers leftward = next.
   - Several flicks in a row chain without waiting for the previous settle.
   - At the first or last item the photo rubber-bands.
   - While zoomed in, the scroll pans first and pages only once the photo edge is reached.
2. **Pinch in the viewer**
   - Zoom is continuous and anchored at the cursor (up to about 8×).
   - Two-finger scroll pans while zoomed.
   - Pinching in to fit and continuing **closes the viewer**: the photo shrinks back into its grid cell,
     which the owner saw as "zoom out to grid".
3. **Pinch-out on a grid cell** opens that photo, growing from its cell. The reverse closes it.
4. **Two-finger double-tap (smart magnify) or double-click** toggles between fit and a ~2× zoom at the pointer.
5. **Keys:**
   - ←/→ page with the same slide animation.
   - Space closes the viewer.
   - Return opens Edit.
   - `.` toggles Favorite.
   - ⌘R rotates left, ⌥⌘R rotates right.
   - ⌘E runs Auto Enhance.
   - ⌘D duplicates, ⌘L hides, ⌘⌫ deletes.
   - Z toggles zoom, ⌘+/⌘− zoom in/out.
6. **Hover near the left or right edge** shows a chevron button to go to the previous or next photo.
7. **Grid pinch** changes the zoom level continuously, anchored at the pinch. It has ~6 levels, down to a
   dense mosaic.

## Visual reference: Photos screens

- **Library.**
  - Content scrolls *under* a translucent glass toolbar.
  - Top left shows the title "Library" plus a date-range subtitle.
  - Toolbar, left to right:
    - sidebar toggle;
    - library-scope icon menu (Both / Personal / Shared);
    - zoom capsule (− | +);
    - Years/Months/All Photos segmented control;
    - Filter icon menu (Show: Screenshots, Shared with You);
    - Sort/arrange icon;
    - "…" menu;
    - Info, Share, Favorite, Rotate;
    - Search field.
  - The Shared Library suggestion banner appears top right ("Review / Not Now").
- **All Photos.** A continuous grid; the date-range title floats over the content, and there are no
  per-section headers. Square-crop is the default; View › Aspect Ratio Grid (⌥T) switches it.
- **Months.** Large "moment" cards, each with a title and location over a hero photo.
- **Years.** One large card per year with its key photo. Clicking a card drills into Months; clicking a
  month card drills into All Photos, scrolled to that month.
- **Grid selection.** A single click selects (blue ring); there is no Select mode. Double-click opens the photo.
- **Sidebar:**
  - Library, Collections.
  - **Pinned:** Favorites, Recently Saved, Map, Videos, Screenshots, People & Pets, Recently Deleted
    (with a lock). Owner-customizable.
  - **Albums:** All Albums, then user albums with thumbnail icons.
  - **No** Search item: search lives in the toolbar.
- **Collections.** A vertical page of horizontally scrolling, collapsible shelves. Each header has a "›"
  (drill in) and a chevron (collapse). The shelves:
  - **Memories:** large 16:9 cards with a Play button.
  - **Pinned:** tiles with real key photos.
  - **Albums.**
  - **People:** face tiles with names.
  - **Featured Photos.**
  - **Shared Albums**, with an empty-state card.
  - **Recent Days:** day cards.
  - **Trips.**
  - **Media Types:** a list with counts (Videos, Selfies, Live Photos, Portrait, Slo-mo, Cinematic,
    Bursts, Screenshots, Screen Recordings, RAW).
  - **Utilities:** a list with counts (Favorites, Captured by Me, Recently Edited, Map, Recently Deleted,
    Recently Saved, Recently Shared, Duplicates, Recently Viewed, Imports).
- **Search.** Typing in the toolbar field opens a suggestion popover:
  - before typing: Recently Viewed / Edited / Shared;
  - while typing: completions with counts, e.g. "Beach 1,300+", "Miami Beach 493".
  - Return shows a results page titled "Search" with a Photos | Collections segmented control, a
    "Top Results" row, and then "1,421 Results".
- **Map.** Full-bleed map under the glass toolbar, with a Map/Satellite/Grid segmented control and a
  search field. Photo clusters are rounded thumbnail pins with count badges, and there are zoom buttons.
- **Album.** The title shows the album name and "96 Photos, 13 Videos · April 2026". The grid is the same
  as Library, with favorite hearts and video durations on cells.
- **Viewer.**
  - The sidebar stays visible; the background is white in light mode.
  - The centre title is the place name ("Key West – Casa Marina"), with a subtitle
    "April 16, 2026 at 12:58:21 PM · 46 of 109".
  - Top left: back chevron and a zoom slider.
  - Top right: Info (with Visual Look Up), Share, Favorite, Rotate, Auto Enhance, and an "Edit" text button.
  - An HDR badge shows top left of the image. Videos get a floating glass control bar.
- **Info.** A floating rounded panel over the right edge, containing:
  - editable title (Add a Title), favorite heart, file name, date, Adjust;
  - camera and lens block (resolution, size, format, fps, duration);
  - Add a Caption, Add a Keyword, Add Faces;
  - an inline map;
  - "Added by <person> to the Shared Library".
- **Viewer and grid right-click menu** (same list in both places):
  - Get Info; Look Up Landmark;
  - Copy Subject, Share Subject…;
  - Copy; Share…;
  - Make Album Cover; Show in All Photos; Show in Album;
  - Rotate Left; Copy Edits, Paste Edits; Revert to Original; Turn On/Off Live Photo;
  - Create ›;
  - Move to Shared/Personal Library;
  - Add to ›; Add to Shared Album; Add to Album;
  - Edit With ›;
  - Duplicate; Hide; Delete; Remove from Album.
- **Edit mode** replaces the whole window, in a dark appearance with the sidebar hidden.
  - **Top bar:** traffic lights, zoom slider, "Revert to Original" (shown once edited), before/after
    compare, centred segmented Adjust | Styles | Crop | Tools.
  - **Top right:** "…" (Markup, App Store…, Manage extensions), Visual Look Up, Favorite, Rotate,
    Auto Enhance, and a **yellow Done**.
  - **Adjust tab:** collapsible Light / Color / Black & White sections.
    - Each section has a filmstrip "smart slider" (thumbnails of the photo at different strengths), an
      AUTO badge, a per-section reset, an enable toggle, and an **Options ›** disclosure.
    - Light › Options: Brilliance, Exposure, Highlights, Shadows, Brightness, Contrast, Black Point.
    - Further sections: Red-Eye, White Balance, Curves, Levels, Definition, Selective Color,
      Noise Reduction, Sharpen, Vignette.
    - Bottom of the panel: Reset Adjustments.
  - **Styles tab:** a 2D colour pad with Tone / Color / Palette values and an Intensity slider.
    - Undertone: Standard, Amber, Gold, Rose Gold, Bright, Neutral, Cool Rose.
    - Mood: Vibrant, Natural, Luminous, Dramatic, Quiet, Cozy, Ethereal, Muted B&W, Stark B&W.
    - Bottom: Reset Style.
  - **Crop tab:** crop handles on the image; Straighten, Vertical and Horizontal dial rows; Flip; Aspect list
    (Original, Freeform, Square, 16:9, 4:5, 5:7, 4:3, 3:5, 3:2, Custom); Auto and Reset buttons.
  - **Tools tab:** Clean Up, Extend, Reframe.
  - **Opening edit:** the preview appears immediately and a spinner (bottom right) shows while the
    full-resolution original downloads (~2.5 s).
- **Menu bar:**
  - **File:** New Album with Selection ⌘N, New Smart Album ⌥⌘N, New Folder ⇧⌘N, New Shared Album,
    New Memory Movie, Share…, Import… ⇧⌘I, Export ›, Create ›, Play Slideshow, Show in All Photos,
    Show in Album, Show Referenced File in Finder, Consolidate…, Close ⌘W, Print… ⌘P.
  - **Image:** Adjust Date and Time…, Location ›, Rotate Left ⌘R, Rotate Right ⌥⌘R, Flip Horizontal,
    Flip Vertical, Auto Enhance ⌘E, Show Edit Tools ↩, Copy Edits ⇧⌘C, Paste Edits ⇧⌘V,
    Revert to Original, Turn On Live Photo, Close Viewer (Space), Start Playback ⌥Space,
    Make Album Cover ⇧⌘K, Make Poster Frame, Save Video Frame as Photo, Remove from Favorites (.),
    Move to Shared/Personal Library, Add to ›, Add to Shared Album ›, Add to Album ⌃⌘A, Edit With ›,
    Reprocess RAW, Use RAW as Original, Select Items ⌃⌘M, Duplicate ⌘D, Hide ⌘L,
    Remove from Album ⌫, Delete ⌘⌫.
  - **View:** Library ⌃1, Collections ⌃2, Pinned ›, Albums ›, Sharing ›, Media Types ›, Utilities ›,
    Projects ›, Both / Personal / Shared Library, Show Explore View ⌥E, Show Thumbnails ⌥S,
    Show Comments, Show Histogram, Metadata ›, Show Face Names, Show Hidden Photo Album,
    Hide Recently Viewed & Shared, Sort ›, Arrange ›, Filter By ›, Aspect Ratio Grid ⌥T,
    Show Screenshots, Show Shared With You, Include Other People, Zoom (Z), Zoom In ⌘+, Zoom Out ⌘−,
    Hide Sidebar ⌃⌘S, Always Show Toolbar and Sidebar in Full Screen, Enter Full Screen.

## What Heirloom does today (observed)

- **Library.**
  - The toolbar is an opaque white band.
  - Title "Library" appears mid-toolbar, with a date-range subtitle and "1 Photo Selected" at the far left.
  - "All Libraries" is a text pop-up; zoom is separate Remove(−)/Add(+) buttons; there is a
    Years/Months/All Photos segmented control, a square-thumbnail toggle, separate Sort and Filter menus,
    Info, Share, Select, Sync, and more.
  - **Years shows the same month grid as Months** (no year cards). **Months** is a continuous grid with
    "January 2026" section headers, not cards.
  - The square-thumbnail toggle only took effect after a reload.
  - Double-click to open a photo worked only about half the time.
  - The footer shows "80,358 Photos, 22,271 Videos".
- **After closing the viewer (P0):**
  - **the grid is blank** (header and footer are still visible) until the sidebar is toggled or the window
    resized; the app is idle, with no query running;
  - the scroll position resets to the top.
- **Returning to Library** from Collections or Search re-runs the full timeline query (18 s to 2 min).
- **Sidebar.**
  - Sections: Library, Collections, **Search**; Pinned (Favorites, Recently Saved, Map, People, Memories);
    **Media Types** (Photos, Videos, Selfies, Live Photos, Portrait, Screenshots, Screen Recordings);
    Shared Libraries (Family, Friends, New…); Shared Albums; External Libraries; Albums (All Albums, …).
  - Album rows use generic icons.
- **Collections (P0).**
  - Every tile reads **"0 items"**. The Albums, People and Memories shelves are empty, and the subtitle
    says "No Photos".
  - Tiles are grey SF-symbol placeholders.
  - There are two refresh/search controls in the toolbar.
- **Search (P0).**
  - A sidebar page with two search fields.
  - "beach" returned what looks like the whole library (no filtering). No suggestions and no counts.
- **Viewer.**
  - Title: date plus location. No "N of M".
  - Toolbar: Favorite, Trash, Move, Add to Album, Adjust (edit), Rotate, Info, and a blue **"Live Text"**
    toggle that is **on by default**.
  - There is no zoom slider, no Share and no Auto Enhance.
  - **Swipe:** discrete hard cut after 80 pt of travel (`PageSwipeTracker`, MacViewer.swift:607). Nothing
    follows the finger and there is no animation.
  - **Pinch and double-tap:** no effect at all. **Root cause (verified):** `liveTextEnabled` defaults to
    `true` (MacViewer.swift:44), so every photo renders through `MacLiveTextView`. That path has no
    magnification; `MacZoomableImageView` is used only when Live Text is off.
  - **Toggling Live Text** blanks the photo.
  - **Right-click on a photo** shows only VisionKit's 4 items (Copy Subject, Share Subject…, Copy Image,
    Share Image…), even on the empty margin.
  - **Video (P0):** a grey placeholder; the play button does nothing. While a video is showing, ←/→ and
    swipe are swallowed, so you **cannot leave the video** except with Back.
  - ←/→ on photos: instant cut, no animation.
  - Info opens an inspector column.
- **Grid right-click menu:** Open, Quick Look, Get Info, Favorite, Rotate Clockwise, Add to Album…,
  Move to…, Delete.
- **Edit.**
  - A ~830×670 **modal sheet** over the dimmed window. The first click on Edit was ignored.
  - Tabs: Adjust / Filters / Crop / Portrait / Markup.
  - **Adjust:** Auto enhance checkbox; Light (Exposure, Brilliance, Highlights, Shadows, Contrast,
    Brightness, Black point) as plain sliders; Color and Detail groups.
  - **Filters:** None, Vivid, Vivid Warm, Vivid Cool, Dramatic, Dramatic Warm, Dramatic Cool, Mono,
    Silvertone, Noir, plus Intensity.
  - **Crop:** aspect buttons (Free, 1:1, 3:2, 4:3, 16:9, 9:16), a Straighten slider, Rotate 90°, Flip H,
    Flip V, Auto-straighten, Reset crop, and V/H keystone steppers. No on-image handles were visible.
  - **Portrait:** depth-blur toggle and aperture.
  - **Markup:** the panel is clipped; its left labels are cut off ("ol", "lor", "dth").
  - **Bottom bar:** Undo, Redo, More ▾ (Copy edits, Paste edits, Revert to original), Cancel, Done.
  - Escape does not cancel.
- **Menu bar:**
  - File, Edit, **View, Image, View** (**View appears twice**), Window, Help.
  - "Add to Album…" is **disabled** while a photo is open in the viewer.
  - The File menu has almost nothing in it.
