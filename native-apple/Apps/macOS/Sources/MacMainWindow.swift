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
  @State private var loader = MacGridLoader()
  @State private var selectionModel = GridSelectionModel()
  @State private var toast: String?
  @State private var moveSheetIds: AssetIdsSheetItem?
  @State private var addToAlbumIds: AssetIdsSheetItem?
  @State private var showingNewSpace = false
  @State private var showingNewAlbum = false
  @State private var managingSpace: Space?
  @State private var pendingDropMove: (ids: [String], target: MoveTarget)?
  @Environment(\.openWindow) private var openWindow
  @SceneStorage("MacSidebar.selection") private var restoredSelection: String?

  var body: some View {
    NavigationSplitView {
      MacSidebarView(
        state: state,
        selection: Binding(
          get: { selection },
          set: {
            selection = $0
            restoredSelection = $0?.restorableID
          }
        ),
        onDropAssets: handleSidebarDrop,
        onNewSpace: { showingNewSpace = true },
        onNewAlbum: { showingNewAlbum = true }
      )
      .navigationSplitViewColumnWidth(min: 200, ideal: 240)
    } detail: {
      detailView
        .navigationTitle(selection?.title ?? "Library")
        .toolbar { toolbarContent }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleFileDrop)
    }
    .focusedValue(\.macAssetActions, gridActions)
    .onReceive(NotificationCenter.default.publisher(for: .macSyncNow)) { _ in
      Task { await state.syncNow(); await reload() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .macImportFiles)) { _ in
      pickImportFiles()
    }
    .task(id: reloadKey) { await reload() }
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
    case .map:
      MacMapView(state: state)
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
        sections: loader.sections,
        assetsById: loader.assetsById,
        rowDates: loader.sections.flatMap { $0.rows.map { Self.dateString($0.localDateTime) } },
        pipeline: state.pipeline,
        exporter: MacExporter(
          serverURL: state.serverURL,
          tokenProvider: exportTokenProvider
        ),
        itemSize: zoom,
        selectedIds: Binding(
          get: { selectionModel.selected },
          set: { selectionModel.selected = $0 }
        ),
        onSelectionChange: { ids in
          selectionModel.retarget(to: loader.allRowIds)
          selectionModel.selected = Set(ids)
        },
        onOpen: openViewer,
        onPreview: showPreview
      )
      .accessibilityIdentifier("asset-grid")
    }
  }

  private var exportTokenProvider: @Sendable () async -> String? {
    let store = state.connection.tokenStore
    return { @Sendable in await store.get() }
  }

  // MARK: - toolbar (brief task 2)

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      Picker("Library", selection: $switcher) {
        Text("All Libraries").tag(LibraryFilterOption.all)
        Text("Personal").tag(LibraryFilterOption.personalOnly)
        ForEach(state.spaces, id: \.space.id) { entry in
          Text(entry.space.name).tag(LibraryFilterOption.space(entry.space.id))
        }
        ForEach(state.libraries, id: \.library.id) { entry in
          Text(entry.library.name).tag(LibraryFilterOption.library(entry.library.id))
        }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("library-switcher")
    }
    ToolbarItemGroup(placement: .principal) {
      Picker("Grouping", selection: $grouping) {
        Text("Years").tag(TimelineGrouping.years)
        Text("Months").tag(TimelineGrouping.months)
        Text("All Photos").tag(TimelineGrouping.all)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("grouping-segmented")
      Slider(value: $zoom, in: 64...300) {
        Text("Zoom")
      }
      .frame(width: 120)
      .accessibilityIdentifier("zoom-slider")
    }
    ToolbarItemGroup {
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
    }
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

  private func reload() async {
    guard let userId = state.userId, let selection else { return }
    await loader.load(
      store: state.store, userId: userId, destination: selection,
      grouping: grouping, switcher: switcher
    )
    selectionModel.retarget(to: loader.allRowIds)
  }

  static func dateString(_ date: Date?) -> String {
    guard let date else { return "" }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
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
        if let first = ids.first { openViewer(id: first) }
      },
      preview: {
        if let first = ids.first { showPreview(id: first) }
      }
    )
  }

  private func openViewer(id: String) {
    state.viewerContext = loader.allRowIds
    openWindow(value: MacWindow.viewer(id))
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
    case .favorites: return "favorites"
    case .recentlySaved: return "recents"
    case .map: return "map"
    case .people: return "people"
    case .memories: return "memories"
    case .mediaPhotos: return "media-photos"
    case .mediaVideos: return "media-videos"
    case .mediaScreenshots: return "media-screenshots"
    case .space(let id): return "space:\(id)"
    case .externalLibrary(let id): return "extlib:\(id)"
    case .album(let id): return "album:\(id)"
    case .imports: return "imports"
    case .recentlyDeleted: return "trash"
    case .hidden: return "hidden"
    case .archive: return "archive"
    case .locked: return "locked"
    }
  }

  init?(restorableID: String) {
    if restorableID == "library" { self = .library; return }
    if restorableID == "collections" { self = .collections; return }
    if restorableID == "favorites" { self = .favorites; return }
    if restorableID == "recents" { self = .recentlySaved; return }
    if restorableID == "map" { self = .map; return }
    if restorableID == "people" { self = .people; return }
    if restorableID == "memories" { self = .memories; return }
    if restorableID == "media-photos" { self = .mediaPhotos; return }
    if restorableID == "media-videos" { self = .mediaVideos; return }
    if restorableID == "media-screenshots" { self = .mediaScreenshots; return }
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

/// Sidebar Map: markers for geotagged assets in the timeline scope.
struct MacMapView: View {
  @Bindable var state: MacAppState
  @State private var pins: [MacMapPin] = []
  @State private var position = MapCameraPosition.automatic

  var body: some View {
    Map(position: $position) {
      ForEach(pins) { pin in
        Marker(pin.id, coordinate: pin.coordinate)
      }
    }
    .overlay(alignment: .bottomLeading) {
      Text("\(pins.count) located photo\(pins.count == 1 ? "" : "s")")
        .padding(8)
        .background(.thinMaterial, in: Capsule())
        .padding()
    }
    .task { await load() }
  }

  private func load() async {
    guard let userId = state.userId else { return }
    do {
      let ctx = try await state.store.timelineContext(for: userId)
      let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
      pins = try await state.store.mapPoints(scope: scope).map { MacMapPin(point: $0) }
    } catch {}
  }
}

struct MacMapPin: Identifiable, Hashable {
  var point: MapPoint
  var id: String { point.id }
  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
  }
}

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

/// Sidebar Memories.
struct MacMemoriesView: View {
  @Bindable var state: MacAppState
  @State private var memories: [Memory] = []

  var body: some View {
    List(memories, id: \.id) { memory in
      VStack(alignment: .leading) {
        Text(memory.type).font(.headline)
        Text(memory.memoryAt.formatted(date: .abbreviated, time: .omitted))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .task {
      guard let userId = state.userId else { return }
      memories = (try? await state.store.savedMemories(forOwner: userId)) ?? []
    }
  }
}
