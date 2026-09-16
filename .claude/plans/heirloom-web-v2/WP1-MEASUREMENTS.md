# WP1 — Native measurements (macOS Heirloom, reference viewport 1400×900)

Provenance legend (per PLAN §4.1/§17 and WP1 acceptance):

- **[S] source-derived** — exact constant read from the working tree (~04:30 UTC;
  tree contains uncommitted user edits, so line numbers are working-tree, not HEAD).
- **[W] window-manager observed** — live `CGWindowListCopyWindowInfo` bounds of the
  running native app. No pixels captured (see `refs/CAPTURE-LOG.md`).
- **[N] not captured** — needs host run with UI automation (no runtime screenshot).

No runtime pixel measurements exist. Every value below is [S] or [W] unless marked [N].

## 1. Window and chrome [S/W]

| Surface | Value | Evidence |
| --- | --- | --- |
| Default window size | 1400 × 900 | [S] `HeirloomMacOSApp.swift:38` `.defaultSize(width: 1400, height: 900)` |
| Live Library window | 1400 × 900 at (164, 95) | [W] window list, window name "Library" |
| Live Settings window | 900 × 512 | [W] window list, window name "Heirloom Settings" |
| Viewer window min | 640 × 480 | [S] `MacViewer.swift:70` |
| Edit sheet min | 900 × 640 | [S] `MacViewer.swift:110` |
| Story player min | 700 × 520 | [S] `MacMemoriesView.swift:72` |
| Quick-Look preview panel | 480 × 360, floating nonactivating | [S] `MacMainWindow.swift:508-516` |
| Connect window min width | 360 | [S] `MacConnectView.swift:32` |
| Settings window min | 420 × 480 | [S] `MacSettings.swift:104` |

Browser chrome (tabs, address bar) and macOS title/menu bar are excluded per PLAN §4.1.

## 2. Sidebar [S]

- Container: `NavigationSplitView`, sidebar column `min: 200, ideal: 240`
  (`MacMainWindow.swift:73`). List style `.sidebar` (`MacSidebar.swift:70`).
- Section order and rows match PLAN §11 exactly (`MacSidebar.swift:17-68`):
  Library (Library, Collections, Search) · Pinned (Favorites, Recently Saved, Map,
  People, Memories) · Media Types (Photos, Videos, Screenshots) ·
  Shared Libraries (spaces + `New…`) · Shared External Libraries (libraries, no New row) ·
  Albums (albums + `New Album…`) · Utilities (Imports, Recently Deleted, Hidden, Archive, Locked).
- Label deltas vs PLAN §11: native renders `New…` (not `New`) and `New Album…`
  (not `New Album`) — `MacSidebar.swift:39,56`.
- Per-destination SF Symbols (`MacSidebarModel.swift:53-75`): library
  `photo.on.rectangle`, collections `rectangle.grid.2x2`, search `magnifyingglass`,
  favorites `heart`, recentlySaved `tray.and.arrow.down`, map `map`, people `person.2`,
  memories `clock`, mediaPhotos `photo`, mediaVideos `video`, mediaScreenshots
  `camera.viewfinder`, space `person.2.circle`, externalLibrary `externaldrive`,
  album `rectangle.stack`, imports `square.and.arrow.down`, recentlyDeleted `trash`,
  hidden `eye.slash`, archive `archivebox`, locked `lock`. Browser must substitute
  licensed icons (PLAN §4.3); names are recorded so V2 picks 1:1 equivalents.
- Stable hooks for automation: `sidebar`, `sidebar-<key>` (spaces/extlibs/albums keyed
  by id, rest by lowercased title), `sidebar-new-space` (`MacSidebar.swift:71-90`).

## 3. Toolbar [S]

- Navigation placement: library switcher, menu picker — `All Libraries`, `Personal`,
  then spaces, then external libraries (`MacMainWindow.swift:219-232`).
- Principal placement: `Years`/`Months`/`All Photos` segmented picker, then zoom
  slider 64–300 at fixed width 120 (`MacMainWindow.swift:233-246`).
- Trailing group: `Manage` (rendered ONLY when a space is selected,
  `MacMainWindow.swift:248-254`) + `Sync` (`arrow.triangle.2.circlepath`),
  disabled while syncing (`MacMainWindow.swift:255-261`).
- Defaults: switcher `.all`, grouping `.months`, zoom `120`
  (`MacMainWindow.swift:43-45`).
- Hooks: `library-switcher`, `grouping-segmented`, `zoom-slider`, `sync-button`.

## 4. Grid geometry [S]

| Region | Value | Evidence |
| --- | --- | --- |
| Collection flow spacing | 2 px inter-item, 2 px line | `MacGridView.swift:235-236` |
| Collection section inset | 8 px all sides | `MacGridView.swift:237` |
| Cell shape | square, `itemSize = zoom` | `MacGridView.swift:326-333,417-422` |
| Library default tile | 120 px | default zoom (`MacMainWindow.swift:45`) |
| Search results tile | fixed 160 px | `MacSearchView.swift:152` |
| Map selection thumbs | 96 × 96, corner radius 6, adaptive min 96 | `MacMapPlacesView.swift:47-52` |
| Memory story covers | 120 × 150, corner radius 8, 12 px HStack spacing | `MacMemoriesView.swift:25,31-32` |
| On This Day thumbs | 44 × 44, corner radius 6 | `MacMemoriesView.swift:58-60` |
| Camera import thumbs | 48 × 48, corner radius 6 | `MacImport.swift:377-378` |
| Grid error treatment | red caption, 4 px padding above grid | `MacMainWindow.swift:180` |
| Loading treatment | `ProgressView` padded, only when sections empty | `MacMainWindow.swift:182-184` |

## 5. Type, color, material [S]

- No custom fonts anywhere: system type only — `.headline` (sheet titles, map count,
  import title, story player title), `.subheadline` (manage-sheet Members, memory
  empty states, OTD dates), `.caption`/`.caption2`-equivalent (errors, details,
  secondary rows), `.body` (camera item names). V2 uses the system font stack with
  the same hierarchy, not SF Pro (PLAN §4.3).
- Colors are semantic: `.secondary` (all helper text), `.red` (all inline errors),
  `.accentColor` (selected suggestion chip), `.white` on black (story player),
  `.gray` (player note, map placeholder `gray.opacity(0.3)`, memory placeholder).
- Black canvases: viewer image area, edit canvas, story player
  (`MacViewer.swift`, `MacEditView`, `MacMemoriesView.swift:148`).
- Toast: bottom overlay, 16 px horizontal / 8 px vertical padding, `.thinMaterial`
  capsule, 4 s auto-dismiss (`MacMainWindow.swift:147-156,435-441`).
- Only literal color in the shell: markup default `#FFCC00` (`MacEditView.swift:31`).
- Bucket/date formats: section header `MMMM yyyy` parsed from `yyyy-MM` bucket keys,
  `en_US_POSIX` (`MacGridView.swift:127-136`); type-to-date rows `yyyy-MM-dd`,
  `en_US_POSIX` (`MacMainWindow.swift:289-295`); viewer inspector date uses
  locale-sensitive abbreviated/shortened style (`MacViewer.swift:318`) — mask in tests.

## 6. Sheets and dialogs [S]

All sheets: `VStack(alignment: .leading, spacing: 12)`, `.padding()`,
headline title, inline red-caption error, `Spacer()` + Cancel/primary button order,
primary carries `.keyboardShortcut(.defaultAction)`:

| Sheet | Min size | Fields/notes |
| --- | --- | --- |
| New Shared Library | 320 wide | Name + Description (optional); Create disabled on blank name |
| Manage space | 360 wide | Title = space name; Name/Description + Save; Members rows (`userId`, role secondary, link-style Remove except self); add-member field + Add (disabled when empty); Leave (contributor only) / Delete Library destructive (owner only); Done |
| New Album | 300 wide | Name only; Create disabled on blank name |
| Add to Album | 300 wide, list min-height 160 | Album rows with `rectangle.stack` icon; toast `Added to album.` |
| Move to… | 320 wide, list min-height 160 | `Move N items to…`; rows sorted by title; library targets confirm (`Files leave the import path once moved. This cannot be undone automatically.`); empty state `No available destinations for this selection.`; result toast `Moved M items (K already there).` / `Moved M; K failed (reasons).` |
| Import chooser | 360 wide | `Import N files`; first 5 names + `…and K more`; destination picker (Default target label / Personal / spaces); Upload→`Queued N files for upload.` / dedupe note; Done |
| Camera import | 520 × 420 | Device picker; item rows (48 px thumb, name `.body`, `%.1f MB · UTI` caption, Imported/✓ state); list min-height 240; Delete-after-import toggle (default off); Import All New (default action) / Import Selected / `N queued` / Done; empty state `No cameras or SD cards found…` |
| External-library drop confirm (alert) | — | `Move into external library?` + Move(destructive)/Cancel |

## 7. Motion and transients [S]

- Toast 4 s; type-to-date buffer resets after 1 s (`MacGridView.swift:532-535`).
- Story auto-advance 5 s/page, loops then dismisses (`MemoryStory.swift:44`,
  `MacMemoriesView.swift:182-191`).
- Viewer tier upgrade crossing 2× magnification (range 1–8×)
  (`MacViewer.swift:252-253,294-298`).
- Thumbnail streaming placeholder→tier per cell (`MacGridView.swift:376-392`).

## 8. Regions requiring screenshot masks (for WP3 manifest)

Grid cells (async thumbnails), toasts (4 s), spinners, story player (5 s advance),
map tiles/clusters (zoom-dependent), suggestion chips/recents (user data), sidebar
space/library/album rows + all counts (`N located photos`, pending count, byte usage),
EXIF values, `On This Day` (today-dependent), fixture dates, locale-sensitive
inspector dates. Everything else (shell, sidebar order, toolbar, sheet layouts) is
deterministic under the fixture seed.

## 9. Year/Month section-header decision (PLAN §6 last bullet) — EVIDENCE

- Loader builds real sections: year spacer sections (empty rows) + `MMMM yyyy`
  month sections for `.years`/`.months`; single headerless section for `.all`;
  favorites/recents/media/album/trash/hidden/archive/locked are single headerless
  sections (`MacGridView.swift:97-125`; `TimelineGrouping.showsBucketHeaders`,
  `groupsByYear`, `MacSidebarModel.swift:160-175`).
- Renderer flattens everything: adapter reports exactly 1 section and concatenates
  all rows (`MacGridView.swift:313-324,358-362`). Section headers are built but
  NEVER displayed in the shipped grid. Search results pass header `"Results"` into
  the same flattening adapter (`MacSearchView.swift:147`) — also invisible.
- Consequence: with flattening, Years vs Months differ only in bucket cap
  (36 vs 12) and invisible year spacers — the segmented control is near-no-op.
- **WP1 decision: V2 implements the loader's intended model — visible year + month
  headers for Years/Months, flat for All** (honors `showsBucketHeaders`,
  `groupsByYear`, `bucketTitle`; gives the segmented control visible meaning).
  DIVERGENCE from shipped-visible (flat) is intentional and must be recorded in the
  release report. Lead sign-off required before WP5.
