import CoreModel
import Foundation
import LocalStore
import Media

/// Deterministic in-app fixture world for previews and XCUITest
/// (`-useFixtureStore` launch arg). Mirrors `A3SmokeTests.makeWorld` (PhotosCoreTests): Alice (u1)
/// + Bob (u2), two member spaces, one owned library with an upload path, personal/space/locked/
//// GPS assets, an album, and a person. Seeded through the public `apply(_:)` pipeline — the same
/// path real sync data takes — so the smoke test exercises production code, not a stub.
///
/// Asset ids all start with `"fx"` (see `FixtureArtwork`): solid-hue generated images with index
/// numbers, real thumbhashes, and a portrait/landscape/panorama + video/live mix.
/// `-fixtureSeedCount=<N>` (1…150000) scales the world to N assets spread over 15 years for
/// simulator perf runs, through the same `apply()` path.
///
/// Disk pre-warm: `refresh()` (extension snapshot writer) `await`s `pipeline.load(.thumbnail)`
/// for the 4 most recent favorites *before* any grid cell exists to warm the memory cache.
/// Against `https://fixture.local` each such load hangs ~60s on a connect timeout, stalling
/// sign-in past the UI-test launch timeout. So the seed renders those thumbnails into the
/// pipeline disk cache up front (same `fixture-media-cache` root `AppSession.startFixture`
/// builds the pipeline on), where `load` resolves without touching the network.
enum FixtureSeed {
  static let userId = "u1"
  static let maxSeedCount = 150_000
  private static let applyChunk = 5_000
  /// Thumbnails pre-warmed to disk: all of them in the small default world, the most recent
  /// favorites (what the snapshot writer reads) in generated worlds.
  private static let generatedPrewarmFavorites = 8

  /// Parses `-fixtureSeedCount=<N>` from the launch arguments; nil when absent or invalid.
  static func seedCount(from args: [String] = CommandLine.arguments) -> Int? {
    let prefix = "-fixtureSeedCount="
    for arg in args where arg.hasPrefix(prefix) {
      guard let n = Int(arg.dropFirst(prefix.count)), n >= 1 else { return nil }
      return min(n, maxSeedCount)
    }
    return nil
  }

  static func seed(into store: PhotosLocalStore) async throws {
    HeirloomLog.store.info("fixture seed begin")
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func day(_ offset: Int) -> Date { now.addingTimeInterval(Double(offset) * 86_400) }
    // Base containers are identical in both worlds.
    try await store.apply(
      [
        .user(User(id: "u1", name: "Alice", email: "alice@fixture.local")),
        .user(User(id: "u2", name: "Bob", email: "bob@fixture.local")),
        .space(Space(id: "s1", name: "Family", description: "", createdAt: now, updatedAt: now)),
        .space(Space(id: "s2", name: "Camera", description: "", createdAt: now, updatedAt: now)),
        .spaceMember(SpaceMember(spaceId: "s1", userId: "u1", role: .contributor, showInTimeline: true)),
        .spaceMember(SpaceMember(spaceId: "s1", userId: "u2", role: .owner, showInTimeline: true)),
        .spaceMember(SpaceMember(spaceId: "s2", userId: "u1", role: .owner, showInTimeline: true)),
        .spaceMember(SpaceMember(spaceId: "s2", userId: "u2", role: .contributor, showInTimeline: true)),
        .library(Library(id: "L1", name: "Archive", ownerId: "u1", createdAt: now, updatedAt: now)),
        .album(Album(id: "al1", name: "Trip", description: "", createdAt: now, updatedAt: now)),
        .albumUser(AlbumMember(albumId: "al1", userId: "u1", role: .editor)),
        .albumUser(AlbumMember(albumId: "al1", userId: "u2", role: .viewer)),
      ],
      currentUserId: userId
    )
    let seeded: SeededWorld
    if let count = seedCount() {
      seeded = try await seedGenerated(count: count, now: now, into: store)
    } else {
      seeded = try await seedDefault(now: now, day: day, into: store)
    }
    // Person + face ride on the first asset, whichever world was seeded.
    try await store.apply(
      [
        .person(
          Person(
            id: "p1", createdAt: now, updatedAt: now, ownerId: "u1", name: "Bob",
            faceAssetId: seeded.firstAssetId)),
        .face(
          Face(
            id: "f1", assetId: seeded.firstAssetId, personId: "p1", imageWidth: 100,
            imageHeight: 200,
            boundingBoxX1: 1, boundingBoxY1: 2, boundingBoxX2: 3, boundingBoxY2: 4,
            sourceType: "machine")),
      ],
      currentUserId: userId
    )
    try await store.setLibraryUploadPath(libraryId: "L1", uploadPath: "/incoming")
    await prewarmDiskCache(assets: seeded.prewarm)
    HeirloomLog.store.info("fixture seed end assets=\(seeded.assetCount)")
  }

  /// The seeded assets plus the subset whose thumbnails must be on disk before `refresh()`.
  private struct SeededWorld {
    var firstAssetId: String
    var assetCount: Int
    var prewarm: [Asset]
  }

  // MARK: - default world (UI tests, previews)

  /// 12 curated assets: portrait/landscape/panorama mix, 0:07 and 1:05:03 videos, a live photo
  /// (+ motion partner, hidden from the timeline by the store), favorites, space/library/locked
  /// containers, and a GPS exif row for Places.
  private static func seedDefault(
    now _: Date, day: (Int) -> Date, into store: PhotosLocalStore
  ) async throws -> SeededWorld {
    let portrait = (768, 1024)
    let landscape = (1024, 768)
    let panorama = (2048, 768)
    func img(
      _ id: String, _ n: Int, _ owner: String, _ size: (Int, Int), _ offset: Int,
      spaceId: String? = nil, libraryId: String? = nil,
      visibility: AssetVisibilityKind = .timeline, favorite: Bool = false,
      livePartner: String? = nil
    ) -> Asset {
      Asset(
        id: id, ownerId: owner, originalFileName: "IMG_\(n).heic",
        thumbhash: FixtureArtwork.thumbhash(index: n), checksum: "fx-c\(n)",
        localDateTime: day(offset), type: .image, isFavorite: favorite,
        visibility: visibility, livePhotoVideoId: livePartner, libraryId: libraryId,
        spaceId: spaceId, width: size.0, height: size.1)
    }
    let assets = [
      img("fx000001", 1, "u1", portrait, -700, favorite: true),
      img("fx000002", 2, "u2", landscape, -650, spaceId: "s1"),
      img("fx000003", 3, "u1", portrait, -600, spaceId: "s1", visibility: .locked),
      Asset(
        id: "fx000004", ownerId: "u1", originalFileName: "VID_4.mov",
        thumbhash: FixtureArtwork.thumbhash(index: 4), checksum: "fx-c4",
        localDateTime: day(-550), durationSeconds: 7, type: .video,
        width: landscape.0, height: landscape.1),
      Asset(
        id: "fx000005", ownerId: "u1", originalFileName: "VID_5.mov",
        thumbhash: FixtureArtwork.thumbhash(index: 5), checksum: "fx-c5",
        localDateTime: day(-500), durationSeconds: 3_903, type: .video,
        width: landscape.0, height: landscape.1),
      img("fx000006", 6, "u1", portrait, -450, livePartner: "fx000006m"),
      Asset(
        id: "fx000006m", ownerId: "u1", originalFileName: "IMG_6.mov",
        thumbhash: FixtureArtwork.thumbhash(index: 6), checksum: "fx-c6m",
        localDateTime: day(-450), durationSeconds: 3, type: .video,
        width: landscape.0, height: landscape.1),
      img("fx000007", 7, "u1", panorama, -400),
      img("fx000008", 8, "u1", landscape, -300, spaceId: "s2"),
      img("fx000009", 9, "u1", portrait, -200, libraryId: "L1"),
      img("fx000010", 10, "u2", landscape, -100, favorite: true),
      img("fx000011", 11, "u1", landscape, -30),
      img("fx000012", 12, "u2", portrait, -7, spaceId: "s1"),
    ]
    var changes: [SyncChange] = assets.map { .asset($0) }
    changes += [
      .assetExif(AssetExif(assetId: "fx000004", latitude: 37.7749, longitude: -122.4194, city: "San Francisco", make: "Apple")),
      .albumAsset(albumId: "al1", assetId: "fx000001"),
      .albumAsset(albumId: "al1", assetId: "fx000002"),
      // WP-P P5/P7 evidence: one saved memory (renders a real card through the
      // production loader) and a city on the GPS asset (backs Trips).
      .memory(
        Memory(
          id: "fxmem1", createdAt: day(-30), updatedAt: day(-7), ownerId: "u1",
          type: "on_this_day", dataJSON: "{}", isSaved: true, memoryAt: day(-30))),
      .memoryAsset(memoryId: "fxmem1", assetId: "fx000001"),
      .memoryAsset(memoryId: "fxmem1", assetId: "fx000002"),
      .memoryAsset(memoryId: "fxmem1", assetId: "fx000011"),
    ]
    try await store.apply(changes, currentUserId: userId)
    return SeededWorld(firstAssetId: "fx000001", assetCount: assets.count, prewarm: assets)
  }

  // MARK: - generated world (simulator perf runs)

  /// N assets spread over 15 years, cycling portrait/landscape/panorama with 0:07 + 1:05:03
  /// videos and live photos (+ motion partners), favorites, and all container kinds.
  private static func seedGenerated(
    count: Int, now: Date, into store: PhotosLocalStore
  ) async throws -> SeededWorld {
    let sizes = [(768, 1024), (1024, 768), (2048, 768)]
    let span = Double(15 * 365) * 86_400 / Double(count)
    var batch: [SyncChange] = []
    batch.reserveCapacity(applyChunk)
    var albumLinks: [SyncChange] = []
    var assets: [Asset] = []
    assets.reserveCapacity(count)
    func flush() async throws {
      guard !batch.isEmpty else { return }
      try await store.apply(batch, currentUserId: userId)
      batch.removeAll(keepingCapacity: true)
    }
    func push(_ asset: Asset) {
      assets.append(asset)
      batch.append(.asset(asset))
    }
    for i in 0..<count {
      let id = String(format: "fx%06d", i)
      let (w, h) = sizes[i % sizes.count]
      let date = now.addingTimeInterval(-Double(i) * span)
      let owner = i % 3 == 2 ? "u2" : "u1"
      var spaceId: String?
      var libraryId: String?
      switch i % 4 {
      case 0: spaceId = "s1"
      case 1: spaceId = "s2"
      default: break
      }
      if i % 9 == 8 { spaceId = nil; libraryId = "L1" }
      let favorite = i % 7 == 0
      let visibility: AssetVisibilityKind = i % 37 == 0 ? .locked : .timeline
      let kind = i % 10
      if kind == 6 {
        let motionId = String(format: "fxM%06d", i)
        push(
          Asset(
            id: id, ownerId: owner, originalFileName: "IMG_\(i).heic",
            thumbhash: FixtureArtwork.thumbhash(index: i), checksum: "fx-c\(i)",
            localDateTime: date, type: .image, isFavorite: favorite, visibility: visibility,
            livePhotoVideoId: motionId, libraryId: libraryId, spaceId: spaceId,
            width: w, height: h))
        push(
          Asset(
            id: motionId, ownerId: owner, originalFileName: "IMG_\(i).mov",
            thumbhash: FixtureArtwork.thumbhash(index: i), checksum: "fxM-c\(i)",
            localDateTime: date, durationSeconds: 3, type: .video,
            libraryId: libraryId, spaceId: spaceId, width: 1_024, height: 768))
      } else if kind == 4 || kind == 5 {
        push(
          Asset(
            id: id, ownerId: owner, originalFileName: "VID_\(i).mov",
            thumbhash: FixtureArtwork.thumbhash(index: i), checksum: "fx-c\(i)",
            localDateTime: date, durationSeconds: kind == 4 ? 7 : 3_903, type: .video,
            isFavorite: favorite, visibility: visibility, libraryId: libraryId,
            spaceId: spaceId, width: w, height: h))
      } else {
        push(
          Asset(
            id: id, ownerId: owner, originalFileName: "IMG_\(i).heic",
            thumbhash: FixtureArtwork.thumbhash(index: i), checksum: "fx-c\(i)",
            localDateTime: date, type: .image, isFavorite: favorite, visibility: visibility,
            libraryId: libraryId, spaceId: spaceId, width: w, height: h))
      }
      if i % 50 == 0 {
        batch.append(
          .assetExif(AssetExif(assetId: id, latitude: 37.7749, longitude: -122.4194, make: "Apple")))
      }
      if i % 5 == 0, albumLinks.count < 5_000 {
        albumLinks.append(.albumAsset(albumId: "al1", assetId: id))
      }
      if batch.count >= applyChunk { try await flush() }
    }
    try await flush()
    if !albumLinks.isEmpty {
      try await store.apply(albumLinks, currentUserId: userId)
    }
    // The snapshot writer reads the 4 most recent favorites; warm a few more for scope margin.
    let recentFavorites = assets.lazy.filter { $0.isFavorite }.prefix(generatedPrewarmFavorites)
    return SeededWorld(
      firstAssetId: "fx000000", assetCount: assets.count, prewarm: Array(recentFavorites))
  }

  // MARK: - disk pre-warm

  /// Renders `assets` through `FixtureArtwork` into the fixture pipeline disk cache so
  /// `pipeline.load(.thumbnail)` resolves from disk. Same root `AppSession.startFixture` uses.
  private static func prewarmDiskCache(assets: [Asset]) async {
    guard !assets.isEmpty else { return }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fixture-media-cache", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let cache = TieredMediaCache(rootDirectory: root)
    for asset in assets {
      guard let image = FixtureArtwork.image(for: asset),
        let data = image.pngData()
      else { continue }
      try? await cache.store(data, assetID: asset.id, tier: .thumbnail, edited: false)
    }
  }
}
