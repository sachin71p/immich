import AppKit
import CoreModel
import LocalStore
import MapKit
import Media
import Rules
import SwiftUI

/// Window values (multiple windows + state restoration — brief task 4).
enum MacWindow: Hashable, Codable {
  case library
  case viewer(String)
}

/// `.sheet(item:)` payload for the move/add-to-album sheets. Bundling the selection with the
/// presentation trigger (rather than a separate `Bool` flag + sibling `[String]` state) avoids a
/// real SwiftUI race: a `.sheet(isPresented:)` content closure can capture the *previous* render's
/// value of a sibling `@State` var even when both are set in the same action, presenting with a
/// stale (here, empty) selection.
private struct AssetIdsSheetItem: Identifiable {
  let id = UUID()
  let ids: [String]
}

/// The three-button Photos toolbar filter. Filters are an inclusive multi-selection: choosing
/// Photos and Videos shows either type, and reopening the menu preserves its checkmarks.
/// Visible to `MacGridLoader.setPresentation`, which rebuilds the snapshot's include
/// predicate from these (Step 4 deletes `matchesQuickFilter` and calls it instead).
enum TimelineQuickFilter: Hashable, Sendable {
  case all, favorites, edited, photos, videos, screenshots, capturedByMe, notInAlbum

  var title: String {
    switch self {
    case .all: return "All Items"
    case .favorites: return "Favorites"
    case .edited: return "Edited"
    case .photos: return "Photos"
    case .videos: return "Videos"
    case .screenshots: return "Screenshots"
    case .capturedByMe: return "Captured by Me"
    case .notInAlbum: return "Not in an Album"
    }
  }

  var systemImage: String {
    switch self {
    case .all: return "square.grid.3x3"
    case .favorites: return "heart.fill"
    case .edited: return "slider.horizontal.3"
    case .photos: return "photo"
    case .videos: return "video"
    case .screenshots: return "camera.viewfinder"
    case .capturedByMe: return "person.crop.circle.badge.checkmark"
    case .notInAlbum: return "rectangle.stack.badge.minus"
    }
  }
}

struct MacMainView: View {
  @Bindable var state: MacAppState
  var window: MacWindow

  var body: some View {
    switch window {
    case .library:
      MacLibraryBrowser(state: state)
    case .viewer(let id):
      MacViewerView(state: state, assetId: id)
    }
  }
}

/// The main library window: sidebar + grid, toolbar, sheets, toasts (brief tasks 1–2).
struct MacLibraryBrowser: View {
  @Bindable var state: MacAppState
  @State private var selection: SidebarDestination? = .library
  @State private var grouping: TimelineGrouping = .months
  @State private var switcher: LibraryFilterOption = .all
  @State private var zoom: CGFloat = 120
  @State private var usesSquareThumbnails = false
  @State private var timelineOrder: TimelineOrder = .newestFirst
  @State private var quickFilters: Set<TimelineQuickFilter> = [.all]
  @State private var albumAssetIds = Set<String>()
  @State private var toolbarSearch = ""
  @State private var isSelecting = false
  @State private var didRequestInitialSync = false
  @State private var loader = MacGridLoader()
  @State private var selectionModel = GridSelectionModel()
  @State private var toast: String?
  @State private var moveSheetIds: AssetIdsSheetItem?
  @State private var addToAlbumIds: AssetIdsSheetItem?
  @State private var showingNewSpace = false
  @State private var showingNewAlbum = false
  @State private var managingSpace: Space?
  @State private var pendingDropMove: (ids: [String], target: MoveTarget)?
  @State private var viewingAssetId: String?
  @Environment(\.openWindow) private var openWindow
  @SceneStorage("MacSidebar.selection") private var restoredSelection: String?

  var body: some View {
    NavigationSplitView {
      MacSidebarView(
        state: state,
        selection: Binding(
          get: { selection },
          set: {
            selectDestination($0)
          }
        ),
        onDropAssets: handleSidebarDrop,
        onNewSpace: { showingNewSpace = true },
        onNewAlbum: { showingNewAlbum = true }
      )
      .navigationSplitViewColumnWidth(min: 200, ideal: 240)
    } detail: {
      // A plain click/double-click opens the asset in the detail pane, sidebar still visible —
      // matching native Photos. `File > New Viewer Window` still opens a real second NSWindow
      // via `MacWindow.viewer(id)` for anyone who explicitly wants a standalone window.
      if let viewingAssetId {
        MacViewerView(
          state: state, assetId: viewingAssetId,
          onNavigate: { self.viewingAssetId = $0 },
          onClose: { self.viewingAssetId = nil }
        )
      } else {
        detailView
          .navigationTitle("")
        .toolbar { toolbarContent }
          .onDrop(of: [.fileURL], isTargeted: nil, perform: handleFileDrop)
      }
    }
    .focusedValue(\.macAssetActions, gridActions)
    .onReceive(NotificationCenter.default.publisher(for: .macSyncNow)) { _ in
      Task { await state.syncNow(); await reload() }
    }
    // `refresh()`/`syncNow()` capture failures into `lastSyncError` but nothing displayed it,
    // so a failed post-login sync (stale libraries/spaces, no thumbnails) looked identical to
    // a slow one — surface it the same way every other error in this view already is.
    .onChange(of: state.lastSyncError) { _, error in
      if let error { showToast("Sync error: \(error)") }
    }
    .onReceive(NotificationCenter.default.publisher(for: .macImportFiles)) { _ in
      pickImportFiles()
    }
    .onReceive(NotificationCenter.default.publisher(for: .macImportCamera)) { _ in
      state.showingCameraImport = true
    }
    .task(id: reloadKey) { await reload() }
    .task {
      // The timeline is local-first, but a newly opened desktop app must initiate the first
      // server stream rather than silently presenting a stale cache as a finished library.
      guard !didRequestInitialSync, state.isConnected else { return }
      didRequestInitialSync = true
      await state.syncNow()
      await reload()
    }
    .onAppear {
      if let restoredSelection, selection == .library {
        selection = SidebarDestination(restorableID: restoredSelection)
      }
    }
    .sheet(item: $moveSheetIds) { item in
      MacMoveSheet(state: state, assetIds: item.ids) { results in
        moveSheetIds = nil
        showToast(Self.moveSummary(results))
        Task { await reload() }
      }
    }
    .sheet(item: $addToAlbumIds) { item in
      MacAddToAlbumSheet(state: state, assetIds: item.ids) {
        addToAlbumIds = nil
        showToast("Added to album.")
      }
    }
    .sheet(isPresented: $showingNewSpace) {
      MacNewSpaceSheet(state: state) {
        showingNewSpace = false
        Task { await reload() }
      }
    }
    .sheet(isPresented: $showingNewAlbum) {
      MacNewAlbumSheet(state: state, seedAssetIds: []) {
        showingNewAlbum = false
        Task { await reload() }
      }
    }
    .sheet(item: $managingSpace) { space in
      if let role = state.spaces.first(where: { $0.space.id == space.id })?.role {
        MacSpaceManageSheet(state: state, space: space, role: role) {
          managingSpace = nil
          Task { await reload() }
        }
      }
    }
    .sheet(isPresented: $state.showingCameraImport) {
      MacCameraImportView(state: state)
    }
    .sheet(isPresented: $state.showingImportChooser) {
      MacImportChooserSheet(state: state, urls: state.pendingImportURLs) {
        state.showingImportChooser = false
        state.pendingImportURLs = []
      }
    }
    .alert(
      "Move into external library?",
      isPresented: Binding(get: { pendingDropMove != nil }, set: { if !$0 { pendingDropMove = nil } })
    ) {
      Button("Move", role: .destructive) {
        if let pending = pendingDropMove { Task { await performMove(ids: pending.ids, to: pending.target) } }
      }
      Button("Cancel", role: .cancel) { pendingDropMove = nil }
    }
    .overlay(alignment: .bottom) {
      if let toast {
        Text(toast)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
          .padding()
          .accessibilityIdentifier("toast")
      }
    }
  }

  // MARK: - detail

  @ViewBuilder
  private var detailView: some View {
    switch selection?.query {
    case .some where selection == .allAlbums:
      MacAllAlbumsView(state: state) { album in
        selectDestination(.album(album.id))
      }
    case .some where selection == .duplicates:
      MacDuplicatesView(state: state, openViewer: openViewer)
    case .search:
      MacSearchView(state: state, onOpenViewer: openViewer)
    case .map:
      MacMapPlacesView(state: state, openViewer: openViewer)
    case .people:
      MacPeopleView(state: state)
    case .memories:
      MacMemoriesView(state: state)
    default:
      gridView
    }
  }

  private var gridView: some View {
    VStack(spacing: 0) {
      if let error = loader.error {
        Text(error).foregroundStyle(.red).font(.caption).padding(4)
      }
      if loader.isLoading && loader.sections.isEmpty {
        ProgressView().padding()
      }
      MacCollectionGridView(
        sections: displayedSections,
        assetsById: loader.assetsById,
        rowDates: displayedSections.flatMap { $0.rows.map { Self.dateString($0.localDateTime) } },
        pipeline: state.pipeline,
        exporter: MacExporter(
          serverURL: state.serverURL,
          tokenProvider: exportTokenProvider
        ),
        itemSize: zoom,
        usesSquareThumbnails: usesSquareThumbnails,
        isSelectionMode: isSelecting,
        selectedIds: Binding(
          get: { selectionModel.selected },
          set: { selectionModel.selected = $0 }
        ),
        onSelectionChange: { ids in
          selectionModel.retarget(to: displayedRowIds)
          selectionModel.selected = Set(ids)
        },
        onOpen: openViewer,
        onPreview: showPreview,
        onToggleFavorite: { id in toggleFavorite(ids: [id]) },
        onMagnify: { delta in
          let step: CGFloat = delta > 0 ? 12 : -12
          zoom = min(300, max(64, zoom + step))
        }
      )
      .accessibilityIdentifier("asset-grid")
      footer
    }
  }

  private var exportTokenProvider: @Sendable () async -> String? {
    let store = state.connection.tokenStore
    return { @Sendable in await store.get() }
  }

  // MARK: - toolbar (brief task 2)

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      VStack(alignment: .leading, spacing: 0) {
        Text(selection?.title ?? "Library").font(.headline)
        Text(librarySubtitle).font(.caption).foregroundStyle(.secondary)
      }
      .fixedSize()
    }
    .sharedBackgroundVisibility(.hidden)
    ToolbarItemGroup(placement: .principal) {
      librarySwitcher
      HStack(spacing: 0) {
        Button { zoom = max(64, zoom - 16) } label: { Image(systemName: "minus") }
          .disabled(zoom <= 64)
        Divider().frame(height: 18)
        Button { zoom = min(300, zoom + 16) } label: { Image(systemName: "plus") }
          .disabled(zoom >= 300)
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("grid-size-controls")
      Picker("Grouping", selection: $grouping) {
        Text("Years").tag(TimelineGrouping.years)
        Text("Months").tag(TimelineGrouping.months)
        Text("All Photos").tag(TimelineGrouping.all)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("grouping-segmented")
    }
    ToolbarItem(placement: .automatic) {
      Button {
        usesSquareThumbnails.toggle()
      } label: {
        Label(
          usesSquareThumbnails ? "Use Full Aspect Ratio" : "Use Square Thumbnails",
          systemImage: usesSquareThumbnails ? "rectangle.on.rectangle.angled" : "square.grid.2x2"
        )
      }
      .labelStyle(.iconOnly)
      .accessibilityIdentifier("thumbnail-display-toggle")
    }
    ToolbarItem(placement: .automatic) {
      Menu {
        sortChoice(.newestFirst)
        sortChoice(.oldestFirst)
      } label: {
        Label("Sort", systemImage: "line.3.horizontal.decrease")
      }
      .labelStyle(.iconOnly)
      .menuIndicator(.hidden)
      .accessibilityIdentifier("timeline-sort-menu")
    }
    ToolbarItem(placement: .automatic) {
      Menu {
        filterChoice(.all)
        Divider()
        filterChoice(.favorites)
        filterChoice(.edited)
        filterChoice(.photos)
        filterChoice(.videos)
        filterChoice(.screenshots)
        filterChoice(.capturedByMe)
        filterChoice(.notInAlbum)
      } label: {
        Label("Filter", systemImage: "ellipsis")
      }
      .labelStyle(.iconOnly)
      .menuIndicator(.hidden)
      .accessibilityIdentifier("timeline-filter-menu")
    }
    ToolbarItemGroup {
      Button {
        if let first = selectionModel.selectedInOrder.first { openViewer(id: first) }
        else { showToast("Select an item to view its info.") }
      } label: {
        Label("Info", systemImage: "info.circle")
      }
      Button {
        guard !selectionModel.selected.isEmpty else {
          showToast("Select an item to share.")
          return
        }
        showToast("Sharing \(selectionModel.selected.count) selected item\(selectionModel.selected.count == 1 ? "" : "s").")
      } label: {
        Label("Share", systemImage: "square.and.arrow.up")
      }
      Button { toggleFavorite(ids: selectionModel.selectedInOrder) } label: {
        Label("Favorite", systemImage: "heart")
      }
      .disabled(selectionModel.selected.isEmpty)
      Button {
        if selectionModel.selected.isEmpty { showToast("Select an item to rotate.") }
        else { showToast("Rotation is available in the viewer.") }
      } label: {
        Label("Rotate", systemImage: "rotate.right")
      }
      Button(isSelecting ? "Done" : "Select") {
        isSelecting.toggle()
        if !isSelecting { selectionModel.clear() }
      }
      .accessibilityIdentifier("timeline-select-button")
      if let selection, case .space(let id) = selection,
        state.spaces.contains(where: { $0.space.id == id })
      {
        Button("Manage") {
          managingSpace = state.spaces.first(where: { $0.space.id == id })?.space
        }
      }
      Button {
        Task { await state.syncNow(); await reload() }
      } label: {
        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
      }
      .disabled(state.isSyncing)
      .accessibilityIdentifier("sync-button")
      TextField("Search", text: $toolbarSearch)
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 160, idealWidth: 220, maxWidth: 280)
        .onSubmit {
          guard !toolbarSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
          selectDestination(.search)
        }
        .accessibilityIdentifier("toolbar-search")
    }
  }

  @ViewBuilder
  private var librarySwitcher: some View {
      // Native `.pickerStyle(.menu)` draws its own system pill with fixed, cramped internal
      // padding we can't reach with `.padding()` (that only adds space *outside* the control).
      // A `Menu` with a custom label gives full control over the capsule's padding/centering,
      // and lets each row append a type glyph — an SF Symbol inline in `Text` renders correctly
      // as a menu-item title, unlike a `Label`, whose icon AppKit always pins before the text.
      Menu {
        Button { switcher = .all } label: {
          Text("All Libraries") + Text(" ") + Text(Image(systemName: "square.grid.2x2"))
        }
        Button { switcher = .personalOnly } label: {
          Text("Personal") + Text(" ") + Text(Image(systemName: "person.crop.circle"))
        }
        ForEach(state.spaces, id: \.space.id) { entry in
          Button { switcher = .space(entry.space.id) } label: {
            Text(entry.space.name) + Text(" ") + Text(Image(systemName: "person.2.circle"))
          }
        }
        ForEach(state.libraries, id: \.library.id) { entry in
          Button { switcher = .library(entry.library.id) } label: {
            Text(entry.library.name) + Text(" ") + Text(Image(systemName: "externaldrive"))
          }
        }
      } label: {
        HStack(spacing: 5) {
          Image(systemName: "photo.on.rectangle.angled")
            .font(.system(size: 15, weight: .semibold))
          Text(switcherTitle)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color(nsColor: .controlColor)))
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .accessibilityLabel("Library source: \(switcherTitle)")
      .accessibilityIdentifier("library-switcher")
  }

  // MARK: - loading

  private var reloadKey: String {
    "\(selection?.restorableID ?? "library")|\(grouping)|\(switcherKey)|\(state.spaces.count)|\(state.albums.count)"
  }

  private var switcherKey: String {
    switch switcher {
    case .all: return "all"
    case .personalOnly: return "personal"
    case .space(let id): return "space-\(id)"
    case .library(let id): return "library-\(id)"
    }
  }

  private var switcherTitle: String {
    switch switcher {
    case .all: return "All Libraries"
    case .personalOnly: return "Personal"
    case .space(let id): return state.spaces.first { $0.space.id == id }?.space.name ?? "Shared Library"
    case .library(let id): return state.libraries.first { $0.library.id == id }?.library.name ?? "External Library"
    }
  }

  private static let dateRangeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    return formatter
  }()

  private var libraryDateRange: String {
    let dates = loader.sections.flatMap(\.rows).compactMap(\.localDateTime)
    guard let first = dates.min(), let last = dates.max() else { return "No Photos" }
    return "\(Self.dateRangeFormatter.string(from: first)) – \(Self.dateRangeFormatter.string(from: last))"
  }

  private var displayedSections: [MacGridSection] {
    let filtered = loader.sections.compactMap { section -> MacGridSection? in
      let rows = section.rows.filter(matchesQuickFilter)
      return rows.isEmpty ? nil : MacGridSection(header: section.header, rows: rows)
    }
    guard timelineOrder == .oldestFirst else { return filtered }
    return filtered.reversed().map { section in
      MacGridSection(header: section.header, rows: section.rows.reversed())
    }
  }

  private var displayedRowIds: [String] { displayedSections.flatMap { $0.rows.map(\.id) } }

  private func matchesQuickFilter(_ row: TimelineRow) -> Bool {
    guard !quickFilters.contains(.all) else { return true }
    guard !quickFilters.isEmpty else { return true }
    let asset = loader.assetsById[row.id]
    return quickFilters.contains { filter in
      switch filter {
      case .all: return true
      case .favorites: return row.isFavorite
      case .edited: return asset?.isEdited == true
      case .photos: return row.mediaKind == .photo || row.mediaKind == .livePhoto
      case .videos: return row.mediaKind == .video
      case .screenshots: return row.mediaKind == .screenshot
      case .capturedByMe: return asset?.ownerId == state.userId
      case .notInAlbum: return !albumAssetIds.contains(row.id)
      }
    }
  }

  @ViewBuilder
  private func sortChoice(_ choice: TimelineOrder) -> some View {
    Button {
      timelineOrder = choice
    } label: {
      HStack {
        Image(systemName: "checkmark").opacity(timelineOrder == choice ? 1 : 0)
        Text(choice == .newestFirst ? "Newest First" : "Oldest First")
      }
    }
  }

  @ViewBuilder
  private func filterChoice(_ filter: TimelineQuickFilter) -> some View {
    Button {
      if filter == .all {
        quickFilters = [.all]
      } else {
        quickFilters.remove(.all)
        if quickFilters.contains(filter) { quickFilters.remove(filter) }
        else { quickFilters.insert(filter) }
        if quickFilters.isEmpty { quickFilters = [.all] }
      }
    } label: {
      HStack {
        Image(systemName: "checkmark").opacity(quickFilters.contains(filter) ? 1 : 0)
        Image(systemName: filter.systemImage)
        Text(filter.title)
      }
    }
  }

  private var librarySubtitle: String {
    let count = selectionModel.selected.count
    guard count > 0 else { return libraryDateRange }
    return "\(libraryDateRange) · \(count) Photo\(count == 1 ? "" : "s") Selected"
  }

  private var footer: some View {
    let rows = loader.sections.flatMap(\.rows)
    let photos = rows.filter { $0.mediaKind != .video }.count
    let videos = rows.filter { $0.mediaKind == .video }.count
    return VStack(spacing: 3) {
      Text("\(photos) Photo\(photos == 1 ? "" : "s"), \(videos) Video\(videos == 1 ? "" : "s")")
        .font(.headline)
      Text(syncStatusText)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .accessibilityIdentifier("library-sync-status")
  }

  private var syncStatusText: String {
    if state.isSyncing { return "Syncing with Immich…" }
    if state.lastSyncError != nil { return "Sync needs attention" }
    if let completed = state.lastCompletedSyncAt {
      return "Last server sync finished \(completed.formatted(date: .omitted, time: .shortened))"
    }
    return "Sync has not completed yet"
  }

  private func selectDestination(_ destination: SidebarDestination?) {
    guard let destination else { selection = nil; restoredSelection = nil; return }
    if destination == .locked {
      Task { @MainActor in
        guard await LockedMediaAuthentication.authenticate() else {
          showToast("Locked photos could not be unlocked.")
          return
        }
        selection = destination
        restoredSelection = destination.restorableID
      }
      return
    }
    selection = destination
    restoredSelection = destination.restorableID
  }

  private func reload() async {
    guard let userId = state.userId, let selection else { return }
    await loader.load(
      store: state.store, userId: userId, destination: selection,
      grouping: grouping, switcher: switcher
    )
    // Keep the local "Not in an Album" toolbar filter accurate without another server call.
    var assigned = Set<String>()
    for entry in state.albums {
      assigned.formUnion((try? await state.store.assetIds(inAlbum: entry.album.id)) ?? [])
    }
    albumAssetIds = assigned
    selectionModel.retarget(to: loader.allRowIds)
  }

  private static let rowDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()

  static func dateString(_ date: Date?) -> String {
    guard let date else { return "" }
    return rowDateFormatter.string(from: date)
  }

  // MARK: - actions (focused value for menus)

  private var gridActions: MacAssetActions {
    let ids = selectionModel.selectedInOrder
    return MacAssetActions(
      favorite: { toggleFavorite(ids: ids) },
      rotate: {},
      trash: { trash(ids: ids) },
      move: {
        moveSheetIds = ids.isEmpty ? nil : AssetIdsSheetItem(ids: ids)
      },
      addToAlbum: {
        addToAlbumIds = ids.isEmpty ? nil : AssetIdsSheetItem(ids: ids)
      },
      toggleInspector: {
        if let first = ids.first { openViewer(id: first) }
      },
      openViewer: {
        // "File > New Viewer Window": unlike a plain click, this explicitly wants a separate
        // NSWindow, so it bypasses `openViewer(id:)`'s inline in-window navigation.
        guard let first = ids.first else { return }
        state.viewerContext = loader.allRowIds
        openWindow(value: MacWindow.viewer(first))
      },
      preview: {
        if let first = ids.first { showPreview(id: first) }
      }
    )
  }

  private func openViewer(id: String) {
    state.viewerContext = loader.allRowIds
    viewingAssetId = id
  }

  private func showPreview(id: String) {
    Task { @MainActor in
      var asset = loader.assetsById[id]
      if asset == nil { asset = try? await state.store.asset(id: id) }
      guard let asset else { return }
      MacPreviewPanel.show(asset: asset, pipeline: state.pipeline)
    }
  }

  private func toggleFavorite(ids: [String]) {
    guard !ids.isEmpty else { return }
    Task { @MainActor in
      do {
        let assets = try await state.store.assets(ids: ids)
        let make = !(assets.first?.isFavorite ?? false)
        try await state.assetMutations().setFavorite(ids: ids, isFavorite: make)
        MacAssetChangeCenter.shared.post(.favorite(ids: Set(ids), isFavorite: make))
        await reload()
      } catch {
        showToast(error.localizedDescription)
      }
    }
  }

  private func trash(ids: [String]) {
    guard !ids.isEmpty else { return }
    Task { @MainActor in
      do {
        try await state.assetMutations().trash(ids: ids)
        MacAssetChangeCenter.shared.post(.removedFromCurrentContexts(ids: Set(ids)))
        await reload()
        showToast("Moved to Recently Deleted.")
      } catch {
        showToast(error.localizedDescription)
      }
    }
  }

  private func performMove(ids: [String], to target: MoveTarget) async {
    do {
      let results = try await state.assetMutations().move(ids: ids, to: target)
      await state.refresh()
      MacAssetChangeCenter.shared.post(.removedFromCurrentContexts(ids: Set(ids)))
      await reload()
      pendingDropMove = nil
      showToast(Self.moveSummary(results))
    } catch {
      pendingDropMove = nil
      showToast(error.localizedDescription)
    }
  }

  static func moveSummary(_ results: [MoveResult]) -> String {
    let moved = results.filter { $0.status == .moved }.count
    let noop = results.filter { $0.status == .noop }.count
    let errors = results.filter { $0.status == .error }
    if errors.isEmpty { return "Moved \(moved) item\(moved == 1 ? "" : "s")\(noop > 0 ? " (\(noop) already there)" : "")." }
    let reasons = Set(errors.compactMap(\.reason)).sorted().joined(separator: ", ")
    return "Moved \(moved); \(errors.count) failed (\(reasons))."
  }

  // MARK: - drops

  private func handleSidebarDrop(ids: [String], destination: SidebarDestination) {
    switch destination.dropAction {
    case .none:
      break
    case .addToAlbum(let albumId):
      Task { @MainActor in
        do {
          _ = try await state.albumMutations().addAssets(ids, toAlbum: albumId)
          MacAssetChangeCenter.shared.post(.albumsChanged)
          showToast("Added to album.")
        } catch {
          showToast(error.localizedDescription)
        }
      }
    case .moveTo(let target):
      if case .library = target {
        pendingDropMove = (ids, target)
      } else {
        Task { await performMove(ids: ids, to: target) }
      }
    }
  }

  private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
    Task { @MainActor in
      var urls: [URL] = []
      for provider in providers {
        if let url = try? await provider.loadFileURL() { urls.append(url) }
      }
      if !urls.isEmpty {
        state.pendingImportURLs = urls
        state.showingImportChooser = true
      }
    }
    return true
  }

  /// File > Import (brief task 5): files/folders → import destination chooser.
  private func pickImportFiles() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    guard panel.runModal() == .OK else { return }
    state.pendingImportURLs = panel.urls
    state.showingImportChooser = true
  }

  private func showToast(_ message: String) {
    toast = message
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(4))
      if toast == message { toast = nil }
    }
  }
}

extension SidebarDestination {
  var restorableID: String {
    switch self {
    case .library: return "library"
    case .collections: return "collections"
    case .search: return "search"
    case .favorites: return "favorites"
    case .recentlySaved: return "recents"
    case .map: return "map"
    case .people: return "people"
    case .memories: return "memories"
    case .mediaPhotos: return "media-photos"
    case .mediaVideos: return "media-videos"
    case .mediaScreenshots: return "media-screenshots"
    case .media(let collection): return "media-\(collection.rawValue)"
    case .space(let id): return "space:\(id)"
    case .externalLibrary(let id): return "extlib:\(id)"
    case .album(let id): return "album:\(id)"
    case .allAlbums: return "all-albums"
    case .imports: return "imports"
    case .recentlyDeleted: return "trash"
    case .duplicates: return "duplicates"
    case .capturedByMe: return "captured-by-me"
    case .camera(let model): return "camera:\(model)"
    case .hidden: return "hidden"
    case .archive: return "archive"
    case .locked: return "locked"
    }
  }

  init?(restorableID: String) {
    if restorableID == "library" { self = .library; return }
    if restorableID == "collections" { self = .collections; return }
    if restorableID == "search" { self = .search; return }
    if restorableID == "favorites" { self = .favorites; return }
    if restorableID == "recents" { self = .recentlySaved; return }
    if restorableID == "map" { self = .map; return }
    if restorableID == "people" { self = .people; return }
    if restorableID == "memories" { self = .memories; return }
    if restorableID == "media-photos" { self = .mediaPhotos; return }
    if restorableID == "media-videos" { self = .mediaVideos; return }
    if restorableID == "media-screenshots" { self = .mediaScreenshots; return }
    if restorableID == "duplicates" { self = .duplicates; return }
    if restorableID == "all-albums" { self = .allAlbums; return }
    if restorableID == "captured-by-me" { self = .capturedByMe; return }
    if restorableID == "imports" { self = .imports; return }
    if restorableID == "trash" { self = .recentlyDeleted; return }
    if restorableID == "hidden" { self = .hidden; return }
    if restorableID == "archive" { self = .archive; return }
    if restorableID == "locked" { self = .locked; return }
    let parts = restorableID.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return nil }
    switch parts[0] {
    case "space": self = .space(parts[1])
    case "extlib": self = .externalLibrary(parts[1])
    case "album": self = .album(parts[1])
    case "camera": self = .camera(parts[1])
    default: return nil
    }
  }
}

/// Quick Look-style floating preview (space bar — brief task 2).
enum MacPreviewPanel {
  @MainActor
  private static var panel: NSPanel?

  @MainActor
  static func show(asset: Asset, pipeline: MediaPipeline) {
    let panel: NSPanel
    if let existing = self.panel {
      panel = existing
    } else {
      let created = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
        backing: .buffered, defer: false
      )
      created.isFloatingPanel = true
      created.collectionBehavior = [.fullScreenAuxiliary]
      self.panel = created
      panel = created
    }
    let imageView = NSImageView(frame: panel.contentView?.bounds ?? .zero)
    imageView.autoresizingMask = [.width, .height]
    imageView.imageScaling = .scaleProportionallyUpOrDown
    panel.contentView = imageView
    panel.title = asset.originalFileName
    panel.makeKeyAndOrderFront(nil)
    Task { @MainActor in
      if let loaded = try? await pipeline.load(asset: asset, tier: .preview) {
        switch loaded.content {
        case .placeholder(let image): imageView.image = image
        case .tier(_, let image, _): imageView.image = image
        }
      }
    }
  }
}

#Preview("Library") {
  MacPreviewFixture { state in
    MacLibraryBrowser(state: state)
      .frame(width: 1400, height: 900)
  }
}

extension NSItemProvider {
  @MainActor
  func loadFileURL() async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      _ = loadObject(ofClass: NSURL.self) { object, error in
        if let error { continuation.resume(throwing: error) }
        else if let url = object as? URL { continuation.resume(returning: url) }
        else {
          continuation.resume(throwing: MacPreviewError.noURL)
        }
      }
    }
  }
}

enum MacPreviewError: Error { case noURL }

/// Sidebar People (per-owner clustering — DECISIONS §11).
struct MacPeopleView: View {
  @Bindable var state: MacAppState
  @State private var people: [Person] = []

  var body: some View {
    List(people, id: \.id) { person in
      Label(person.name.isEmpty ? "Unnamed" : person.name, systemImage: "person.circle")
    }
    .task {
      guard let userId = state.userId else { return }
      people = (try? await state.store.people(forOwner: userId)) ?? []
    }
  }
}
