# Heirloom macOS Reconnaissance Facts

## 1. TimelineRow struct

**File:line** — PhotosCore/Sources/CoreModel/Timeline.swift:15

**Stored properties:**
```swift
public var id: String
public var thumbhash: String?
public var aspectRatio: Double
public var mediaKind: TimelineMediaKind
public var isFavorite: Bool
public var isTrashed: Bool
public var isArchived: Bool
public var localDateTime: Date?
```

**Initializers:**
- Lines 26-44: designated initializer with all properties as parameters
- Lines 50-62: `init(asset:)` — computes aspect ratio and mediaKind from Asset

**Conformances:** Sendable, Hashable, Identifiable

---

## 2. SQL/GRDB queries producing TimelineRow

**LocalStore+Timeline.swift:**
- `timelineAssets()` (line 119): SELECT id, thumbhash, width, height, isFavorite, deletedAt, visibility, localDateTime, mediaKind
- `favoriteAssets()` (line 139): same SELECT columns
- `recentAssets()` (line 153): same SELECT columns
- `assets()` (line 166): same SELECT columns + client-side filter on mediaKind
- `trashedAssets()` (line 187): same SELECT columns
- `lockedAssets()` (line 202): same SELECT columns

**LocalStore+Browse.swift:**
- `albumAssets()` (line 106): same SELECT columns as rowSelectSQL
- `visibilityAssets()` (line 157): same SELECT columns
- `mediaAssets()` (line 176): same SELECT columns + client-side filter by collection type

SELECT column list (rows 32-47 in LocalStore+Timeline.swift):
```
asset.id, asset.thumbhash, asset.width, asset.height, asset.isFavorite, 
asset.deletedAt, asset.visibility, asset.localDateTime,
CASE WHEN asset.livePhotoVideoId IS NOT NULL THEN 'livePhoto'
  WHEN assetExif.projectionType = 'equirectangular' THEN 'panorama'
  WHEN asset.type = 'VIDEO' THEN 'video'
  WHEN asset.originalFileName LIKE 'Screenshot%' OR asset.originalFileName LIKE 'screenshot%' THEN 'screenshot'
  ELSE 'photo' END AS mediaKind
FROM asset
JOIN visibleAsset ON visibleAsset.id = asset.id
LEFT JOIN assetExif ON assetExif.assetId = asset.id
```

---

## 3. Asset struct

**File:line** — PhotosCore/Sources/CoreModel/Asset.swift:5

**Properties:**
- id: String
- ownerId: String ✓
- originalFileName: String ✓
- thumbhash: String? ✓
- checksum: String
- fileCreatedAt: Date?
- fileModifiedAt: Date?
- createdAt: Date?
- localDateTime: Date?
- durationSeconds: Int? (NOT `duration`)
- type: AssetKind
- deletedAt: Date?
- isFavorite: Bool
- visibility: AssetVisibilityKind
- livePhotoVideoId: String?
- stackId: String?
- libraryId: String?
- spaceId: String?
- width: Int? ✓
- height: Int? ✓
- isEdited: Bool ✓
- localIdentifier: String?

**Has isEdited, ownerId, thumbhash, originalFileName, width, height:** YES  
**Has duration property:** NO (has durationSeconds instead)

---

## 4. UI presentation methods in Apps/macOS/Sources

| File | Line | Method | Presented View | Cancel/Close | Keyboard Shortcut |
|------|------|--------|----------------|--------------|-------------------|
| MacViewer.swift | 133 | .sheet(isPresented: $showingMove) | MacMoveSheet | ✓ Button("Cancel") in sheet | — |
| MacViewer.swift | 136 | .sheet(isPresented: $showingAddToAlbum) | MacAddToAlbumSheet | ✓ Button in sheet | — |
| MacViewer.swift | 139 | .sheet(isPresented: $showingEdit) | MacEditView | ✓ .onExitCommand in EditView | — |
| MacMemoriesView.swift | 70 | .sheet(item: $playingStory) | MacStoryPlayerView | ✓ Button("Close") (line 157) | — |
| MacMainWindow.swift | 160 | .sheet(item: $moveSheetIds) | MacMoveSheet | ✓ Button("Cancel") in sheet | — |
| MacMainWindow.swift | 167 | .sheet(item: $addToAlbumIds) | MacAddToAlbumSheet | ✓ Button in sheet | — |
| MacMainWindow.swift | 173 | .sheet(isPresented: $showingNewSpace) | MacNewSpaceSheet | ✓ Button in sheet | — |
| MacMainWindow.swift | 179 | .sheet(isPresented: $showingNewAlbum) | MacNewAlbumSheet | ✓ Button in sheet | — |
| MacMainWindow.swift | 185 | .sheet(item: $managingSpace) | MacSpaceManageSheet | ✓ Button in sheet | — |
| MacMainWindow.swift | 193 | .sheet(isPresented: $state.showingCameraImport) | MacCameraImportView | ✓ Button in view | — |
| MacMainWindow.swift | 196 | .sheet(isPresented: $state.showingImportChooser) | MacImportChooserSheet | ✓ Button in sheet | — |
| MacMainWindow.swift | 202 | .alert("Move into external library?") | — | ✓ Button("Cancel") | — |
| MacEditView.swift | 90 | .alert("Save failed") | — | ✓ OK button | — |
| MacMoveSheet.swift | 51 | .alert(...) | — | ✓ Button("Cancel") | — |

**No .popover(), .confirmationDialog(), or NSAlert detected in Apps/macOS/Sources**

---

## 5. tokenStore.get() implementation

**File:line** — PhotosCore/Sources/ImmichAPI/ImmichConnection.swift:21–23

```swift
public func get() -> String? {
  token
}
```

**Behavior:** Returns cached in-memory value. Does NOT read Keychain each call. The `token` is held as a private actor field (line 11) and only updated via `set()` (line 17) after login. Keychain read/write lives in the app layer (line 7 comment).

---

## 6. MacMainWindow.swift layout and reload

**Navigation title (toolbar):**
- Line 299: `Text(selection?.title ?? "Library").font(.headline)`
- Computed from `selection?.title` property of SidebarDestination enum

**Navigation subtitle (toolbar):**
- Line 300: `Text(librarySubtitle).font(.caption).foregroundStyle(.secondary)`
- Line 565-569: `librarySubtitle` property computes date range + selection count

**Toolbar declared:**
- Lines 295-419: `@ToolbarContentBuilder var toolbarContent`

**Selection → content view mapping:**
- Lines 227-244: `detailView` switch statement maps selection.query to views:
  - `.allAlbums` → MacAllAlbumsView
  - `.duplicates` → MacDuplicatesView
  - `.search` → MacSearchView
  - `.map` → MacMapPlacesView
  - `.people` → MacPeopleView
  - `.memories` → MacMemoriesView
  - default → gridView

**viewerContext set at:**
- Line 661: `state.viewerContext = loader.allRowIds` (File > New Viewer Window action)
- Line 671: `state.viewerContext = loader.allRowIds` (openViewer inline navigation)

**Footer:**
- Lines 571-585: VStack showing photo/video counts and sync status; uses `loader.sections.flatMap(\.rows)`

**Reload trigger:**
- Line 146: `.task(id: reloadKey) { await reload() }`
- Line 468-470: `reloadKey` = computed string from selection, grouping, switcher, space/album counts

---

## 7. SidebarDestination enum

**File:line** — Apps/macOS/Sources/MacSidebarModel.swift:8

**Cases (lines 9-32):**
```
library, collections, search, favorites, recentlySaved, map, people, memories,
mediaPhotos, mediaVideos, mediaScreenshots, media(NativeMediaCollection),
space(String), externalLibrary(String), album(String), allAlbums, imports,
recentlyDeleted, duplicates, capturedByMe, camera(String), hidden, archive, locked
```

**title property:** Lines 34-61 (returns display title for each case)

**query property:** Lines 118-145 (maps each case to a DestinationQuery enum for store queries)

---

## 8. MacViewer.swift paging, rotation, title

**Prev/next paging:**
- Lines 154-155: `.onKeyPress(.leftArrow)` / `.onKeyPress(.rightArrow)` call `page(by: ±1)`
- Lines 165-173: `page()` method wraps index with modulo, calls `onNavigate(next)` or `openWindow(MacWindow.viewer(next))`

**Rotation applied:**
- Line 28: `@State private var rotation: Double = 0`
- Line 45: Action increments by 90°
- Lines 76, 79: `.rotationEffect(.degrees(rotation))` on image views

**Title shown:**
- Line 100: `.navigationTitle(asset?.originalFileName ?? "Viewer")`

---

## 9. People / Memories / Map sidebar renders

**MacPeopleView:**
- File: MacMainWindow.swift, lines 916-929
- Displays: person.name in a List (line 922: `Label(person.name.isEmpty ? "Unnamed" : person.name, ...)`)

**MacMemoriesView:**
- File: Apps/macOS/Sources/MacMemoriesView.swift
- Displays: Stories with thumbnails + "On This Day" grid
- Story cover: first assetId thumbnail (lines 29-32)
- On This Day: TimelineRow thumbnail + localDateTime (lines 56-64)

**MacMapPlacesView:**
- File: Apps/macOS/Sources/MacMapPlacesView.swift
- Map: clustered annotations via MKMapView (lines 34-40)
- Grid: thumbnails of LocatedAsset (lines 46-59)
- **2,000 cap:** LocalStore+Browse.swift line 134 in `locatedAssets()` default param `limit: Int = 2000`

---

## 10. Build and test targets

**Makefile (native-apple root):**
```makefile
build-macos: xcodegen
	@mkdir -p $(MODULE_CACHE)
	cd $(NATIVE_DIR) && CLANG_MODULE_CACHE_PATH="$$PWD/.build/clang-module-cache" xcodebuild \
		-project Heirloom.xcodeproj \
		-scheme Heirloom-macOS \
		-destination 'platform=macOS' \
		-derivedDataPath .build/DerivedData \
		-skipPackagePluginValidation \
		-allowProvisioningUpdates \
		build

install-macos: build-macos
	@app=$$(find $(DERIVED_DATA)/Build/Products -maxdepth 2 -iname 'Heirloom-macOS.app' -type d | head -1); \
	if [ -z "$$app" ]; then echo "error: Heirloom-macOS.app not found..." >&2; exit 1; fi; \
	echo "Installing $$app -> /Applications/Heirloom-macOS.app"; \
	rm -rf "/Applications/Heirloom-macOS.app"; \
	cp -R "$$app" /Applications/; \
	xattr -dr com.apple.quarantine "/Applications/Heirloom-macOS.app" 2>/dev/null || true; \
	open "/Applications/Heirloom-macOS.app"
```

**PhotosCore Package.swift test target:**
- Line 42-49: testTarget "PhotosCoreTests" with dependencies on all major modules

**Xcode test target:**
- Heirloom-macOS-UITests (project.pbxproj line 156) with UITests at Apps/macOS/UITests/MacSmokeTests.swift
- Heirloom-macOS scheme: no explicit test action in Makefile (tests run via xcodebuild -scheme if specified)

---

## 11. Deployment targets and Nuke version

**Deployment targets:**
- PhotosCore Package.swift line 6: `.iOS("27.0"), .macOS("27.0")`
- macOS and iOS both target OS version 27.0

**Nuke version:**
- Package.resolved: 13.2.0 (https://github.com/kean/Nuke)

---

## 12. Logging in codebase

**Apps/macOS/Sources:** 0 instances of Logger(), os_log(), or print()  
**PhotosCore/Sources:** 0 instances of Logger(), os_log(), or print()  

**Total logging:** None detected; no structured or print-based logging configured.

---

## 13. TieredMediaCache construction sites

**File:line and call sites:**

1. **MacAppState.swift line 84-87:**
   ```swift
   let diskCache = TieredMediaCache(
     rootDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
       .appendingPathComponent("Heirloom/Media", isDirectory: true)
   )
   ```

2. **MacAppState.swift line 84 (same init as above)**

3. **AppSession.swift (iOS) line 100:**
   ```swift
   diskCache: TieredMediaCache(rootDirectory: cacheRoot)
   ```

**usage() / totalUsage() calls:** None detected at launch; cache methods not called during initialization.

---

## 14. Tests touching MacGridLoader / timeline / MediaPipeline

**PhotosCore/Tests test files:**
- TimelinePerformanceTests.swift — tests timeline query performance
- MediaPipelineTests.swift — tests MediaPipeline.load(), memory cache limits
- TieredMediaCacheTests.swift — tests cache eviction and persistence
- RulesTests.swift — tests TimelineScope resolution (referenced at lines 124-145)

**Apps/macOS/UITests:**
- MacSmokeTests.swift — UI smoke tests (runs with --fixture-seed flag)

**No direct MacGridLoader unit tests found** (loader is view-layer only, tested via UI integration)

---

## Notable findings

- TimelineRow uses `thumbhash` (optional) to avoid full asset hydration for scrolling performance
- Asset has `durationSeconds` (not `duration`) for video length
- tokenStore is actor-protected in-memory cache, NOT Keychain-backed (Keychain read/write in app layer)
- No logging infrastructure; all errors surfaced as toasts/alerts in UI
- Deployment target is macOS 27.0 (which requires Sonoma or later, though version ID is unusual)
- macOS scheme has no explicit test target in Makefile; tests require separate xcodebuild invocation
