import CoreModel
import Foundation
import GRDB
import Rules
import Testing
@testable import LocalStore

/// WP-F F2 (query plans, grid projection) + F4 (filter pages use SQL-side indexes).
///
/// Red-first: on the pre-fix schema/projection this suite fails —
/// `rowSelectSQL` joins `assetExif`, the timeline-shaped query SCANs `asset`,
/// and reader connections report `mmap_size == 0`.
struct TimelineQueryPlanTests {
  private static func makeStore(assetCount: Int) async throws -> PhotosLocalStore {
    let store = try PhotosLocalStore(inMemory: true)
    try await store.dbQueue.write { db in
      let base = Date(timeIntervalSince1970: 1_700_000_000)
      for index in 0..<assetCount {
        let day = base.addingTimeInterval(Double(-index * 3600))
        let type = index % 5 == 0 ? "VIDEO" : "IMAGE"
        let favorite = index % 10 == 0 ? 1 : 0
        try db.execute(
          sql: """
            INSERT INTO asset (
              id, ownerId, originalFileName, checksum, type, isFavorite, visibility, isEdited,
              localDateTime, createdAt, width, height
            ) VALUES (?, 'me', ?, ?, ?, ?, 'timeline', 0, ?, ?, 4000, 3000)
            """,
          arguments: ["asset-\(index)", "IMG_\(index).heic", "chk-\(index)", type, favorite, day, day]
        )
        if index % 25 == 0 {
          try db.execute(
            sql: "INSERT INTO albumAsset (albumId, assetId) VALUES ('album-1', ?)",
            arguments: ["asset-\(index)"])
        }
      }
      try db.execute(sql: "ANALYZE")
    }
    return store
  }

  /// EXPLAIN QUERY PLAN detail lines for `sql` on `store`.
  private static func plan(_ store: PhotosLocalStore, _ sql: String) async throws -> [String] {
    try await store.dbQueue.read { db in
      try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN \(sql)").map { row in
        let detail: String = row["detail"]
        return detail
      }
    }
  }

  /// A bare table scan (`SCAN asset` with no `USING …`): an index scan
  /// (`SCAN asset USING INDEX …`) is index-served and allowed.
  private static func hasBareAssetScan(_ details: [String]) -> Bool {
    details.contains { $0.contains("SCAN asset") && !$0.contains("USING") }
  }

  private static func timelineShapedSQL() -> String {
    """
      \(PhotosLocalStore.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked'
        AND (asset.spaceId IS NULL AND asset.libraryId IS NULL AND asset.ownerId IN ('me'))
      ORDER BY asset.localDateTime DESC LIMIT 200
      """
  }

  @Test("[F2] grid projection has no assetExif join")
  func gridProjectionHasNoExifJoin() {
    #expect(!PhotosLocalStore.rowSelectSQL.contains("assetExif"))
  }

  @Test("[F2] panorama media-kind still classifies without the exif join")
  func panoramaClassifiesViaDenormalizedColumn() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let alice = "user-alice"
    try await store.apply(
      [
        .user(User(id: alice, name: "Alice", email: "alice@example.com")),
        .asset(
          Asset(
            id: "pano-1", ownerId: alice, originalFileName: "PANO_1.JPG", checksum: "c1",
            localDateTime: date, type: .image, width: 8000, height: 2000)),
        .assetExif(AssetExif(assetId: "pano-1", projectionType: "equirectangular")),
      ], currentUserId: alice)
    let rows = try await store.timelineRows(scope: ContainerScope(personalUserIds: [alice]))
    #expect(rows.count == 1)
    #expect(rows.first?.mediaKind == .panorama)
  }

  @Test("[F2] exif-before-asset batches still denormalize via batch repair")
  func exifBeforeAsset() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let alice = "user-alice"
    try await store.apply(
      [.user(User(id: alice, name: "Alice", email: "alice@example.com"))],
      currentUserId: alice)
    // Exif lands a batch before its asset row (backfill ordering).
    try await store.apply(
      [.assetExif(AssetExif(assetId: "pano-9", projectionType: "equirectangular"))],
      currentUserId: alice)
    try await store.apply(
      [
        .asset(
          Asset(
            id: "pano-9", ownerId: alice, originalFileName: "PANO_9.JPG", checksum: "c9",
            localDateTime: date, type: .image, width: 8000, height: 2000))
      ], currentUserId: alice)
    let rows = try await store.timelineRows(scope: ContainerScope(personalUserIds: [alice]))
    #expect(rows.first?.mediaKind == .panorama)
  }

  @Test("[F2] timeline-shaped query uses an index, never SCANs asset")
  func timelineQueryUsesIndex() async throws {
    let store = try await Self.makeStore(assetCount: 5_000)
    let details = try await Self.plan(store, Self.timelineShapedSQL())
    #expect(!details.isEmpty)
    #expect(!Self.hasBareAssetScan(details), "\(details)")
    #expect(
      details.contains(where: { $0.contains("asset_timeline") }),
      "expected the F2 covering index asset_timeline* in \(details)")
  }

  @Test("[F2/F4] filter queries (favorites, media-kind, album, visibility) use indexes")
  func filterQueriesUseIndexes() async throws {
    let store = try await Self.makeStore(assetCount: 5_000)
    let scope = "(asset.spaceId IS NULL AND asset.libraryId IS NULL AND asset.ownerId IN ('me'))"
    let queries = [
      """
      \(PhotosLocalStore.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND asset.isFavorite = 1 AND \(scope)
      ORDER BY asset.localDateTime DESC LIMIT 200
      """,
      """
      \(PhotosLocalStore.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND asset.type = 'VIDEO' AND \(scope)
      ORDER BY asset.localDateTime DESC LIMIT 200
      """,
      """
      \(PhotosLocalStore.rowSelectSQL)
      JOIN albumAsset ON albumAsset.assetId = asset.id AND albumAsset.albumId = 'album-1'
      WHERE asset.deletedAt IS NULL
      ORDER BY asset.localDateTime DESC LIMIT 200
      """,
    ]
    for sql in queries {
      let details = try await Self.plan(store, sql)
      #expect(!Self.hasBareAssetScan(details), "\(details)")
      #expect(
        details.contains(where: { $0.contains("asset_timeline") || $0.contains("albumAsset") }),
        "expected an F2 index (asset_timeline*/albumAsset_on_albumId) in \(details)")
    }
  }

  @Test("[F2] reader connections use a 256MB mmap")
  func readerMmapSize() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    let mmap = try await store.dbQueue.read { db in
      try Int.fetchOne(db, sql: "PRAGMA mmap_size") ?? 0
    }
    #expect(mmap == 268_435_456)
  }

  @Test("[F2] perf migration is idempotent and additive")
  func migrationIdempotentAndAdditive() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let alice = "user-alice"
    try await store.apply(
      [
        .user(User(id: alice, name: "Alice", email: "alice@example.com")),
        .asset(
          Asset(
            id: "keep-1", ownerId: alice, originalFileName: "IMG_1.HEIC", checksum: "c1",
            localDateTime: date, type: .image)),
      ], currentUserId: alice)
    // Re-running the migrator (as a second launch would) is a no-op and keeps data.
    try Schema.makeMigrator().migrate(store.dbQueue)
    try Schema.makeMigrator().migrate(store.dbQueue)
    let rows = try await store.timelineRows(scope: ContainerScope(personalUserIds: [alice]))
    #expect(rows.count == 1)
  }
}
