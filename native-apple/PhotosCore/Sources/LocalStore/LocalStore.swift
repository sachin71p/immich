import CoreModel
import Foundation
import GRDB
import Rules

/// The GRDB-backed, offline-first UI store — A0 Architecture: "The local DB is the UI's only data
/// source; network fills it (sync) and the media cache." `GRDB.DatabasePool` (WAL, concurrent
/// readers) backs the store so launch grid reads run alongside the sync session's write
/// transactions instead of serializing behind them; writers keep queue semantics (a single
/// serialized writer, each `write` its own transaction), so `PhotosLocalStore` just wraps the
/// pool plus the schema migrator (`Schema.swift`). The pool is `Sendable`.
/// The accessor keeps its historic `dbQueue` name (100+ `read`/`write` call sites share the
/// `DatabaseWriter` API, which is identical on pool and queue).
public final class PhotosLocalStore: Sendable {
  let dbQueue: DatabasePool

  /// Mapped-memory budget for every pool connection (WP-F F2: the 229 MB owner DB
  /// memory-maps its read working set instead of faulting pages through `sqlite3_step`).
  public static let readerMmapSizeBytes = 268_435_456

  private static func makePool(path: String) throws -> DatabasePool {
    var configuration = Configuration()
    try configuration.prepareDatabase { db in
      try db.execute(sql: "PRAGMA mmap_size = \(readerMmapSizeBytes)")
    }
    return try DatabasePool(path: path, configuration: configuration)
  }

  /// Opens (creating if needed) the database at `path` and migrates it to the latest schema.
  /// An existing rollback-journal owner DB is converted to WAL on open (GRDB pool default).
  public init(path: String) throws {
    dbQueue = try Self.makePool(path: path)
    try Schema.makeMigrator().migrate(dbQueue)
  }

  /// An ephemeral store — used by tests and previews.
  public init(inMemory: Bool = true) throws {
    // A pool can not WAL-activate ":memory:" (SQLite refuses journal_mode=WAL there),
    // so the ephemeral store is a temp-dir file: still private per instance, fully
    // pooled, and never near the real library. The OS reclaims TMPDIR contents.
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("PhotosLocalStore-\(UUID().uuidString).sqlite")
    dbQueue = try Self.makePool(path: url.path)
    try Schema.makeMigrator().migrate(dbQueue)
  }

  /// Builds `StatementArguments` from a mix of scalar/array pieces of different `DatabaseValueConvertible`
  /// types (GRDB's own `StatementArguments(_:)` initializers require a single homogeneous `Sequence` type,
  /// which raw SQL call sites here rarely have — e.g. a `String` bucket key plus `Int` limit/offset).
  static func sqlArgs(_ parts: [any DatabaseValueConvertible]...) -> StatementArguments {
    StatementArguments(parts.flatMap { $0 })
  }

  /// Drops and recreates every table — `SyncResetV1` handling (CODEMAP §F / A1 brief task 2).
  public func wipe() async throws {
    try await dbQueue.write { db in
      for table in [
        "user", "partner", "asset", "assetExif", "album", "albumUser", "albumAsset", "stack", "space",
        "spaceMember", "library", "libraryMember", "person", "face", "memory", "memoryAsset",
        "userMetadata", "syncAck", "mediaCache", "uploadQueue", "backupChangeToken",
      ] {
        try db.execute(sql: "DELETE FROM \(table)")
      }
    }
  }
}
