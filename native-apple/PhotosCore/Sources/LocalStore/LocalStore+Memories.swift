import CoreModel
import Foundation
import GRDB
import Rules

/// A9.3 queries: memory contents + "On this day" (client-computed from capture dates).
extension PhotosLocalStore {
  /// Asset ids linked to one memory, in link order (backed by `memoryAsset`).
  public func assetIds(forMemory memoryId: String) async throws -> [String] {
    try await dbQueue.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT assetId FROM memoryAsset WHERE memoryId = ?",
        arguments: [memoryId]
      )
    }
  }

  /// Non-trashed, non-locked assets in scope captured on `month`/`day` in any year —
  /// the "On this day" shelf. Ordered newest-first by capture time.
  public func onThisDayAssets(
    scope: ContainerScope, month: Int, day: Int, limit: Int = 200
  ) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let monthKey = String(format: "%02d", month)
    let dayKey = String(format: "%02d", day)
    let sql = """
      \(Self.rowSelectSQL)
      WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked'
        AND strftime('%m', asset.localDateTime) = ? AND strftime('%d', asset.localDateTime) = ?
        AND \(whereSQL)
      ORDER BY asset.localDateTime DESC
      LIMIT ?
      """
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs([monthKey, dayKey], args, [limit]))
        .map(Self.row)
    }
  }
}
