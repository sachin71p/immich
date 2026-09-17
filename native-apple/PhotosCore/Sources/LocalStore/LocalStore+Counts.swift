import CoreModel
import Foundation
import GRDB
import Rules

/// WP6 slice B (Collections): cheap `COUNT(*)` queries for the Collections shelves.
///
/// Every count mirrors its destination's row predicate (same `WHERE` the grid query
/// uses), so a tile count of N always means "N items when you navigate there".
/// All counts run on the GRDB reader thread via `dbQueue.read` — callers still
/// invoke them off the main actor and cache until `timelineVersion` changes.
extension PhotosLocalStore {
  /// Per-kind counts for the Media Types shelf, in ONE query: `GROUP BY` the same
  /// `mediaKindCaseSQL` the row projection uses, with the exact predicate of the
  /// `assets(scope:mediaKind:)` destination (`deletedAt IS NULL`, no visibility
  /// filter), so a tile count always equals the navigated grid's size.
  /// NOTE: that predicate includes hidden/locked assets — the grid shows them too
  /// (TimelineRow carries no hidden flag). Flagged for the orchestrator; not changed
  /// here (existing PhotosCore files are read-only for WP6).
  /// (Selfies/live/portrait/screenshots/screen-recordings are filename-derived in
  /// `mediaAssets`, but every one of those filenames classifies as `.photo` here —
  /// the shelf counts by grid kind, which is what the Photos/Media tiles open.)
  public func mediaKindCounts(scope: ContainerScope) async throws -> [TimelineMediaKind: Int] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      SELECT \(Self.mediaKindCaseSQL) AS mediaKind, COUNT(*) AS n
      FROM asset
      JOIN (
        SELECT id FROM asset
        WHERE id NOT IN (SELECT livePhotoVideoId FROM asset WHERE livePhotoVideoId IS NOT NULL)
      ) AS visibleAsset ON visibleAsset.id = asset.id
      LEFT JOIN assetExif ON assetExif.assetId = asset.id
      WHERE asset.deletedAt IS NULL AND \(whereSQL)
      GROUP BY mediaKind
      """
    return try await dbQueue.read { db in
      var counts: [TimelineMediaKind: Int] = [:]
      for row in try Row.fetchAll(db, sql: sql, arguments: Self.sqlArgs(args)) {
        guard let kindString: String = row["mediaKind"],
          let kind = TimelineMediaKind(rawValue: kindString),
          let n: Int = row["n"]
        else { continue }
        counts[kind] = n
      }
      return counts
    }
  }

  /// Filename/classification counts for the Media Types shelf tiles that open a
  /// `NativeMediaCollection` — the exact predicate `mediaAssets` uses for that
  /// collection (same `WHERE`, same scope), so tile and grid agree.
  public func nativeCollectionCount(
    scope: ContainerScope, collection: NativeMediaCollection
  ) async throws -> Int {
    let predicate: String
    switch collection {
    case .videos: predicate = "asset.type = 'VIDEO'"
    case .selfies: predicate = "lower(asset.originalFileName) LIKE '%selfie%'"
    case .livePhotos: predicate = "asset.livePhotoVideoId IS NOT NULL"
    case .portraits: predicate = "lower(asset.originalFileName) LIKE '%portrait%'"
    case .screenshots: predicate = "lower(asset.originalFileName) LIKE 'screenshot%'"
    case .screenRecordings:
      predicate =
        "asset.type = 'VIDEO' AND (lower(asset.originalFileName) LIKE 'screen recording%' OR lower(asset.originalFileName) LIKE 'screenrecording%')"
    }
    return try await scalarCount(
      scope: scope,
      predicate:
        "asset.deletedAt IS NULL AND asset.visibility != 'locked' AND \(predicate)")
  }

  /// Favorites tile — same predicate as `favoriteAssets`.
  public func favoriteCount(scope: ContainerScope) async throws -> Int {
    try await scalarCount(
      scope: scope, predicate: "asset.deletedAt IS NULL AND asset.isFavorite = 1")
  }

  /// Recently Saved + Imports tiles — both destinations serve `recentAssets`, so one
  /// count covers both (same `createdAt`-ordered predicate, no limit).
  public func recentCount(scope: ContainerScope) async throws -> Int {
    try await scalarCount(
      scope: scope,
      predicate: "asset.deletedAt IS NULL AND asset.visibility != 'locked'")
  }

  /// Hidden tile — same predicate as `hiddenAssets`.
  public func hiddenCount(scope: ContainerScope) async throws -> Int {
    try await scalarCount(
      scope: scope, predicate: "asset.deletedAt IS NULL AND asset.visibility = 'hidden'")
  }

  /// Recently Deleted tile — same predicate as `trashedAssets`.
  public func trashCount(scope: ContainerScope) async throws -> Int {
    try await scalarCount(scope: scope, predicate: "asset.deletedAt IS NOT NULL")
  }

  /// Map pin tile — same predicate as `locatedAssetPoints` (every located asset, no limit).
  public func locatedCount(scope: ContainerScope) async throws -> Int {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      SELECT COUNT(*) AS n FROM asset
      JOIN assetExif ON assetExif.assetId = asset.id
      WHERE asset.deletedAt IS NULL AND assetExif.latitude IS NOT NULL
        AND assetExif.longitude IS NOT NULL AND \(whereSQL)
      """
    return try await dbQueue.read { db in
      (try Int.fetchOne(db, sql: sql, arguments: Self.sqlArgs(args))) ?? 0
    }
  }

  /// Captured-by-Me tile — same predicate as `capturedByUser` (owner-based, not
  /// container-based: a photo stays "mine" after sharing or moving).
  public func capturedByMeCount(userId: String, scope: ContainerScope) async throws -> Int {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = """
      SELECT COUNT(*) AS n FROM asset
      WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked'
        AND asset.ownerId = ? AND \(whereSQL)
      """
    return try await dbQueue.read { db in
      (try Int.fetchOne(db, sql: sql, arguments: Self.sqlArgs([userId], args))) ?? 0
    }
  }

  /// Archive tile — same predicate as `visibilityAssets(.archive)`.
  public func archiveCount(scope: ContainerScope) async throws -> Int {
    try await scalarCount(
      scope: scope, predicate: "asset.deletedAt IS NULL AND asset.visibility = 'archive'")
  }

  /// Locked tile — same predicate as `lockedAssets` (personal-only by design:
  /// ignores scope and restricts to the signed-in user's own assets).
  public func lockedCount(userId: String) async throws -> Int {
    let sql = """
      SELECT COUNT(*) AS n FROM asset
      WHERE asset.deletedAt IS NULL AND asset.visibility = 'locked'
        AND asset.spaceId IS NULL AND asset.libraryId IS NULL AND asset.ownerId = ?
      """
    return try await dbQueue.read { db in
      (try Int.fetchOne(db, sql: sql, arguments: [userId])) ?? 0
    }
  }

  /// One `COUNT(*)` over `asset` with the caller's scope. The `visibleAsset` join is
  /// intentionally omitted (unlike the media-kind query): favorites/recents/hidden/
  /// trash predicates match their row queries, which don't filter live-photo members.
  private func scalarCount(scope: ContainerScope, predicate: String) async throws -> Int {
    let (whereSQL, args) = Self.scopeWhere(scope)
    let sql = "SELECT COUNT(*) AS n FROM asset WHERE \(predicate) AND \(whereSQL)"
    return try await dbQueue.read { db in
      (try Int.fetchOne(db, sql: sql, arguments: Self.sqlArgs(args))) ?? 0
    }
  }
}
