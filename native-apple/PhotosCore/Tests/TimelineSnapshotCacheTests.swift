import CoreModel
import Foundation
import Testing
@testable import LocalStore

/// WP-F F1: `TimelineSnapshotCache` returns hits synchronously with no store call,
/// invalidates only affected keys on change-center events, evicts LRU at 7 entries,
/// and purges on memory pressure. New infrastructure (no base equivalent): green on
/// arrival; the red state on base `9b9bb7f2e` is the type's absence.
@Suite struct TimelineSnapshotCacheTests {
  private static func key(_ scope: String, _ filter: String = "all") -> TimelineSnapshotCache.Key {
    TimelineSnapshotCache.Key(scope: scope, filter: filter, grouping: "months", sort: "newestFirst")
  }

  private static func snapshot(ids: [String]) -> TimelineGridSnapshot {
    let rows = ids.map {
      TimelineRow(
        id: $0, thumbhash: nil, aspectRatio: 1, mediaKind: .photo, isFavorite: false,
        isTrashed: false, isArchived: false, localDateTime: nil)
    }
    return TimelineGridSnapshot.build(
      sections: [TimelineSourceSection(kind: .none, rows: rows)],
      order: .newestFirst, include: { _ in true }, generation: 1)
  }

  @Test("hit returns the stored snapshot synchronously and clean")
  func hitReturnsStoredSnapshot() {
    let cache = TimelineSnapshotCache()
    let stored = Self.snapshot(ids: ["a", "b"])
    cache.store(stored, for: Self.key("library"))
    let hit = cache.snapshot(for: Self.key("library"))
    #expect(hit?.snapshot === stored)
    #expect(hit?.dirty == false)
  }

  @Test("miss returns nil for unknown keys")
  func missReturnsNil() {
    let cache = TimelineSnapshotCache()
    cache.store(Self.snapshot(ids: ["a"]), for: Self.key("library"))
    #expect(cache.snapshot(for: Self.key("favorites")) == nil)
  }

  @Test("different filter/grouping/sort keys do not collide")
  func keysDoNotCollide() {
    let cache = TimelineSnapshotCache()
    let base = TimelineSnapshotCache.Key(
      scope: "library", filter: "all", grouping: "months", sort: "newestFirst")
    cache.store(Self.snapshot(ids: ["a"]), for: base)
    #expect(
      cache.snapshot(
        for: TimelineSnapshotCache.Key(
          scope: "library", filter: "favorites", grouping: "months", sort: "newestFirst")) == nil)
    #expect(
      cache.snapshot(
        for: TimelineSnapshotCache.Key(
          scope: "library", filter: "all", grouping: "years", sort: "newestFirst")) == nil)
    #expect(
      cache.snapshot(
        for: TimelineSnapshotCache.Key(
          scope: "library", filter: "all", grouping: "months", sort: "oldestFirst")) == nil)
  }

  @Test("change-center invalidation drops only the affected scope")
  func invalidationIsScoped() {
    let cache = TimelineSnapshotCache()
    cache.store(Self.snapshot(ids: ["a"]), for: Self.key("library"))
    cache.store(Self.snapshot(ids: ["b"]), for: Self.key("favorites"))
    cache.invalidate { $0.scope == "library" }
    #expect(cache.snapshot(for: Self.key("library")) == nil)
    #expect(cache.snapshot(for: Self.key("favorites")) != nil)
  }

  @Test("dirty marking keeps the snapshot but flags revalidation")
  func dirtyKeepsSnapshot() {
    let cache = TimelineSnapshotCache()
    let stored = Self.snapshot(ids: ["a"])
    cache.store(stored, for: Self.key("library"))
    cache.markDirty { $0.scope == "library" }
    let hit = cache.snapshot(for: Self.key("library"))
    #expect(hit?.snapshot === stored)
    #expect(hit?.dirty == true)
  }

  @Test("LRU evicts the oldest entry at 7 stored snapshots")
  func lruEviction() {
    let cache = TimelineSnapshotCache()
    for index in 0..<7 {
      cache.store(Self.snapshot(ids: ["row-\(index)"]), for: Self.key("scope-\(index)"))
    }
    #expect(cache.count == 6)
    #expect(cache.snapshot(for: Self.key("scope-0")) == nil)
    #expect(cache.snapshot(for: Self.key("scope-6")) != nil)
  }

  @Test("LRU refreshes recency on hit")
  func lruRefreshOnHit() {
    let cache = TimelineSnapshotCache()
    for index in 0..<6 {
      cache.store(Self.snapshot(ids: ["row-\(index)"]), for: Self.key("scope-\(index)"))
    }
    _ = cache.snapshot(for: Self.key("scope-0"))
    cache.store(Self.snapshot(ids: ["new"]), for: Self.key("scope-new"))
    #expect(cache.snapshot(for: Self.key("scope-0")) != nil)
    #expect(cache.snapshot(for: Self.key("scope-1")) == nil)
  }

  @Test("memory-pressure notification purges all entries")
  func memoryPressurePurges() {
    let cache = TimelineSnapshotCache()
    cache.store(Self.snapshot(ids: ["a"]), for: Self.key("library"))
    cache.store(Self.snapshot(ids: ["b"]), for: Self.key("favorites"))
    NotificationCenter.default.post(
      name: TimelineSnapshotCache.memoryPressureNotification, object: nil)
    #expect(cache.count == 0)
  }
}
