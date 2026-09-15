import CoreModel
import Foundation
import GRDB

struct MemoryRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "memory"

  var id: String
  var createdAt: Date
  var updatedAt: Date
  var deletedAt: Date?
  var ownerId: String
  var type: String
  var dataJSON: String
  var isSaved: Bool
  var memoryAt: Date
  var seenAt: Date?
  var showAt: Date?
  var hideAt: Date?

  init(_ memory: Memory) {
    id = memory.id
    createdAt = memory.createdAt
    updatedAt = memory.updatedAt
    deletedAt = memory.deletedAt
    ownerId = memory.ownerId
    type = memory.type
    dataJSON = memory.dataJSON
    isSaved = memory.isSaved
    memoryAt = memory.memoryAt
    seenAt = memory.seenAt
    showAt = memory.showAt
    hideAt = memory.hideAt
  }

  var model: Memory {
    Memory(
      id: id, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, ownerId: ownerId, type: type,
      dataJSON: dataJSON, isSaved: isSaved, memoryAt: memoryAt, seenAt: seenAt, showAt: showAt, hideAt: hideAt
    )
  }
}

struct MemoryAssetRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "memoryAsset"

  var memoryId: String
  var assetId: String
}

/// One user preference / metadata entry (server `UserMetadataKey`); `valueJSON` is the raw JSON payload
/// so `Rules`/app code can decode whichever shape a given `key` uses without LocalStore knowing about it.
struct UserMetadataRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "userMetadata"

  var userId: String
  var key: String
  var valueJSON: String
}

/// Per-`SyncEntityType` resume checkpoint — `ack` is the exact `"type|updateId|extraId"` string the
/// server expects back in `POST /sync/ack` (`server/src/utils/sync.ts`). CODEMAP §F.
struct SyncAckRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "syncAck"

  var type: String
  var ack: String
}

struct MediaCacheRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "mediaCache"

  var assetId: String
  var variant: String
  var localPath: String
  var sizeBytes: Int
  var lastAccessedAt: Date
}
