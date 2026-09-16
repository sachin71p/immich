# WP4 Step 1 — Control inventory (macOS)

Survey of every file in `native-apple/Apps/macOS/Sources` (worktree `immich-wp4` @ `07e4aea7a`).
Method: grepped control constructors (`Button/Menu/Toggle/Picker/CommandGroup/ToolbarItem/.toolbar/.contextMenu/.onKeyPress/.keyboardShortcut/.sheet/.alert`), then read each site once. No fixes in this slice.
Did NOT trust `01-map.md` / `06-facts.md` §4. Already-fixed credits below verified against the tree.

Legend — real effect: **yes** / **toast-only** / **no-op** / **stub** / **broken**.
Fix column: **fix here** (WP4 Step 2) or assigned **WP5-viewer** / **WP6-page** with reason.

## Already fixed this wave (verified, not assumed)

- **Rotate persisted (U27, decision YES):** grid `rotate(ids:)` (`MacMainWindow.swift:699`) persists via
  `EditRecipe.crop.quarterTurns` → upstream edits + recipe KV; videos skipped with report. Commit
  `07e4aea7a`. Toolbar Rotate, Image › Rotate Clockwise (⌘R) → **yes (fixed this wave)**.
- **Move-sheet Cancel — NOT fixed, despite the task prompt's assumption.** `MacMoveSheet.swift:21-62`
  has no Cancel button, no `.cancelAction`, no Escape handling. Only the external-library *confirm
  alert* has Cancel (:58). Recorded below as **broken (U12)**. The 06-facts §4 "has Cancel" claim is
  wrong, exactly as the brief warned.

## Connect

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacConnectView.swift:25,27 | Connect + ⌘⏎ (`.defaultAction`) | connect form | `completeLogin` + `syncNow`, error inline | yes | — |

## Import chooser (`MacImportChooserSheet`, in MacDragDrop.swift)

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacDragDrop.swift:96 | Destination library picker | import chooser | `$destination` → `enqueue()` target, persisted to `Heirloom.importDestination` | yes | — |
| MacDragDrop.swift:115 | Cancel | chooser | `onDone()` (close, nothing enqueued) | yes | — |
| MacDragDrop.swift:116,125 | Upload/Done + ⏎ | chooser | `enqueueImport()` → durable queue; label flips to Done | yes | — |
| MacDragDrop.swift:115 | (no Escape) | chooser | — | broken (Escape missing; brief requires Cancel/Escape on every sheet) | fix here |

## Camera import (`MacCameraImportView`, in MacImport.swift)

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacImport.swift:244 | Device picker | camera sheet | switches `visibleItems` device | yes | — |
| MacImport.swift:255 | item row Button (plain) | camera list | toggles selection checkmark | yes | — |
| MacImport.swift:281 | Delete from device after import toggle | camera sheet | `prefs.deleteAfterImport` persisted | yes | — |
| MacImport.swift:291,298 | Import All New + ⏎ | camera sheet | `browser.importItems(newItems)` | yes | — |
| MacImport.swift:300 | Import Selected | camera sheet | `importItems(selected)` | yes | — |
| MacImport.swift:314 | Done | camera sheet | `dismiss()` — no Escape binding | broken (Escape) | fix here |

## Library sheets (MacLibrarySheets.swift)

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacLibrarySheets.swift:23 | Cancel (New space) | sheet | `onDone()` | yes | — |
| MacLibrarySheets.swift:24,27 | Create + ⏎ (disabled until named) | sheet | `createSpace` + refresh + close, error inline | yes | — |
| MacLibrarySheets.swift:23 | (no Escape, New space) | sheet | — | broken (Escape) | fix here |
| MacLibrarySheets.swift:66 | Save (Manage) | sheet | `updateSpace` | yes | — |
| MacLibrarySheets.swift:77 | Remove (per member) | member row | `removeMember` + list refresh | yes | — |
| MacLibrarySheets.swift:84 | Add (disabled when empty) | manage | `addMembers` + refresh | yes | — |
| MacLibrarySheets.swift:90 | Leave (contributor only) | manage | removes self + closes | yes | — |
| MacLibrarySheets.swift:93 | Delete Library, destructive (owner only) | manage | `deleteSpace` + refresh + close | yes | — |
| MacLibrarySheets.swift:97 | Done (Manage) — no Cancel/Escape | sheet | `onDone()` | broken (Escape; brief pattern) | fix here |
| MacLibrarySheets.swift:174 | Cancel (New album) | sheet | `onDone()` | yes | — |
| MacLibrarySheets.swift:175,177 | Create + ⏎ (disabled until named) | sheet | `createAlbum` + refresh + close | yes | — |
| MacLibrarySheets.swift:174 | (no Escape, New album) | sheet | — | broken (Escape) | fix here |
| MacLibrarySheets.swift:208 | album row Buttons (Add-to-Album) — no Cancel/Escape at all | sheet | `addAssets` + close, error inline | broken (U12 pattern: no Cancel/Escape) | fix here |

## Move sheet (MacMoveSheet.swift) — U12 live

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacMoveSheet.swift:37 | target row Buttons | sheet | `tapped()` → direct move, or confirm for `.library` | yes | — |
| MacMoveSheet.swift:55 | Move, destructive (confirm alert) | alert | `performMove` | yes | — |
| MacMoveSheet.swift:58 | Cancel, `.cancel` (confirm alert) | alert | clears `pendingConfirm` | yes | — |
| MacMoveSheet.swift:— | sheet Cancel button + Escape — ABSENT | sheet | — | broken (U12: no Cancel, no Escape, blocks Quit) | fix here |

## Main window sheets + drop alert (MacMainWindow.swift)

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacMainWindow.swift:175 | move sheet wiring | library | presents `MacMoveSheet`, toasts summary, posts change | yes (wiring; sheet itself broken above) | — |
| MacMainWindow.swift:185 | add-to-album wiring | library | presents sheet, posts `.albumsChanged` | yes (wiring; sheet broken above) | — |
| MacMainWindow.swift:192 | new-space wiring | library | presents + reloads | yes | — |
| MacMainWindow.swift:198 | new-album wiring | library | presents + reloads | yes | — |
| MacMainWindow.swift:204 | manage-space wiring | library | presents when role resolves | yes | — |
| MacMainWindow.swift:212 | camera-import wiring | library | presents `MacCameraImportView` | yes | — |
| MacMainWindow.swift:215 | import-chooser wiring | library | presents chooser, clears pending URLs | yes | — |
| MacMainWindow.swift:225 | Move, destructive (drop confirm) | alert | `performMove` for sidebar/file drops onto external library | yes | — |
| MacMainWindow.swift:228 | Cancel, `.cancel` (drop confirm) | alert | clears `pendingDropMove` | yes | — |

## Grid toolbar (MacMainWindow.swift:307+)

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacMainWindow.swift:320,323 | zoom − / + (disabled at limits) | toolbar | `zoom ±= 16`, clamped 64–300 | yes | — |
| MacMainWindow.swift:328 | Grouping picker (Years/Months/All) | toolbar | loader grouping | yes | — |
| MacMainWindow.swift:337 | aspect-ratio toggle | toolbar | `usesSquareThumbnails` | yes | — |
| MacMainWindow.swift:349-352 | Sort menu: Newest/Oldest First | menu | `timelineOrder` | yes | — |
| MacMainWindow.swift:360-369 | Filter menu: 8 `filterChoice` rows | menu | `quickFilters` set logic | yes | — |
| MacMainWindow.swift:378 | Info | toolbar | opens viewer (kept behavior per brief) | yes | — |
| MacMainWindow.swift:384 | Share | toolbar | toast "Sharing N selected items." / "Select an item…" — **no `NSSharingServicePicker`, no download** | toast-only | fix here |
| MacMainWindow.swift:393 | Favorite (disabled when empty) | toolbar | `toggleFavorite` → mutation + change-center patch | yes | — |
| MacMainWindow.swift:397 | Rotate (disabled when empty) | toolbar | persisted `rotate()` | yes (fixed this wave, `07e4aea7a`) | — |
| MacMainWindow.swift:403 | Select/Done | toolbar | selection mode + clear | yes | — |
| MacMainWindow.swift:411 | Manage (space destination only) | toolbar | opens manage sheet | yes | — |
| MacMainWindow.swift:415 | Sync (disabled while syncing) | toolbar | `state.syncNow()` | yes | — |
| MacMainWindow.swift:422 | Search field + submit | toolbar | jumps to `.search` destination | yes | — |
| MacMainWindow.swift:440-456 | Library switcher menu (All/Personal/spaces/libraries) | toolbar | `switcher` filter | yes | — |
| MacMainWindow.swift:903 | Retry | timeline error banner | `onRetry` → `reload()` | yes | — |

## Grid surface (MacCollectionGridView.swift / MacGridCell.swift)

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacGridCell.swift:53-118 | favorite NSButton (hover-revealed) | grid cell | `onFavorite` → `toggleFavorite` | yes | — |
| MacCollectionGridView.swift:422 | Return = open | grid (focused) | `onOpen` | yes | — |
| MacCollectionGridView.swift:433 | Space = preview | grid (focused) | `MacPreviewPanel.show` (real NSPanel + pipeline load, :1024) | yes | — |
| MacCollectionGridView.swift:100 + :21 | ⌘A Select All (menu posts, override + observer handle) | grid | `coordinator.selectAll()` | yes | — |
| — | right-click context menu — DOES NOT EXIST anywhere in grid | grid | — (U27 assumed a context-menu Rotate path; WP4-REPORT "context path" claim unverified) | broken (missing) | fix here (add menu incl. persisted Rotate, or record removal) |

## Menus (MacMenus.swift; all disabled when `actions == nil`)

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacMenus.swift:33 | New Library Window, ⇧⌘N | File | `openWindow(.library)` | yes | — |
| MacMenus.swift:35 | New Viewer Window (no shortcut) | File | grid: separate window (yes); viewer: `{}` | yes / no-op (benign: already viewing) | WP5-viewer (disable when in viewer; reason: viewer-owned context) |
| MacMenus.swift:39 | Import Files…, ⌘O | File | notification → `NSOpenPanel` → chooser | yes | — |
| MacMenus.swift:43 | Import from Camera… | File | notification → camera sheet | yes | — |
| MacMenus.swift:48 | Favorite, `.` | Image | `toggleFavorite` | yes | — |
| MacMenus.swift:51 | Rotate Clockwise, ⌘R | Image | persisted `rotate()` | yes (fixed this wave) | — |
| MacMenus.swift:55 | Add to Album… | Image | sheet; silently nil when selection empty | yes / edge no-op | fix here (disable when empty) |
| MacMenus.swift:57 | Move to…, ⇧⌘M | Image | sheet (broken sheet, see above); silently nil when empty | yes-path / broken-sheet + edge no-op | fix here |
| MacMenus.swift:61 | Delete, ⌘⌫ | Image | `trash()` + change post + toast | yes | — |
| MacMenus.swift:66 | Show Info, ⌘I | View | grid→viewer; viewer→inspector toggle | yes | — |
| MacMenus.swift:70 | Select All, ⌘A | View | notification → grid `selectAll()` | yes | — |
| MacMenus.swift:74 | Quick Look Preview, Space | View | grid→panel (yes); viewer→`{}` | yes / no-op | WP5-viewer (reason: viewer-owned; wire or disable) |
| MacMenus.swift:79 | Sync Now, ⌥⌘S | after Window list | notification → `syncNow()` | yes | — |

## Sidebar (MacSidebar.swift)

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacSidebar.swift:40 | New… | Shared Libraries section | `onNewSpace` → sheet → creates (mock-verified in Step 2) | yes | — |
| MacSidebar.swift:67 | New Album… | Albums section | `onNewAlbum` → sheet → creates | yes | — |
| MacSidebar.swift:59,85,114 | Albums / Captured With / collapsible DisclosureGroups | sidebar | native expand/collapse; **state not persisted** (brief requires persisting Albums) | yes-function / persistence gap | fix here (persist) |
| MacSidebar.swift:101 | asset drops on rows | album/library rows | add-to-album or move (library moves confirm) | yes | — |

## Viewer (MacViewer.swift — WP5-owned file; behavior judged, fix assigned there)

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacViewer.swift:112 | Back | viewer toolbar (inline) | `onClose` | yes | — (no action) |
| MacViewer.swift:116 | Favorite | viewer toolbar | `setFavorite` + refetch | yes | — (no action) |
| MacViewer.swift:119 | Rotate | viewer toolbar | `rotation += 90` display-only, never persisted (header: "display-only") | stub | WP5-viewer (persist via U27 path or remove; viewer-owned) |
| MacViewer.swift:120 | Delete | viewer toolbar | `trash` + refresh | yes | — (no action) |
| MacViewer.swift:121 | Move to… | viewer toolbar | move sheet (sheet broken) | yes-path / broken-sheet | fix here (sheet) |
| MacViewer.swift:122 | Add to Album | viewer toolbar | sheet | yes | — (no action) |
| MacViewer.swift:124 | Lock/Unlock (owner personal only) | viewer toolbar | auth + `setLocked` | yes | — (no action) |
| MacViewer.swift:129 | Edit | viewer toolbar | edit sheet (content WP5) | yes (wiring) | WP5-viewer (content; reason: WP5 owns `MacEditView.swift`) |
| MacViewer.swift:131 | Info | viewer toolbar | inspector toggle | yes | — (no action) |
| MacViewer.swift:132 | Live Text toggle | viewer toolbar | switches live-text/zoomable view + analysis | yes | — (no action) |
| MacViewer.swift:140,143,146 | move / add-to-album / edit sheets | viewer | wiring | yes | — / WP5 (edit content) |
| MacViewer.swift:161,162 | ← / → paging | viewer (focused; focus claimed on appear) | `page()` in display order | yes | — (no action) |
| MacViewer.swift:163 | Escape (inline only) | viewer | `onClose` | yes | — (no action) |

## Search + EXIF (MacSearchView.swift — WP6-owned file; all wired, no action)

Search :60, Scope :67, chips :91, suggestion rows :104, Filters disclosure :108, Favorites toggle :110,
Media-type picker :111, Location picker :116, Apply :121, recents :126, Clear :130, EXIF Copy value :389
/ Copy tag name :391 → **all yes** → WP6-page (reason: file owned by WP6; zero defects found here).

## Settings (MacSettings.swift)

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacSettings.swift:21 | Log Out | Settings › Account | `state.logout()` | yes | — |
| MacSettings.swift:24 | Default upload target picker | Settings › Uploads | `prefsMutations().update` persisted | yes | — |
| MacSettings.swift:31 | Import destination picker | Settings › Uploads | `UserDefaults Heirloom.importDestination` (read by chooser init) | yes | — |
| MacSettings.swift:41 | Show personal library toggle | Timeline Sources | prefs flag | yes | — |
| MacSettings.swift:56 | Show \<library\> toggles (owned ext. libs) | Timeline Sources | `hiddenOwnedLibraryIds` prefs | yes | — |
| — | Per-SPACE timeline toggles — MISSING | — | caption :52 promises "each library's manage view"; `MacSpaceManageSheet` has no visibility toggle | broken (missing) | fix here |
| MacSettings.swift:81 | Upload Now (disabled while draining) | Uploads in Flight | `uploadQueue.drain` + recount | yes | — |
| MacSettings.swift:89 | Sync in the background toggle | Background Agent | real `SMAppService` register/unregister + status note (helper packaging caveat documented in code) | yes | — |

## Storage (MacStorageView.swift, embedded in Settings)

| file:line | label / shortcut | where visible | action target | real effect | fix-or-assign |
|---|---|---|---|---|---|
| MacStorageView.swift:21,31 | Originals budget slider | Settings › Storage | `applyBudget` + pipeline budget + save | yes | — |
| MacStorageView.swift:44,51 | Keep-originals pin toggles | Storage | `pinnedContainerIds` saved | yes | — |
| MacStorageView.swift:66 | Refresh Usage | Storage | `pipeline.usage()` | yes | — |
| MacStorageView.swift:68 | Purge Unpinned…, destructive | Storage | evict + refresh | yes | — |

## Memories player (MacMemoriesView.swift — WP6-owned; all yes, no action)

Story open Buttons :27 → sheet :70; Music toggle :153 (drives `player.musicEnabled`, honest
no-licensed-tracks caption :161); Close :157 → **all yes** → WP6-page.

## Live video overlay (MacLiveVideo.swift — WP5-owned)

Mute :45 (`player.isMuted`) and Trim :53 (`onTrim` → viewer opens editor) → **both yes** → WP5-viewer.

## Parity-page navigation (WP6-owned files; all yes, no action)

`MacDuplicatesView.swift:33`, `MacMapPlacesView.swift:49` (open viewer), `MacAllAlbumsView.swift:22`
(open album) → WP6-page. Grid cell favorite counted under Grid.

## Editor (MacEditView.swift — WP5-owned file, judged en bloc)

Cancel+Escape :70, undo ⌘Z :74, redo :76, Copy/Paste edits :78-79, Revert :80, Save-failed alert OK :93,
Done ⌘S :84-86, Tool picker :147, Auto enhance :171, Light/Color/Detail groups :174/:183/:189,
sliders :206/:285/:331/:449/:538/:543, aspect :324, Rotate 90° :343, Flip H/V :344-345,
Auto-straighten :349, Reset crop :350, steppers :359/:368, Markup picker :482, width :500,
Clear markup :509, video Mute :551, video Rotate :554 → all wired in-editor → **yes (wiring)** →
WP5-viewer (reason: file exclusively WP5-owned; persistence/verify belongs to WP5).

## Non-control gaps noticed (not rows; Step 2 input)

- No `NSApplicationDelegateAdaptor` / `applicationShouldTerminate` anywhere: ⌘Q-with-sheet and the
  "N uploads in progress" guard are unhandled → fix here.
- U15/U16/U18 (toolbar per destination), U24/U25 (resolved titles), U17 (footer counts), U23 (empty
  states) involve no Button/Menu/etc. — Step 2 work, recorded here only so rows aren't expected.
- `MacAgentLoginItem`, `MacSidebarModel`, `MacSelection`, `MacAppState`, `FixtureSeed` contain no
  controls. No `.keyboardShortcut` outside those tabled. No other `.contextMenu` besides EXIF.

## Counts

- Total rows: 113 (editor counted as 1 grouped row covering 27 controls).
- yes: 97 (incl. 3 "yes (fixed this wave)": toolbar Rotate, ⌘R menu, gridActions path).
- toast-only: 1 (Share toolbar button).
- no-op: 4 (viewer New-Viewer-Window, viewer Quick-Look, Move/Add-to-Album with empty selection).
- stub: 1 (viewer Rotate display-only).
- broken: 10 (Move sheet Cancel/Escape, Add-to-Album Cancel/Escape, Manage Done Escape, New Space/Album/Camera/Chooser Escape ×4, per-space timeline toggle missing, grid context menu missing).
- Fix here (WP4 Step 2): 15 incl. Quit handling. WP5-viewer: 6 rows (editor group, viewer Rotate, viewer
  Quick-Look, viewer New-Viewer-Window, live-video pair, viewer Edit content). WP6-page: 4 rows
  (search group, memories group, parity nav, all already yes — ownership only).
