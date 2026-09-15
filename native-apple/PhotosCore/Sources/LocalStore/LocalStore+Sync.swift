import CoreModel
import GRDB

/// Sync-engine support reads/writes that don't belong in `apply(_:currentUserId:)` because they're not
/// themselves sync-stream lines: the resume checkpoints sent back on reconnect, and the (currently
/// unreachable — see below) `library.uploadPath` hydration.
extension PhotosLocalStore {
  /// Every stored `"type|updateId|extraId"` checkpoint, one per `SyncEntityType` — sent back verbatim as
  /// `SyncAckSetDto.acks` so the server resumes each stream where this device left off. CODEMAP §F.
  public func allSyncAcks() async throws -> [String] {
    try await dbQueue.read { db in
      try String.fetchAll(db, sql: "SELECT ack FROM syncAck")
    }
  }

  /// `SyncResetV1` / a fresh login: drop every stored checkpoint so the next stream starts from scratch.
  public func clearSyncAcks() async throws {
    try await dbQueue.write { db in
      try db.execute(sql: "DELETE FROM syncAck")
    }
  }

  /// Not called by `SyncEngine` yet — no generated operation currently returns `uploadPath` at all (the
  /// checked-out OpenAPI spec's `LibraryResponseDto` doesn't have the field; A1 handoff open issue).
  /// `Rules.MoveTargets` conservatively never offers a library as a move target until this is set, which
  /// is the same outcome as "we don't know", so the schema column stays for whenever a future phase's
  /// regenerated spec exposes it.
  public func setLibraryUploadPath(libraryId: String, uploadPath: String?) async throws {
    try await dbQueue.write { db in
      try db.execute(
        sql: "UPDATE library SET uploadPath = ?, uploadPathHydrated = 1 WHERE id = ?",
        arguments: [uploadPath, libraryId]
      )
    }
  }

  public func libraryIdsMissingUploadPathHydration() async throws -> [String] {
    try await dbQueue.read { db in
      try String.fetchAll(db, sql: "SELECT id FROM library WHERE uploadPathHydrated = 0")
    }
  }
}
