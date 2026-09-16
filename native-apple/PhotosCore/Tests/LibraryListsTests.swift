import CoreModel
import Foundation
import LocalStore
import Rules
import Testing

/// A4 coverage for `LocalStore+LibraryLists` (the sidebar/destination queries the macOS shell
/// and iOS shell share) plus AP-04: move-sheet targets for a mixed-container selection equal
/// the `Rules.MoveTargets` expectations (DECISIONS §6). Seeded programmatically through the
/// public `apply()` path — no world fixtures involved.
struct LibraryListsTests {
  private static func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 0)
  }

  private static func seed(into store: PhotosLocalStore) async throws {
    let alice = "user-alice", bob = "user-bob"
    let changes: [SyncChange] = [
      .user(User(id: alice, name: "Alice", email: "alice@example.com")),
      .user(User(id: bob, name: "Bob", email: "bob@example.com")),
      .space(
        Space(
          id: "space-family", name: "Family", description: "", createdAt: date("2023-01-01T00:00:00Z"),
          updatedAt: date("2023-01-01T00:00:00Z"))
      ),
      .spaceMember(SpaceMember(spaceId: "space-family", userId: alice, role: .owner, showInTimeline: true)),
      .spaceMember(
        SpaceMember(spaceId: "space-family", userId: bob, role: .contributor, showInTimeline: true)),
      .library(
        Library(
          id: "library-archive", name: "Archive", ownerId: alice,
          createdAt: date("2023-01-01T00:00:00Z"), updatedAt: date("2023-01-01T00:00:00Z"))
      ),
      .album(
        Album(
          id: "album-trip", name: "Trip", description: "",
          createdAt: date("2024-05-01T00:00:00Z"), updatedAt: date("2024-05-01T00:00:00Z"))
      ),
      .albumUser(AlbumMember(albumId: "album-trip", userId: alice, role: .editor)),
      .asset(
        Asset(
          id: "a-personal", ownerId: alice, originalFileName: "IMG_1.HEIC", checksum: "c1",
          localDateTime: date("2024-06-01T12:00:00Z"), type: .image, width: 4000, height: 3000)),
      .assetExif(AssetExif(assetId: "a-personal", latitude: 37.7749, longitude: -122.4194)),
      .asset(
        Asset(
          id: "a-space", ownerId: alice, originalFileName: "VID_1.MOV", checksum: "c2",
          localDateTime: date("2024-06-02T12:00:00Z"), type: .video, spaceId: "space-family")),
      .asset(
        Asset(
          id: "a-bob-space", ownerId: bob, originalFileName: "IMG_2.JPG", checksum: "c3",
          localDateTime: date("2022-11-20T12:00:00Z"), type: .image, spaceId: "space-family")),
      .asset(
        Asset(
          id: "a-archived", ownerId: alice, originalFileName: "IMG_3.JPG", checksum: "c4",
          localDateTime: date("2023-08-08T12:00:00Z"), type: .image, visibility: .archive)),
      .albumAsset(albumId: "album-trip", assetId: "a-personal"),
      .albumAsset(albumId: "album-trip", assetId: "a-space"),
    ]
    try await store.apply(changes, currentUserId: alice)
    try await store.setLibraryUploadPath(libraryId: "library-archive", uploadPath: "/import/archive")
  }

  @Test func memberSpaces() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let spaces = try await store.memberSpaces(for: "user-alice")
    #expect(spaces.count == 1)
    #expect(spaces.first?.space.name == "Family")
    #expect(spaces.first?.role == .owner)
    #expect(try await store.memberSpaces(for: "user-nobody").isEmpty)
  }

  @Test func accessibleLibrariesAndAlbums() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let libraries = try await store.accessibleLibraries(for: "user-alice")
    #expect(libraries.count == 1)
    #expect(libraries.first?.library.name == "Archive")
    #expect(libraries.first?.isOwner == true)
    #expect(try await store.accessibleLibraries(for: "user-bob").isEmpty)
    let albums = try await store.memberAlbums(for: "user-alice")
    #expect(albums.map(\.album.id) == ["album-trip"])
    #expect(try await store.albumAssetCount(albumId: "album-trip") == 2)
    #expect(try await store.assetIds(inAlbum: "album-trip") == ["a-space", "a-personal"])
  }

  @Test func utilitiesQueries() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let ctx = try await store.timelineContext(for: "user-alice")
    let scope = TimelineScope.resolve(purpose: .manage, context: ctx)
    #expect(try await store.archivedAssets(scope: scope).map(\.id) == ["a-archived"])
    #expect(try await store.hiddenAssets(scope: scope).isEmpty)
    let timelineCtx = try await store.timelineContext(for: "user-alice")
    let timelineScope = TimelineScope.resolve(purpose: .timeline, context: timelineCtx)
    let points = try await store.mapPoints(scope: timelineScope)
    #expect(points.map(\.id) == ["a-personal"])
  }

  /// AP-04: the move sheet offers exactly the union of per-group `MoveTargets.allowed` sets
  /// (DECISIONS §6 rules 1–4, 7, 9) for a mixed personal/space selection.
  @Test func moveSheetTargetsMatchRules() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let ctx = try await store.accessContext(for: "user-alice")
    let assets = try await store.assets(ids: ["a-personal", "a-space", "a-bob-space"])
    #expect(assets.count == 3)
    var offered = Set<MoveTarget>()
    for asset in assets {
      offered.formUnion(MoveTargets.allowed(for: asset, in: ctx))
    }
    // Personal (alice's own assets), the member space; the current container is never
    // offered back (rule 7: no-op, not a sheet target).
    #expect(offered.contains(.personal))
    #expect(offered.contains(.space("space-family")))
    // a-bob-space already lives in space-family, and a-personal's set excludes no-ops —
    // per-asset: alice's personal asset offers {.personal? no: current is personal → removed}.
    let byId = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    let personalAllowed = MoveTargets.allowed(for: byId["a-personal"]!, in: ctx)
    #expect(!personalAllowed.contains(.personal))
    #expect(personalAllowed.contains(.space("space-family")))
    #expect(personalAllowed.contains(.library("library-archive")))
  }
}
