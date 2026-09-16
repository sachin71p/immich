import CoreModel
import Foundation
import LocalStore
import Rules
import Testing

/// A9 extras: clustering (A9.4), story player state (A9.3), extension snapshot (A9.5/A9.6),
/// and the memory store queries. Pure-logic tests run anywhere; store tests use the
/// in-memory database through the public `apply()` path (A4 precedent).
struct A9ExtrasTests {
  // MARK: - A9.4 clustering

  @Test func emptyInputClustersToNothing() {
    #expect(MapClusterer.cluster([], zoomLevel: 10).isEmpty)
  }

  @Test func distantPointsStaySeparate() {
    let items = [
      MapClusterItem(id: "sf", latitude: 37.7749, longitude: -122.4194),
      MapClusterItem(id: "nyc", latitude: 40.7128, longitude: -74.0060),
      MapClusterItem(id: "london", latitude: 51.5074, longitude: -0.1278),
    ]
    let clusters = MapClusterer.cluster(items, zoomLevel: 10)
    #expect(clusters.count == 3)
    #expect(clusters.allSatisfy { !$0.isCluster })
  }

  @Test func nearbyPointsClusterAtLowZoomAndSplitAtHighZoom() {
    let items = [
      MapClusterItem(id: "a", latitude: 37.7749, longitude: -122.4194),
      MapClusterItem(id: "b", latitude: 37.7750, longitude: -122.4195),
      MapClusterItem(id: "c", latitude: 37.7751, longitude: -122.4196),
    ]
    let coarse = MapClusterer.cluster(items, zoomLevel: 8)
    #expect(coarse.count == 1)
    #expect(coarse[0].isCluster)
    #expect(coarse[0].count == 3)
    let fine = MapClusterer.cluster(items, zoomLevel: 21)
    #expect(fine.count == 3)
  }

  @Test func clusterIdIsStableAcrossReloads() {
    let items = [
      MapClusterItem(id: "b", latitude: 37.7750, longitude: -122.4195),
      MapClusterItem(id: "a", latitude: 37.7749, longitude: -122.4194),
    ]
    let first = MapClusterer.cluster(items, zoomLevel: 8)[0].id
    let second = MapClusterer.cluster(items.reversed(), zoomLevel: 8)[0].id
    #expect(first == second)
    #expect(first == "a,b")
  }

  // MARK: - A9.3 story player

  @Test func playerAdvancesAndReportsFinish() {
    var player = MemoryStoryPlayer(
      story: MemoryStory(memoryId: "m", title: "Trip", memoryAt: Date(), assetIds: ["a", "b"]))
    #expect(player.musicEnabled == false)
    #expect(player.currentAssetId == "a")
    #expect(player.advance() == true)
    #expect(player.currentAssetId == "b")
    #expect(player.advance() == false)
    player.restart()
    #expect(player.currentAssetId == "a")
  }

  @Test func emptyStoryHasZeroProgress() {
    let player = MemoryStoryPlayer(
      story: MemoryStory(memoryId: "m", title: "Trip", memoryAt: Date(), assetIds: []))
    #expect(player.currentAssetId == nil)
    #expect(player.progress == 0)
  }

  // MARK: - A9.5/A9.6 snapshot

  @Test func snapshotRoundTripsThroughJSON() throws {
    let snapshot = ExtensionSnapshot(
      favoritesCount: 3,
      locatedCount: 12,
      favoriteThumbnailFileNames: ["fav-0.jpg"],
      memory: ExtensionSnapshot.MemorySummary(title: "Trip", memoryAt: Date()),
      libraries: [
        ExtensionSnapshot.LibraryOption(id: "personal", name: "Personal"),
        ExtensionSnapshot.LibraryOption(id: "space:s1", name: "Family"),
      ])
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(ExtensionSnapshot.self, from: data)
    #expect(decoded == snapshot)
    #expect(decoded.spaceId(forDestination: "space:s1") == "s1")
    #expect(decoded.spaceId(forDestination: "personal") == nil)
    #expect(decoded.spaceId(forDestination: nil) == nil)
  }

  // MARK: - A9.3 store queries

  private static func seed(into store: PhotosLocalStore) async throws {
    let alice = "user-alice"
    let calendar = Calendar(identifier: .gregorian)
    let now = Date()
    let month = calendar.component(.month, from: now)
    let day = calendar.component(.day, from: now)
    var thisYear = calendar.dateComponents([.year], from: now)
    func date(year: Int) -> Date {
      thisYear.year = year
      thisYear.month = month
      thisYear.day = day
      thisYear.hour = 12
      return calendar.date(from: thisYear) ?? now
    }
    let changes: [SyncChange] = [
      .user(User(id: alice, name: "Alice", email: "alice@example.com")),
      .asset(Asset(
        id: "a-then", ownerId: alice, originalFileName: "IMG_1.HEIC", checksum: "c1",
        localDateTime: date(year: 2021), type: .image)),
      .asset(Asset(
        id: "a-now", ownerId: alice, originalFileName: "IMG_2.HEIC", checksum: "c2",
        localDateTime: date(year: 2024), type: .image)),
      .asset(Asset(
        id: "a-other", ownerId: alice, originalFileName: "IMG_3.HEIC", checksum: "c3",
        localDateTime: Date(timeIntervalSince1970: 0),
        type: .image)),
      .memory(Memory(
        id: "m-trip", createdAt: now, updatedAt: now, ownerId: alice, type: "trip",
        dataJSON: "{}", isSaved: true, memoryAt: date(year: 2021))),
      .memoryAsset(memoryId: "m-trip", assetId: "a-then"),
      .memoryAsset(memoryId: "m-trip", assetId: "a-now"),
    ]
    try await store.apply(changes, currentUserId: alice)
  }

  @Test func memoryAssetIdsFollowLinkOrder() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let ids = try await store.assetIds(forMemory: "m-trip")
    #expect(Set(ids) == ["a-then", "a-now"])
    #expect(try await store.assetIds(forMemory: "m-missing").isEmpty)
  }

  @Test func onThisDayFindsSameMonthDayAcrossYears() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let ctx = try await store.timelineContext(for: "user-alice")
    let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
    let calendar = Calendar(identifier: .gregorian)
    let now = Date()
    let rows = try await store.onThisDayAssets(
      scope: scope,
      month: calendar.component(.month, from: now),
      day: calendar.component(.day, from: now))
    #expect(Set(rows.map(\.id)) == ["a-then", "a-now"])
  }
}
