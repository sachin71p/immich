import CoreModel
import Foundation
import GRDB
import Rules

/// The GRDB-backed, offline-first UI store — A0 Architecture: "The local DB is the UI's only data
/// source; network fills it (sync) and the media cache." `GRDB.DatabaseQueue` is internally
/// thread-safe/`Sendable`, so `PhotosLocalStore` just wraps it plus the schema-v1 migrator (`Schema.swift`).
public final class PhotosLocalStore: Sendable {
  let dbQueue: DatabaseQueue

  /// Opens (creating if needed) the database at `path` and migrates it to schema v1.
  public init(path: String) throws {
    dbQueue = try DatabaseQueue(path: path)
    try Schema.makeMigrator().migrate(dbQueue)
  }

  /// An ephemeral, in-memory store — used by tests and previews.
  public init(inMemory: Bool = true) throws {
    dbQueue = try DatabaseQueue()
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
