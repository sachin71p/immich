import Foundation
import GRDB
import Rules
import Testing
@testable import LocalStore

/// Brief Tests section: "bucket queries on a 50k-asset generated DB must return in <50 ms (performance
/// test)". Rows are inserted directly via GRDB (bypassing `apply(_:currentUserId:)`'s one-row-at-a-time
/// record path) purely so *generating* the fixture database doesn't itself dominate the test run; the
/// query under measurement is the real `timelineBuckets`/`timelineAssets` SQL.
@Suite struct TimelinePerformanceTests {
  private static func makeStore(assetCount: Int) throws -> PhotosLocalStore {
    let store = try PhotosLocalStore(inMemory: true)
    try store.dbQueue.write { db in
      let calendar = Calendar(identifier: .gregorian)
      for index in 0..<assetCount {
        let day = calendar.date(byAdding: .hour, value: -index, to: Date())!
        try db.execute(
          sql: """
            INSERT INTO asset (
              id, ownerId, originalFileName, checksum, type, isFavorite, visibility, isEdited,
              localDateTime, createdAt, width, height
            ) VALUES (?, 'me', ?, ?, 'IMAGE', ?, 'timeline', 0, ?, ?, 100, 100)
            """,
          arguments: [
            "asset-\(index)", "IMG_\(index).heic", "chk-\(index)", index % 37 == 0, day, day,
          ]
        )
      }
    }
    return store
  }

  @Test("[perf] timelineBuckets on a 50k-asset DB returns in under 50ms")
  func bucketQueryPerformance() async throws {
    let store = try Self.makeStore(assetCount: 50_000)
    let scope = ContainerScope(personalUserIds: ["me"])

    let start = DispatchTime.now()
    let buckets = try await store.timelineBuckets(scope: scope)
    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

    #expect(!buckets.isEmpty)
    #expect(elapsedMs < 50, "timelineBuckets took \(elapsedMs)ms, expected <50ms")
  }

  @Test("[perf] timelineAssets page fetch on a 50k-asset DB returns in under 50ms")
  func bucketPagePerformance() async throws {
    let store = try Self.makeStore(assetCount: 50_000)
    let scope = ContainerScope(personalUserIds: ["me"])
    let firstBucket = try #require(try await store.timelineBuckets(scope: scope).first)

    let start = DispatchTime.now()
    let rows = try await store.timelineAssets(scope: scope, bucketKey: firstBucket.key, limit: 200)
    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

    #expect(!rows.isEmpty)
    #expect(elapsedMs < 50, "timelineAssets took \(elapsedMs)ms, expected <50ms")
  }
}
