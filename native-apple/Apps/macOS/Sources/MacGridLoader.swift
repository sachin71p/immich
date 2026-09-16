import AppKit
import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI

/// One grid section: an optional bucket header plus its rows.
struct MacGridSection: Sendable, Hashable {
  var header: String?
  var rows: [TimelineRow]
}

/// Loads grid content from the local store (A0 Architecture: the DB is the UI's only data source).
@MainActor
@Observable
final class MacGridLoader {
  /// This is an in-process UI safety net, not normal pagination. It comfortably exceeds the
  /// largest library we support in the desktop timeline, so list views and their footer counts
  /// never silently describe only the first page.
  private static let completeViewLimit = 250_000
  var sections: [MacGridSection] = []
  var assetsById: [String: Asset] = [:]
  var isLoading = false
  var error: String?

  var allRowIds: [String] { sections.flatMap { $0.rows.map(\.id) } }

  func load(
    store: PhotosLocalStore, userId: String, destination: SidebarDestination,
    grouping: TimelineGrouping, switcher: LibraryFilterOption
  ) async {
    isLoading = true
    error = nil
    defer { isLoading = false }
    do {
      sections = try await Self.fetch(
        store: store, userId: userId, destination: destination,
        grouping: grouping, switcher: switcher
      )
      assetsById = try await Self.assetsById(store: store, ids: allRowIds)
    } catch {
      self.error = error.localizedDescription
      sections = []
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
  ) async throws -> [MacGridSection] {
    let override = switcher.explicitFilter
    switch destination.query {
    case .timeline(let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      return try await bucketed(store: store, scope: s, grouping: grouping)
    case .favorites(let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      let rows = try await store.favoriteAssets(scope: s, limit: completeViewLimit)
      return [MacGridSection(header: nil, rows: rows)]
    case .recents, .imports:
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override)
      let rows = try await store.recentAssets(scope: s, limit: completeViewLimit)
      return [MacGridSection(header: nil, rows: rows)]
    case .media(let kind, let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      let rows = try await store.assets(scope: s, mediaKind: kind, limit: completeViewLimit)
      return [MacGridSection(header: nil, rows: rows)]
    case .mediaCollection(let collection, let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      return [MacGridSection(header: nil, rows: try await store.mediaAssets(scope: s, collection: collection, limit: completeViewLimit))]
    case .album(let id):
      let ids = try await store.assetIds(inAlbum: id)
      let assets = try await store.assets(ids: ids)
      let byId = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
      let sorted = assets.sorted { (byId[$0.id] ?? 0) < (byId[$1.id] ?? 0) }
      return [MacGridSection(header: nil, rows: sorted.map(TimelineRow.init(asset:)))]
    case .trash:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [MacGridSection(header: nil, rows: try await store.trashedAssets(scope: s, limit: completeViewLimit))]
    case .hidden:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [MacGridSection(header: nil, rows: try await store.hiddenAssets(scope: s).map(TimelineRow.init(asset:)))]
    case .archive:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [MacGridSection(header: nil, rows: try await store.archivedAssets(scope: s).map(TimelineRow.init(asset:)))]
    case .locked:
      return [MacGridSection(header: nil, rows: try await store.lockedAssets(currentUserId: userId, limit: completeViewLimit))]
    case .capturedByMe:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      let assets = try await store.capturedByUser(userId, scope: s, limit: completeViewLimit)
      return [MacGridSection(header: nil, rows: assets.map(TimelineRow.init(asset:)))]
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
      return [MacGridSection(header: nil, rows: assets.map(TimelineRow.init(asset:)))]
    case .map, .people, .memories, .search:
      return []
    }
  }

  private static func bucketed(
    store: PhotosLocalStore, scope: ContainerScope, grouping: TimelineGrouping
  ) async throws -> [MacGridSection] {
    let buckets = try await store.timelineBuckets(scope: scope, granularity: .month)
    if grouping == .all {
      // All Photos is the complete local timeline, not merely the first screenful. Images are
      // still loaded lazily per visible cell; only lightweight row metadata is retained here.
      var rows: [TimelineRow] = []
      for bucket in buckets {
        rows += try await store.timelineAssets(
          scope: scope, bucketKey: bucket.key, granularity: .month, limit: bucket.count)
      }
      return [MacGridSection(header: nil, rows: rows)]
    }
    var sections: [MacGridSection] = []
    var lastYear: String?
    for bucket in buckets {
      let rows = try await store.timelineAssets(
        scope: scope, bucketKey: bucket.key, granularity: .month, limit: bucket.count)
      guard !rows.isEmpty else { continue }
      if grouping.groupsByYear {
        let year = String(bucket.key.prefix(4))
        if year != lastYear {
          sections.append(MacGridSection(header: year, rows: []))
          lastYear = year
        }
      }
      sections.append(MacGridSection(header: Self.bucketTitle(bucket.key), rows: rows))
    }
    return sections
  }

  private static func bucketTitle(_ key: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    if let date = formatter.date(from: key) {
      formatter.dateFormat = "MMMM yyyy"
      return formatter.string(from: date)
    }
    return key
  }

  private static func assetsById(store: PhotosLocalStore, ids: [String]) async throws -> [String: Asset] {
    var result: [String: Asset] = [:]
    for chunk in ids.chunked(into: 400) {
      for asset in try await store.assets(ids: chunk) { result[asset.id] = asset }
    }
    return result
  }
}

extension Array {
  func chunked(into size: Int) -> [[Element]] {
    guard size > 0 else { return [self] }
    return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
}
