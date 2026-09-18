import Combine
import CoreModel
import Foundation
import LocalStore
import Rules

// MARK: - zoom levels (brief task 1)

/// Apple-style grid zoom: Years → Months → All. Each level maps to a bucket
/// granularity (backed by `PhotosLocalStore.timelineBuckets`) and a default column count; pinch
/// moves between column counts within and across levels.
/// Zoom levels (WP2 owns the Years/Months views; Days is removed — All is the flat
/// grid, Months/Years are separate views driven by `bucketSummaries`).
enum LibraryZoomLevel: String, CaseIterable, Identifiable {
  case years, months, all

  var id: String { rawValue }
  var title: String {
    switch self {
    case .years: return "Years"
    case .months: return "Months"
    case .all: return "All"
    }
  }

  var granularity: PhotosLocalStore.Granularity {
    switch self {
    case .years: return .year
    case .months: return .month
    case .all: return .day
    }
  }

  var defaultColumns: Int {
    switch self {
    case .years: return 2
    case .months: return 3
    case .all: return 5
    }
  }
}

/// The timeline source picked in the library switcher (brief task 2, DECISIONS §9 explicit filter).
/// `all` is the preference-driven timeline (Both/all sources); the rest are access-checked explicit
/// filters resolved through `Rules.TimelineScope`.
enum LibrarySource: Hashable {
  case all
  case personal
  case space(String)
  case library(String)

  var filter: ExplicitContainerFilter? {
    switch self {
    case .all: return nil
    case .personal: return .personalOnly
    case .space(let id): return .space(id)
    case .library(let id): return .library(id)
    }
  }
}

// MARK: - grid data request

/// What feeds the grid: a store-backed timeline (one index query) or an explicit id list in
/// the caller's order (search results). Small and value-typed — SwiftUI passes these, never
/// a hydrated model.
enum GridDataRequest: Sendable, Hashable {
  case timeline(scope: ContainerScope, granularity: PhotosLocalStore.Granularity)
  case ids([String])
}

// MARK: - loader

/// WP1 §3: the grid's data owner (a `@MainActor` `ObservableObject`) publishing only an
/// immutable `GridSnapshot` plus `isLoading`. The snapshot is built in a detached task from
/// the one-query `timelineIndex`, gated by generation (a newer request cancels an older
/// one); cancellation is silent. Row details (thumbhash/badges) page in per visible window
/// via `assetsLite` — the snapshot itself carries ids only.
///
/// Sync updates: `noteSyncBump` re-queries the index and publishes a new generation only
/// when membership or order changed (the VC diffs, never tearing down); flag-only changes
/// refresh the row cache and reconfigure visible cells in place. Bumps debounce to a
/// leading load plus at most one trailing load per 2 s.
@MainActor
final class LibraryGridLoader: ObservableObject {
  @Published private(set) var snapshot = GridSnapshot.empty
  @Published private(set) var isLoading = false

  /// Full rows behind the visible window (thumbhash, favorite, duration) for badges and
  /// placeholders. Read synchronously from the VC's cell configuration (O(1) lookup).
  private var rowsById: [String: TimelineRow] = [:]
  private var flagsById: [String: PhotosLocalStore.TimelineIndexFlags] = [:]

  /// Fires when only the row/flag cache changed (same snapshot generation): the VC
  /// reconfigures visible cells in place instead of applying a snapshot.
  var onRowsUpdated: (() -> Void)?

  /// First-paint timing for the perf gate: seconds from `load` start to the first
  /// non-empty snapshot publish. Read by the flick-scroll UI test via the VC hook.
  private(set) var lastFirstPaintMs: Double?
  /// Latest GridLoad / SnapshotBuild wall times (the signposts also emit these for
  /// Instruments; the UI test reads the numbers from the perf summary).
  private(set) var lastGridLoadMs: Double = 0
  private(set) var lastSnapshotBuildMs: Double = 0

  private var generation = 0
  private var loadTask: Task<Void, Never>?
  private var debounceTask: Task<Void, Never>?
  private var lastReloadStart = Date.distantPast
  private var loadStart = Date()
  /// The request behind the currently published snapshot (F4 early-out below).
  private var lastLoadedRequest: GridDataRequest?

  /// Cross-instance retained timeline product (F4): tab switches recreate the
  /// SwiftUI view and with it this loader, and a cold `timelineIndex` over 102k
  /// rows plus snapshot build plus first-window page is what blanks the grid for
  /// ~4 s on return. Retaining the last timeline product lets a fresh loader
  /// paint synchronously from what was on screen, then refresh in the background
  /// without blanking. Timelines only — `.ids` (search) results go stale by
  /// definition and are never retained. Bounded: one snapshot (~10 MB at 102k
  /// ids) plus the already-paged rows; thumbnails themselves live in the
  /// pipeline's budgeted memory/disk caches, not here.
  private struct RetainedTimeline: Sendable {
    var request: GridDataRequest
    var snapshot: GridSnapshot
    var rows: [String: TimelineRow]
    var flags: [String: PhotosLocalStore.TimelineIndexFlags]
  }

  private static var retainedTimeline: RetainedTimeline?

  func row(for id: String) -> TimelineRow? { rowsById[id] }
  func flags(for id: String) -> PhotosLocalStore.TimelineIndexFlags { flagsById[id] ?? [] }

  /// Loads one pass for `request`, replacing any in-flight load. Empty `.ids` publishes an
  /// empty snapshot immediately (search with no results never spins).
  /// - Parameter force: sync bumps (`noteSyncBump`) always re-query; a tab return
  ///   re-issuing the identical request skips it (F4 early-out below).
  func load(request: GridDataRequest, store: PhotosLocalStore, force: Bool = false) async {
    loadTask?.cancel()
    debounceTask?.cancel()
    loadStart = Date()
    // F4: a tab return re-issues the identical load. When this instance already
    // holds it, the published snapshot is right — skip the index re-query entirely.
    if !force, request == lastLoadedRequest, !snapshot.isEmpty { return }
    // F4: a fresh instance (recreated tab view) replays the retained timeline
    // synchronously for first paint, then falls through to the background refresh
    // below, which publishes only on change — the grid never blanks.
    if snapshot.isEmpty, case .timeline = request,
      let kept = Self.retainedTimeline, kept.request == request
    {
      rowsById = kept.rows
      flagsById = kept.flags
      lastFirstPaintMs = Date().timeIntervalSince(loadStart) * 1000
      snapshot = kept.snapshot
      lastLoadedRequest = request
    }
    generation += 1
    let current = generation
    isLoading = true
    defer {
      if current == generation { isLoading = false }
    }
    await runLoad(request: request, store: store, generation: current)
  }

  /// Sync landed: re-query with a leading load when idle, else one trailing load per 2 s.
  func noteSyncBump(request: GridDataRequest, store: PhotosLocalStore) {
    if Date().timeIntervalSince(lastReloadStart) >= 2 {
      Task { await load(request: request, store: store, force: true) }
      return
    }
    debounceTask?.cancel()
    debounceTask = Task {
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard !Task.isCancelled else { return }
      await self.load(request: request, store: store, force: true)
    }
  }

  /// Pages full rows for ids not yet cached (visible window + prefetch). Merges into the
  /// cache and notifies for in-place reconfiguration when the snapshot is unchanged.
  func ensureRows(ids: [String], store: PhotosLocalStore) async {
    let missing = ids.filter { rowsById[$0] == nil }
    guard !missing.isEmpty else { return }
    guard let rows = try? await store.assetsLite(ids: missing) else { return }
    guard !Task.isCancelled else { return }
    for row in rows { rowsById[row.id] = row }
    onRowsUpdated?()
  }

  // MARK: - internals

  private func runLoad(
    request: GridDataRequest, store: PhotosLocalStore, generation current: Int
  ) async {
    lastReloadStart = Date()
    // All heavy work (SQL + grouping) runs detached: the closure captures only Sendable
    // state, and gating re-checks the generation back on the main actor afterwards.
    let req = request
    typealias GridProduct = (
      snapshot: GridSnapshot, flags: [(String, PhotosLocalStore.TimelineIndexFlags)], buildMs: Double
    )
    let work: @Sendable () async -> GridProduct = {
      switch req {
      case .timeline(let scope, let granularity):
        guard let index = try? await store.timelineIndex(scope: scope),
          !Task.isCancelled
        else {
          return (GridSnapshot.empty, [], 0)
        }
        let flags = index.entries.map { ($0.id, $0.flags) }
        let buildStart = Date()
        let built = HeirloomSignpost.interval(HeirloomSignpost.snapshotBuild) {
          GridSnapshot.build(entries: index.entries, granularity: granularity, generation: current)
        }
        return (built, flags, Date().timeIntervalSince(buildStart) * 1000)
      case .ids(let ids):
        return (GridSnapshot.flat(ids: ids, title: "Results", generation: current), [], 0)
      }
    }
    // Detached so the index decode and grouping never run on the main actor; the async
    // signpost only brackets the interval, it does not hop threads by itself.
    let loadStartDetached = Date()
    let GridWork: @Sendable () async -> GridProduct = {
      await HeirloomSignpost.interval(HeirloomSignpost.gridLoad, work)
    }
    let product = await Task.detached(operation: GridWork).value
    lastGridLoadMs = Date().timeIntervalSince(loadStartDetached) * 1000
    lastSnapshotBuildMs = product.buildMs
    let (snapshot, flags) = (product.snapshot, product.flags)
    guard current == self.generation && !Task.isCancelled else { return }
    lastLoadedRequest = req
    for (id, flag) in flags { flagsById[id] = flag }
    let firstPaint = self.snapshot.isEmpty && !snapshot.isEmpty
    // Publish a new generation only when membership or order changed — identical sync
    // re-queries leave the published instance (and the collection view) untouched.
    if snapshot.allIds != self.snapshot.allIds || self.snapshot.generation == 0 {
      // Stamp first-paint BEFORE publishing: the bridge's synchronous subscriber reads
      // these timings during the assignment itself (before the next line would run).
      if firstPaint {
        lastFirstPaintMs = Date().timeIntervalSince(loadStart) * 1000
      }
      self.snapshot = snapshot
    }
    // Page the first window for badges/placeholders even when the snapshot was unchanged.
    await ensureRows(ids: Array(snapshot.allIds.prefix(300)), store: store)
    // Refresh the retained product (F4) so the next fresh instance replays what is
    // on screen now. Timelines only; later row pages stay instance-local (the
    // pipeline caches serve their thumbnails after a return).
    if case .timeline = req {
      Self.retainedTimeline = RetainedTimeline(
        request: req, snapshot: self.snapshot, rows: rowsById, flags: flagsById)
    }
  }
}
