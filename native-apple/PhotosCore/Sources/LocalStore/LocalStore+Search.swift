import CoreModel
import Foundation
import GRDB
import Rules

/// Offline instant filtering over the `asset` + `assetExif` mirror (A7 task 3) plus the generic
/// `userMetadata` string slot the Search module's recent-searches store persists through.
/// Same `TimelineRow` projection as every other grid (`rowSelectSQL` / `row(from:)`), so search
/// results drop straight into the A3/A4 grids. Set filter fields AND together; the container
/// scope ANDs with them via `scopeWhere`.
extension PhotosLocalStore {
  /// Filtered rows inside `scope`, newest first. Excludes trashed and locked assets (locked has
  /// its own screen — same rule as the timeline queries).
  public func filterAssets(
    _ filter: LocalAssetFilter, scope: ContainerScope, limit: Int = 200, offset: Int = 0
  ) async throws -> [TimelineRow] {
    let (whereSQL, args) = Self.scopeWhere(scope)
    var clauses = ["asset.deletedAt IS NULL", "asset.visibility != 'locked'", whereSQL]
    var stringArgs: [String] = args
    var mixedArgs: [any DatabaseValueConvertible] = []

    func add(_ clause: String, _ values: [any DatabaseValueConvertible] = []) {
      clauses.append(clause)
      mixedArgs += values
    }

    if let make = filter.make { add("assetExif.make = ?", [make]) }
    if let model = filter.model { add("assetExif.model = ?", [model]) }
    if let lens = filter.lensModel { add("assetExif.lensModel = ?", [lens]) }
    if let city = filter.city { add("assetExif.city = ?", [city]) }
    if let state = filter.state { add("assetExif.state = ?", [state]) }
    if let country = filter.country { add("assetExif.country = ?", [country]) }
    if let min = filter.isoMin { add("assetExif.iso >= ?", [min]) }
    if let max = filter.isoMax { add("assetExif.iso <= ?", [max]) }
    if let min = filter.fNumberMin { add("assetExif.fNumber >= ?", [min]) }
    if let max = filter.fNumberMax { add("assetExif.fNumber <= ?", [max]) }
    if let min = filter.focalLengthMin { add("assetExif.focalLength >= ?", [min]) }
    if let max = filter.focalLengthMax { add("assetExif.focalLength <= ?", [max]) }
    // Exif stores exposure as text ("1/125"); compare in seconds, mirroring the S7 server
    // fraction handling. Unparseable values CAST to 0.0/NULL and never match a range bound.
    if filter.exposureTimeMin != nil || filter.exposureTimeMax != nil {
      let seconds = """
        CASE WHEN assetExif.exposureTime LIKE '%/%'
          THEN CAST(substr(assetExif.exposureTime, 1, instr(assetExif.exposureTime, '/') - 1) AS REAL) /
            NULLIF(CAST(substr(assetExif.exposureTime, instr(assetExif.exposureTime, '/') + 1) AS REAL), 0)
          ELSE CAST(assetExif.exposureTime AS REAL) END
        """
      if let min = filter.exposureTimeMin { add("\(seconds) >= ?", [min]) }
      if let max = filter.exposureTimeMax { add("\(seconds) <= ?", [max]) }
    }
    if let min = filter.fileSizeMin { add("assetExif.fileSizeInByte >= ?", [min]) }
    if let max = filter.fileSizeMax { add("assetExif.fileSizeInByte <= ?", [max]) }
    if let min = filter.widthMin { add("asset.width >= ?", [min]) }
    if let min = filter.heightMin { add("asset.height >= ?", [min]) }
    let extensions = Self.filenameExtensions(for: filter)
    if !extensions.isEmpty {
      let orClause = extensions.map { _ in "LOWER(asset.originalFileName) LIKE ?" }.joined(separator: " OR ")
      add("(\(orClause))", extensions.map { "%.\($0.lowercased())" })
    }
    if let projection = filter.projectionType { add("assetExif.projectionType = ?", [projection]) }
    if let hasLocation = filter.hasLocation {
      clauses.append(
        hasLocation
          ? "assetExif.latitude IS NOT NULL AND assetExif.longitude IS NOT NULL"
          : "(assetExif.latitude IS NULL OR assetExif.longitude IS NULL)")
    }
    if let orientation = filter.orientation { add("assetExif.orientation = ?", [orientation]) }
    if let min = filter.fpsMin { add("assetExif.fps >= ?", [min]) }
    if let max = filter.fpsMax { add("assetExif.fps <= ?", [max]) }
    if let rating = filter.rating { add("assetExif.rating = ?", [rating]) }
    if let kind = filter.mediaType { add("asset.type = ?", [kind.rawValue]) }
    if let favorite = filter.isFavorite { add("asset.isFavorite = ?", [favorite]) }
    if let after = filter.takenAfter { add("asset.localDateTime >= ?", [after]) }
    if let before = filter.takenBefore { add("asset.localDateTime <= ?", [before]) }
    if let personIds = filter.personIds, !personIds.isEmpty {
      let placeholders = personIds.map { _ in "?" }.joined(separator: ",")
      add(
        """
        EXISTS (SELECT 1 FROM face WHERE face.assetId = asset.id AND face.personId IN (\(placeholders))
          AND face.isVisible = 1 AND face.deletedAt IS NULL)
        """, personIds)
    }

    // WP-F F2: the grid projection no longer joins `assetExif` (hot-path removal),
    // so search adds its own explicit join — but only when an exif predicate is
    // present; pure asset-column searches stay on the join-free fast path.
    let needsExifJoin =
      filter.make != nil || filter.model != nil || filter.lensModel != nil || filter.city != nil
      || filter.state != nil || filter.country != nil || filter.isoMin != nil || filter.isoMax != nil
      || filter.fNumberMin != nil || filter.fNumberMax != nil || filter.focalLengthMin != nil
      || filter.focalLengthMax != nil || filter.exposureTimeMin != nil || filter.exposureTimeMax != nil
      || filter.fileSizeMin != nil || filter.fileSizeMax != nil || filter.projectionType != nil
      || filter.hasLocation != nil || filter.orientation != nil || filter.fpsMin != nil
      || filter.fpsMax != nil || filter.rating != nil
    let exifJoin =
      needsExifJoin ? "LEFT JOIN assetExif ON assetExif.assetId = asset.id" : ""
    let sql = """
      \(Self.rowSelectSQL)
      \(exifJoin)
      WHERE \(clauses.joined(separator: " AND "))
      ORDER BY asset.localDateTime DESC
      LIMIT ? OFFSET ?
      """
    let sqlArgs = Self.sqlArgs(stringArgs, mixedArgs, [limit, offset])
    return try await dbQueue.read { db in
      try Row.fetchAll(db, sql: sql, arguments: sqlArgs).map(Self.row(from:))
    }
  }

  /// The mirror has no MIME column, so `mimeTypes` degrade to filename-suffix matching through
  /// this table, OR-ed with explicit `fileExtensions`. A MIME with no known suffixes is dropped
  /// (server search covers it online); documented here so the gap is visible, not silent.
  static func filenameExtensions(for filter: LocalAssetFilter) -> [String] {
    var out = filter.fileExtensions ?? []
    for mime in filter.mimeTypes ?? [] {
      out += Self.extensionsByMime[mime.lowercased()] ?? []
    }
    return Array(Set(out))
  }

  private static let extensionsByMime: [String: [String]] = [
    "image/jpeg": ["jpg", "jpeg"],
    "image/png": ["png"],
    "image/heic": ["heic"],
    "image/heif": ["heif", "heic"],
    "image/webp": ["webp"],
    "image/gif": ["gif"],
    "image/tiff": ["tif", "tiff"],
    "image/dng": ["dng"],
    "image/x-sony-arw": ["arw"],
    "image/x-canon-cr2": ["cr2"],
    "image/x-nikon-nef": ["nef"],
    "video/mp4": ["mp4"],
    "video/quicktime": ["mov"],
    "video/x-msvideo": ["avi"],
    "video/webm": ["webm"],
    "video/x-matroska": ["mkv"],
    "audio/mpeg": ["mp3"],
    "audio/mp4": ["m4a"],
    "audio/x-wav": ["wav"],
  ]

  // MARK: - generic userMetadata string slot (recent searches)

  /// Raw `valueJSON` for an app-defined `userMetadata` key (e.g. recent searches) — the table
  /// stores opaque JSON so LocalStore never learns the Search module's shapes.
  public func metadataValue(userId: String, key: String) async throws -> String? {
    try await dbQueue.read { db in
      try String.fetchOne(
        db, sql: "SELECT valueJSON FROM userMetadata WHERE userId = ? AND key = ?",
        arguments: [userId, key])
    }
  }

  public func setMetadataValue(_ value: String, userId: String, key: String) async throws {
    try await dbQueue.write { db in
      try UserMetadataRecord(userId: userId, key: key, valueJSON: value).save(db)
    }
  }
}
