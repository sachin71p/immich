import CoreModel
import Foundation
import GRDB
import Rules

/// WP6 slice A (People + Memories): read-only person-timeline queries.
///
/// Face-link finding: the asset↔person link EXISTS locally — the `face` table
/// (`face.personId` → `face.assetId`, migration `v1_people_faces` in
/// Schema.swift, indexed by `face_on_assetId`), synced from the server people
/// endpoints. No server `/people` fallback is needed, and no rename control is
/// added: the API client has no `updatePerson`.
extension PhotosLocalStore {
  /// Non-trashed, non-locked rows whose visible faces belong to `personId`,
  /// newest first, additionally restricted to `scope` so the person detail
  /// honors the library switcher like every other destination.
  public func personAssets(personId: String, scope: ContainerScope, limit: Int = 2000) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      \(Self.rowSelectSQL)
      JOIN face ON face.assetId = asset.id
      WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked'
        AND face.personId = ? AND face.isVisible = 1 AND face.deletedAt IS NULL
        AND \(whereSQL)
      ORDER BY asset.localDateTime DESC
      LIMIT ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs([personId], args, [limit])).map(Self.row)
    }
  }

  /// Rows for an explicit id list (Memories "Show all photos"), newest first.
  public func timelineRows(ids: [String], limit: Int = 2000) async throws -> [TimelineRow] {
    guard !ids.isEmpty else { return [] }
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.id IN (\(ids.map { _ in "?" }.joined(separator: ",")))
      ORDER BY asset.localDateTime DESC
      LIMIT ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(ids, [limit])).map(Self.row)
    }
  }
}
