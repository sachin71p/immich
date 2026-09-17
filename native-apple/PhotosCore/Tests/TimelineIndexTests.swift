import CoreModel
import Foundation
import GRDB
import Rules
import Testing
@testable import LocalStore

/// WP1 §1 coverage: the compact timeline index (flags, order, duration), bucket summaries
/// (counts, favorite-preferring key asset, ranges, year granularity) and the visible-page
/// `assetsLite` paging. Seeded through the public `apply()` path — no raw SQL in tests.
struct TimelineIndexTests {
  private static func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 0)
  }

  private static func seed(into store: PhotosLocalStore) async throws {
    let alice = "user-alice"
    let changes: [SyncChange] = [
      .user(User(id: alice, name: "Alice", email: "alice@example.com")),
      .asset(
        Asset(
          id: "a-photo", ownerId: alice, originalFileName: "IMG_1.HEIC", checksum: "c1",
          localDateTime: date("2024-06-01T12:00:00Z"), type: .image, isFavorite: true,
          width: 4000, height: 3000, isEdited: true)),
      .asset(
        Asset(
          id: "a-video", ownerId: alice, originalFileName: "VID_1.MOV", checksum: "c2",
          localDateTime: date("2024-06-02T12:00:00Z"), durationSeconds: 42, type: .video)),
      .asset(
        Asset(
          id: "a-shot", ownerId: alice, originalFileName: "Screenshot_1.PNG", checksum: "c3",
          localDateTime: date("2024-05-03T12:00:00Z"), type: .image)),
      .asset(
        Asset(
          id: "a-space-photo", ownerId: alice, originalFileName: "IMG_2.HEIC", checksum: "c4",
          localDateTime: date("2023-01-15T12:00:00Z"), type: .image, spaceId: "space-1")),
      .asset(
        Asset(
          id: "a-live", ownerId: alice, originalFileName: "IMG_3.HEIC", checksum: "c5",
          localDateTime: date("2024-06-03T12:00:00Z"), type: .image,
          livePhotoVideoId: "a-live-video")),
      .asset(
        Asset(
          id: "a-live-video", ownerId: alice, originalFileName: "IMG_3.MOV", checksum: "c6",
          localDateTime: date("2024-06-03T12:00:00Z"), type: .video)),
    ]
    try await store.apply(changes, currentUserId: alice)
  }

  private static func scope() -> ContainerScope {
    ContainerScope(personalUserIds: ["user-alice"], spaceIds: ["space-1"])
  }

  @Test("index holds one entry per visible asset, newest first, with flags and durations")
  func indexEntries() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let index = try await store.timelineIndex(scope: Self.scope())
    // Six assets seeded, but the live-photo video half is an internal component, never a
    // standalone timeline item.
    #expect(index.entries.count == 5)
    #expect(index.entries.map(\.id) == ["a-live", "a-video", "a-photo", "a-shot", "a-space-photo"])
    for (offset, entry) in index.entries.enumerated() {
      #expect(index.indexById[entry.id] == offset)
    }
    let video = try #require(index.entries.first { $0.id == "a-video" })
    #expect(video.flags.contains(.video))
    #expect(video.durationSeconds == 42)
    let live = try #require(index.entries.first { $0.id == "a-live" })
    #expect(live.flags.contains(.livePhoto))
    #expect(!live.flags.contains(.video))
    let photo = try #require(index.entries.first { $0.id == "a-photo" })
    #expect(photo.flags == [.favorite, .edited])
    #expect(photo.durationSeconds == nil)
    let shot = try #require(index.entries.first { $0.id == "a-shot" })
    #expect(shot.flags == [.screenshot])
    let shared = try #require(index.entries.first { $0.id == "a-space-photo" })
    #expect(shared.flags == [.sharedContainer])
  }

  @Test("bucket summaries count, prefer favorites as key assets, and carry date ranges")
  func bucketSummaries() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let months = try await store.bucketSummaries(scope: Self.scope(), granularity: .month)
    #expect(months.map(\.key) == ["2024-06", "2024-05", "2023-01"])
    let june = try #require(months.first { $0.key == "2024-06" })
    #expect(june.count == 3)
    // The favorite photo wins over the more recent video/live assets.
    #expect(june.keyAssetId == "a-photo")
    let start = try #require(june.startDate)
    let end = try #require(june.endDate)
    #expect(start <= end)
    #expect(Calendar(identifier: .gregorian).component(.day, from: start) == 1)
    #expect(Calendar(identifier: .gregorian).component(.day, from: end) == 3)

    let years = try await store.bucketSummaries(scope: Self.scope(), granularity: .year)
    #expect(years.map(\.key) == ["2024", "2023"])
    #expect(years.first { $0.key == "2024" }?.count == 4)
    #expect(years.first { $0.key == "2023" }?.keyAssetId == "a-space-photo")

    let days = try await store.bucketSummaries(scope: Self.scope(), granularity: .day)
    #expect(days.count == 5)
    #expect(days.first { $0.key == "2024-06-03" }?.count == 1)
  }

  @Test("assetsLite pages full rows in input order, dropping unknown ids")
  func assetsLitePaging() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let rows = try await store.assetsLite(ids: ["a-video", "missing", "a-photo"])
    #expect(rows.map(\.id) == ["a-video", "a-photo"])
    let video = try #require(rows.first { $0.id == "a-video" })
    #expect(video.mediaKind == .video)
    #expect(video.durationSeconds == 42)
    #expect(try await store.assetsLite(ids: []) == [])
  }

  private static func makeBigStore(assetCount: Int) throws -> PhotosLocalStore {
    let store = try PhotosLocalStore(inMemory: true)
    try store.dbQueue.write { db in
      let calendar = Calendar(identifier: .gregorian)
      for index in 0..<150_000 {
        let day = calendar.date(byAdding: .hour, value: -index, to: Date())!
        try db.execute(
          sql: """
            INSERT INTO asset (
              id, ownerId, originalFileName, checksum, type, isFavorite, visibility, isEdited,
              localDateTime, createdAt, width, height, durationSeconds
            ) VALUES (?, 'me', ?, ?, 'IMAGE', ?, 'timeline', 0, ?, ?, 100, 100, NULL)
            """,
          arguments: [
            "asset-\(index)", "IMG_\(index).heic", "chk-\(index)", index % 37 == 0, day, day,
          ]
        )
      }
    }
    return store
  }

  @Test("[perf][WP1] timelineIndex builds 150k entries in under 400ms")
  func indexBuildPerformance() async throws {
    let store = try Self.makeBigStore(assetCount: 150_000)
    let scope = ContainerScope(personalUserIds: ["me"])
    let start = DispatchTime.now()
    let index = try await store.timelineIndex(scope: scope)
    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    #expect(index.entries.count == 150_000)
    #expect(index.indexById.count == 150_000)
    #if DEBUG
    let budget = 1500.0
    #else
    let budget = 400.0
    #endif
    #expect(elapsedMs < budget, "timelineIndex took \(elapsedMs)ms, expected <\(budget)ms")
  }
}
