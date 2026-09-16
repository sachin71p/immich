import Combine
import CoreModel
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

// MARK: - grid model

/// Everything the UIKit grid needs for one render pass: bucket headers, row ids per bucket, and
/// the hydrated assets behind the visible rows (badges need duration/container/favorite).
struct LibraryGridModel {
  var buckets: [TimelineBucket] = []
  var rowIdsByBucket: [String: [String]] = [:]
  var rowsById: [String: TimelineRow] = [:]
  var assetsById: [String: Asset] = [:]

  var allRowIds: [String] { buckets.flatMap { rowIdsByBucket[$0.key] ?? [] } }
}

@MainActor
final class LibraryGridLoader: ObservableObject {
  @Published var model = LibraryGridModel()
  @Published var isLoading = false

  /// Loads one granularity pass for `scope`: bucket headers, then the first page of every bucket,
  /// then the assets behind those rows for badges. Pagination within a bucket stays a scroll-driven
  /// follow-up (`loadMore`) so first paint never waits on the whole library.
  func load(scope: ContainerScope, granularity: PhotosLocalStore.Granularity, store: PhotosLocalStore) async {
    isLoading = true
    defer { isLoading = false }
    do {
      let buckets = try await store.timelineBuckets(scope: scope, granularity: granularity)
      var rowIdsByBucket: [String: [String]] = [:]
      var rowsById: [String: TimelineRow] = [:]
      for bucket in buckets {
        let rows = try await store.timelineAssets(scope: scope, bucketKey: bucket.key, granularity: granularity)
        rowIdsByBucket[bucket.key] = rows.map(\.id)
        for row in rows { rowsById[row.id] = row }
      }
      let assets = try await store.assets(ids: Array(rowsById.keys))
      model = LibraryGridModel(
        buckets: buckets, rowIdsByBucket: rowIdsByBucket, rowsById: rowsById,
        assetsById: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }))
    } catch {
      model = LibraryGridModel()
    }
  }
}
