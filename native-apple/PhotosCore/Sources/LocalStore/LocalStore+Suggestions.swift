import CoreModel
import Foundation
import GRDB
import Rules

/// Local-first search suggestions (WP5 S2a).
///
/// Server `search/suggestions` returns `[]` whenever the app is offline or in fixture
/// mode, which left the Places/Camera/Lens/File-type chips reading "No suggestions".
/// These queries serve the same chips from the on-device exif mirror instead, scoped
/// to the caller's timeline scope. The server stays as a fallback for the empty-local
/// case only (see `SearchSuggestions` in the iOS app).
extension PhotosLocalStore {
  /// Distinct non-blank cities present in scope, most-photographed first.
  public func distinctCities(scope: ContainerScope, limit: Int = 50) async throws -> [String] {
    let (whereSQL, args) = Self.scopeWhereValues(scope)
    return try await dbQueue.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT assetExif.city FROM asset
          JOIN assetExif ON assetExif.assetId = asset.id
          WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked'
            AND assetExif.city IS NOT NULL AND trim(assetExif.city) != '' AND \(whereSQL)
          GROUP BY assetExif.city COLLATE NOCASE
          ORDER BY COUNT(*) DESC, assetExif.city COLLATE NOCASE LIMIT ?
          """,
        arguments: Self.sqlArgs(args, [limit])
      )
    }
  }

  /// Distinct non-blank lens models present in scope, most-photographed first.
  public func distinctLensModels(scope: ContainerScope, limit: Int = 50) async throws -> [String] {
    let (whereSQL, args) = Self.scopeWhereValues(scope)
    return try await dbQueue.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT assetExif.lensModel FROM asset
          JOIN assetExif ON assetExif.assetId = asset.id
          WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked'
            AND assetExif.lensModel IS NOT NULL AND trim(assetExif.lensModel) != '' AND \(whereSQL)
          GROUP BY assetExif.lensModel COLLATE NOCASE
          ORDER BY COUNT(*) DESC, assetExif.lensModel COLLATE NOCASE LIMIT ?
          """,
        arguments: Self.sqlArgs(args, [limit])
      )
    }
  }

  /// Distinct lowercase file extensions present in scope (`originalFileName` suffix after
  /// the last `.`), most common first. Files without an extension are skipped.
  public func distinctFileExtensions(scope: ContainerScope, limit: Int = 50) async throws -> [String] {
    let (whereSQL, args) = Self.scopeWhereValues(scope)
    return try await dbQueue.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT LOWER(SUBSTR(asset.originalFileName, INSTR(asset.originalFileName, '.') + 1)) AS ext FROM asset
          WHERE asset.deletedAt IS NULL AND asset.visibility != 'locked'
            AND INSTR(asset.originalFileName, '.') > 0 AND \(whereSQL)
          GROUP BY ext
          ORDER BY COUNT(*) DESC, ext LIMIT ?
          """,
        arguments: Self.sqlArgs(args, [limit])
      )
    }
  }

  /// Named people for the owner, A–Z. Unnamed rows are excluded: face/person sync can
  /// leave person rows with empty names and zero assets (WP4 owns that C1a sync gap),
  /// and a blank chip is never a useful suggestion.
  public func namedPeople(forOwner ownerId: String) async throws -> [Person] {
    try await dbQueue.read { db in
      try PersonRecord
        .filter(sql: "ownerId = ? AND name IS NOT NULL AND trim(name) != ''", arguments: [ownerId])
        .order(Column("name"))
        .fetchAll(db)
        .map(\.model)
    }
  }
}
