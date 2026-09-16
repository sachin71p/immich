# Heirloom macOS App: UI Performance & Functionality Reconnaissance

## 1. File Inventory

macOS Sources (28 files, 6,740 total lines):

| File | Lines | Purpose |
|------|-------|---------|
| MacEditView.swift | 1037 | Image/video metadata editor, crop/rotation/filter UI |
| MacMainWindow.swift | 929 | Main library window: sidebar + grid + toolbar + action coordination |
| MacGridView.swift | 752 | NSCollectionView grid: thumbnails, keyboard, selection, drag-drop |
| MacViewer.swift | 422 | Full-asset viewer: zoom, paging, Live Photo, video, inspector |
| MacSearchView.swift | 409 | Search query builder and timeline rendering |
| MacImport.swift | 391 | File/camera import UI and processing |
| MacAppState.swift | 234 | @Observable app state: server connection, sync, mutations |
| MacLibrarySheets.swift | 231 | Move/album/space management sheets |
| MacSidebarModel.swift | 205 | Sidebar menu: albums, spaces, views, counts |
| MacMemoriesView.swift | 204 | Memories/stories timeline display |
| MacLiveVideo.swift | 203 | Live Photo video playback |
| MacSidebar.swift | 177 | Sidebar navigation UI |
| MacMapPlacesView.swift | 172 | Geographic timeline clustering and map view |
| MacSettings.swift | 164 | Preferences, cache settings |
| MacDragDrop.swift | 156 | Drag-drop handlers and export logic |
| MacStorageView.swift | 144 | Storage usage dashboard |
| MacMoveSheet.swift | 136 | Destination chooser for move operations |
| MacPreviewCatalog.swift | 119 | SwiftUI Preview fixtures and preview modes |
| MacSelection.swift | 109 | Multi-selection tracking and state |
| MacMenus.swift | 90 | Focused value for menu actions (File/Edit/Image/View) |
| MacAllAlbumsView.swift | 85 | Album list view |
| MacDuplicatesView.swift | 77 | Duplicate detection and clustering |
| FixtureSeed.swift | 70 | UI smoke test fixture data |
| HeirloomMacOSApp.swift | 64 | App entry point, window management |
| MacConnectView.swift | 52 | Server connection/login UI |
| MacAgentLoginItem.swift | 42 | Background upload agent launcher |
| MacLiveText.swift | 41 | Vision text recognition overlay |
| MacPreviewFixtures.swift | 25 | Preview mode activation helpers |

Shared (3 files, ~150 lines):
- ConnectView.swift: Unified auth UI
- SharedContainer.swift: App Group container, Keychain, defaults
- LockedMediaAuthentication.swift: Face ID / Touch ID for locked assets

PhotosCore/Sources (key modules, ~9,250 lines):
- LocalStore (1,400 LOC): SQLite/GRDB schema, timeline/album/space queries
- Media (700 LOC): Nuke-backed pipeline, thumbhash→thumbnail→preview→original tiers
- SyncEngine (500 LOC): Server delta sync, mutation handling
- Editing (1,100 LOC): Edit recipes, rendering, persistence
- Search (500 LOC): Filter DSL, search queries
- CoreModel (1,100 LOC): Asset, Album, Space, User, Timeline data types

---

## 2. Main Grid / Timeline

**Container:** NSCollectionView (macOS-native, not LazyVGrid)

**Data flow:**
- `MacLibraryBrowser` → `MacGridLoader` (async fetch) → `MacCollectionGridView` (NSViewRepresentable)
- Grid rows: flattened array of `TimelineRow` (id/thumbhash/ratio/mediaKind/flags only, not full Asset)
- Sections: computed in `MacGridLoader.bucketed()` with year headers + month grouping
- No paging: loads all rows at once up to 250k limit; uses `completeViewLimit = 250_000`

**Query shape (LocalStore+Timeline):**
```sql
SELECT id, thumbhash, width, height, isFavorite, deletedAt, visibility, localDateTime,
  CASE WHEN livePhotoVideoId IS NOT NULL THEN 'livePhoto' ... END AS mediaKind
FROM asset
JOIN visibleAsset (filters out Live Photo videos)
WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked' AND strftime(...) = ?
ORDER BY asset.localDateTime DESC
LIMIT ? OFFSET ?
```
- Queries run async via `dbQueue.read { db in ... }` (background thread via GRDB)
- Date formatting happens in `bucketTitle()` on main thread (one DateFormatter per buck)

**ID handling:** Row `id` is asset ID; flattened into `flatIds: [String]` array for index lookup.

**Sorting/filtering in body:**
- `displayedSections` computed property filters rows by `quickFilters` (photos/videos/favorites)
- `matchesQuickFilter()` on main thread per row on every render
- Reverse order toggle creates two reversed arrays + reverses section order (O(n) copy)
- Date range footer computed from `loader.sections.flatMap(\.rows)` every render

**Work in body:**
- Section reverse + filter happens every render (displayedSections is computed, not cached)
- DateFormatter created once but `.dateFormat` reassigned per bucket (cheap but visible)

---

## 3. Thumbnail Pipeline

**Fetch initiation:** `MacGridCell.itemForRepresentedObjectAt()` line 516
```swift
cell.loadTask = Task {
  for try await step in await pipeline.stream(asset: asset, tier: .thumbnail) {
    // yield placeholder, disk cache, then network tiers
  }
}
```

**Tiers:** thumbhash placeholder → disk cache (any tier) → .thumbnail (150px) → .preview (800px) → .original

**Caching:**
- Memory: Nuke's ImageCache, 15% of RAM clamped 32–256 MB
- Disk: `TieredMediaCache` with per-tier subdirs, no eviction policy documented
- ThumbHash: decoded once per asset, returned as NSImage

**Decode:** Synchronous (on background Task) via `ThumbHash.decode()` + `makeCGImage()`

**Cancellation:** `cell.prepareForReuse()` calls `loadTask?.cancel()` when cell recycled during scroll

**Prefetch:** Not implemented for grid scroll (unlike iOS with `UICollectionViewDataSourcePrefetching`)

**Decode on main thread:** NO — MediaPipeline operations run in `Task.detached` (background executor)

**Image update:** `MainActor.run { box.setImage() }` batches updates back to main for UI

---

## 4. State Management

**Single giant object:** `MacAppState` (@Observable, 28 properties)

```swift
@Observable final class MacAppState:
  var serverURL, userId, isConnected
  var store, connection, sync, uploadQueue, pipeline, diskCache
  var prefs, spaces, libraries, albums, cameras, cameraCategories
  var lastSyncError, lastCompletedSyncAt, isSyncing
  var pendingImportURLs, viewerContext, showingImportChooser, showingCameraImport
```

**Mutating property:** Any change to any property invalidates the entire window's body.

**Observation hierarchy:**
- `MacMainView` → `MacLibraryBrowser` (bindable to state)
- Every subview that reads `state.userId`, `state.spaces`, etc. observes all changes
- SidebarModel, GridLoader, etc. hold no independent state; they re-read from store

**Derived state:**
- `MacGridLoader` (@Observable, 4 properties): sections, assetsById, isLoading, error — independent from MacAppState
- `GridSelectionModel` (GridSelectionState value type): selectedIds, selectedInOrder — managed locally
- `MacSidebarModel` (@Observable): reads store for album/space counts every render

**Refresh pattern:**
```swift
func refresh() async {
  prefs = try await store.prefs(for: userId)
  async let s = store.memberSpaces(for: userId), l = store.accessibleLibraries(...), a = store.memberAlbums(...)
  spaces, libraries, albums = try await (s, l, a)  // all fetched concurrently, then assigned (triggers rerender)
}
```

**No granular invalidation:** Every mutation (`setFavorite`, `trash`, `move`) calls `await reload()` on grid, which re-queries from scratch.

---

## 5. Data Layer

**Tech:** GRDB (Swift wrapper over SQLite)

**All queries async:** `dbQueue.read { db in ... }` or `dbQueue.write { db in ... }` — GRDB's background serial executor

**Schema:** 20+ tables (asset, album, space, library, user, exif, etc.) defined in LocalStore+Schema.swift (300 LOC)

**No main-thread queries:** Examined LocalStore+Timeline, LocalStore+Browse, LocalStore+Context — all use `await dbQueue.read/write`.

**Timeline query latency sources:**
1. `timelineBuckets()`: GROUP BY localDateTime with COUNT(*), ORDER BY bucketKey DESC
2. Per-bucket `timelineAssets()`: fetches all rows in bucket (up to bucket.count rows), ordered by localDateTime DESC
3. For large months (10k+ assets): single GROUP BY query fast, but 12 sequential `timelineAssets()` calls (one per month) add up

**No indexes documented:** Asset table queries on localDateTime, visibility, deletedAt — assume SQLite uses default indexed columns.

---

## 6. Viewer

**Full-size loading:** `MacViewerView` → `MacZoomableImageView` (NSScrollView-backed)

- Starts at `.thumbnail` tier, upgrades on pinch zoom >2×
- `MediaPipeline.stream()` yields tiers progressively
- Zoom tracking via NSScrollView magnification KVO (lines 354–375)

**Paging:** Arrow-key navigation via `handleKey()` in grid coordinator
- Updates `assetId` @State in inline viewer
- Standalone viewer opens new NSWindow via `openWindow(value: MacWindow.viewer(nextId))`

**Preloading:** Not implemented — viewer loads only current asset, neighbors load only on navigation

**Sibling context:** `state.viewerContext: [String]` set when viewer opens; used for arrow-key bounds

---

## 7. Actions / Buttons Inventory

**Source:** MacMenus.swift (menu definitions) + MacMainWindow.swift (implementations)

| Action | Menu | Grid | Viewer | Implementation | Status |
|--------|------|------|--------|-----------------|--------|
| Favorite | Image > Favorite | ✓ | ✓ Button | `toggleFavorite(ids:)` calls `setFavorite()` mutation | **OK** |
| Rotate | Image > Rotate Clockwise | ✓ | ✓ Button | Grid: `rotate: {}` **EMPTY** / Viewer: `rotation += 90` | **BROKEN (grid only)** |
| Delete | Image > Delete | ✓ | ✓ Button | `trash(ids:)` calls mutation, shows toast | **OK** |
| Move to… | Image > Move | ✓ | ✓ Button | Opens `MacMoveSheet`, calls `performMove()` | **OK** |
| Add to Album | Image > Add to Album | ✓ | ✓ Button | Opens `MacAddToAlbumSheet` | **OK** |
| Show Info | View > Show Info | ✓ | ✓ Button | Grid toggleInspector opens inline viewer / Viewer shows inspector panel | **OK** |
| Select All | View > Select All | ✓ | ✗ | `selectAll()` in coordinator, notification-based | **OK** |
| Quick Look | View > Quick Look Preview | ✓ | ✗ | `showPreview(id:)` calls `MacPreviewPanel.show()` | **OK** |
| Open Viewer | File > New Viewer Window | ✓ | ✗ | Opens separate NSWindow with `MacWindow.viewer(id)` | **OK** |
| Import Files | File > Import Files | ✗ | ✗ | Posts notification, triggers sheet | **OK** |
| Import Camera | File > Import from Camera | ✗ | ✗ | Posts notification, triggers sheet | **OK** |
| New Library Window | File > New Library Window | ✗ | ✗ | `openWindow(value: MacWindow.library)` | **OK** |
| Sync Now | Window > Sync Now | ✗ | ✗ | `state.syncNow()`, shows disabled state | **OK** |

**Broken/Stub buttons:**
- **Line 646 in MacMainWindow.swift:** `rotate: {}` in `gridActions` — empty closure, does nothing. Viewer rotate works.
- Reason: Immich server doesn't support persisted image rotation (A9 task mentions "display-only until A8 persists edits")

**Menu disablement:** `actions?.favorite()` etc. disabled when `actions == nil` (no grid selection or inline viewer active) — correct pattern

---

## 8. TODO / FIXME / HACK Markers

Searched all scope files:

| File | Line | Marker |
|------|------|--------|
| PhotosCore/Sources/Search/SearchService.swift | (no line given) | "server may return null entries (known upstream TODO)" | 

Only one upstream TODO found; no FIXMEs, HACKs, or "not implemented" strings in macOS/Shared/PhotosCore.

**Suspicious patterns (not markers, but notable):**
- MacGridView line 365–368: Comment about `estimatedItemSize` causing infinite recursion loop on 100k+ items — reverted to full layout (side effect: multi-second launch lag for huge libraries)
- MediaPipeline: No error handling for offline + no cached tier (throws `MediaError.unavailableOffline`)

---

## 9. Build / Run

**Makefile targets** (native-apple relevant):
- `make build-ios`: Xcode build for iOS Simulator
- `make build-macos`: Xcode build for macOS (ad-hoc signed)
- `make install-macos`: Builds + installs to /Applications
- `make mock-server`: Starts local Heirloom server via Docker Compose
- `make ios-sim`: Full end-to-end (server + iOS build + simulator + launch)

**Xcode schemes:**
- `Heirloom-iOS.xcscheme`: iOS app + UI tests
- `Heirloom-macOS.xcscheme`: macOS app, no UI tests (Heirloom-macOS-UITests exists but not in scheme)

**Server URL / credentials:**
- Hardcoded in Makefile: `SERVER_URL := http://localhost:2283`
- At runtime: read from SharedContainer.sharedDefaults (saved on login)
- Keychain stores token; missing token → ConnectView prompts for login

**Fixture mode:**
- Activated by: `--fixture-seed` command-line arg or environment variable
- `FixtureSeed.swift` (70 LOC): Returns hardcoded library + 20 assets for UI smoke test
- `MacPreviewCatalog.swift`: SwiftUI preview fixtures for individual components
- `MacPreviewFixtures.swift`: Catalog of preview-mode asset card variants

**App launch flow:**
1. `HeirloomMacOSApp.swift` → `MacAppState.standard()` (loads DB + token from Keychain)
2. `adoptKeychainSession()` async → verifies token still valid
3. `MacMainWindow(state:)` routes to library or viewer
4. No URL scheme or launch arguments route to specific assets yet

---

## 10. Existing Performance-Related Notes in `.claude/plans/`

| Path | Relevance |
|------|-----------|
| shared-libraries/APPLE-BUILD-BRIEF.md | Build warnings, Swift 6 concurrency fixes (no runtime perf notes) |
| shared-libraries/STATUS.md | Test coverage, no macOS perf mentions |
| deploy-heirloom-prod.md | Server deployment, not app-side |
| No dedicated macOS perf doc | **None found** |

---

## Summary of Findings

**UI Lag Risk Vectors:**
1. **macOS-specific:** NSCollectionView layout pass on 100k+ items (line 365–368: known issue, `estimatedItemSize` reverted)
2. **Filter/sort on main thread:** `displayedSections` computed every render, `matchesQuickFilter()` iterates all rows
3. **State invalidation:** Any `@Observable` MacAppState change re-renders entire window
4. **No grid prefetch:** Unlike iOS, thumbnails load only on-demand; fast scroll freezes until nearby cells load
5. **No paging:** Full 250k row timeline fetched into memory at once (design choice: simplifies A0 arch but limits scale)

**Non-Functional Buttons:**
1. **Grid Rotate (line 646 MacMainWindow.swift):** Empty closure `rotate: {}` — intentional stub, server doesn't persist rotation yet

**Data Layer:** Solid — all DB queries async, no main-thread blocking detected.

**MediaPipeline:** Solid — progressive tiers, cancellation on scroll, Nuke handles memory/disk caching.
