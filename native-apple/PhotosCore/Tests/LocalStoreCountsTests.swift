import CoreModel
import Foundation
import LocalStore
import Rules
import Testing

/// WP6 slice B: `LocalStore+Counts` mirrors each destination's row predicate —
/// a tile count of N means N items after navigating there.
struct LocalStoreCountsTests {
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
          width: 4000, height: 3000)),
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
          id: "a-hidden", ownerId: alice, originalFileName: "IMG_2.HEIC", checksum: "c4",
          localDateTime: date("2024-05-04T12:00:00Z"), type: .image,
          visibility: .hidden)),
      .asset(
        Asset(
          id: "a-trash", ownerId: alice, originalFileName: "IMG_3.HEIC", checksum: "c5",
          localDateTime: date("2024-05-05T12:00:00Z"), type: .image,
          deletedAt: date("2024-06-10T00:00:00Z"))),
      .assetExif(AssetExif(assetId: "a-photo", latitude: 37.7749, longitude: -122.4194)),
    ]
    try await store.apply(changes, currentUserId: alice)
  }

  private static func scope() -> ContainerScope {
    ContainerScope(personalUserIds: ["user-alice"])
  }

  @Test("mediaKindCounts groups by the grid classifier in one query")
  func mediaKinds() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    // Mirrors `assets(scope:mediaKind:)`: trashed excluded; hidden included (the
    // destination query has no visibility filter — flagged in LocalStore+Counts).
    let counts = try await store.mediaKindCounts(scope: Self.scope())
    #expect(counts[.photo] == 2)
    #expect(counts[.video] == 1)
    #expect(counts[.screenshot] == 1)
    #expect(counts.values.reduce(0, +) == 4)
  }

  @Test("favorite/recent/hidden/trash/located counts match their destinations")
  func tiles() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    #expect(try await store.favoriteCount(scope: Self.scope()) == 1)
    // Recents: every non-trashed, non-locked asset (hidden counts as recent —
    // `recentAssets` has no visibility filter beyond locked).
    #expect(try await store.recentCount(scope: Self.scope()) == 4)
    #expect(try await store.hiddenCount(scope: Self.scope()) == 1)
    #expect(try await store.trashCount(scope: Self.scope()) == 1)
    #expect(try await store.locatedCount(scope: Self.scope()) == 1)
    #expect(try await store.nativeCollectionCount(scope: Self.scope(), collection: .videos) == 1)
    #expect(
      try await store.nativeCollectionCount(scope: Self.scope(), collection: .screenshots) == 1)
    #expect(
      try await store.nativeCollectionCount(scope: Self.scope(), collection: .selfies) == 0)
  }

  @Test("captured/archive/locked counts match their destinations")
  func utilityCounts() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    // Owner-based: all 5 seeded assets are alice's; a-trash is excluded
    // (trashed) while a-hidden counts (only locked is excluded).
    #expect(try await store.capturedByMeCount(userId: "user-alice", scope: Self.scope()) == 4)
    #expect(try await store.capturedByMeCount(userId: "nobody", scope: Self.scope()) == 0)
    #expect(try await store.archiveCount(scope: Self.scope()) == 0)
    #expect(try await store.lockedCount(userId: "user-alice") == 0)
  }

  // MARK: - C1a (WP4): why person counts read 0 with empty names

  /// Verifies the C1a hypothesis on fixture-shaped data: the person↔asset link is
  /// the `face` join (`face.personId` set + `isVisible`), so a named person with a
  /// visible face counts 1; an unassigned face (`personId == nil`, the clustered /
  /// unconfirmed state the server syncs) attributes to nobody; and an unnamed
  /// person with no faces is returned with count 0 — the row the UI must hide
  /// (hide unnamed AND zero-asset), not a mapping bug to fix in sync.
  @Test("C1a: person counts come from the face join; unassigned faces count nowhere")
  func personCountsComeFromFaceJoin() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await Self.seed(into: store)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try await store.apply(
      [
        .person(
          Person(
            id: "p-bob", createdAt: now, updatedAt: now, ownerId: "user-alice",
            name: "Bob", faceAssetId: "a-photo")),
        .face(
          Face(
            id: "f1", assetId: "a-photo", personId: "p-bob", imageWidth: 100,
            imageHeight: 200, boundingBoxX1: 1, boundingBoxY1: 2, boundingBoxX2: 3,
            boundingBoxY2: 4, sourceType: "machine")),
        // Clustered but unconfirmed face: no personId, so it joins to nobody.
        .face(
          Face(
            id: "f2", assetId: "a-video", personId: nil, imageWidth: 100,
            imageHeight: 200, boundingBoxX1: 1, boundingBoxY1: 2, boundingBoxX2: 3,
            boundingBoxY2: 4, sourceType: "machine")),
        // Unnamed person with no faces: the "Unnamed · 0" row from the audit.
        .person(
          Person(
            id: "p-ghost", createdAt: now, updatedAt: now, ownerId: "user-alice",
            name: "")),
      ],
      currentUserId: "user-alice"
    )
    let summaries = try await store.peopleSummaries(userId: "user-alice")
    let bob = summaries.first { $0.id == "p-bob" }
    #expect(bob?.assetCount == 1)
    #expect(bob?.name == "Bob")
    // The unassigned face attributes to nobody: total attributed faces stays 1.
    #expect(summaries.reduce(0) { $0 + $1.assetCount } == 1)
    let ghost = summaries.first { $0.id == "p-ghost" }
    #expect(ghost?.name == "")
    #expect(ghost?.assetCount == 0)
    // And the id path agrees with the summary count.
    #expect(try await store.assetIds(forPerson: "p-bob") == ["a-photo"])
  }
}
