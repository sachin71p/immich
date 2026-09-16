import Combine
import CoreModel
import Foundation
import LocalStore
import Rules

// MARK: - zoom levels (brief task 1)

/// Apple-style grid zoom: Years → Months → Days → All Photos. Each level maps to a bucket
/// granularity (backed by `PhotosLocalStore.timelineBuckets`) and a default column count; pinch
/// moves between column counts within and across levels.
enum LibraryZoomLevel: String, CaseIterable, Identifiable {
  case years, months, days, all

  var id: String { rawValue }
  var title: String {
    switch self {
    case .years: return "Years"
    case .months: return "Months"
    case .days: return "Days"
    case .all: return "All Photos"
    }
  }

  var granularity: PhotosLocalStore.Granularity {
    switch self {
    case .years, .months: return .month
    case .days, .all: return .day
    }
  }

  var defaultColumns: Int {
    switch self {
    case .years: return 2
    case .months: return 3
    case .days: return 5
    case .all: return 7
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

// MARK: - interim model (removed in step 9)

/// Pre-WP1 hydrated model. Kept until LibraryView/SearchView move onto `AssetGridView`;
/// filled from the single-transaction `timelineRows` query (no per-bucket fan-out).
struct LibraryGridModel {
  var buckets: [TimelineBucket] = []
  var rowIdsByBucket: [String: [String]] = [:]
  var rowsById: [String: TimelineRow] = [:]
  var assetsById: [String: Asset] = [:]

  var allRowIds: [String] { buckets.flatMap { rowIdsByBucket[$0.key] ?? [] } }
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
  /// Interim pre-WP1 model (removed in step 9).
  @Published var model = LibraryGridModel()

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

  private var generation = 0
  private var loadTask: Task<Void, Never>?
  private var debounceTask: Task<Void, Never>?
  private var lastReloadStart = Date.distantPast
  private var loadStart = Date()

  func row(for id: String) -> TimelineRow? { rowsById[id] }
  func flags(for id: String) -> PhotosLocalStore.TimelineIndexFlags { flagsById[id] ?? [] }

  /// Interim pre-WP1 entry point (LibraryView/SearchView until step 9). One
  /// `timelineRows` transaction grouped client-side — no per-bucket fan-out, no `assets`
  /// hydration (badges read the row projection).
  func load(
    scope: ContainerScope, granularity: PhotosLocalStore.Granularity, store: PhotosLocalStore
  ) async {
    isLoading = true
    defer { isLoading = false }
    do {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
      let rows = try await store.timelineRows(scope: scope, granularity: granularity)
      var order: [String] = []
      var grouped: [String: [TimelineRow]] = [:]
      for row in rows {
        let key = GridSnapshot.bucketKey(
          for: row.localDateTime, granularity: granularity, calendar: calendar)
        if grouped[key] == nil {
          grouped[key] = []
          order.append(key)
        }
        grouped[key]?.append(row)
      }
      var rowIdsByBucket: [String: [String]] = [:]
      var rowsById: [String: TimelineRow] = [:]
      for key in order {
        let members = grouped[key] ?? []
        rowIdsByBucket[key] = members.map(\.id)
        for row in members { rowsById[row.id] = row }
      }
      // Newest bucket first (rows arrive newest-first, so first-seen order is desc).
      let buckets = order.map { TimelineBucket(key: $0, count: rowIdsByBucket[$0]?.count ?? 0) }
      self.rowsById = rowsById
      // Interim model carries no assets; badges fall back to rows.
      model = LibraryGridModel(
        buckets: buckets, rowIdsByBucket: rowIdsByBucket, rowsById: rowsById, assetsById: [:])
    } catch {
      model = LibraryGridModel()
    }
  }

  /// Loads one pass for `request`, replacing any in-flight load. Empty `.ids` publishes an
  /// empty snapshot immediately (search with no results never spins).
  func load(request: GridDataRequest, store: PhotosLocalStore) async {
    loadTask?.cancel()
    debounceTask?.cancel()
    generation += 1
    let current = generation
    isLoading = true
    loadStart = Date()
    defer {
      if current == generation { isLoading = false }
    }
    await runLoad(request: request, store: store, generation: current)
  }

  /// Sync landed: re-query with a leading load when idle, else one trailing load per 2 s.
  func noteSyncBump(request: GridDataRequest, store: PhotosLocalStore) {
    if Date().timeIntervalSince(lastReloadStart) >= 2 {
      Task { await load(request: request, store: store) }
      return
    }
    debounceTask?.cancel()
    debounceTask = Task {
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard !Task.isCancelled else { return }
      await self.load(request: request, store: store)
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
    let work: @Sendable () async -> (GridSnapshot, [(String, PhotosLocalStore.TimelineIndexFlags)]) =
      {
        switch req {
        case .timeline(let scope, let granularity):
          guard let index = try? await store.timelineIndex(scope: scope),
            !Task.isCancelled
          else {
            return (GridSnapshot.empty, [])
          }
          let flags = index.entries.map { ($0.id, $0.flags) }
          let built = await HeirloomSignpost.interval(HeirloomSignpost.snapshotBuild) {
            GridSnapshot.build(entries: index.entries, granularity: granularity, generation: current)
          }
          return (built, flags)
        case .ids(let ids):
          return (GridSnapshot.flat(ids: ids, title: "Results", generation: current), [])
        }
      }
    // Detached so the index decode and grouping never run on the main actor; the async
    // signpost only brackets the interval, it does not hop threads by itself.
    let GridWork: @Sendable () async -> (GridSnapshot, [(String, PhotosLocalStore.TimelineIndexFlags)]) =
      {
        await HeirloomSignpost.interval(HeirloomSignpost.gridLoad, work)
      }
    let (snapshot, flags) = await Task.detached(operation: GridWork).value
    guard current == self.generation && !Task.isCancelled else { return }
    for (id, flag) in flags { flagsById[id] = flag }
    let firstPaint = self.snapshot.isEmpty && !snapshot.isEmpty
    // Publish a new generation only when membership or order changed — identical sync
    // re-queries leave the published instance (and the collection view) untouched.
    if snapshot.allIds != self.snapshot.allIds || self.snapshot.generation == 0 {
      self.snapshot = snapshot
      if firstPaint {
        lastFirstPaintMs = Date().timeIntervalSince(loadStart) * 1000
      }
    }
    // Page the first window for badges/placeholders even when the snapshot was unchanged.
    await ensureRows(ids: Array(snapshot.allIds.prefix(300)), store: store)
  }
}
