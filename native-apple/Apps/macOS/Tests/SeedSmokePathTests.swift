import CoreModel
import Foundation
import LocalStore
import Rules
import XCTest

/// WP-T: guards the seed side of the UI-smoke path at unit-test speed. Pins down
/// two of the three empty-grid suspects — a throwing single-transaction `apply`
/// and pre-sync scope-gating — so a future empty grid points at load sequencing.
/// (The sequencing itself, `seedForSmoke`'s post-seed `timelineVersion` bump, is
/// covered by the UI suite: every grid test waits on real cells.) Runs via
/// `verify.sh mac-unit`.
final class SeedSmokePathTests: XCTestCase {
  /// The sized small fixture applies cleanly and the timeline-scope grid queries
  /// the app path runs (`timelineBuckets`/`favoriteAssets`/`timelineRows`) see
  /// the rows — i.e. neither a throwing `apply` nor pre-sync scope-gating can
  /// explain an empty grid.
  func testSmallFixtureSeedsAndGridQueriesSeeRows() async throws {
    let changes = FixtureSeed.sizedChanges(assetTarget: FixtureSeed.smallAssetTarget)
    let store = try PhotosLocalStore(inMemory: true)
    for start in stride(from: 0, to: changes.count, by: 10_000) {
      try await store.apply(
        Array(changes[start..<min(start + 10_000, changes.count)]),
        currentUserId: FixtureSeed.userId)
    }
    let ctx = try await store.timelineContext(for: FixtureSeed.userId)
    let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
    XCTAssertTrue(scope.personalUserIds.contains(FixtureSeed.userId), "personal scope resolves pre-sync")
    let buckets = try await store.timelineBuckets(scope: scope, granularity: .month)
    XCTAssertGreaterThan(buckets.reduce(0) { $0 + $1.count }, 0, "grid buckets see seeded rows")
    let favorites = try await store.favoriteAssets(scope: scope, limit: 250_000)
    XCTAssertGreaterThan(favorites.count, 0, "favorites see seeded rows")
    let rows = try await store.timelineRows(scope: scope)
    XCTAssertGreaterThan(rows.count, 0, "timeline sees seeded rows")
  }

  /// The sized small fixture applies in one `apply()` call too (the pre-chunking
  /// shape): a single transaction over the whole set must not throw, so no seed
  /// shape can poison the store into an all-or-nothing empty world.
  func testSmallFixtureSingleApplyDoesNotThrow() async throws {
    let changes = FixtureSeed.sizedChanges(assetTarget: FixtureSeed.smallAssetTarget)
    let store = try PhotosLocalStore(inMemory: true)
    try await store.apply(changes, currentUserId: FixtureSeed.userId)
    let ctx = try await store.timelineContext(for: FixtureSeed.userId)
    let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
    let rows = try await store.timelineRows(scope: scope)
    XCTAssertGreaterThan(rows.count, 0, "single-apply seed visible to grid queries")
  }
}
