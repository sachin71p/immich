# Design reference: what "done" should look like

**Every implementer must open the pair images for their gap IDs before writing UI code, and again before
reporting done.**

Each image in `evidence/design/pairs/` is a labelled side-by-side: **Apple Photos (target)** on the left,
**Heirloom (current)** on the right. The single-app originals are in `evidence/design/photos/` and
`evidence/design/heirloom/`.
- Window captures are 3456×2052 px, which is 2× of a 1728×1026 pt window.
- Menu and popover captures are full-display, 3456×2234 px.
- Measure sizes from them in points (px ÷ 2).

Motion (swipe, pinch, transitions, launch, scroll) can't be shown in stills. The reference clips are in
`evidence/video/` (REF = Photos, CUR = Heirloom); see `EVIDENCE.md`.

> **Private data.** These images contain the owner's family photos and, in full-display captures, part of
> a Claude chat panel floating on the right edge; ignore that panel, it isn't app UI. `evidence/` is
> git-ignored. **Never commit, upload or attach these files.** Snapshot-test baselines must be rendered
> from synthetic fixture images (see `TEST-PLAN.md` §2), never from these captures.

## Pair index

| Pair | Gap IDs | What to match (look for these specifically) |
|---|---|---|
| `T1-toolbar-library-strip` | C7 | **Toolbar exactness** (Photos top, Heirloom bottom). See `SPEC-TOOLBAR-SETTINGS.md` §1 for the itemised differences. Owner exception: the scope capsule keeps the full library name |
| `T2-toolbar-viewer-strip` | C7, V9 | Viewer toolbar (Photos top, Heirloom bottom): §2 of the spec |
| `S1-settings-general-vs-account` | C8, C9 | Photos General tab (label-column form) vs Heirloom's scrolling form (Account, Uploads, Timeline Sources) |
| `S2-settings-icloud-vs-storage` | C8 | Photos iCloud tab vs Heirloom originals budget and keep list. Owner: merge, **no Download Originals** |
| `S3-settings-sharedlib-vs-timeline` | C8 | Photos Shared Library tab (participants, suggestions, deletion notifications) vs Heirloom Timeline Sources. Owner: merge |
| `S4-settings-icloud-vs-usage-agent` | C8 | Heirloom Usage / Uploads in Flight / Background Agent, which go to the Storage and Server tabs |
| `L1-library-allphotos` | G5, G8, G11, C2, C3 | Content under glass toolbar; title + date subtitle top left; toolbar order and capsule grouping; square crops with tight 1–2 pt gutters; favorite hearts and shared-library badges on cells |
| `L2-library-months` | G4 | Photos: large moment cards (Photos currently shows a dense grid with a "January 2026" title at this zoom). Heirloom: sections with bold headers. Use the Months card spec in WP-G step 5 |
| `L3-library-years` | G3 | Photos Years = one large card per year. Heirloom shows the month grid with a "2026" header |
| `L4-toolbar-scope-menu` | C3 | Photos: icon button → menu with Both / Personal / Shared, SF symbols, and a checkmark. Heirloom: "All Libraries" text pop-up |
| `L5-toolbar-filter-menu` | C3 | Photos filter menu: All Items, Favorites, Edited, Photos, Videos, Screenshots, Captured by Me, Not in an Album, Manage Keywords… (icons on every row) |
| `L6-toolbar-more-vs-sort` | C3 | Photos "…" = Show: Screenshots / Shared with You. Heirloom has a separate Sort menu (Newest/Oldest First); in Photos sort lives in View › Sort |
| `L7-grid-context-menu` | G10, V10 | Photos' full grid menu (Get Info … Delete) vs Heirloom's 8 items |
| `V1-viewer-photo` | V9, V1 | Photos centre title (place) + subtitle (date · N of M), zoom slider top left, right cluster Info/Share/Favorite/Rotate/Auto-Enhance + **Edit**, LIVE badge, white canvas. Heirloom: date title, Trash/Move/Album/Adjust/Rotate/Info + blue Live Text |
| `V2-viewer-context-menu` | V10 | Photos: full menu (Get Info, Copy Subject, Share Subject…, Copy, Share…, Show in All Photos, Rotate Left, Copy/Paste Edits, Revert, Turn Off Live Photo, Create ›, Move to Personal Library, Add to ›, Edit With ›, Duplicate, Hide, Delete). Heirloom: 4 VisionKit items |
| `V3-viewer-info` | V12 | Photos: floating rounded Info card over the photo (title, filename, date, camera block, Add a Caption / Keyword, faces row, inline map, "Added by … to the Shared Library"). Heirloom: full-height column with a plain label list |
| `I1-info-panel` | V12 | Photos Info panel (left, 280×610 pt window) vs Heirloom's column. Full spec: `SPEC-INFO-PANEL.md`; all variants in `evidence/design/info/` |
| `I2-info-placement` | V12 | Placement reference only. Photos floats Info over the photo, but **the owner wants Heirloom to keep an in-window sidebar** (as Heirloom does now, right side) with Photos' content and styling |
| `V4-viewer-video` | V3, V4 | Photos: poster frame + floating glass controls (mute, play, captions, AirPlay, scrubber, times). Heirloom: grey canvas, dead play button, controls at the bottom edge |
| `V5-viewer-chevron-vs-nav-bug` | V11, V15 | Photos: previous-photo chevron at the left edge on hover. Heirloom (right): sidebar says Search, but the viewer is still on screen (V15 bug) |
| `E1-edit-adjust` | E2, E3, E4 | Photos full-window dark edit mode (tabs, right panel, yellow Done) vs Heirloom modal sheet |
| `E2-edit-light-options` | E4 | Photos Light › Options sliders (filled track, value right-aligned, section filmstrip) vs Heirloom plain blue sliders |
| `E3-edit-styles-vs-filters` | E5 | Photos Styles pad + Undertone/Mood lists vs Heirloom Filters grid |
| `E4-edit-crop` | E6 | Photos: on-image handles, dial rows, aspect list, Auto/Reset. Heirloom: button grid, no on-image handles |
| `E5-edit-tools-vs-portrait` | E8, E3 | Photos Tools tab (Clean Up / Extend / Reframe) vs Heirloom Portrait tab |
| `M1-menubar-file` | C1 | Photos File menu (album creation, import, export, create, slideshow, print) vs Heirloom's 5 items |
| `M2-menubar-view` | C1 | Photos View menu (library scope, navigation submenus, sort/arrange/filter, aspect grid, zoom, sidebar) vs Heirloom's second "View" (Show Info / Select All / Quick Look) |
| `M3-menubar-image` | C1 | Photos Image menu (rotate/flip/enhance/edit tools/…) vs Heirloom (Favorite, Rotate Clockwise, Add to Album…, Move to…, Delete) |
| `M4-menubar-view-duplicate` | C1 | Heirloom's *first* View menu (system: Show Tab Bar, Show All Tabs, Enter Full Screen): this is the duplicate |
| `P1-collections` | P1, P4 | Photos shelves with real imagery vs Heirloom "0 items" grey tiles. See also `photos/40b-collections-bottom.png` for the Media Types and Utilities lists |
| `P2-search` | C5, P2, P5 | Photos toolbar search with completions and counts vs Heirloom Search page (two fields, scope pills, suggestion chips). See also `photos/41-search-results.png` and `photos/41-search-suggestions-empty.png` |
| `P3-map` | P6 | Photos full-bleed map with thumbnail pins vs Heirloom split map + "photos in this area" side panel |
| `P4-people` | P6 | Photos: Groups shelf + large named face tiles. Heirloom: circular faces, all "Add Name" (check whether Immich has names: P8) |
| `P5-videos` | P3, G11 | Photos Videos page (duration badges, portrait crops) vs Heirloom (took ~8 s, "0 Photos, 22,271 Videos") |
| `P6-all-albums` | P6 | Photos rounded album cards with titles overlaid vs Heirloom small tiles with a Sort/Name/Recent picker |
| `P7-album` | P6, C2 | Photos album title + count subtitle vs Heirloom (the Years segment shown inside an album) |
| `F1-launch-early` | F3 | Photos: empty window with sidebar + spinner at 1.3 s. Heirloom: **Connect to server** form flashes |
| `F2-launch-grid-vs-zero` | F3 | Photos grid at 2.9 s vs Heirloom "0 Photos, 0 Videos" empty Library at 5 s |

Single-app extras without a pair:
- `photos/09-allphotos-min-zoom.png`: the densest mosaic zoom (G7).
- `photos/20-edit-video-adjust.png`: edit mode for a video.
- `photos/13-viewer-edge-chevron.png`.
- `photos/41-search-suggestions-empty.png`.
- `heirloom/05-menu-sort.png`, `heirloom/44-memories.png` ("On This Day" cards), `heirloom/21-edit-adjust-light.png`,
  `heirloom/51-launch-zero-photos.png`.

## Visual tokens to copy from Photos (measure and confirm on the PNGs)
- **Toolbar:** one row, ~52 pt tall. Controls sit in rounded glass capsules grouped as: [sidebar] [scope]
  [− +] [Years Months All Photos] [aspect · filter · …] [info · share · favorite · rotate] [search].
- **Title:** bold ~15 pt, with a secondary ~11 pt subtitle underneath, top left (after the sidebar toggle).
- **Sidebar:** source list with section headers (Pinned, Albums) in 11 pt secondary text. Rows are 28 pt
  with 16 pt symbol icons in the accent colour; album rows use rounded photo thumbnails.
- **Grid:**
  - Square crops, ~2 pt gutters, no section headers in All Photos.
  - Badges are 12 pt white symbols with a soft shadow: heart bottom left, duration bottom right, shared
    two-person badge top right.
- **Viewer:**
  - Canvas uses the window background (white/light, black/dark). The image is aspect-fit with no border.
  - Badges (LIVE, HDR) are small translucent capsules top left of the image.
- **Info panel:** ~260 pt wide floating card, 12 pt corner radius, material background, 8 pt inset from the
  top-right corner.
- **Edit mode:** dark window, ~300 pt right panel. The Done button is a yellow capsule (system yellow) with
  black text.
- **Menus:** SF Symbols on context-menu rows where Photos shows them; key equivalents as in EVIDENCE.md.
