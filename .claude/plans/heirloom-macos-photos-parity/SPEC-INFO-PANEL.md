# Spec: Info sidebar (owner request 2026-09-17), binding for WP-V (gap V12, plus V16 and V17)

The owner wants Heirloom's Info to match Photos in content, layout and styling.

Captures are in `evidence/design/info/`, and the pair is `evidence/design/pairs/I1-info-panel.png`.

| File | What |
|---|---|
| `photos-info-photo.png` | Photos, still photo with full EXIF, people and location (280×610 pt; the **content and styling** reference; Heirloom renders it in a sidebar) |
| `photos-info-video.png` | Photos, video (4K / FPS / duration variant, "Add Faces") |
| `photos-info-screenshot-no-location.png` | Photos, item with no lens and no GPS ("No lens information", dashes, "Assign a Location") |
| `photos-info-no-selection-collection.png` | Photos with nothing selected in a collection: the panel summarises the collection (name, date range, counts, size) |
| `photos-adjust-date-time-sheet.png` | The sheet opened by the blue **Adjust** link |
| `photos-viewer-behind-info.png` | The viewer while Info is open. In Photos the panel floats over the photo; **Heirloom must instead use an in-window sidebar (owner decision, §1)** |
| `heirloom-info-photo1-*.png`, `heirloom-info-photo2-*.png` | Heirloom today: a full-height right column inside the window |
| `heirloom-info-grid-selection-bug.png` | Heirloom bug: a grid item is selected ("1 Photo Selected") but Info shows "Select an item to view its info" (**V16**) |

## 1. Container: owner decision (overrides Photos)

The owner (2026-09-17) wants **Photos' content, layout and styling**, but **not** Photos' separate
floating window. Info stays **inside the main window as a trailing sidebar** next to the open photo.

- **Implementation:** SwiftUI `.inspector(isPresented:)`, or a trailing `NSSplitViewItem` with
  `behavior = .inspector`. It is a real split pane, not an overlay.
- **Width:** default **280 pt**, the Photos panel width, so the content matches Photos 1:1. User-resizable
  between 260 and 360 pt. The width persists (autosave).
- **Visual style:** the pane uses the same material/glass background as the Photos panel. It runs full
  height under the toolbar, with a leading hairline divider. It has no title bar and no traffic lights
  (those belong to Photos' separate window).
- **Photo layout:** the photo **re-fits** to the remaining width with an animated 0.2 s resize (this
  replaces Photos' overlay behaviour). Zoom state and the centred anchor are preserved across the resize.
  Paging still works with the inspector open.
- **Toggle:** ⌘I, the toolbar ⓘ button (pressed state while open), Window/View › Show Info, and the
  context menu's Get Info.
  - The open/closed state persists per window.
  - The inspector **follows the current selection** live: viewer page changes and grid selection.
- It is also available in the **grid** (a trailing sidebar next to the grid, driven by selection). The
  grid re-lays out to the narrower width without losing the scroll anchor.
- **Hide it** in edit mode and in full-screen slideshow.

## 2. Content and layout, top to bottom
Styling: system font. Primary rows are 15 pt regular. Placeholders ("Add a Title", "Add a Caption",
"Add a Keyword", "Assign a Location", "Add Faces") are 15 pt *italic, tertiary colour*. Sections are
divided by hairline separators spanning the full width. Horizontal padding is 11 pt.

1. **Header block**
   - Row 1: **title field**, an inline-editable text field with the placeholder *"Add a Title"*, and a
     **heart** button at the trailing edge (filled when favourite; it toggles favourite).
   - Row 2: **original filename** (`originalFileName`), e.g. `IMG_3760.HEIC`.
   - Row 3: **date** and **time** ("April 14, 2026   6:48:28 PM", local to the asset's time zone). A
     trailing blue **Adjust** link opens the Adjust Date and Time sheet (§4).
2. **Camera card**: a rounded (10 pt) inset card with a slightly darker fill.
   - Line 1: **device**: `make model` ("Apple iPhone 17 Pro Max"), or "Screenshot" for screenshots, or
     "Unknown camera".
   - Line 2: **lens**: lens model or "Main Camera — 24 mm ƒ1.78"; "No lens information" when absent.
   - Trailing icons on lines 1–2 are status glyphs: *WB* (white balance, auto/manual) and *metering*.
     Show them only when EXIF has those values; otherwise use the dimmed "?" glyph as Photos does.
   - Line 3 (photo): **megapixels** ("24 MP"), **dimensions** ("4284 × 5712"), **file size** ("4.6 MB"),
     and a **format badge** (small grey capsule, "HEIF" / "JPEG" / "PNG" / "RAW").
   - Line 3 (video): **resolution class** ("4K" / "HD"), **dimensions**, **size**, **codec** ("HEVC" /
     "H.264"), and a video glyph.
   - Separator inside the card, then line 4 as an evenly spaced strip:
     - photo: **ISO · focal length · exposure bias (ev) · ƒ-number · shutter** ("ISO 80 · 24 mm · 0 ev ·
       ƒ1.78 · 1/1812 s"), with "–" placeholders for missing values;
     - video: **FPS · duration** ("59.97 FPS · 00:17").
3. **Caption**: an inline-editable field with the placeholder *"Add a Caption"*, bound to Immich
   `exifInfo.description` and saved through `PUT /assets/{id}` `description`.
4. **Keywords**: *"Add a Keyword"*. Show the asset's **tags** as token chips; edit through the Immich tags
   API. If tag editing isn't available, show the chips read-only and hide the placeholder.
5. **People**: a row of 40 pt **circular face avatars** (Immich `people` with face thumbnails) plus a
   circular **+** button (Add Faces). With no people: a **+** circle and the italic *"Add Faces"*. Hover
   shows the name; click opens that person's page. Adding faces is P2 (hide the + when unsupported).
6. **Location**
   - A text row with the place, "City, State, Country" (`exifInfo.city/state/country`).
   - Then an **inline map** (MapKit, ≈220 pt tall, full panel width, no corner radius inside the panel)
     with a red pin at lat/long, zoom +/− buttons bottom right, and the Legal link.
   - Click the map to open the Map page centred there.
   - With no GPS: a single italic *"Assign a Location"* row, which opens a location search. Editing
     through `latitude`/`longitude` is allowed by the API (P2).
7. **Footer (shared-library attribution)**: when the asset is in a shared library, show the owner's
   **avatar** plus "Added by **<owner name>** to the **<library name>** ›". Clicking it opens that
   library. The footer is **always shown**, to preserve Heirloom's Container and Owner fields. Personal
   assets read "In your **Personal Library**"; owner-attribution rules are in the preservation table below.

**Preserve everything Heirloom shows today (owner decision).** No information is dropped; it moves into
the Photos layout:

| Heirloom today | Where it goes |
|---|---|
| Caption (description) | §2.3 Caption field (editable) |
| Date & Time › Taken | §2.1 row 3 date + time |
| Camera (make/model or "No camera information") | §2.2 card lines 1–2 |
| File › Dimensions, Megapixels, Size, Format | §2.2 card line 3 (MP · dimensions · size · format badge) |
| File › Name | §2.1 row 2 filename |
| Library › Container (e.g. Family) | §2.7 footer "Added by … to the **Family** library ›"; for personal assets the footer reads "In your **Personal Library**" (the container is always shown) |
| Library › Owner (e.g. Bhargavi Patel) | §2.7 footer owner name + avatar (always shown, including your own assets: "Added by **You**") |
| Library › Favorite | §2.1 heart button (state visible) |

**Heirloom-only extras** go in a collapsible **"Details"** disclosure at the bottom of the sidebar (below
the footer, collapsed by default, state persisted). Photos has no equivalent, so this is where
server-specific data lives:
- album membership (chips; click to open);
- original path / storage label (if the server returns it);
- uploaded / modified dates (`createdAt`, `fileModifiedAt`);
- checksum (short, with copy);
- asset ID (monospaced, with copy);
- rating (if set);
- live-photo pair / stack info;
- offline / archived / trashed flags when true.

The grouped-form visual style ("Caption / Date & Time / Camera / File / Library" section boxes) is
replaced by the Photos styling.

## 3. States
- **Single item:** as above.
- **Multiple selection:** the header reads "N Items" with the date range; the camera card is hidden; shared
  editable fields (caption, keywords, favourite) apply to all; there is no map, or a map with multiple pins
  if cheap. Verify Photos' exact multi-select rendering at the gate (the capture attempt this session
  didn't produce a multi-select).
- **Nothing selected in a collection or album:** a summary card with the collection name, date range
  ("November 5, 2020 – September 16, 2026"), counts ("813 Photos"), and total size if known.
- **Multiple selection in the sidebar** uses the same width and styling.
- **Loading:** show cached values instantly and fill in missing EXIF fields without layout jumps (reserve
  the heights).

## 4. Adjust Date and Time sheet (P2)
A sheet on the main window with:
- a thumbnail of the item;
- "Adjust date and time of N selected photo(s)";
- Original (read-only) and Adjusted (date/time stepper);
- a world map for time zone, with Time Zone and Closest City pickers;
- Revert / Cancel / **Adjust** buttons.

It saves through `dateTimeOriginal` (plus time zone) in `PUT /assets`. It must never apply without the
owner pressing Adjust.

## 5. Data checks (do before styling)
- **V17:** Heirloom showed "No camera information" for both inspected assets. Verify that `assetExif`
  make/model/lens/iso/fNumber/exposureTime/focalLength are actually synced into the local store and
  exposed to the inspector for assets that have EXIF on the server (compare with the web UI for the same
  asset id). If the sync or projection drops them, fix it in WP-F's store code, which is shared, and hand
  it to WP-F.
- The owner/user **name** comes from `UserResponseDto.name` (also needed for Settings; see
  `SPEC-TOOLBAR-SETTINGS.md` §3).

## 6. Gap rows (PLAN §1, WP-V)
| ID | Pri | Gap |
|---|---|---|
| V12 | P1 (raised from P2 by the owner) | Info **in-window sidebar** with Photos content and styling, preserving all Heirloom fields, per §1–§3 |
| V16 | P0 | Grid Info ignores the selection ("Select an item…" while 1 photo is selected) |
| V17 | P1 | Camera/EXIF fields missing in the inspector; verify sync/projection (§5) |
| V18 | P2 | Adjust Date and Time sheet (§4); Assign Location; Add Faces |

## 7. Tests (TEST-PLAN §2)
| ID | Tests |
|---|---|
| V12 | **S:** Info sidebar snapshots for fixture assets: (a) photo with full EXIF, people, GPS, shared library; (b) video; (c) screenshot with no lens/GPS; (d) collection summary; each light and dark, 280 pt wide.<br>**U:** formatter golden tests: MP rounding, dimensions, size, codec/format badge, "ISO · mm · ev · ƒ · s" strip with dashes for missing values, "4K/HD" class, FPS, duration "00:17", "City, State, Country" assembly.<br>**UI:** ⌘I opens `inspector` **inside the main window** (no new window appears: the window count is unchanged). The viewer image re-fits to the narrower content width without losing its zoom anchor. The Details disclosure holds the asset ID, albums and dates. Every field from Heirloom's old panel is still present (container, owner, favourite, name, format, size, MP, dimensions, caption, taken date). The panel follows ← / → paging (filename changes). The heart toggles favourite. Caption edit saves (fixture stub records `PUT description`) |
| V16 | **UI:** select a grid cell and press ⌘I → the panel shows that asset's filename; ⌘-click a second → "2 Items" |
| V17 | **C:** a sync fixture with full EXIF → the store row exposes make/model/lens/iso/fNumber/exposureTime/focalLength/city. **U:** the inspector view model maps them (no "No camera information" when data exists) |
| V18 | **UI:** Adjust opens the sheet; Cancel makes no API call (stub asserts zero writes) |
