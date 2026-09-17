import CoreModel
import Foundation
import LocalStore
import Rules

// MARK: - library filter model (WP2 §2)

// Native Photos filter menu, persisted in `@AppStorage` (`heirloom.*` naming).
// The grid itself only understands `.timeline(scope, granularity)` and `.ids` —
// `resolveGrid` below maps the menu state onto one of those two, off-main.

/// Sort section: the two large buttons at the top of the filter menu.
enum LibrarySort: String, CaseIterable {
  case added
  case captured

  var title: String {
    switch self {
    case .added: return "Added"
    case .captured: return "Captured"
    }
  }
}

/// "Filter:" items with checkmarks. Only one is active at a time (`all` = no filter).
enum LibraryFilterItem: String, CaseIterable {
  case all
  case favorites
  case edited
  case sharedWithYou
  case capturedByMe
  case notInAlbum

  var title: String {
    switch self {
    case .all: return "All Items"
    case .favorites: return "Favorites"
    case .edited: return "Edited"
    case .sharedWithYou: return "Shared with You"
    case .capturedByMe: return "Captured by Me"
    case .notInAlbum: return "Not in an Album"
    }
  }
}

/// Media Types submenu. Only kinds the store classifies are offered — there is no
/// selfie classifier in `mediaKindCaseSQL`, so Selfies is omitted (see WP2 report).
enum LibraryMediaKind: String, CaseIterable {
  case videos
  case livePhotos
  case screenshots
  case panoramas

  var title: String {
    switch self {
    case .videos: return "Videos"
    case .livePhotos: return "Live Photos"
    case .screenshots: return "Screenshots"
    case .panoramas: return "Panoramas"
    }
  }
}

// MARK: - grid resolution

/// A resolved grid input plus the item count for the bottom "N Items" label.
/// Counts come from the same fetch that produces the ids — never a second query.
struct ResolvedLibraryGrid: Sendable {
  var source: AssetGridSource
  var count: Int
}

/// Maps filter-menu state onto an `AssetGridSource`. The default state (All Items,
/// no kinds, Captured sort, nothing hidden) keeps the fast `.timeline` path — one
/// index query in the loader. Any active filter/sort/kind/hide resolves ids through
/// paged store queries in this detached task and returns `.ids` (caller order kept).
func resolveLibraryGrid(
  scope: ContainerScope,
  granularity: PhotosLocalStore.Granularity,
  sort: LibrarySort,
  filter: LibraryFilterItem,
  kinds: Set<LibraryMediaKind>,
  hideScreenshots: Bool,
  hideSharedWithYou: Bool,
  store: PhotosLocalStore,
  userId: String
) async throws -> ResolvedLibraryGrid {
  let isDefault =
    sort == .captured && filter == .all && kinds.isEmpty && !hideScreenshots
    && !hideSharedWithYou
  if isDefault {
    // Fast path: the loader pages the index itself. The count still needs one
    // query — the compact index (id/date/flags only), off-main here.
    let index = try await store.timelineIndex(scope: scope)
    return ResolvedLibraryGrid(
      source: .timeline(scope: scope, granularity: granularity), count: index.entries.count)
  }

  // Filtered path: one index fetch for flags/dates, plus row fetches only for the
  // dimensions the index lacks (owner for Captured-by-Me, mediaKind for panoramas,
  // createdAt order for Added sort).
  let index = try await store.timelineIndex(scope: scope)
  var flagsById: [String: PhotosLocalStore.TimelineIndexFlags] = [:]
  flagsById.reserveCapacity(index.entries.count)
  for entry in index.entries { flagsById[entry.id] = entry.flags }

  // Added sort fetches createdAt-ordered rows once and reuses them both for order
  // and for the owner/kind dimensions the index lacks.
  var addedRows: [TimelineRow] = []
  if sort == .added {
    addedRows = try await pageRows(scope: scope) {
      try await store.recentAssets(scope: $0, limit: $1, offset: $2)
    }
  }
  let needsRows = filter == .capturedByMe || kinds.contains(.panoramas)
  var rowsById: [String: TimelineRow] = [:]
  if sort == .added {
    rowsById.reserveCapacity(addedRows.count)
    for row in addedRows { rowsById[row.id] = row }
  } else if needsRows {
    let rows = try await store.timelineRows(scope: scope)
    rowsById.reserveCapacity(rows.count)
    for row in rows { rowsById[row.id] = row }
  }

  var albumIds: Set<String> = []
  if filter == .notInAlbum {
    albumIds = (try? await store.assetIdsInAnyAlbum(userId: userId)) ?? []
  }

  // Base order: Added sort follows createdAt desc (recentAssets page order);
  // otherwise the index's capture-date-desc order.
  let baseIds: [String] =
    sort == .added ? addedRows.map(\.id) : index.entries.map(\.id)

  var kept: [String] = []
  kept.reserveCapacity(baseIds.count)
  for id in baseIds {
    let flags = flagsById[id] ?? []
    if hideScreenshots && flags.contains(.screenshot) { continue }
    if hideSharedWithYou && flags.contains(.sharedContainer) { continue }
    if !kinds.isEmpty {
      let row = rowsById[id]
      let inKinds =
        (kinds.contains(.videos) && flags.contains(.video))
        || (kinds.contains(.livePhotos) && flags.contains(.livePhoto))
        || (kinds.contains(.screenshots) && flags.contains(.screenshot))
        || (kinds.contains(.panoramas) && row?.mediaKind == .panorama)
      if !inKinds { continue }
    }
    switch filter {
    case .all: break
    case .favorites:
      if !flags.contains(.favorite) { continue }
    case .edited:
      if !flags.contains(.edited) { continue }
    case .sharedWithYou:
      if !flags.contains(.sharedContainer) { continue }
    case .capturedByMe:
      if rowsById[id]?.ownerId != userId { continue }
    case .notInAlbum:
      if albumIds.contains(id) { continue }
    }
    kept.append(id)
  }
  return ResolvedLibraryGrid(source: .ids(kept), count: kept.count)
}

/// Pages a limit/offset store query until a short page. Page size 2000 keeps each
/// read small; cancellation aborts the loop (the caller's `.task(id:)` owns it).
private func pageRows(
  scope: ContainerScope,
  pageSize: Int = 2000,
  _ page: (
    _ scope: ContainerScope, _ limit: Int, _ offset: Int
  ) async throws -> [TimelineRow]
) async throws -> [TimelineRow] {
  var all: [TimelineRow] = []
  var offset = 0
  while true {
    try Task.checkCancellation()
    let rows = try await page(scope, pageSize, offset)
    all.append(contentsOf: rows)
    if rows.count < pageSize { return all }
    offset += rows.count
  }
}
