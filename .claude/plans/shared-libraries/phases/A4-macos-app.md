# A4 — macOS app: Photos-for-Mac style shell

Depends on: A2 · Parallel-safe with A3 · Reads: A0 Architecture+Rules · DECISIONS §4, §6, §9 · handoffs A1, A2.

## Tasks
1. Window: `NavigationSplitView` sidebar — Library (Library, Collections), Pinned: Favorites, Recently Saved,
   Map, People, Memories; Media Types; Shared Libraries (each space + "New…"); Shared External Libraries; Albums
   (folders later), Shared Albums; Utilities: Imports, Recently Deleted, Hidden, Archive. Sidebar drop targets:
   drop assets on an album (add) or on a library (move, confirm dialog).
2. Grid: AppKit `NSCollectionView` wrapped for SwiftUI; toolbar zoom slider (column size), Years/Months/All Photos
   segmented control, library switcher popup (same options as iOS), marquee + ⌘/⇧ selection, full keyboard
   navigation, type-to-jump by date, space bar = Quick Look-style preview, return = open.
3. Viewer: in-window and full-screen, arrow keys paging, pinch/scroll zoom with tier upgrade, Info inspector (⌘I)
   floating panel, favorite (.), rotate (⌘R), delete (⌘⌫), move to… (menu + ⌘⇧M), add to album.
4. Menus & shortcuts mirroring Photos for Mac conventions (File/Edit/Image/View/Window), multiple windows,
   state restoration.
5. Drag & drop out: export originals or edited renders to Finder (file promises); drag in: files/folders → import
   (A5 wires the upload queue; here just the UI + destination library chooser).
6. Shared libraries/albums management UIs as sheets (same Core calls as iOS).
7. Settings window: server/account, default upload target, import destination default, timeline sources,
   cache/offline (A6), agent (login item) toggle placeholder (A5).

## Tests
UI smoke: launch with fixture DB → sidebar + grid render; keyboard selection; move sheet targets.

Verify: `native-apple/scripts/verify.sh mac`.
