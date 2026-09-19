import CoreModel
import Foundation
import LocalStore
import SwiftUI

// MARK: - collections loader (WP4 §1)

/// Staged, shells-first loading for Collections (P9: never hydrate full row arrays to
/// show counts). The view paints section shells immediately from nil state; each stage
/// publishes incrementally off the main-actor hot path (all store work is `await`ed on
/// the GRDB reader, `@Published` sets are the only main-actor work).
@MainActor
final class CollectionsLoader: ObservableObject {
  @Published var counts: CollectionsCounts?
  @Published var albums: [AlbumTileData]?
  @Published var people: [PersonTileData]?
  @Published var stories: [MemoryStory]?
  @Published var days: [DayTileData]?
  @Published var cameras: [CameraModel]?
  @Published var onThisDayIds: [String]?
  @Published var favoriteCoverId: String?
  @Published var recentCoverId: String?

  /// Wall time of the counts stage (the "all counts" half of the perf budget).
  var countsMs: Double = 0

  func reload(session: AppSession) async {
    guard let store = session.store, !session.userId.isEmpty else { return }
    do {
      let scope = try await session.timelineScope()
      let manage = try await session.manageScope()

      // Stage 1 (counts budget): scalars only, one cheap query each.
      let start = Date()
      var filled = CollectionsCounts()
      async let favorites = store.favoriteCount(scope: scope)
      async let recents = store.recentCount(scope: scope)
      async let trash = store.trashCount(scope: manage)
      async let hidden = store.hiddenCount(scope: manage)
      async let archived = store.archiveCount(scope: manage)
      async let locked = store.lockedCount(userId: session.userId)
      async let captured = store.capturedByMeCount(userId: session.userId, scope: manage)
      async let located = store.locatedCount(scope: scope)
      filled.favorites = (try? await favorites) ?? 0
      filled.recents = (try? await recents) ?? 0
      filled.trash = (try? await trash) ?? 0
      filled.hidden = (try? await hidden) ?? 0
      filled.archived = (try? await archived) ?? 0
      filled.locked = (try? await locked) ?? 0
      filled.capturedByMe = (try? await captured) ?? 0
      filled.located = (try? await located) ?? 0
      var media: [NativeMediaCollection: Int] = [:]
      for collection in NativeMediaCollection.allCases {
        media[collection] = (try? await store.nativeCollectionCount(scope: scope, collection: collection)) ?? 0
      }
      filled.media = media
      countsMs = Date().timeIntervalSince(start) * 1000
      counts = filled
      favoriteCoverId = try? await store.favoriteAssets(scope: scope, limit: 1).first?.id
      recentCoverId = try? await store.recentAssets(scope: scope, limit: 1).first?.id

      // Stage 2: albums with member lists, cover + count per album.
      let allAlbums = (try? await store.albumsForUser(session.userId)) ?? []
      var tiles: [AlbumTileData] = []
      tiles.reserveCapacity(allAlbums.count)
      for album in allAlbums {
        let members = (try? await store.membersOfAlbum(album.id)) ?? []
        let cover = try? await store.albumAssets(albumId: album.id, limit: 1)
        let count = (try? await store.albumAssetCount(album.id)) ?? 0
        tiles.append(AlbumTileData(
          album: album, memberCount: members.count,
          coverId: cover?.first?.id, assetCount: count))
      }
      albums = tiles

      // Stage 3: people — one GROUP BY (`peopleSummaries`), C1a rule applied here:
      // hide people who are unnamed AND have zero assets. Face-asset ids come from
      // the person rows for the thumbnail fallback chain.
      let summaries = (try? await store.peopleSummaries(userId: session.userId)) ?? []
      let persons = (try? await store.peopleForOwner(session.userId)) ?? []
      let faces = Dictionary(uniqueKeysWithValues: persons.map { ($0.id, $0.faceAssetId) })
      people = summaries
        .filter { !($0.name.isEmpty && $0.assetCount == 0) }
        .map { PersonTileData(summary: $0, faceAssetId: faces[$0.id] ?? nil) }

      // Stage 4: memories stories (carousel) + on-this-day ids (card grid).
      let memories = (try? await store.savedMemories(forOwner: session.userId)) ?? []
      var built: [MemoryStory] = []
      for memory in memories {
        let ids = (try? await store.assetIds(forMemory: memory.id)) ?? []
        guard !ids.isEmpty else { continue }
        built.append(MemoryStory(
          memoryId: memory.id, title: MemoryStory.title(for: memory),
          memoryAt: memory.memoryAt, assetIds: ids))
      }
      stories = built
      let now = Date()
      let calendar = Calendar.current
      onThisDayIds = (try? await store.onThisDayAssets(
        scope: scope,
        month: calendar.component(.month, from: now),
        day: calendar.component(.day, from: now)).map(\.id)) ?? []

      // Stage 5: recent days (covers + counts) and camera models.
      let buckets = (try? await store.bucketSummaries(scope: scope, granularity: .day)) ?? []
      days = Array(buckets.prefix(7)).map { bucket in
        DayTileData(key: bucket.key, count: bucket.count, keyAssetId: bucket.keyAssetId)
      }
      cameras = (try? await store.cameraModels(scope: manage)) ?? []
    } catch {
      // L2: cancellation is never a user-facing error.
      if !error.isCancellation { session.lastError = error.localizedDescription }
    }
  }
}

// MARK: - tile models (small values for the section views)

/// Scalar counts only — no row arrays (P9).
struct CollectionsCounts {
  var favorites = 0
  var recents = 0
  var trash = 0
  var hidden = 0
  var archived = 0
  var locked = 0
  var capturedByMe = 0
  var located = 0
  var media: [NativeMediaCollection: Int] = [:]
}

struct AlbumTileData: Identifiable {
  var album: Album
  /// Shared albums have more than one member (DECISIONS §4 R11).
  var memberCount: Int
  var coverId: String?
  var assetCount: Int
  var id: String { album.id }
  var isShared: Bool { memberCount > 1 }
}

struct PersonTileData: Identifiable {
  var summary: PersonSummary
  /// Cover fallback when the person-thumbnail endpoint has nothing (fixture mode).
  var faceAssetId: String?
  var id: String { summary.id }
}

struct DayTileData: Identifiable {
  /// `yyyy-MM-dd` bucket key.
  var key: String
  var count: Int
  var keyAssetId: String
  var id: String { key }

  private static let keyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let labelFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE"
    return formatter
  }()

  /// "Monday" etc.; falls back to the key when parsing fails (never crashes tiles).
  var label: String {
    guard let date = Self.keyFormatter.date(from: key) else { return key }
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    return Self.labelFormatter.string(from: date)
  }
}

// MARK: - section order / collapse persistence

enum CollectionsSection: String, CaseIterable, Identifiable {
  case memories, pinned, albums, people, sharedAlbums, spaces, recentDays, mediaTypes, utilities, places,
    trips, wallpaper
  var id: String { rawValue }
  var title: String {
    switch self {
    case .memories: return "Memories"
    case .pinned: return "Pinned"
    case .albums: return "Albums"
    case .people: return "People"
    case .sharedAlbums: return "Shared Albums"
    case .spaces: return "Shared Libraries"
    case .recentDays: return "Recent Days"
    case .mediaTypes: return "Media Types"
    case .utilities: return "Utilities"
    case .places: return "Places"
    case .trips: return "Trips"
    case .wallpaper: return "Wallpaper Suggestions"
    }
  }
}

enum CollectionsPrefs {
  // Computed over UserDefaults (stored statics trip Swift 6 concurrency errors).
  static var sectionOrder: String {
    get { UserDefaults.standard.string(forKey: "heirloom.collections.sectionOrder") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "heirloom.collections.sectionOrder") }
  }
  static var collapsed: String {
    get { UserDefaults.standard.string(forKey: "heirloom.collections.collapsed") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "heirloom.collections.collapsed") }
  }
  static var pinnedOrder: String {
    get { UserDefaults.standard.string(forKey: "heirloom.collections.pinnedOrder") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "heirloom.collections.pinnedOrder") }
  }

  static func orderedSections() -> [CollectionsSection] {
    let ids = sectionOrder.split(separator: ",").map(String.init)
    let known = ids.compactMap(CollectionsSection.init(rawValue:))
    let missing = CollectionsSection.allCases.filter { !known.contains($0) }
    return known + missing
  }

  static func isCollapsed(_ section: CollectionsSection) -> Bool {
    collapsed.split(separator: ",").map(String.init).contains(section.rawValue)
  }

  static func setCollapsed(_ section: CollectionsSection, collapsed: Bool) {
    var ids = Set(self.collapsed.split(separator: ",").map(String.init))
    if collapsed { ids.insert(section.rawValue) } else { ids.remove(section.rawValue) }
    self.collapsed = ids.sorted().joined(separator: ",")
  }
}

enum PinnedItem: String, CaseIterable, Identifiable {
  case favorites, recents, map
  var id: String { rawValue }
  var title: String {
    switch self {
    case .favorites: return "Favorites"
    case .recents: return "Recently Saved"
    case .map: return "Map"
    }
  }

  static func ordered() -> [PinnedItem] {
    let ids = CollectionsPrefs.pinnedOrder.split(separator: ",").map(String.init)
    let known = ids.compactMap(PinnedItem.init(rawValue:))
    return known + PinnedItem.allCases.filter { !known.contains($0) }
  }
}
