# A3 — iOS app: library, collections, viewer, shared libraries, move

Depends on: A2 · Parallel-safe with A4 · Reads: A0 Architecture+Rules · DECISIONS §4, §6, §9 · handoffs A1, A2.

## Tasks
1. Library grid: UIKit `UICollectionView` (compositional/custom layout) hosted in SwiftUI; zoom levels Years → Months →
   Days → All Photos with pinch to change column count (3/5/7/…); date scrubber; smooth 120 Hz scrolling with the A2
   prefetcher; aspect/square toggle; badges (video duration, live, favorite, container icon for space/library assets).
2. Library switcher (Apple-style menu in the top bar): Both/all timeline sources · Personal · each shared library ·
   each shared external library (DECISIONS §9 explicit filter); "Show in timeline" management sheet.
3. Collections screen: Albums, Shared Albums, Shared Libraries, People (per-owner, §11), Places (map), Favorites,
   Recents, Media Types, Utilities (Recently Deleted = trash manage scope, Hidden, Archive).
4. Viewer: horizontal paging, pinch/double-tap zoom with progressive tier upgrade, swipe-down dismiss with matched
   transition from grid cell, swipe-up info panel (date, location mini-map, camera/lens/exposure summary, container,
   people, albums, "All metadata" placeholder for A7), toolbar: share, favorite, info, edit (A8), delete, … menu
   (move to…, add to album, archive, hide, copy).
5. Multi-select: drag-to-select, select all per section, action bar (share, favorite, add to album, move to…, archive,
   delete). Move sheet uses `Rules.MoveTargets` and shows per-asset results.
6. Shared libraries: list, detail (timeline scoped by spaceId), create, rename, members (add/remove, leave, transfer,
   delete with consequences text from §8).
7. Albums & shared albums: create, add/remove (any member, R11), share with users, album timeline.
8. Settings: server/account, default upload target, timeline sources, cache usage (A6 fills in), about.
9. Permission-aware UI everywhere via `Rules.Permissions`.

## Tests
UI smoke tests (launch with fixture DB → grid renders; open viewer; select + move sheet lists correct targets).

Verify: `native-apple/scripts/verify.sh ios`.
