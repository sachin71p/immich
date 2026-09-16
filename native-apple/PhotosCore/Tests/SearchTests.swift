import CoreModel
import Foundation
import LocalStore
import Rules
import Search
import Testing

/// A7 coverage: filter-DSL round-trip, local query correctness on a seeded mirror, and the
/// pure server param mapping. Seeded programmatically through the public `apply()` path.
struct SearchTests {
  private static func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 0)
  }

  private static func seed() async throws -> PhotosLocalStore {
    let store = try PhotosLocalStore(inMemory: true)
    let alice = "user-alice"
    let changes: [SyncChange] = [
      .user(User(id: alice, name: "Alice", email: "alice@example.com")),
      .asset(
        Asset(
          id: "a-canon", ownerId: alice, originalFileName: "IMG_1.JPG", checksum: "c1",
          localDateTime: Self.date("2024-06-01T12:00:00Z"), type: .image, isFavorite: true,
          width: 6000, height: 4000)),
      .assetExif(
        AssetExif(
          assetId: "a-canon", fileSizeInByte: 8_000_000, latitude: 37.7749, longitude: -122.4194,
          city: "San Francisco", country: "USA", make: "Canon", model: "EOS R5",
          lensModel: "RF 24-70mm", fNumber: 2.8, focalLength: 35, iso: 400,
          exposureTime: "1/125", rating: 5)),
      .asset(
        Asset(
          id: "a-nikon", ownerId: alice, originalFileName: "DSC_2.NEF", checksum: "c2",
          localDateTime: Self.date("2024-06-02T12:00:00Z"), type: .image, width: 4000, height: 3000)),
      .assetExif(
        AssetExif(
          assetId: "a-nikon", fileSizeInByte: 20_000_000, make: "Nikon", model: "Z8",
          fNumber: 8, focalLength: 200, iso: 3200, exposureTime: "0.02")),
      .asset(
        Asset(
          id: "a-video", ownerId: alice, originalFileName: "VID_1.MOV", checksum: "c3",
          localDateTime: Self.date("2024-06-03T12:00:00Z"), type: .video,
          width: 3840, height: 2160)),
      .assetExif(AssetExif(assetId: "a-video", fileSizeInByte: 100_000_000, fps: 60)),
      .person(
        Person(
          id: "person-ada", createdAt: Self.date("2024-01-01T00:00:00Z"),
          updatedAt: Self.date("2024-01-01T00:00:00Z"), ownerId: alice, name: "Ada")),
      .face(
        Face(
          id: "face-1", assetId: "a-canon", personId: "person-ada", imageWidth: 6000,
          imageHeight: 4000, boundingBoxX1: 0, boundingBoxY1: 0, boundingBoxX2: 100,
          boundingBoxY2: 100, sourceType: "machine")),
    ]
    try await store.apply(changes, currentUserId: alice)
    return store
  }

  private static let scope = ContainerScope(personalUserIds: ["user-alice"])

  private static func ids(_ rows: [TimelineRow]) -> [String] { rows.map(\.id).sorted() }

  // MARK: - DSL round-trip (A7 task 4)

  @Test func dslRoundTrip() throws {
    let filter = SearchFilter(
      query: "sunset beach",
      local: LocalAssetFilter(
        make: "Canon", model: "EOS R5", lensModel: "RF 24-70mm", city: "San Francisco",
        country: "USA", isoMin: 100, isoMax: 800, fNumberMin: 1.8, fNumberMax: 4,
        focalLengthMin: 24, focalLengthMax: 70, exposureTimeMin: 0.001, exposureTimeMax: 0.01,
        fileSizeMin: 1000, fileSizeMax: 10_000_000, widthMin: 3000, heightMin: 2000,
        fileExtensions: ["jpg"], mimeTypes: ["image/jpeg"], projectionType: "equirectangular",
        hasLocation: true, fpsMin: 24, fpsMax: 60, rating: 5, mediaType: .image,
        isFavorite: true, takenAfter: Self.date("2024-01-01T00:00:00Z"),
        takenBefore: Self.date("2024-12-31T00:00:00Z"), personIds: ["person-ada"]),
      scope: .space("space-1"),
      tagIds: ["tag-1"])
    let parsed = try #require(SearchFilter(serialized: filter.serialized))
    #expect(parsed == filter)
  }

  @Test func dslEmptyAndDefaults() throws {
    #expect(SearchFilter(serialized: "") == nil)
    #expect(SearchFilter().serialized.isEmpty)
    #expect(SearchFilter().scope == .all)
    #expect(SearchFilter(query: "x").wantsServerSearch)
    #expect(!SearchFilter().wantsServerSearch)
    #expect(SearchFilter(local: LocalAssetFilter(make: "Canon")).wantsServerSearch == false)
  }

  @Test func scopeServerParameters() {
    let (spaceId, libraryId, personal) = SearchScope.space("s").serverScopeParameters()
    #expect(spaceId == "s" && libraryId == nil && !personal)
    let personalParams = SearchScope.personal.serverScopeParameters()
    #expect(personalParams.personalOnly && personalParams.spaceId == nil)
    let allParams = SearchScope.all.serverScopeParameters()
    #expect(!allParams.personalOnly && allParams.spaceId == nil && allParams.libraryId == nil)
  }

  // MARK: - local query correctness (A7 task 3)

  @Test func localCameraAndRanges() async throws {
    let store = try await Self.seed()
    #expect(Self.ids(try await store.filterAssets(LocalAssetFilter(make: "Canon"), scope: Self.scope)) == ["a-canon"])
    #expect(
      Self.ids(try await store.filterAssets(LocalAssetFilter(isoMin: 100, isoMax: 800), scope: Self.scope))
        == ["a-canon"])
    #expect(
      Self.ids(
        try await store.filterAssets(
          LocalAssetFilter(fNumberMin: 2, fNumberMax: 3, focalLengthMin: 30, focalLengthMax: 40),
          scope: Self.scope)) == ["a-canon"])
    #expect(
      Self.ids(try await store.filterAssets(LocalAssetFilter(lensModel: "RF 24-70mm"), scope: Self.scope))
        == ["a-canon"])
  }

  @Test func localExposureFraction() async throws {
    let store = try await Self.seed()
    // 1/125s = 0.008s; the fraction text must compare as seconds, not lexicographically.
    #expect(
      Self.ids(
        try await store.filterAssets(
          LocalAssetFilter(exposureTimeMin: 0.007, exposureTimeMax: 0.009), scope: Self.scope))
        == ["a-canon"])
    #expect(
      Self.ids(
        try await store.filterAssets(
          LocalAssetFilter(exposureTimeMin: 0.015, exposureTimeMax: 0.025), scope: Self.scope))
        == ["a-nikon"])
  }

  @Test func localLocationFavoriteTypeAndSize() async throws {
    let store = try await Self.seed()
    #expect(
      Self.ids(try await store.filterAssets(LocalAssetFilter(hasLocation: true), scope: Self.scope))
        == ["a-canon"])
    #expect(
      Self.ids(try await store.filterAssets(LocalAssetFilter(hasLocation: false), scope: Self.scope))
        == ["a-nikon", "a-video"])
    #expect(
      Self.ids(try await store.filterAssets(LocalAssetFilter(isFavorite: true), scope: Self.scope))
        == ["a-canon"])
    #expect(
      Self.ids(try await store.filterAssets(LocalAssetFilter(mediaType: .video), scope: Self.scope))
        == ["a-video"])
    #expect(
      Self.ids(try await store.filterAssets(LocalAssetFilter(fileExtensions: ["mov"]), scope: Self.scope))
        == ["a-video"])
    #expect(
      Self.ids(try await store.filterAssets(LocalAssetFilter(mimeTypes: ["image/jpeg"]), scope: Self.scope))
        == ["a-canon"])
    #expect(
      Self.ids(
        try await store.filterAssets(
          LocalAssetFilter(fileSizeMin: 50_000_000, widthMin: 1000), scope: Self.scope)) == ["a-video"])
    #expect(
      Self.ids(try await store.filterAssets(LocalAssetFilter(fpsMin: 30), scope: Self.scope)) == ["a-video"])
    #expect(Self.ids(try await store.filterAssets(LocalAssetFilter(rating: 5), scope: Self.scope)) == ["a-canon"])
    #expect(
      Self.ids(try await store.filterAssets(LocalAssetFilter(city: "San Francisco"), scope: Self.scope))
        == ["a-canon"])
    #expect(
      Self.ids(try await store.filterAssets(LocalAssetFilter(personIds: ["person-ada"]), scope: Self.scope))
        == ["a-canon"])
  }

  @Test func localScopeAndDates() async throws {
    let store = try await Self.seed()
    let empty = ContainerScope(personalUserIds: ["user-nobody"])
    #expect(try await store.filterAssets(LocalAssetFilter(), scope: empty).isEmpty)
    #expect(
      Self.ids(
        try await store.filterAssets(
          LocalAssetFilter(
            takenAfter: Self.date("2024-06-02T00:00:00Z"), takenBefore: Self.date("2024-06-02T23:59:59Z")),
          scope: Self.scope)) == ["a-nikon"])
  }

  // MARK: - server param mapping (A7 task 2)

  @Test func metadataBodyMapping() {
    let filter = SearchFilter(
      local: LocalAssetFilter(
        make: "Canon", isoMin: 100, isoMax: 800, fileExtensions: ["jpg"], hasLocation: true,
        mediaType: .image, personIds: ["p1"]),
      scope: .space("space-1"),
      tagIds: ["t1"])
    let body = filter.metadataBody()
    #expect(body["spaceId"] as? String == "space-1")
    #expect(body["libraryId"] == nil)
    #expect(body["personalOnly"] == nil)
    #expect(body["make"] as? String == "Canon")
    #expect(body["isoMin"] as? Int == 100)
    #expect(body["isoMax"] as? Int == 800)
    #expect(body["hasLocation"] as? Bool == true)
    #expect(body["type"] as? String == "IMAGE")
    #expect(body["fileExtensions"] as? [String] == ["jpg"])
    #expect((body["personIds"] as? [String]) == ["p1"])
    #expect((body["tagIds"] as? [String]) == ["t1"])
    #expect(body["withExif"] as? Bool == true)
    // Unset fields are omitted, never null.
    #expect(body["model"] == nil)
    #expect(body["fNumberMin"] == nil)
  }

  @Test func smartBodyMapping() {
    let filter = SearchFilter(query: "dog", scope: .personal)
    let body = filter.smartBody()
    #expect(body["query"] as? String == "dog")
    #expect(body["personalOnly"] as? Bool == true)
    #expect(body["isoMin"] == nil)
  }

  // MARK: - full-exif model

  @Test func fullExifDecodeAndMatch() throws {
    let json = """
      {"groups":{"EXIF":{"Make":"Canon","ISO":400,"BinaryBlob":{"binary":1,"bytes":12}},"File":{"FileName":"IMG_1.JPG"}}}
      """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(FullExifResponseForTest.self, from: json)
    let exif = FullExif(groups: decoded.groups)
    #expect(exif.groupNames == ["EXIF", "File"])
    #expect(exif.matching("canon").count == 1)
    #expect(exif.matching("binary").first?.value.displayText == "Binary data (12 bytes)")
    #expect(exif.matching("no-such-tag").isEmpty)
  }

  // MARK: - recent searches

  @Test func recentSearchesRoundTrip() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    let recents = RecentSearchStore(store: store, userId: "user-alice")
    #expect(try await recents.recents().isEmpty)
    let first = SearchFilter(query: "beach", scope: .personal)
    let second = SearchFilter(local: LocalAssetFilter(make: "Canon"))
    try await recents.record(first)
    try await recents.record(second)
    #expect(try await recents.recents() == [second, first])
    // Re-recording moves to the front without duplicating.
    try await recents.record(first)
    #expect(try await recents.recents() == [first, second])
    try await recents.clear()
    #expect(try await recents.recents().isEmpty)
  }
}

/// `FullExif`'s wire shape (`{groups: …}`) for decode tests — mirrors `SearchService`'s
/// private response without reaching into it.
private struct FullExifResponseForTest: Decodable {
  var groups: [String: [String: FullExifValue]]
}
