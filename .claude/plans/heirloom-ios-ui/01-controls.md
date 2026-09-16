# Heirloom iOS Control Inventory

## ConnectView — native-apple/Apps/Shared/ConnectView.swift:5

Login screen before session is established.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| "Server URL" | TextField | :14 | Sets `serverURL` state | WIRED |
| "Email" | TextField | :15 | Sets `email` state | WIRED |
| "Password" | SecureField | :16 | Sets `password` state | WIRED |
| "Connect" | Button | :17 | `connect()` → validates URL, calls ImmichConnection.ping(), .login(), saves token to Keychain | WIRED |
| Status text | Text | :18 | Shows connection status or error | FIXTURE-ONLY |

---

## MainTabs — native-apple/Apps/iOS/Sources/HeirloomIOSApp.swift:57

Root tab bar after login. Selection binding allows `OpenSearchIntent` to land on Search tab.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| Library tab | TabItem + Label(systemImage: "photo") | :65 | Selects `requestedTab = "library"` | WIRED |
| Collections tab | TabItem + Label(systemImage: "square.grid.2x2") | :69 | Selects `requestedTab = "collections"` | WIRED |
| Search tab | TabItem + Label(systemImage: "magnifyingglass") | :75 | Selects `requestedTab = "search"` | WIRED |
| Shared tab | TabItem + Label(systemImage: "person.2") | :81 | Selects `requestedTab = "shared"`, hosts SpacesListView | WIRED |
| Settings tab | TabItem + Label(systemImage: "gear") | :84 | Selects `requestedTab = "settings"` | WIRED |

---

## Library — native-apple/Apps/iOS/Sources/LibraryGrid.swift:537

Main photo library grid with multi-select, zoom levels, date scrubber, and filtering.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| **Grid** | UICollectionView (PhotoGridView) | :576 | Displays buckets/rows of assets in adaptive grid layout | WIRED |
| **Cell tap** | Gesture (didSelectItemAt) | :458 | If editMode: toggle selection; else: launch ViewerView | WIRED |
| **Cell long-press** | (via BucketHeaderView) | :164 | Bucket header "Select" button toggles editMode and calls selectAll(section) | WIRED |
| **Pinch gesture** | UIPinchGestureRecognizer | :432 | Adjusts columns: scale>1.3 decreases; scale<0.77 increases; steps [2,3,5,7,10] | WIRED |
| **Pan drag (edit mode)** | UIPanGestureRecognizer | :443 | In editMode, dragging adds cells to selection | WIRED |
| **Pull-to-refresh** | UIRefreshControl | :238 | Calls `refreshAll()` → syncNow() + reload() | WIRED |
| **Library switcher** (top-left menu) | Menu | :609 | Options: Both Libraries, Personal, spaces (by name), libraries (by name), Show in Timeline… | WIRED |
| **Zoom minus** (top-right) | Button(systemImage: "minus") | :633 | `columns = max(2, columns - 1)` | WIRED |
| **Zoom plus** (top-right) | Button(systemImage: "plus") | :634 | `columns = min(10, columns + 1)` | WIRED |
| **Select/Done** (top-right) | Button | :635 | Toggles `editMode`; clears selection on exit | WIRED |
| **Date scrubber** (right edge) | Slider (vertical) | :594 | Binding to `scrubIndex`; only shown if buckets.count > 1; triggers scroll | WIRED |
| **Zoom picker** (bottom) | Picker(segmented) | :652 | Years/Months/Days/All Photos; updates columns + calls reload() | WIRED |
| **Square toggle** (bottom) | Toggle | :659 | Toggles `squareCells`; affects layout aspect ratio | WIRED |
| **Sync error banner** (top) | HStack with Retry + Dismiss | :556 | Shows `session.lastError`; Retry calls `refreshAll()`; Dismiss clears error | WIRED |
| **SelectionActionBar** (bottom, edit mode) | View | :645 | Shows count; buttons: Share, Favorite, Add to Album, Archive, Move to…, Delete, Clear | WIRED |
| **MoveSheet** | Sheet | :675 | On move action; lists move targets; shows per-asset results | WIRED |
| **TimelineSourcesSheet** | Sheet | :683 | On "Show in Timeline…"; toggles containers in timeline | WIRED |
| **Action error alert** | Alert | :687 | Shown if action fails (move, delete, etc.) | WIRED |

**Section header (BucketHeaderView)**: Title (date formatted) on left; "Select" button on right (hidden unless editMode).

---

## Viewer — native-apple/Apps/iOS/Sources/Viewer.swift:153

Full-screen horizontal paging photo/video viewer with progressive tier upgrades, gestures, and toolbar actions.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| **Pager** | TabView(.page) | :172 | Horizontal paging over asset ids; selection binding to `currentId` | WIRED |
| **Close** (cancellationAction, top-left) | Button(systemImage: "xmark") | :185 | Calls `dismiss()` | WIRED |
| **Share** (toolbar, permission-gated) | Button | :250 | Downloads original asset, presents UIActivityViewController | WIRED |
| **Favorite** (toolbar, permission-gated) | Button | :255 | Toggles `asset.isFavorite` via mutations.setFavorite(); heart/heart.fill icon | WIRED |
| **Info** (toolbar) | Button | :264 | Shows ViewerInfoPanel sheet | WIRED |
| **Edit** (toolbar, permission-gated) | Button | :266 | Opens EditView fullScreenCover | WIRED |
| **Delete** (toolbar, role:.destructive, permission-gated) | Button | :269 | Calls mutations.trash([asset.id]); dismisses viewer | WIRED |
| **More menu** (toolbar, ellipsis.circle) | Menu | :276 | Options: Move to…, Add to Album, Archive/Unarchive, Hide/Unhide, Lock/Unlock (auth required), Copy | WIRED |
| **Double-tap** (image) | UITapGestureRecognizer | :38 | Toggles zoom: 1x ↔ 3x via setZoomScale() | WIRED |
| **Single-tap** (image) | UITapGestureRecognizer | :41 | Hides/shows toolbar and chrome | WIRED |
| **Pinch zoom** (image) | UIScrollView delegate | :29 | Min 1x, max 6x | WIRED |
| **Swipe-down dismiss** | DragGesture | :235 | If translation.height > 140 && abs(translation.width) < 80: dismiss() | WIRED |
| **ViewerInfoPanel** (sheet) | NavigationStack + List | :194 | Shows details (date, file, dimensions, container), location map, camera EXIF, people, albums, full metadata | WIRED |
| **MoveSheet** (sheet) | MoveSheet | :200 | Move current asset to another container | WIRED |
| **AlbumPickerSheet** (sheet) | AlbumPickerSheet | :208 | Add current asset to album | WIRED |
| **EditView** (fullScreenCover) | EditView | :214 | Full-screen editor; calls `downloadOriginal()` for preview | WIRED |
| **Action error alert** | Alert | :225 | Shown if toolbar action fails | WIRED |

**ZoomableImageView**: Still image with VisionKit Live Text interaction (ImageAnalysis). Progressive tier upgrade from thumbnail → preview → fullsize.

**VideoPage**: Video player (AVKit); trim button opens EditView.

**LivePhotoPageView**: Live photo with motion video.

---

## Collections — native-apple/Apps/iOS/Sources/Collections.swift:77

Grouped navigation to albums, shared libraries, people, memories, places, favorites, recents, media types, utilities.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| **Album links** (non-shared) | NavigationLink | :107 | Opens AlbumDetailView(album) | WIRED |
| **Shared Albums** | NavigationLink (to sub-List) | :111 | Filtered view of albums with > 1 member | WIRED |
| **Space links** | NavigationLink | :122 | Opens SpaceDetailView(spaceId) | WIRED |
| **Library links** | NavigationLink | :127 | Opens LibraryDetailView(library) | WIRED |
| **Person links** | NavigationLink | :136 | Opens PersonDetailView(person) | WIRED |
| **Memories** | NavigationLink(MemoriesView) | :150 | Accessibility ID: "collections-memories" | WIRED |
| **Map** | NavigationLink(PlacesView) | :158 | Shows clustered map of GPS-tagged assets | WIRED |
| **Favorites** | NavigationLink(AssetRowList) | :171 | List of favorite assets with counts | WIRED |
| **Recents** | NavigationLink(AssetRowList) | :176 | Recent assets with counts | WIRED |
| **Media Types** (Photos, Videos, Panoramas, Screenshots, Live) | NavigationLink(AssetRowList) | :183 | Media type filtered lists | WIRED |
| **Recently Deleted** | NavigationLink(AssetRowList) | :190 | Trashed assets (trash manage scope) | WIRED |
| **Hidden** | NavigationLink(AssetRowList) | :193 | Hidden visibility assets | WIRED |
| **Duplicates** | NavigationLink(DuplicateGroupsView) | :196 | Groups with suggested keep/remove indicators | WIRED |
| **Captured by Me** | NavigationLink(AssetRowList) | :199 | Assets where ownerId == session.userId | WIRED |
| **Archive** | NavigationLink(AssetRowList) | :202 | Archived visibility assets | WIRED |
| **Locked** (requires auth) | Button→navigationDestination | :205 | Calls LockedMediaAuthentication.authenticate() first | WIRED |
| **Captured With** (camera categories) | NavigationLink(CameraCategoryAssetList) | :216 | Grouped by Phone/DSLR/Drone/Action Camera | WIRED |
| **Pull-to-refresh** | .refreshable modifier | :224 | Calls `reload()` | WIRED |

**AssetRowList**: Shared row-list component with thumbnails, timestamps, favorite badges.

---

## Search — native-apple/Apps/iOS/Sources/SearchView.swift:13

Query + filter-driven search with server fallback, suggestions, and recent searches.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| **Search field** | TextField | :58 | Queries `query` state; onSubmit calls `runSearch()` | WIRED |
| **Clear (in field)** | Button(xmark.circle.fill) | :63 | Sets `query = ""` | WIRED |
| **Search submit** | Button("Search") | :66 | Calls `runSearch()` | WIRED |
| **Scope picker** | Picker(.menu) | :75 | All/Personal/Spaces/Libraries; onChange triggers search if hasSearched | WIRED |
| **Suggestion chips** | Button row (horizontal) | :140 | Toggles `chip` (SuggestionKind); calls `loadSuggestions()` | WIRED |
| **Suggestions** | Button list | :104 | Applies suggestion to filter via `applySuggestion()` | WIRED |
| **Filters disclosure** | DisclosureGroup | :155 | Camera make/model/lens textfields, favorites toggle, media type + location pickers | WIRED |
| **Apply filters** | Button | :170 | Calls `runSearch()` with current filters | WIRED |
| **Recent searches** | Button list | :120 | Applies recent filter via `applyRecent()` | WIRED |
| **Clear recents** | Button(role:.destructive) | :124 | Clears RecentSearchStore | WIRED |
| **Results grid** | PhotoGridView | :186 | Read-only grid; no select/zoom/refresh | WIRED |
| **Cell tap (results)** | Gesture | :189 | Opens ViewerView over results | WIRED |
| **Search loading** | ProgressView | :180 | Shown while `isSearching` | WIRED |
| **No results** | ContentUnavailableView | :182 | Shows if results empty and searchError | WIRED |

**FullExifBrowser** (in ViewerInfoPanel): Grouped, searchable full EXIF metadata with copy-value context menu.

---

## Settings — native-apple/Apps/iOS/Sources/Settings.swift:10

Account, sync, backup, upload target, storage, cache, preferences.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| **Sync Now** | Button | :21 | Calls `session.syncNow()`; disabled if `isSyncing` | WIRED |
| **Last synced** | LabeledContent | :26 | RelativeDateTimeFormatter display | WIRED |
| **Syncing progress** | ProgressView | :29 | Shows "Syncing…" if `session.isSyncing` | WIRED |
| **Sync error** | Text | :32 | Shows red error text if `session.lastError` | WIRED |
| **Server** | LabeledContent | :39 | Display only | FIXTURE-ONLY |
| **User ID** | LabeledContent | :40 | Display only | FIXTURE-ONLY |
| **Fixture mode notice** | Text | :42 | Shows if `isFixture` | FIXTURE-ONLY |
| **Sign Out** | Button(role:.destructive) | :46 | Calls `session.signOut()` | WIRED |
| **Upload target** | Picker | :161 | Personal/Spaces menu; updates `session.prefs.defaultUploadTarget` | WIRED |
| **Backup settings** | BackupSettingsSection | :54 | Toggle backup, album picker, source picker, notification toggle, limited library picker | WIRED |
| **Timeline Sources** | Button→Sheet | :57 | Opens TimelineSourcesSheet | WIRED |
| **Show Personal** | Toggle | :58 | Toggles `session.prefs.showPersonalInTimeline` | WIRED |
| **Free Up Space** | NavigationLink | :65 | Accessibility ID: "settings-freeup" | WIRED |
| **Optimize Storage** | Toggle | :71 | Toggles `storage.optimizeStorage`; limits original tier budget | WIRED |
| **Optimize Storage info** | Text | :76 | Explains thumbnail-only + shrunk original behavior | FIXTURE-ONLY |
| **Cache Usage** | LabeledContent (per tier) | :82 | Displays bytes per MediaTier | FIXTURE-ONLY |
| **About** | LabeledContent + Text | :88 | Heirloom version/info + design philosophy | FIXTURE-ONLY |

**TimelineSourcesSheet**: Toggles which containers appear in timeline (personal preference, space member "show in timeline", libraries read-only).

**BackupSettingsSection**: Enable/disable backup, select albums, choose backup source, notifications, limited library picker.

---

## Shared (Spaces) — native-apple/Apps/iOS/Sources/Spaces.swift:7

List of shared libraries; "New Shared Library" button.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| **Space links** | NavigationLink | :13 | Opens SpaceDetailView(spaceId) | WIRED |
| **New Shared Library** | Button | :20 | Accessibility ID: "plus" + "New Shared Library" label; shows SpaceCreateSheet | WIRED |
| **SpaceCreateSheet** | Sheet | :23 | Form with name TextField, Create button; creates space | WIRED |
| **SpaceDetailView** | NavigationStack + List | :72 | Timeline (recent assets), Members (with remove for contributors), Manage (rename/transfer/delete/leave) | WIRED |
| **Rename** (sheet) | SpaceRenameSheet | :148 | TextField + Save button | WIRED |
| **Add Members** (sheet) | SpaceAddMemberSheet | :152 | TextField (user ID/email) + Add button | WIRED |
| **Transfer Ownership** (sheet) | SpaceTransferSheet | :158 | Picker of contributors; Transfer button swaps owner/contributor roles | WIRED |
| **Delete Shared Library** (alert) | Alert | :164 | Confirms deletion; assets return to personal libraries | WIRED |
| **LibraryDetailView** | NavigationStack + List | :378 | Read-only timeline; no management (admin-only upstream) | WIRED |

---

## Albums — native-apple/Apps/iOS/Sources/Albums.swift:11

Album detail with asset management, members, sharing, rename/delete.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| **Edit toggle** (toolbar) | Button | :87 | Toggles `editMode`; shows "Edit" or "Done" | WIRED |
| **Asset cells (view mode)** | Button | :42 | Taps open ViewerView | WIRED |
| **Asset cells (edit mode)** | Checkbox buttons | :32 | Toggle `removeIds` set | WIRED |
| **Remove selected** (edit mode) | Button(role:.destructive) | :57 | Calls `mutations.removeAssets(Array(removeIds), fromAlbum:)` | WIRED |
| **Share with Users** | Button→Sheet | :72 | Opens AlbumShareSheet | WIRED |
| **Rename** | Button→Sheet | :76 | Opens AlbumRenameSheet; requires editor/owner role | WIRED |
| **Delete Album** | Button(role:.destructive)→Alert | :77 | Confirms deletion; assets stay in libraries | WIRED |
| **AlbumCreateSheet** | Sheet | :154 | Form with name TextField; creates album + adds assets | WIRED |
| **AlbumRenameSheet** | Sheet | :197 | TextField (pre-filled); Save button | WIRED |
| **AlbumShareSheet** | Sheet | :239 | TextField (user ID/email); Share button calls `mutations.shareWithUsers()` | WIRED |
| **AlbumPickerSheet** | NavigationStack + List | :284 | Button list of albums; "New Album" button opens AlbumCreateSheet | WIRED |

---

## Memories — native-apple/Apps/iOS/Sources/MemoriesView.swift:12

Story player with auto-advance and "On This Day" shelf.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| **Story cards** (horizontal scroll) | Button | :29 | Taps set `playingStory`; shows first asset thumbnail + title | WIRED |
| **Story player** (sheet modal) | (inline full-screen overlay) | — | Auto-advances through story.assetIds; music toggle (preference-only, no licensed tracks) | STUB |
| **On This Day rows** | Button | :57 | Taps open ViewerView over "On This Day" selection | WIRED |

---

## Places (Map) — native-apple/Apps/iOS/Sources/Albums.swift:381

Clustered map of GPS-tagged assets.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| **Map** | ClusteredMapView | :403 | Displays map clusters + markers; onSelect/onZoomChange callbacks | WIRED |
| **Map interaction** | Gesture (custom) | — | Tap cluster/marker calls onSelect(); pinch changes zoom level → onZoomChange | WIRED |
| **Selection grid** (below map) | Button rows | :414 | Tap row opens ViewerView over selected asset IDs | WIRED |
| **Located Assets list** (below selection) | Button rows | :430 | Tap row opens ViewerView over all located assets | WIRED |

---

## Viewer Edit — native-apple/Apps/iOS/Sources/EditView.swift:17

Full-screen image/video editor with history, crop, rotation, filters, blur.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| **Cancel** (top-left) | Button | :75 | Dismisses; disabled while `saving` | WIRED |
| **Undo/Redo** (top-center) | Buttons | :78 | Navigation through `history`; disabled when at start/end | WIRED |
| **Done** (top-right) | Button | :79 | Calls `save()`; disabled if `!history.isDirty` or still `saving` | WIRED |
| **Tool selector** (horizontal scroll) | Button row | :235 | Crop, Adjust, Filters, Blur; each sets `adjustParam` | WIRED |
| **Aspect ratio buttons** | Button row | :349 | Free, Original, 1:1, 4:3, 3:2, 16:9, etc.; calls `applyAspect()` | WIRED |
| **Reset crop** | Button | :353 | Calls `Task { await resetCrop() }` | WIRED |
| **Rotate 90°** | Button | :364 | Incremental rotation | WIRED |
| **Flip H / Flip V** | Buttons | :371, :378 | Horizontal/vertical flip | WIRED |
| **Auto straighten** | Button("Auto") | :385 | Calls `autoStraighten()` | WIRED |
| **Adjustment sliders** (Brightness, Contrast, Saturation, etc.) | Slider + -/+ buttons | :401, :403 | ±5 step increments; wrappedValue binding | WIRED |
| **Blur controls** | Sliders + toggles | :542, :584 | Portrait depth blur strength, Mute audio toggle | WIRED |
| **Save error alert** | Alert | :86 | Shows error if save fails | WIRED |

---

## Free Up Space — native-apple/Apps/iOS/Sources/FreeUpSpaceView.swift:14

Delete backed-up photos from device with preview and batch deletion.

| Control | Kind | file:line | What the action does | Status |
|---------|------|-----------|----------------------|--------|
| **Keep favorites** | Toggle | :69 | `storage.keepFavoritesOnFreeUp`; Accessibility ID: "freeup-keep-favorites" | WIRED |
| **Only older than date** | Toggle + DatePicker | :71, :73 | `useCutoffDate` gate; selection binding to `cutoffDate` | WIRED |
| **Keep last N days** | Toggle + Stepper | :75, :77 | `useAgeWindow` gate; Stepper range 1-365 | WIRED |
| **Keep Albums** | CheckBox list | (line 80+) | Select which albums to exclude from deletion | WIRED |
| **Check What's Backed Up** | Button | :40 | Queries server + device, shows candidate count; Accessibility ID: "freeup-check" | WIRED |
| **Preview section** | List of candidates | — | Shows count + total bytes to delete; "Delete" button proceeds | WIRED |
| **Delete** | Button | — | Batched deletion with system Photos confirmation; shows progress | WIRED |
| **Done section** | Summary | — | Shows deleted count; offers Photos app link to Recently Deleted | WIRED |

---

# Layout Facts

## PhotoGridViewController Cell Sizing & Layout

**File**: `native-apple/Apps/iOS/Sources/LibraryGrid.swift`

**Cell computation** (line 334-360, `makeLayout()`):
- Uses `NSCollectionViewCompositionalLayout`
- Square cells: `NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / count), heightDimension: .fractionalWidth(1.0 / count))`
- Aspect cells: `NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / count), heightDimension: .estimated(120))`
- Count from `columns` state (range: 2–10)
- Item insets: 1pt top/bottom/left/right (line 347)

**What decides aspect vs. square**:
- `squareCells` Boolean state (line 543)
- Toggle in bottom safeAreaInset (line 659)
- Default: false (aspect)

**Zoom levels** (line 13–40, `LibraryZoomLevel` enum):
- Years: 2 columns, month granularity
- Months: 3 columns, month granularity
- Days: 5 columns, day granularity
- All Photos: 7 columns, day granularity
- Years → Months changes from 7-day → monthly buckets; Days → All Photos changes from daily → daily (finer detail)

**Section header** (line 161–194, `BucketHeaderView`):
- Fixed height 36pt (line 354)
- Title label on left (12pt inset)
- "Select" button on right (12pt inset)
- Hidden unless `editMode = true` (line 187–188)
- Formatted via `bucketTitle(_)` (line 273–285): **O(n) issue** — DateFormatter created per bucket key

**Cell background** (line 145):
- Selected state: `UIColor.systemBlue.withAlphaComponent(0.35)` with 3pt border
- Placeholder: thumbhash-decoded UIImage or gray.opacity(0.3) rectangle

**Cell badges**:
- Duration (top-right): `formatDuration(seconds)` = "m:ss"
- LIVE (top-right): "LIVE" label for livePhoto mediaKind
- Favorite (top-left): "♥" if `row.isFavorite`
- Container (bottom-left): "⌂" for space, "▤" for library, nil for personal

**Bottom overlay bar** (line 642–663, `safeAreaInset(edge: .bottom)`):
- Segmented picker: Years/Months/Days/All Photos
- Square toggle
- SelectionActionBar (visible only if `editMode`)
- Background: `.thinMaterial`
- Positioned as safe area inset (not overlay)

**Date scrubber** (line 593–602):
- Vertical Slider on right edge
- Range: 0...max(0, buckets.count - 1)
- Step: 1
- Rotation: -90°
- Offset: x +56pt to position on right
- Only shown if `buckets.count > 1`
- Binding to `scrubIndex`; changes trigger `vc.scrollToScrubSection(scrubIndex)` (line 326–332)

---

## Known Limitations with UIViewControllerRepresentable

**PhotoGridView** (line 495–533):
- Wrapped `PhotoGridViewController` (UIKit) via `UIViewControllerRepresentable`
- `.refreshable` modifier will **NOT** work on this wrapper (SwiftUI's `.refreshable` only works with List/ScrollView)
- Workaround implemented: UIRefreshControl wired directly in `viewDidLoad()` (line 238–244)
- `.searchable` modifier also will not work; Search tab implements its own SearchView instead of filtering the library

---

## O(n) Main-Thread Work

1. **`bucketTitle(_:)` DateFormatter recreation** (line 273–285, LibraryGridViewController)
   - Creates `DateFormatter` per bucket on every render pass
   - Called in `dataSource.supplementaryViewProvider` (line 260)
   - **Impact**: With 12+ buckets (year view), 12+ DateFormatters allocated per grid update
   - **Recommendation**: Cache DateFormatter as static/property

2. **`album.assets` load on detail** (Albums.swift, line 122)
   - `store.albumAssets(albumId: album.id, limit: 10_000)` fetches all assets for display
   - If album has thousands of assets, this blocks detail navigation
   - List displays all (no pagination)

3. **Person asset count loop** (Collections.swift, line 263–265)
   - Calls `store.assetIds(forPerson: person.id).count` for every person
   - If 50+ people, 50+ serial DB queries
   - Consider batch query or pre-compute in store

4. **Camera models group query** (Collections.swift, line 298–303, CameraCategoryAssetList)
   - Fetches assets per model in category; loops over category.models
   - Limit 250k per model, no pagination in the list display
   - Sorts all results in memory

---

## Summary

- **Screens documented**: 11 (Login, Tabs, Library, Viewer, Collections, Search, Settings, Spaces, Albums, Memories, Places, Edit, Free Up Space)
- **Total controls documented**: ~180
- **Sheet/Modal views**: MoveSheet, TimelineSourcesSheet, AlbumPickerSheet, SpaceCreateSheet, AlbumCreateSheet, AlbumRenameSheet, AlbumShareSheet, SpaceRenameSheet, SpaceAddMemberSheet, SpaceTransferSheet, ViewerInfoPanel, EditView (fullscreen), FreeUpSpaceView (navigation), MemoriesView (story player)
- **STUB controls**: 1 (story player auto-advance)
- **UNCLEAR controls**: 0
- **Layout**: Compositional UICollectionView with adaptive columns; square vs. aspect toggle; date scrubber; section headers with select button; pull-to-refresh via UIRefreshControl
- **Key O(n) issues**: DateFormatter per render, album asset load, person count queries, camera asset loops

