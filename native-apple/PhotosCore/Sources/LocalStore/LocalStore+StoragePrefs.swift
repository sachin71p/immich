import CoreModel
import Foundation
import GRDB

extension PhotosLocalStore {
  /// A6 storage preferences, stored as JSON in the generic `userMetadata` slot under key
  /// `"storage"` (same table as `sharedLibraries`/recent-searches — no schema change).
  /// Plain `Codable`: synthesized `decodeIfPresent` defaults keep old rows decodable.
  public static let storagePrefsKey = "storage"

  public func storagePrefs(for userId: String) async throws -> StoragePrefs {
    if let json = try await metadataValue(userId: userId, key: Self.storagePrefsKey),
      let data = json.data(using: .utf8),
      let prefs = try? JSONDecoder().decode(StoragePrefs.self, from: data)
    {
      return prefs
    }
    return StoragePrefs()
  }

  public func setStoragePrefs(_ prefs: StoragePrefs, for userId: String) async throws {
    let data = try JSONEncoder().encode(prefs)
    try await setMetadataValue(String(decoding: data, as: UTF8.self), userId: userId, key: Self.storagePrefsKey)
  }

  /// Extension/agent entry points with no signed-in user id handy — first row wins,
  /// same convention as `anyPrefs()`.
  public func anyStoragePrefs() async throws -> StoragePrefs {
    try await dbQueue.read { db in
      if let json = try String.fetchOne(
        db, sql: "SELECT valueJSON FROM userMetadata WHERE key = 'storage' LIMIT 1",
        arguments: []
      ), let data = json.data(using: .utf8),
        let prefs = try? JSONDecoder().decode(StoragePrefs.self, from: data)
      {
        return prefs
      }
      return StoragePrefs()
    }
  }
}

extension PhotosLocalStore {
  /// A6 free-up-space upload matching: uploaded assets' checksums (+ server-known file
  /// sizes for the preview screen) keyed by PhotoKit local identifier. The DB only
  /// supplies the checksum — backup proof still comes from the server verifier at
  /// deletion time, never from this map alone.
  public func checksumByLocalIdentifier() async throws -> [String: String] {
    try await dbQueue.read { db in
      let rows = try Row.fetchAll(
        db, sql: "SELECT localIdentifier, checksum FROM asset WHERE localIdentifier IS NOT NULL")
      var map: [String: String] = [:]
      for row in rows {
        let identifier: String = row["localIdentifier"]
        let checksum: String = row["checksum"]
        map[identifier] = checksum
      }
      return map
    }
  }

  /// Server-known file sizes (exif `fileSizeInByte`) keyed by PhotoKit local identifier,
  /// for the free-up-space preview's byte counts. Assets without exif sizes count as 0.
  public func fileSizeByLocalIdentifier() async throws -> [String: Int] {
    try await dbQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT asset.localIdentifier AS localIdentifier, assetExif.fileSizeInByte AS fileSize
          FROM asset LEFT JOIN assetExif ON assetExif.assetId = asset.id
          WHERE asset.localIdentifier IS NOT NULL
          """)
      var map: [String: Int] = [:]
      for row in rows {
        let identifier: String = row["localIdentifier"]
        let fileSize: Int? = row["fileSize"]
        map[identifier] = fileSize ?? 0
      }
      return map
    }
  }
}
