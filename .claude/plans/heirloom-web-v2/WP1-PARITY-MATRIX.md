# WP1 — Visual parity matrix (native macOS → V2 browser)

Reference: 1400×900, light+dark (PLAN §4.1). Geometry source: `WP1-MEASUREMENTS.md`.
Provenance: [S] source-derived (working tree), [W] window-observed, [N] needs host
screenshots — see `refs/CAPTURE-LOG.md`. No runtime pixel baselines exist yet; the
matrix maps every V2 route/action to its native surface so captures can be slotted in.

## 1. Route map (PLAN §7 — every route has ≥1 native reference)

| V2 route | Native surface | Evidence |
| --- | --- | --- |
| `/v2` | redirect to `/v2/library` (contract, no surface) | PLAN §2 |
| `/v2/library/[[assetId]]` | `MacLibraryBrowser` grid + toolbar + sidebar | [S] `MacMainWindow.swift:40-157` |
| `/v2/collections` | SAME grid as Library — native `.collections` resolves to `.timeline(nil)`, identical query to `.library` | [S] `MacSidebarModel.swift:102` |
| `/v2/search/[[assetId]]` | `MacSearchView` (field + scope + suggestions/recents/filters + 160 px results grid + viewer wiring) | [S] `MacSearchView.swift:13-161` |
| `/v2/favorites` | single headerless section via `favoriteAssets` (limit 1000) | [S] `MacGridView.swift:63-66` |
| `/v2/recently-saved` | single section via `recentAssets` (limit 1000) | [S] `MacGridView.swift:67-70` |
| `/v2/map` | `MacMapPlacesView`: HSplitView — clustered map (min 300) + selection grid (min 220/ideal 320), headline count | [S] `MacMapPlacesView.swift:32-63` |
| `/v2/people` | `MacPeopleView`: plain `List`, `person.circle` rows, `Unnamed` fallback, per-owner query | [S] `MacMainWindow.swift:552-566` |
| `/v2/memories` | `MacMemoriesView`: Stories shelf (120×150 covers) + On This Day (44×44) + auto-advance player (700×520, music default off) | [S] `MacMemoriesView.swift:10-99,130-204` |
| `/v2/media/photos|videos|screenshots` | single section via `assets(scope:mediaKind:)` (limit 1000); screenshot kind = filename-prefix heuristic | [S] `MacGridView.swift:71-74,153-158` |
| `/v2/spaces/[spaceId]` | `.space` → timeline grid + toolbar `Manage` + manage sheet; sidebar drop = move | [S] `MacSidebarModel.swift:112,131-139`; `MacMainWindow.swift:248-254` |
| `/v2/libraries/[libraryId]` | `.externalLibrary` → timeline grid (no Manage); sidebar drop = move with confirm | [S] `MacSidebarModel.swift:113,131-139` |
| `/v2/albums/[albumId]` | `.album` → album-order single section + Add-to-Album sheet; sidebar drop = add | [S] `MacGridView.swift:75-80`; `MacSidebarModel.swift:131-139` |
| `/v2/imports` | `.imports` → `recentAssets` — SAME query as Recently Saved (data semantics TBD per PLAN §13, owner: WP2) | [S] `MacGridView.swift:67-70` |
| `/v2/trash` | `.trash` → `trashedAssets` (manage purpose) | [S] `MacGridView.swift:81-83` |
| `/v2/hidden` | `.hidden` → `hiddenAssets` (manage purpose) | [S] `MacGridView.swift:84-86` |
| `/v2/archive` | `.archive` → `archivedAssets` (manage purpose) | [S] `MacGridView.swift:87-89` |
| `/v2/locked` | `.locked` → `lockedAssets` (limit 1000) | [S] `MacGridView.swift:90-91` |
| `/v2/settings` | `MacSettingsView` (Account / Uploads / Timeline Sources / Cache&Offline / Uploads in Flight / Background Agent) + `MacConnectView` logged-out | [S] `MacSettings.swift:16-109`; `MacConnectView.swift:19-33` |

No planned route lacks a native surface. Native-only surfaces with no V2 route
(camera import sheet, edit view) are covered in §§8/10/11.

## 2. Sidebar IA vs PLAN §11 — MATCH [S]

Order/labels/grouping in `MacSidebar.swift:17-68` equal the §11 contract except two
ellipsis deltas: `New…` (§11 `New…` ✓), `New Album…` (§11 `New Album` — record `…`).
Classic-web deltas (comparison only, classic stays): classic has Photos/Explore/Map/
Memories/People/Shared links/Sharing/Library-group/Favorites/Albums/Shared
libraries/Tags/Recently added/Folders/Utilities/Archive/Locked/Trash
(`UserSidebar.svelte:48-128`) — i.e. no Collections-as-grid, no Search destination,
no Recently Saved, no Media-Types split, no Imports; Tags/Folders/Sharing/Workflows
stay classic-only behind a More/classic link per §11.

## 3. Toolbar contract [S]

Navigation: source picker (All Libraries/Personal/spaces/libraries).
Principal: Years/Months/All Photos segmented (default Months) + 64–300 zoom slider.
Trailing: Manage (space-selected only) + Sync (disabled while syncing).
V2 URL mapping: `source=` (all/personal/space:/library:), `group=` (years/months/all),
`zoom=` 64–300 — mirrors `LibraryFilterOption`/`TimelineGrouping`/zoom
(`MacSidebarModel.swift:143-175`; PLAN §9).

## 4. Action matrix (toolbar / sidebar / menus → V2 behavior or exception)

| Native action | Shortcut | V2 behavior |
| --- | --- | --- |
| Source pick | — | URL-backed filter, same options |
| Years/Months/All | — | URL-backed grouping; visible headers per WP1 decision (§9 MEASUREMENTS) |
| Zoom 64–300 | — | URL-backed square tile size, scroll anchor preserved |
| Manage (space) | — | manage sheet (§8 MEASUREMENTS); role-gated Leave/Delete |
| Sync | ⌘⌥S | refresh/invalidate client data (PLAN §13: NOT background sync) |
| New… / New Album… | — | creation sheets; sidebar refresh |
| Sidebar drop on album | drag | add-to-album + `Added to album.` toast |
| Sidebar drop on library/space | drag | move; external-library targets confirm |
| File drop on detail | drag | import chooser + destination (V2: file picker, same chooser) |
| File > Import Files | ⌘O | file picker → chooser (browser exception: no NSOpenPanel folders-as-is) |
| Import from Camera | — | EXCEPTION — file picker + capture input (PLAN §4.3) |
| New Library/Viewer Window | ⌘⇧N | EXCEPTION — URL-backed views; optional `window.open` viewer |
| Favorite | `.` | toggle + grid refresh |
| Rotate | ⌘R | viewer display rotation (native: display-only until persisted — same in V2) |
| Delete | ⌘⌫ | trash + `Moved to Recently Deleted.` toast |
| Move to… | ⌘⇧M | move sheet, union targets, per-asset results toast |
| Add to Album | — | album picker sheet |
| Show Info | ⌘I | inspector panel (V2: side panel, same fields + EXIF browser) |
| Select All | ⌘A | full selection (both menu paths converge — `MacGridView.swift:211-218`) |
| Quick Look | Space | EXCEPTION — Heirloom viewer/preview (PLAN §4.3); grid Space opens preview panel equivalent |
| Open | Return | viewer at V2 asset URL |
| Type-to-date | digits/`-` | jump to first matching row, 1 s buffer reset |
| Arrows/⌘/⇧/marquee | — | GridSelectionModel semantics (single/toggle/extend-from-anchor/marquee/select-all/clear; `MacSelection.swift`) |
| Drag out to Finder | drag | EXCEPTION — explicit Download (PLAN §4.3); no file promises |
| Copy value / Copy tag name (EXIF rows) | context menu | clipboard write (allowed in browser) |

## 5. Viewer and inspector [S]

Black canvas; toolbar order Favorite, Rotate, Delete, Move to…, Add to Album,
[Edit iff `canEdit`], Info, Live Text toggle; ←/→ paging across `viewerContext`
(wrap-around); tiered loading with >2×-zoom upgrade; video page, Live Photo page;
inspector = Name/Date/Container/Owner/Dimensions/Favorite + All-metadata browser
(grouped DisclosureGroups, filter field, copy value/tag-name rows)
(`MacViewer.swift:47-116,243-306,308-342`; `MacSearchView.swift:334-398`).

## 6. Search / map / people / memories [S]

- Search: `Search photos` field + Search button; scope segmented (All/Personal/spaces/
  libraries); idle = suggestion chips (People/Places/Camera/Lens/File type —
  people served locally, rest `city`/`camera-make`/`camera-lens-model`/`file-extension`),
  Filters disclosure (make text, Favorites-only, Photo/Video, Any/Has/No location,
  Apply), Recent searches + Clear; results = single grid section; server failure →
  offline rows + `Server search unavailable — showing offline results.`
- Map: clustered annotations (blue count / red single), tap fills selection grid,
  double-click opens viewer; count headline (`N located photos` / `N selected`).
- People: minimal list (no cards/stories in native) — V2 matches list + navigates.
- Memories: two-section list + player (black, title, Music toggle default-off with
  no-licensed-tracks note, Close, 5 s advance, dismiss at end).

## 7. Management sheets [S]

Geometries/fields/validation in §6 MEASUREMENTS. Cancel/Done semantics: Done/close
without primary action = no side effects; success → minimal store refresh + toast;
failure → inline red-caption error, selection preserved.

## 8. Settings: working vs unavailable (PLAN WP9 rules) [S]

Working in V2: account/server read-only display, Log Out (clears session),
default upload target, import destination, timeline source toggles, pending-upload
count + Upload Now. Unavailable-with-explanation: editable server URL (same-origin
app — native shows it read-only too), cache budget/pins/purge (browser-storage
implementation or unavailable), background agent toggle (real PWA feature or
unavailable). VisionKit visual-lookup and Live Text are macOS-only (viewer keeps
server-backed OCR where functional).

## 9. Editor scope note (input to WP10) [S]

Native: canvas (black, min 480×400) + tool panel (280–340); tools Adjust (15 params:
exposure→vignette), Filters, Crop, Portrait, Markup (6 vector tools), Video
(video/live only); undo/redo ⌘Z/⌘⇧Z, copy/paste edits, revert, compare; Cancel/Done
(⌘S, dirty-gated) + saving overlay + save-failure alert (`MacEditView.swift:18-110,
758-789`). V2 ships Decision A (existing browser tools only, macOS-only tools
labeled) unless WP10 records B. No inert replicas (PLAN §2).

## 10. Acceptance checklist (WP1)

- [x] Every §7 route → ≥1 native reference or explicit no-surface entry (§1; none missing)
- [x] Every toolbar/sidebar action → behavior or exception (§4)
- [x] Measurements with provenance (§-file MEASUREMENTS; [N] items flagged for host)
- [x] Year/Month ambiguity resolved with file:line evidence (MEASUREMENTS §9; lead sign-off pending)
- [ ] [N] Runtime screenshots light+dark @1400×900 (blocker log: `refs/CAPTURE-LOG.md`)
- [ ] [N] Pixel-diff baselines (downstream, needs screenshots + WP3 masks)
