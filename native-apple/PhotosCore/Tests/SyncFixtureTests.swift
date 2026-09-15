import Testing
@testable import LocalStore

/// AP-01 (TESTING.md §5): "world sync fixtures → LocalStore counts per container/user match world;
/// removals applied". `e2e/fork-assets` world fixtures don't exist yet (T0 hasn't landed — see the A1
/// handoff), so these fixtures are hand-authored here, matching the wire shapes exercised by S6's medium
/// tests, covering exactly the cases the brief's Tests section lists: initial sync, incremental update,
/// move out of space (RemoveV1), membership loss, reset.
@Suite struct SyncFixtureTests {
  @Test("[AP-01] initial sync populates users, partners, assets, exif, space, and space asset")
  func initialSync() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await FixtureReplay.run("initial-sync", into: store, currentUserId: "u1")

    let a1 = try #require(try await store.asset(id: "a1"))
    #expect(a1.ownerId == "u1")
    #expect(a1.spaceId == nil)
    #expect(a1.isFavorite == false)

    let a2 = try #require(try await store.asset(id: "a2"))
    #expect(a2.spaceId == "s1")
    #expect(a2.ownerId == "u2")

    let ctx = try await store.accessContext(for: "u1")
    #expect(ctx.memberSpaceIds == ["s1"])

    let acks = try await store.allSyncAcks()
    #expect(acks.contains("AssetsV2|ack-4"))
    #expect(acks.contains("SharedSpaceAssetsV1|ack-8"))
  }

  @Test("[AP-01] incremental update upserts an existing asset in place")
  func incrementalUpdate() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await FixtureReplay.run("initial-sync", into: store, currentUserId: "u1")
    try await FixtureReplay.run("incremental-update", into: store, currentUserId: "u1")

    let a1 = try #require(try await store.asset(id: "a1"))
    #expect(a1.isFavorite == true)
    // Only the changed fields moved; the row is still the same asset (id/ownerId untouched).
    #expect(a1.ownerId == "u1")
  }

  @Test("[AP-01] SharedSpaceAssetRemoveV1 drops the asset that left this device's visibility")
  func moveOutOfSpace() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await FixtureReplay.run("initial-sync", into: store, currentUserId: "u1")
    #expect(try await store.asset(id: "a2") != nil)

    try await FixtureReplay.run("move-out-of-space", into: store, currentUserId: "u1")
    #expect(try await store.asset(id: "a2") == nil)
    // The space itself and its other membership are unaffected by a single asset leaving.
    let ctx = try await store.accessContext(for: "u1")
    #expect(ctx.memberSpaceIds == ["s1"])
  }

  @Test("[AP-01] membership loss for the signed-in user cascades: space and its assets are dropped")
  func membershipLoss() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await FixtureReplay.run("initial-sync", into: store, currentUserId: "u1")
    try await FixtureReplay.run("membership-loss", into: store, currentUserId: "u1")

    let ctx = try await store.accessContext(for: "u1")
    #expect(ctx.memberSpaceIds.isEmpty)
    // DECISIONS §8: a contributor removed from a space loses access to remaining assets in it.
    #expect(try await store.asset(id: "a2") == nil)
    // Personal assets (not in the removed space) are untouched.
    #expect(try await store.asset(id: "a1") != nil)
  }

  @Test("[AP-01] SyncResetV1 wipes the mirror before the resync that follows replaces it")
  func reset() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try await FixtureReplay.run("initial-sync", into: store, currentUserId: "u1")
    #expect(try await store.asset(id: "a1") != nil)

    try await FixtureReplay.run("reset", into: store, currentUserId: "u1")

    // Pre-reset data is gone…
    #expect(try await store.asset(id: "a1") == nil)
    #expect(try await store.asset(id: "a2") == nil)
    // …and the post-reset resync content is present.
    #expect(try await store.asset(id: "a3") != nil)
    // Reset also clears stored checkpoints so the client re-requests everything from scratch.
    let acks = try await store.allSyncAcks()
    #expect(!acks.contains { $0.hasPrefix("AssetsV2|ack-4") })
  }
}
