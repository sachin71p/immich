import AppKit
import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI
import os

/// Loads grid content from the local store (A0 Architecture: the DB is the UI's only data source).
@MainActor
@Observable
final class MacGridLoader {
  enum Phase: Equatable {
    case idle, loading, loaded, failed(String)
  }

  /// Presentation inputs: sort order plus the include-predicate inputs. Copied by value
  /// into every off-main rebuild, so the predicate never touches main-actor state.
  /// `Equatable` so `setPresentation` with unchanged input skips the rebuild (the view
  /// re-syncs presentation before every load).
  private struct Presentation: Sendable, Equatable {
    var order: TimelineOrder = .newestFirst
    var filters: Set<TimelineQuickFilter> = [.all]
    var userId = ""
    var albumMemberIds: Set<String>? = nil

    /// All cases resolve from the row alone — no store fetch, no dictionary lookup —
    /// so this runs as a `@Sendable` closure inside the detached snapshot build.
    func include(_ row: TimelineRow) -> Bool {
      if filters.contains(.all) || filters.isEmpty { return true }
      return filters.contains { filter in
        switch filter {
        case .all: return true
        case .favorites: return row.isFavorite
        case .edited: return row.isEdited
        case .photos: return row.mediaKind == .photo || row.mediaKind == .livePhoto
        case .videos: return row.mediaKind == .video
        case .screenshots: return row.mediaKind == .screenshot
        case .capturedByMe: return row.ownerId == userId
        case .notInAlbum: return albumMemberIds.map { !$0.contains(row.id) } ?? true
        }
      }
    }
  }

  /// This is an in-process UI safety net, not normal pagination. It comfortably exceeds the
  /// largest library we support in the desktop timeline, so list views and their footer counts
  /// never silently describe only the first page.
  private static let completeViewLimit = 250_000

  /// The grid's single source of truth: a reference type, so publishing a new snapshot is
  /// an O(1) identity comparison instead of a value-by-value `==` over 102k rows (R2).
  private(set) var snapshot: TimelineGridSnapshot = .empty
  private(set) var phase: Phase = .idle
  private(set) var lastPatch: (revision: Int, indexes: [Int]) = (0, [])

  @ObservationIgnored private var source: [TimelineSourceSection] = []
  @ObservationIgnored private var presentation = Presentation()
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  @ObservationIgnored private var rebuildTask: Task<Void, Never>?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var currentDestination: SidebarDestination?
  @ObservationIgnored private var currentGrouping: TimelineGrouping = .months
  @ObservationIgnored private var currentSwitcher: LibraryFilterOption = .all
  @ObservationIgnored private var currentStore: PhotosLocalStore?
  @ObservationIgnored private var currentUserId = ""
  /// Set by the view so edited rows can evict stale cache entries.
  @ObservationIgnored var pipeline: MediaPipeline?

  /// Launch-signpost emitter for the WP0/WP7 harness. A local signposter (same
  /// subsystem/category as `HeirloomSignpost`, whose `interval()` helpers can't take this
  /// MainActor-isolated loader's closures under Swift 6 region isolation) emitting the exact
  /// `HeirloomSignpost.gridLoad` / `.snapshotBuild` interval names.
  private static let launchSignposter = OSSignposter(
    subsystem: "com.immich.heirloom", category: "timeline")

  // MARK: - load

  func load(
    store: PhotosLocalStore, userId: String, destination: SidebarDestination,
    grouping: TimelineGrouping, switcher: LibraryFilterOption
  ) async {
    loadTask?.cancel()
    // A new destination must never show the old destination's content under a new title:
    // clear immediately. Grouping/switcher/sync reloads in the same destination keep the
    // old snapshot until the new one is ready. (The view shows a spinner only past 150 ms.)
    let destinationChanged = destination != currentDestination
    currentDestination = destination
    currentGrouping = grouping
    currentSwitcher = switcher
    currentStore = store
    currentUserId = userId
    if destinationChanged {
      snapshot = .empty
    }
    phase = .loading
    let myGeneration = nextGeneration()
    let frozen = presentation
    loadTask = Task {
      let gridLoadState = Self.launchSignposter.beginInterval(HeirloomSignpost.gridLoad)
      defer { Self.launchSignposter.endInterval(HeirloomSignpost.gridLoad, gridLoadState) }
      do {
        // Store queries are nonisolated async: they suspend off the main thread even
        // though this task runs on the main actor. No MainActor wrapping anywhere.
        let sections = try await Self.fetch(
          store: store, userId: userId, destination: destination,
          grouping: grouping, switcher: switcher
        )
        try Task.checkCancellation()
        let built = await Self.buildSnapshot(
          sections: sections, presentation: frozen, generation: myGeneration)
        guard !Task.isCancelled, myGeneration == self.generation else { return }
        self.source = sections
        self.snapshot = built
        self.phase = .loaded
      } catch is CancellationError {
        // Cancellation is not an error: keep the current snapshot, show nothing.
        return
      } catch let urlError as URLError where urlError.code == .cancelled {
        return
      } catch {
        HeirloomLog.timeline.error(
          "Grid load failed: \(error.localizedDescription, privacy: .public)")
        phase = .failed(error.localizedDescription)
        // Keep the old snapshot when the destination didn't change (already `.empty`
        // above when it did), so a failed refresh never blanks a good grid.
      }
    }
  }

  // MARK: - presentation

  func setPresentation(
    order: TimelineOrder, filters: Set<TimelineQuickFilter>,
    userId: String, albumMemberIds: Set<String>?
  ) {
    let next = Presentation(
      order: order, filters: filters, userId: userId, albumMemberIds: albumMemberIds)
    guard next != presentation else { return }
    presentation = next
    // Rebuild only: reuse the last fetch, no store I/O, no main-thread pass over rows.
    guard currentStore != nil else { return }
    startRebuild()
  }

  // MARK: - apply

  func apply(_ change: MacAssetChange, destination: SidebarDestination) {
    switch change {
    case .favorite(let ids, let isFavorite):
      if destination == .favorites, !isFavorite {
        snapshot = snapshot.removing(ids: ids, generation: nextGeneration())
      } else {
        // `patching` carries dateRange and only touches the named rows (WP1 contract:
        // the transform must not reorder rows or change dates).
        let (next, changed) = snapshot.patching(ids: ids) { $0.isFavorite = isFavorite }
        snapshot = next
        lastPatch = (next.revision, changed)
      }
    case .removedFromCurrentContexts(let ids):
      snapshot = snapshot.removing(ids: ids, generation: nextGeneration())
    case .edited(let ids):
      let (next, changed) = snapshot.patching(ids: ids) { $0.isEdited = true }
      snapshot = next
      lastPatch = (next.revision, changed)
      evictCaches(ids: ids)
    case .albumsChanged:
      guard presentation.filters.contains(.notInAlbum), let store = currentStore else { return }
      let userId = currentUserId
      rebuildTask?.cancel()
      rebuildTask = Task {
        do {
          let memberIds = try await store.assetIdsInAnyAlbum(userId: userId)
          try Task.checkCancellation()
          presentation.albumMemberIds = memberIds
          startRebuild()
        } catch is CancellationError {
          return
        } catch let urlError as URLError where urlError.code == .cancelled {
          return
        } catch {
          HeirloomLog.timeline.error(
            "Not-in-album refetch failed: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
  }

  // MARK: - private

  private func nextGeneration() -> Int {
    generation += 1
    return generation
  }

  /// Rebuild the snapshot from the last fetch with the current presentation, off-main.
  private func startRebuild() {
    rebuildTask?.cancel()
    let sections = source
    let frozen = presentation
    let myGeneration = nextGeneration()
    rebuildTask = Task {
      let built = await Self.buildSnapshot(
        sections: sections, presentation: frozen, generation: myGeneration)
      guard !Task.isCancelled, myGeneration == self.generation else { return }
      self.snapshot = built
    }
  }

  /// Snapshot construction runs detached at user-initiated priority: the row filter and
  /// section assembly never execute on the main thread, no matter the library size. Wrapped in
  /// the exact `HeirloomSignpost.snapshotBuild` interval (begin fires before the detached hop,
  /// end after `.value` returns, so the detached section is inside the interval).
  private static func buildSnapshot(
    sections: [TimelineSourceSection], presentation: Presentation, generation: Int
  ) async -> TimelineGridSnapshot {
    let state = Self.launchSignposter.beginInterval(HeirloomSignpost.snapshotBuild)
    defer { Self.launchSignposter.endInterval(HeirloomSignpost.snapshotBuild, state) }
    return await Task.detached(priority: .userInitiated) {
      TimelineGridSnapshot.build(
        sections: sections, order: presentation.order,
        include: { presentation.include($0) }, generation: generation)
    }.value
  }

  /// Drop stale unedited memory-cache entries for rows whose edited rendition just
  /// changed. Disk has no per-id removal through the pipeline (its cache is private),
  /// so disk entries age out on their normal edited-flag lookup instead.
  private func evictCaches(ids: Set<String>) {
    guard let pipeline else { return }
    let memory = pipeline.memory
    for id in ids {
      for tier in MediaTier.allCases {
        memory.remove(id: id, tier: tier, edited: false)
      }
    }
  }

  // MARK: - fetch

  private static func scope(
    store: PhotosLocalStore, userId: String, purpose: TimelinePurpose,
    filter: ExplicitContainerFilter?
  ) async throws -> ContainerScope {
    let ctx = try await store.timelineContext(for: userId, explicitFilter: filter)
    return TimelineScope.resolve(purpose: purpose, context: ctx)
  }

  static func fetch(
    store: PhotosLocalStore, userId: String, destination: SidebarDestination,
    grouping: TimelineGrouping, switcher: LibraryFilterOption
  ) async throws -> [TimelineSourceSection] {
    let override = switcher.explicitFilter
    switch destination.query {
    case .timeline(let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      return try await timelineSections(store: store, scope: s, grouping: grouping)
    case .favorites(let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      let rows = try await store.favoriteAssets(scope: s, limit: completeViewLimit)
      return [TimelineSourceSection(kind: .none, rows: rows)]
    case .recents(let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      let rows = try await store.recentAssets(scope: s, limit: completeViewLimit)
      return [TimelineSourceSection(kind: .none, rows: rows)]
    case .imports:
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override)
      let rows = try await store.recentAssets(scope: s, limit: completeViewLimit)
      return [TimelineSourceSection(kind: .none, rows: rows)]
    case .media(let kind, let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      let rows = try await store.assets(scope: s, mediaKind: kind, limit: completeViewLimit)
      return [TimelineSourceSection(kind: .none, rows: rows)]
    case .mediaCollection(let collection, let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      return [TimelineSourceSection(kind: .none, rows: try await store.mediaAssets(scope: s, collection: collection, limit: completeViewLimit))]
    case .album(let id):
      return [TimelineSourceSection(kind: .none, rows: try await store.albumAssets(albumId: id, limit: completeViewLimit))]
    case .trash:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [TimelineSourceSection(kind: .none, rows: try await store.trashedAssets(scope: s, limit: completeViewLimit))]
    case .hidden:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [TimelineSourceSection(kind: .none, rows: try await store.hiddenAssets(scope: s).map(TimelineRow.init(asset:)))]
    case .archive:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [TimelineSourceSection(kind: .none, rows: try await store.archivedAssets(scope: s).map(TimelineRow.init(asset:)))]
    case .locked:
      return [TimelineSourceSection(kind: .none, rows: try await store.lockedAssets(currentUserId: userId, limit: completeViewLimit))]
    case .capturedByMe:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      let assets = try await store.capturedByUser(userId, scope: s, limit: completeViewLimit)
      return [TimelineSourceSection(kind: .none, rows: assets.map(TimelineRow.init(asset:)))]
    case .camera(let category):
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      // Category destinations deliberately resolve their member EXIF models at query time. This
      // keeps "Phone" and "DSLR" complete as new models arrive in a subsequent sync.
      let models = try await store.cameraModels(scope: s)
        .filter { $0.category == category }
        .map(\.model)
      var assets: [Asset] = []
      for model in models {
        assets += try await store.assets(cameraModel: model, scope: s, limit: completeViewLimit)
      }
      assets.sort { ($0.localDateTime ?? .distantPast) > ($1.localDateTime ?? .distantPast) }
      return [TimelineSourceSection(kind: .none, rows: assets.map(TimelineRow.init(asset:)))]
    case .map, .people, .memories, .search:
      return []
    }
  }

  /// Timeline fetch: bucket counts plus one single-transaction `timelineRows` read (WP1),
  /// partitioned client-side into month groups. All Photos flattens to one `.none` section;
  /// Months emits `.month` sections; Years emits an empty `.year` marker before each
  /// year's `.month` sections.
  private static func timelineSections(
    store: PhotosLocalStore, scope: ContainerScope, grouping: TimelineGrouping
  ) async throws -> [TimelineSourceSection] {
    let buckets = try await store.timelineBuckets(scope: scope, granularity: .month)
    let rows = try await store.timelineRows(
      scope: scope, bucketKeys: buckets.map(\.key), granularity: .month)
    if grouping == .all {
      return [TimelineSourceSection(kind: .none, rows: rows)]
    }
    // Rows arrive newest-first, so same-month rows are contiguous: group in one pass
    // without re-formatting every date. Keys come from the bucket list; membership is
    // restricted to those keys so sections match the counts query exactly.
    let knownKeys = Set(buckets.map(\.key))
    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var groups: [(key: String, rows: [TimelineRow])] = []
    for row in rows {
      guard let date = row.localDateTime else { continue }
      let components = utcCalendar.dateComponents([.year, .month], from: date)
      guard let year = components.year, let month = components.month else { continue }
      let key = String(format: "%04d-%02d", year, month)
      guard knownKeys.contains(key) else { continue }
      if groups.last?.key == key {
        groups[groups.count - 1].rows.append(row)
      } else {
        groups.append((key, [row]))
      }
    }
    var sections: [TimelineSourceSection] = []
    var lastYear: String?
    for group in groups {
      if grouping.groupsByYear {
        let year = String(group.key.prefix(4))
        if year != lastYear {
          sections.append(TimelineSourceSection(header: year, kind: .year, rows: []))
          lastYear = year
        }
      }
      sections.append(TimelineSourceSection(
        header: TimelineBucketTitle.title(forKey: group.key, kind: .month),
        kind: .month, rows: group.rows))
    }
    return sections
  }

}
