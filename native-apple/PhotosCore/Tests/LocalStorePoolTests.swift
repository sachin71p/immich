import CoreModel
import Foundation
import GRDB
import Rules
import Testing
@testable import LocalStore

/// `DatabasePool` (WAL) backing for `PhotosLocalStore`: launch grid reads must run
/// concurrently with the sync session's write transactions instead of serializing behind
/// them, and an existing on-disk owner DB must open + migrate in order under the pool.
@Suite struct LocalStorePoolTests {
  /// Seeds `count` minimal asset rows via raw SQL (same fast path as
  /// `TimelinePerformanceTests.makeStore` — bypasses `apply(_:currentUserId:)` so fixture
  /// generation doesn't dominate the run).
  private static func seedAssets(into store: PhotosLocalStore, count: Int, prefix: String = "pool") throws {
    let calendar = Calendar(identifier: .gregorian)
    try store.dbQueue.write { db in
      for index in 0..<count {
        let day = calendar.date(byAdding: .hour, value: -index, to: Date())!
        try db.execute(
          sql: """
            INSERT INTO asset (
              id, ownerId, originalFileName, checksum, type, isFavorite, visibility, isEdited,
              localDateTime, createdAt, width, height
            ) VALUES (?, 'me', ?, ?, 'IMAGE', 0, 'timeline', 0, ?, ?, 100, 100)
            """,
          arguments: ["\(prefix)-\(index)", "IMG_\(prefix)_\(index).heic", "chk-\(prefix)-\(index)", day, day]
        )
      }
    }
  }

  @Test("[pool] 100k-scale grid read overlaps a held sync write txn instead of serializing behind it")
  func concurrentReadDuringWrite() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    try Self.seedAssets(into: store, count: 100_000)
    let scope = ContainerScope(personalUserIds: ["me"])

    // Launch-shaped writer: the sync session holds ONE write transaction open ~6 s
    // applying server batches. On `DatabaseQueue` every reader serializes behind it;
    // on the WAL pool readers proceed on a snapshot. A task group (not shared `var`s)
    // carries the writer's timestamps back, keeping every closure `@Sendable`.
    // The hold is deliberately long (6 s vs a ~1 s unloaded read) so the overlap
    // assertion survives full-suite parallel load, which starves timing-sensitive tests.
    let t0 = DispatchTime.now()
    func ms(_ t: DispatchTime) -> Double {
      Double(t.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
    }
    var rows: [TimelineRow] = []
    var readStartMs = 0.0
    var readEndMs = 0.0
    let writeEndMs = try await withThrowingTaskGroup(of: Double.self) { group in
      group.addTask {
        try await store.dbQueue.write { db in
          for batch in 0..<12 {
            try db.execute(
              sql: """
                INSERT INTO asset (
                  id, ownerId, originalFileName, checksum, type, isFavorite, visibility, isEdited,
                  localDateTime, createdAt, width, height
                ) VALUES (?, 'me', ?, ?, 'IMAGE', 0, 'timeline', 0, ?, ?, 100, 100)
                """,
              arguments: [
                "sync-batch-\(batch)", "SYNC_\(batch).heic", "chk-sync-\(batch)", Date(), Date(),
              ]
            )
            Thread.sleep(forTimeInterval: 0.5)
          }
        }
        // Inline (not via local `ms`): the task closure must capture only `Sendable` state.
        return Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
      }
      // Let the writer take the write lock first, then run the launch grid read.
      try await Task.sleep(nanoseconds: 300_000_000)
      readStartMs = ms(DispatchTime.now())
      rows = try await store.timelineRows(scope: scope)
      readEndMs = ms(DispatchTime.now())
      return try await group.next() ?? -1
    }

    #expect(rows.count >= 100_000, "expected the seeded 100k rows, got \(rows.count)")
    #expect(writeEndMs >= 5_500, "writer should have held the txn ~6 s, held \(writeEndMs)ms")
    // The read must have finished while the writer still held its transaction (with
    // 1 s margin) — on a serialized queue it would end strictly after `writeEndMs`.
    #expect(
      readEndMs + 1000 < writeEndMs,
      "grid read overlapped the write txn by only \(writeEndMs - readEndMs)ms (read \(readEndMs - readStartMs)ms, write held \(writeEndMs)ms)")
  }

  /// Builds a legacy owner DB the way v1 shipped it: file-backed `DatabaseQueue`,
  /// migrated only up to v3, holding raw millisecond durations, in rollback-journal mode.
  private static func buildLegacyDB(at path: String) throws {
    let legacy = try DatabaseQueue(path: path)
    let migrator = Schema.makeMigrator()
    try migrator.migrate(legacy, upTo: "v3_timeline_cover_index")
    try legacy.write { db in
      try db.execute(
        sql: "INSERT INTO asset (id, ownerId, originalFileName, checksum, type, durationSeconds) VALUES ('v1', 'u1', 'a.mp4', 'c1', 'VIDEO', 90000)")
      try db.execute(
        sql: "INSERT INTO asset (id, ownerId, originalFileName, checksum, type) VALUES ('s1', 'u1', 'c.jpg', 'c3', 'IMAGE')")
      // Pre-WAL owner file: the pool must convert journal mode on open.
      try db.execute(sql: "PRAGMA journal_mode=DELETE")
    }
    // `legacy` deallocates (closing the file) on scope exit so the pool can take over.
  }

  @Test("[pool] existing on-disk owner DB opens under the pool: WAL, data kept, migrations in order")
  func onDiskOpenMigratesInOrder() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("owner.sqlite").path
    try Self.buildLegacyDB(at: path)

    let store = try PhotosLocalStore(path: path)
    let journalMode: String? = try store.dbQueue.read { db in
      try String.fetchOne(db, sql: "PRAGMA journal_mode")
    }
    #expect(journalMode?.lowercased() == "wal", "expected WAL journal mode, got \(journalMode ?? "nil")")

    let (count, v1, s1): (Int?, Int?, Int?) = try store.dbQueue.read { db in
      (
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM asset"),
        try Int.fetchOne(db, sql: "SELECT durationSeconds FROM asset WHERE id = 'v1'"),
        try Int.fetchOne(db, sql: "SELECT durationSeconds FROM asset WHERE id = 's1'")
      )
    }
    #expect(count == 2, "legacy rows must survive the pool open")
    #expect(v1 == 90, "v4 migration must still apply in order (90000ms -> 90s), got \(v1 ?? -1)")
    #expect(s1 == nil, "NULL durations stay NULL")

    // Migration order on the converted file must equal a fresh pool-created DB's.
    let fresh = try PhotosLocalStore(inMemory: true)
    func applied(_ store: PhotosLocalStore) throws -> [String] {
      try store.dbQueue.read { db in
        try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
      }
    }
    #expect(try applied(store) == applied(fresh), "converted DB migrations must match fresh order")

    // The pool owns the file: writes work after conversion.
    try store.dbQueue.write { db in
      try db.execute(
        sql: "INSERT INTO asset (id, ownerId, originalFileName, checksum, type) VALUES ('post', 'u1', 'd.jpg', 'c4', 'IMAGE')")
    }
    let postCount: Int? = try store.dbQueue.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM asset")
    }
    #expect(postCount == 3)
  }
}
