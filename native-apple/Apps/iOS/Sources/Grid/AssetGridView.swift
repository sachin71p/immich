import Combine
import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI

// MARK: - grid data source (WP1 §8, W2 contract)

/// What feeds an `AssetGridView`. Small and value-typed: SwiftUI passes these, the
/// loader resolves them into a `GridSnapshot` off-main.
enum AssetGridSource: Sendable {
  /// A store-backed timeline: one index query at `granularity`.
  case timeline(scope: ContainerScope, granularity: PhotosLocalStore.Granularity)
  /// An explicit id list in the caller's order (search results, relevance order kept).
  case ids([String])
  /// An async id producer (filtered queries); resolved to `.ids` before loading.
  case query(@Sendable () async throws -> [String])
}

// MARK: - the single grid component (WP1 §8, W2 contract)

/// The one grid component every photo collection uses (Library, search results, albums,
/// spaces — W2 screens only *use* this). A `LibraryGridLoader` owns the data (index →
/// snapshot off-main); a `PhotoGridViewController` renders it through the cheap setters;
/// SwiftUI passes only small values (`columns`, `aspectFit`, ids) across the boundary.
struct AssetGridView: View {
  var source: AssetGridSource
  var store: PhotosLocalStore?
  var pipeline: MediaPipeline?
  @Binding var columns: Int
  var aspectFit: Bool = false
  var selection: GridSelectionModel?
  var onOpen: (ViewerRoute) -> Void
  var header: AnyView? = nil
  var onRefresh: (() async -> Void)? = nil
  var onVisibleRange: ((Date?, Date?) -> Void)? = nil
  var showsSectionHeaders: Bool = true
  /// Bumped to reload (sync landed, scope changed, new search ran).
  var reloadToken: Int = 0
  /// WP-G: current user for the selective people badge (G3); scroll-activity
  /// signal for the header subtitle (G6); pinch-past-edge for the density ↔
  /// time-level continuum (G7). All defaulted so existing callers are untouched.
  var currentUserId: String? = nil
  var onPinchEdge: ((Bool) -> Void)? = nil
  var onScrollActive: ((Bool) -> Void)? = nil
  /// WP-M (G4): menu owner for the grid long-press provider. Optional so
  /// callers without a session keep tap-to-open untouched.
  var session: AppSession? = nil

  @StateObject private var loader = LibraryGridLoader()
  @ObservedObject private var selectionModel: GridSelectionModel

  init(
    source: AssetGridSource,
    store: PhotosLocalStore?,
    pipeline: MediaPipeline?,
    columns: Binding<Int>,
    aspectFit: Bool = false,
    selection: GridSelectionModel? = nil,
    onOpen: @escaping (ViewerRoute) -> Void,
    header: AnyView? = nil,
    onRefresh: (() async -> Void)? = nil,
    onVisibleRange: ((Date?, Date?) -> Void)? = nil,
    showsSectionHeaders: Bool = true,
    reloadToken: Int = 0,
    currentUserId: String? = nil,
    onPinchEdge: ((Bool) -> Void)? = nil,
    onScrollActive: ((Bool) -> Void)? = nil,
    session: AppSession? = nil
  ) {
    self.source = source
    self.store = store
    self.pipeline = pipeline
    self._columns = columns
    self.aspectFit = aspectFit
    self.selection = selection
    self._selectionModel = ObservedObject(
      wrappedValue: selection ?? GridSelectionModel())
    self.onOpen = onOpen
    self.header = header
    self.onRefresh = onRefresh
    self.onVisibleRange = onVisibleRange
    self.showsSectionHeaders = showsSectionHeaders
    self.reloadToken = reloadToken
    self.currentUserId = currentUserId
    self.onPinchEdge = onPinchEdge
    self.onScrollActive = onScrollActive
    self.session = session
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      GridBridge(
        loader: loader,
        store: store,
        pipeline: pipeline,
        columns: $columns,
        aspectFit: aspectFit,
        selection: selectionModel,
        onOpen: onOpen,
        onRefresh: onRefresh,
        onVisibleRange: onVisibleRange,
        showsSectionHeaders: showsSectionHeaders,
        currentUserId: currentUserId,
        onPinchEdge: onPinchEdge,
        onScrollActive: onScrollActive,
        session: session
      )
      .ignoresSafeArea(edges: .bottom)
    }
    // Source changes reload immediately; token bumps (sync landed, new search) go
    // through the loader's debounce for timelines and reload directly for id lists.
    .task(id: sourceKey) { await reload(immediate: true) }
    .onChange(of: reloadToken) { _, _ in Task { await reload(immediate: false) } }
  }

  private var sourceKey: String {
    switch source {
    case .timeline(let scope, let granularity):
      let parts = (scope.personalUserIds.sorted() + scope.spaceIds.sorted() + scope.libraryIds.sorted())
        .joined(separator: ",")
      return "timeline-\(parts)-\(granularity.rawValue)"
    case .ids(let ids):
      return "ids-\(ids.count)-\(ids.prefix(3).joined(separator: ","))"
    case .query:
      return "query"
    }
  }

  private func request() async -> GridDataRequest? {
    switch source {
    case .timeline(let scope, let granularity):
      return .timeline(scope: scope, granularity: granularity)
    case .ids(let ids):
      return .ids(ids)
    case .query(let produce):
      guard let ids = try? await produce() else { return nil }
      return .ids(ids)
    }
  }

  private func reload(immediate: Bool) async {
    guard let store, let request = await request() else { return }
    if immediate || !isTimeline {
      await loader.load(request: request, store: store)
    } else {
      loader.noteSyncBump(request: request, store: store)
    }
  }

  private var isTimeline: Bool {
    if case .timeline = source { return true }
    return false
  }
}

// MARK: - UIKit bridge (drives only the cheap setters)

/// `UIViewControllerRepresentable` over the WP1 controller. Every update calls the
/// comparing setters — SwiftUI never computes diffs, layouts or selection loops itself.
/// All references are stable classes/bindings/closures (never a copied view value, which
/// would fork the loader's `StateObject` storage).
private struct GridBridge: UIViewControllerRepresentable {
  var loader: LibraryGridLoader
  var store: PhotosLocalStore?
  var pipeline: MediaPipeline?
  @Binding var columns: Int
  var aspectFit: Bool
  var selection: GridSelectionModel
  var onOpen: (ViewerRoute) -> Void
  var onRefresh: (() async -> Void)?
  var onVisibleRange: ((Date?, Date?) -> Void)?
  var showsSectionHeaders: Bool
  var currentUserId: String?
  var onPinchEdge: ((Bool) -> Void)?
  var onScrollActive: ((Bool) -> Void)?
  var session: AppSession? = nil

  func makeCoordinator() -> Coordinator { Coordinator() }

  /// Owns the loader→VC subscription (lives with the representable, dies with it).
  final class Coordinator {
    var snapshotCancellable: AnyCancellable?
    /// Coalesced prefetch (F5): one in-flight window at a time, cancel-and-replace
    /// on new windows, unchanged windows dropped by the gate below.
    var prefetchTask: Task<Void, Never>?
    var prefetchGate = PrefetchWindowGate()
  }

  func makeUIViewController(context: Context) -> PhotoGridViewController {
    let vc = PhotoGridViewController()
    // First-paint delivery must not depend on SwiftUI's async update pass alone: a
    // published snapshot whose update never ran left the 100k grid empty until the
    // test timed out (nothing re-renders a quiescent grid). The Combine sink applies
    // synchronously on publish, on the main thread; the generation guard inside
    // applySnapshot dedupes against updateUIViewController.
    context.coordinator.snapshotCancellable = loader.$snapshot.sink { [weak vc] snapshot in
      // The sink replays the current (empty) snapshot at subscribe time, before the
      // view loads and the data source exists — skip until then; updateUIViewController
      // applies whatever is current once the view is up.
      guard let vc, vc.isViewLoaded else { return }
      vc.applySnapshot(snapshot, animating: true)
    }
    // The route provider captures the VC's immutable snapshot value (Sendable), never
    // the loader — no per-tap array copy, no actor hop.
    vc.onTap = { [weak vc, onOpen] id in
      guard let snapshot = vc?.currentSnapshot else { return }
      onOpen(ViewerRoute(startId: id) { snapshot.allIds })
    }
    // WP-M (G4): grid long-press menu. Without a session the provider stays
    // nil and tap-to-open is untouched.
    vc.menuProvider = { [session] id, _ in
      guard let session else { return nil }
      return UIHostingController(
        rootView: GridContextMenuSheet(assetId: id).environmentObject(session))
    }
    vc.onSelectionChange = { [weak selection] ids in
      selection?.ids = ids
    }
    // F5: coalesce prefetch events — a fling delivers many overlapping windows and
    // each one used to spawn a full task group against the pipeline's fixed budget,
    // so stale windows crowded out the current one. Now: unchanged windows are
    // dropped, and a new window cancels the stale in-flight one (cancellation
    // propagates through the pipeline's deduped fetch).
    let coordinator = context.coordinator
    vc.onPrefetch = { [weak pipeline, weak coordinator] ids in
      guard let coordinator, let forward = coordinator.prefetchGate.idsToForward(ids)
      else { return }
      // Fixture art never reaches the network (same guard the pre-WP1 grid had).
      let real = forward.filter { !FixtureArtwork.isFixtureAsset($0) }
      guard !real.isEmpty else { return }
      coordinator.prefetchTask?.cancel()
      coordinator.prefetchTask = Task { await pipeline?.prefetch(ids: real, tier: .thumbnail) }
    }
    // Pinch writes straight through the binding (the parent owns the column state).
    let columnsBinding = _columns
    vc.onPinchColumns = { next in columnsBinding.wrappedValue = next }
    vc.onRefresh = onRefresh
    vc.onPinchEdge = onPinchEdge
    vc.onScrollActive = onScrollActive
    vc.pipeline = pipeline
    vc.showsHeaders = showsSectionHeaders
    vc.onNeedRows = { [weak loader, weak store] ids in
      guard let loader, let store else { return }
      Task { await loader.ensureRows(ids: ids, store: store) }
    }
    vc.onVisibleRange = { [onVisibleRange] first, last in onVisibleRange?(first, last) }
    vc.onFirstPaint = { [weak loader, weak vc] in
      vc?.monitor?.firstPaintMs = loader?.lastFirstPaintMs
      vc?.monitor?.gridLoadMs = loader?.lastGridLoadMs ?? 0
      vc?.monitor?.snapshotBuildMs = loader?.lastSnapshotBuildMs ?? 0
    }
    return vc
  }

  func updateUIViewController(_ vc: PhotoGridViewController, context: Context) {
    vc.pipeline = pipeline
    vc.currentUserId = currentUserId
    vc.onPinchEdge = onPinchEdge
    vc.onScrollActive = onScrollActive
    vc.onRefresh = onRefresh
    vc.rowProvider = { [weak loader] in loader?.row(for: $0) }
    vc.flagsProvider = { [weak loader] in loader?.flags(for: $0) ?? [] }
    vc.dateProvider = { [weak loader] in loader?.row(for: $0)?.localDateTime }
    vc.setShowsHeaders(showsSectionHeaders)
    vc.setAspectFit(aspectFit)
    vc.setColumns(columns, animated: false)
    vc.setEditMode(selection.isSelecting)
    vc.applySnapshot(loader.snapshot, animating: true)
    vc.setSelection(selection.ids)
    loader.onRowsUpdated = { [weak vc] in vc?.reconfigureVisibleRows() }
  }
}
