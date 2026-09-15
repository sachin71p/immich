import Foundation
import Testing
@testable import Media

private func freshCache(budgets: CacheBudgets = CacheBudgets(bytes: [:])) async throws -> (TieredMediaCache, URL) {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  return (TieredMediaCache(rootDirectory: root, budgets: budgets), root)
}

private func bytes(_ count: Int, seed: UInt8 = 0) -> Data {
  Data((0..<count).map { seed &+ UInt8($0 & 0xff) })
}

@Suite struct TieredMediaCacheTests {
  @Test("[A2-03] usage accounts every tier and the total")
  func budgetAccounting() async throws {
    let (cache, _) = try await freshCache()
    try await cache.store(bytes(40), assetID: "a", tier: .thumbnail)
    try await cache.store(bytes(60), assetID: "b", tier: .preview)
    try await cache.store(bytes(10), assetID: "c", tier: .original)
    let usage = await cache.usage()
    #expect(usage[.thumbnail] == 40)
    #expect(usage[.preview] == 60)
    #expect(usage[.fullsize] == 0)
    #expect(usage[.original] == 10)
    #expect(await cache.totalUsage() == 110)
  }

  @Test("[A2-03] LRU eviction drops the stalest unpinned entry, never a pin")
  func lruRespectsPins() async throws {
    let (cache, _) = try await freshCache(
      budgets: CacheBudgets(bytes: [.thumbnail: 100]))
    try await cache.store(bytes(40, seed: 1), assetID: "a", tier: .thumbnail)
    try await cache.store(bytes(40, seed: 2), assetID: "b", tier: .thumbnail)
    // Touch "a" so "b" is the eviction candidate, then pin "a".
    _ = await cache.retrieve(assetID: "a", tier: .thumbnail)
    await cache.setPinned(true, assetID: "a", tier: .thumbnail)
    try await cache.store(bytes(40, seed: 3), assetID: "c", tier: .thumbnail)

    #expect(await cache.retrieve(assetID: "a", tier: .thumbnail) == bytes(40, seed: 1))
    #expect(await cache.retrieve(assetID: "b", tier: .thumbnail) == nil)
    #expect(await cache.retrieve(assetID: "c", tier: .thumbnail) == bytes(40, seed: 3))
    #expect(await cache.usage()[.thumbnail] == 80)
  }

  @Test("[A2-03] evict frees at least the requested bytes; all-pinned frees nothing")
  func explicitEvict() async throws {
    let (cache, _) = try await freshCache()
    try await cache.store(bytes(30), assetID: "a", tier: .preview)
    try await cache.store(bytes(30), assetID: "b", tier: .preview)
    try await cache.store(bytes(30), assetID: "c", tier: .preview)
    let freed = await cache.evict(freeing: 50, from: .preview)
    #expect(freed >= 50)
    #expect(await cache.usage()[.preview]! <= 40)

    // Only "c" survived the eviction above; pinning it must block all further frees.
    await cache.setPinned(true, assetID: "c", tier: .preview)
    let kept = await cache.evict(freeing: 1_000, from: .preview)
    #expect(kept == 0)
    #expect(await cache.retrieve(assetID: "c", tier: .preview) != nil)
  }

  @Test("[A2-03] setBudget applies immediately; nil means unlimited (all thumbnails on device)")
  func setBudget() async throws {
    let (cache, _) = try await freshCache()
    try await cache.store(bytes(100), assetID: "a", tier: .thumbnail)
    try await cache.store(bytes(100), assetID: "b", tier: .thumbnail)
    await cache.setBudget(150, for: .thumbnail)
    #expect(await cache.usage()[.thumbnail]! <= 150)
    await cache.setBudget(nil, for: .thumbnail)
    try await cache.store(bytes(10_000), assetID: "big", tier: .thumbnail)
    #expect(await cache.retrieve(assetID: "big", tier: .thumbnail)?.count == 10_000)
  }

  @Test("[A2-03] original bytes round-trip verbatim; edited variants are separate entries")
  func verbatimOriginalsAndEditedKeys() async throws {
    let (cache, _) = try await freshCache()
    let original = bytes(1024, seed: 7)
    try await cache.store(original, assetID: "a", tier: .original)
    try await cache.store(bytes(8, seed: 9), assetID: "a", tier: .original, edited: true)
    #expect(await cache.retrieve(assetID: "a", tier: .original) == original)
    #expect(await cache.retrieve(assetID: "a", tier: .original, edited: true) == bytes(8, seed: 9))
  }

  @Test("[A2-03] cached tiers report best quality first for offline serving")
  func cachedTierOrder() async throws {
    let (cache, _) = try await freshCache()
    try await cache.store(bytes(4), assetID: "a", tier: .thumbnail)
    try await cache.store(bytes(4), assetID: "a", tier: .fullsize)
    #expect(await cache.cachedTiers(assetID: "a") == [.fullsize, .thumbnail])
    #expect(await cache.bestCachedTier(assetID: "a") == .fullsize)
    #expect(await cache.bestCachedTier(assetID: "missing") == nil)
  }

  @Test("[A2-03] the index rebuilds from disk so usage survives restarts")
  func persistsAcrossInstances() async throws {
    let (cache, root) = try await freshCache()
    try await cache.store(bytes(25), assetID: "a", tier: .preview)
    let reopened = TieredMediaCache(rootDirectory: root, budgets: CacheBudgets(bytes: [:]))
    #expect(await reopened.usage()[.preview] == 25)
    #expect(await reopened.retrieve(assetID: "a", tier: .preview) == bytes(25))
  }
}
