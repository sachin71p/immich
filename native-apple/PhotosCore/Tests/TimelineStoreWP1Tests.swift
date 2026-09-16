import CoreModel
import Foundation
import LocalStore
import Rules
import Testing

/// WP1 §1 coverage: row fields, the SQL media-kind filter, single-transaction timeline
/// loads, album-asset ids, map points, and people summaries. Seeded through the public
/// `apply()` path like `LibraryListsTests` — no raw SQL in tests.
struct TimelineStoreWP1Tests {
  private static func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 0)
  }

  private static func seed(into store: PhotosLocalStore) async throws {
    let alice = "user-alice"
    let changes: [SyncChange] = [
      .user(User(id: alice, name: "Alice", email: "alice@example.com")),
      .album(
        Album(
          id: "album-trip", name: "Trip", description: "",
          createdAt: date("2024-05-01T00:00:00Z"), updatedAt: date("2024-05-01T00:00:00Z"))),
      .albumUser(AlbumMember(albumId: "album-trip", userId: alice, role: .editor)),
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
      .assetExif(AssetExif(assetId: "a-photo", latitude: 37.7749, longitude: -122.4194)),
      .albumAsset(albumId: "album-trip", assetId: "a-photo"),
      .albumAsset(albumId: "album-trip", assetId: "a-video"),
      .person(
        Person(
          id: "person-ada", createdAt: date("2024-01-01T00:00:00Z"),
          updatedAt: date("2024-01-01T00:00:00Z"), ownerId: alice, name: "Ada")),
      .person(
        Person(
          id: "person-unnamed", createdAt: date("2024-01-01T00:00:00Z"),
          updatedAt: date("2024-01-01T00:00:00Z"), ownerId: alice, name: "")),
      .face(
        Face(
          id: "face-1", assetId: "a-photo", personId: "person-ada", imageWidth: 100,
          imageHeight: 100, boundingBoxX1: 0, boundingBoxY1: 0, boundingBoxX2: 10,
          boundingBoxY2: 10, sourceType: "machine")),
      .face(
        Face(
          id: "face-2", assetId: "a-video", personId: "person-ada", imageWidth: 100,
          imageHeight: 100, boundingBoxX1: 0, boundingBoxY1: 0, boundingBoxX2: 10,
          boundingBoxY2: 10, sourceType: "machine")),
      .face(
        Face(
          id: "face-3", assetId: "a-shot", personId: "person-unnamed", imageWidth: 100,
          imageHeight: 100, boundingBoxX1: 0, boundingBoxY1: 0, boundingBoxX2: 10,
          boundingBoxY2: 10, sourceType: "machine")),
    ]
    try await store.apply(changes, currentUserId: alice)
  }

  private static func scope() -> ContainerScope {
    ContainerScope(personalUserIds: ["user-alice"])
  }

  @Test("rows carry ownerId/isEdited/durationSeconds from SQL and init(asset:)")
  func rowFields() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let rows = try await store.timelineRows(scope: Self.scope())
    let photo = try #require(rows.first { $0.id == "a-photo" })
    #expect(photo.ownerId == "user-alice")
    #expect(photo.isEdited)
    #expect(photo.durationSeconds == nil)
    #expect(photo.isFavorite)
    // The julianday fast path round-trips capture times (tolerance 1s for jd precision).
    #expect(
      abs(photo.localDateTime?.timeIntervalSince(Self.date("2024-06-01T12:00:00Z")) ?? 99) < 1)
    let video = try #require(rows.first { $0.id == "a-video" })
    #expect(video.durationSeconds == 42)
    #expect(!video.isEdited)
    // `init(asset:)` agrees with the SQL projection.
    let direct = TimelineRow(
      asset: Asset(
        id: "x", ownerId: "u", originalFileName: "IMG.HEIC", checksum: "c",
        localDateTime: Self.date("2024-06-01T12:00:00Z"), durationSeconds: 7, type: .image,
        isEdited: true))
    #expect(direct.ownerId == "u")
    #expect(direct.isEdited)
    #expect(direct.durationSeconds == 7)
  }

  @Test("SQL kind filter agrees with the projection classifier")
  func sqlKindFilter() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let scope = Self.scope()
    let videos = try await store.assets(scope: scope, mediaKind: .video)
    #expect(videos.map(\.id) == ["a-video"])
    let screenshots = try await store.assets(scope: scope, mediaKind: .screenshot)
    #expect(screenshots.map(\.id) == ["a-shot"])
    // Every SQL-filtered kind matches filtering the full load client-side.
    let all = try await store.timelineRows(scope: scope)
    for kind in [TimelineMediaKind.photo, .video, .screenshot] {
      let viaSQL = try await store.assets(scope: scope, mediaKind: kind)
      #expect(viaSQL.map(\.id) == all.filter { $0.mediaKind == kind }.map(\.id))
    }
  }

  @Test("timelineRows loads the whole timeline in one transaction, newest first")
  func wholeTimeline() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let scope = Self.scope()
    let rows = try await store.timelineRows(scope: scope)
    #expect(rows.map(\.id) == ["a-video", "a-photo", "a-shot"])
    // Bucket-restricted loads agree with the bucket pages.
    let buckets = try await store.timelineBuckets(scope: scope)
    #expect(buckets.count == 2)
    let june = try await store.timelineRows(
      scope: scope, bucketKeys: ["2024-06"], granularity: .month)
    #expect(june.map(\.id) == ["a-video", "a-photo"])
    #expect(try await store.timelineRows(scope: scope, bucketKeys: [], granularity: .month).isEmpty)
  }

  @Test("assetIdsInAnyAlbum returns visible album members in one query")
  func albumAssetIds() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    #expect(try await store.assetIdsInAnyAlbum(userId: "user-alice") == ["a-photo", "a-video"])
    #expect(try await store.assetIdsInAnyAlbum(userId: "user-nobody").isEmpty)
  }

  @Test("locatedAssetPoints returns every pin with its date, no limit")
  func mapPoints() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let points = try await store.locatedAssetPoints(scope: Self.scope())
    #expect(points.count == 1)
    #expect(points.first?.id == "a-photo")
    #expect(points.first?.localDateTime == Self.date("2024-06-01T12:00:00Z"))
  }

  @Test("peopleSummaries counts visible faces, named first, count desc")
  func people() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let summaries = try await store.peopleSummaries(userId: "user-alice")
    #expect(summaries.count == 2)
    #expect(summaries[0].id == "person-ada")
    #expect(summaries[0].assetCount == 2)
    #expect(summaries[1].id == "person-unnamed")
    #expect(summaries[1].assetCount == 1)
    #expect(try await store.peopleSummaries(userId: "user-nobody").isEmpty)
  }
}
