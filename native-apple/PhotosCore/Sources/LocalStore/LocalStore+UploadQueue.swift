import CoreModel
import Foundation
import GRDB

/// A5 durable upload queue. One row per file part: a live photo enqueues motion + still rows
/// (motion first, still links via `livePhotoVideoId` once the motion upload returns its id);
/// an original+edit backup enqueues two rows sharing `pairId` (decided A5 #1).
public enum UploadItemKind: String, Sendable, Codable, Hashable {
  case original
  case edit
  case motion
  case still
}

public enum UploadItemState: String, Sendable, Codable, Hashable {
  case pending
  case uploading
  case paused
  case failed
  case done
  case duplicate
}

public struct QueuedUpload: Sendable, Hashable, Codable, Identifiable {
  public var id: String
  public var pairId: String?
  public var kind: UploadItemKind
  public var state: UploadItemState
  public var localIdentifier: String?
  public var filePath: String
  public var checksum: String
  public var fileName: String
  public var fileCreatedAt: Date?
  public var fileModifiedAt: Date?
  public var isFavorite: Bool
  public var durationMs: Int?
  public var isVideo: Bool
  public var spaceId: String?
  public var livePhotoVideoId: String?
  public var serverAssetId: String?
  public var attempts: Int
  public var nextRetryAt: Date?
  public var lastError: String?
  public var createdAt: Date

  public init(
    id: String = UUID().uuidString,
    pairId: String? = nil,
    kind: UploadItemKind = .original,
    state: UploadItemState = .pending,
    localIdentifier: String? = nil,
    filePath: String,
    checksum: String,
    fileName: String,
    fileCreatedAt: Date? = nil,
    fileModifiedAt: Date? = nil,
    isFavorite: Bool = false,
    durationMs: Int? = nil,
    isVideo: Bool = false,
    spaceId: String? = nil,
    livePhotoVideoId: String? = nil,
    serverAssetId: String? = nil,
    attempts: Int = 0,
    nextRetryAt: Date? = nil,
    lastError: String? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.pairId = pairId
    self.kind = kind
    self.state = state
    self.localIdentifier = localIdentifier
    self.filePath = filePath
    self.checksum = checksum
    self.fileName = fileName
    self.fileCreatedAt = fileCreatedAt
    self.fileModifiedAt = fileModifiedAt
    self.isFavorite = isFavorite
    self.durationMs = durationMs
    self.isVideo = isVideo
    self.spaceId = spaceId
    self.livePhotoVideoId = livePhotoVideoId
    self.serverAssetId = serverAssetId
    self.attempts = attempts
    self.nextRetryAt = nextRetryAt
    self.lastError = lastError
    self.createdAt = createdAt
  }
}

struct UploadQueueRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "uploadQueue"

  var id: String
  var pairId: String?
  var kind: String
  var state: String
  var localIdentifier: String?
  var filePath: String
  var checksum: String
  var fileName: String
  var fileCreatedAt: Date?
  var fileModifiedAt: Date?
  var isFavorite: Bool
  var durationMs: Int?
  var isVideo: Bool
  var spaceId: String?
  var livePhotoVideoId: String?
  var serverAssetId: String?
  var attempts: Int
  var nextRetryAt: Date?
  var lastError: String?
  var createdAt: Date

  init(_ item: QueuedUpload) {
    id = item.id
    pairId = item.pairId
    kind = item.kind.rawValue
    state = item.state.rawValue
    localIdentifier = item.localIdentifier
    filePath = item.filePath
    checksum = item.checksum
    fileName = item.fileName
    fileCreatedAt = item.fileCreatedAt
    fileModifiedAt = item.fileModifiedAt
    isFavorite = item.isFavorite
    durationMs = item.durationMs
    isVideo = item.isVideo
    spaceId = item.spaceId
    livePhotoVideoId = item.livePhotoVideoId
    serverAssetId = item.serverAssetId
    attempts = item.attempts
    nextRetryAt = item.nextRetryAt
    lastError = item.lastError
    createdAt = item.createdAt
  }

  var model: QueuedUpload {
    QueuedUpload(
      id: id, pairId: pairId,
      kind: UploadItemKind(rawValue: kind) ?? .original,
      state: UploadItemState(rawValue: state) ?? .pending,
      localIdentifier: localIdentifier, filePath: filePath, checksum: checksum,
      fileName: fileName, fileCreatedAt: fileCreatedAt, fileModifiedAt: fileModifiedAt,
      isFavorite: isFavorite, durationMs: durationMs, isVideo: isVideo, spaceId: spaceId,
      livePhotoVideoId: livePhotoVideoId, serverAssetId: serverAssetId, attempts: attempts,
      nextRetryAt: nextRetryAt, lastError: lastError, createdAt: createdAt
    )
  }
}

struct BackupChangeTokenRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "backupChangeToken"

  var scope: String
  var tokenData: Data?
  var updatedAt: Date
}

extension PhotosLocalStore {
  /// Appends items; skips rows whose checksum already has a live (pending/uploading/paused/failed)
  /// row, so re-scans never double-enqueue. Returns the rows actually inserted.
  public func enqueueUploads(_ items: [QueuedUpload]) async throws -> [QueuedUpload] {
    try await dbQueue.write { db in
      var inserted: [QueuedUpload] = []
      for item in items {
        let live = try UploadQueueRecord.filter(
          Column("checksum") == item.checksum
            && Column("state") != UploadItemState.done.rawValue
            && Column("state") != UploadItemState.duplicate.rawValue
        ).fetchCount(db)
        guard live == 0 else { continue }
        try UploadQueueRecord(item).insert(db, onConflict: .ignore)
        inserted.append(item)
      }
      return inserted
    }
  }

  /// Oldest actionable row: a still waits while its pair's motion row is still live
  /// (motion uploads first, then the still links — upstream `background_upload.service.dart` order).
  public func nextUploadable(now: Date = Date()) async throws -> QueuedUpload? {
    try await dbQueue.read { db in
      let rows = try UploadQueueRecord.filter(
        Column("state") == UploadItemState.pending.rawValue
          || Column("state") == UploadItemState.failed.rawValue
      )
        .order(Column("createdAt"))
        .fetchAll(db)
      for row in rows {
        // Failed rows re-enter only once their backoff gate has passed; a retry re-marks
        // the row pending on success path via `setUploadState` in the drain.
        if let retry = row.nextRetryAt, retry > now { continue }
        if row.state == UploadItemState.failed.rawValue { return row.model }
        if row.kind == UploadItemKind.still.rawValue, let pair = row.pairId {
          let motionLive = try UploadQueueRecord.filter(
            Column("pairId") == pair
              && Column("kind") == UploadItemKind.motion.rawValue
              && Column("state") != UploadItemState.done.rawValue
              && Column("state") != UploadItemState.duplicate.rawValue
          ).fetchCount(db)
          if motionLive > 0 { continue }
        }
        return row.model
      }
      return nil
    }
  }

  public func pendingUploadCount() async throws -> Int {
    try await dbQueue.read { db in
      try UploadQueueRecord.filter(
        Column("state") == UploadItemState.pending.rawValue
          || Column("state") == UploadItemState.uploading.rawValue
          || Column("state") == UploadItemState.paused.rawValue
          || Column("state") == UploadItemState.failed.rawValue
      ).fetchCount(db)
    }
  }

  public func uploadQueueSnapshot() async throws -> [QueuedUpload] {
    try await dbQueue.read { db in
      try UploadQueueRecord.order(Column("createdAt")).fetchAll(db).map(\.model)
    }
  }

  public func setUploadState(
    id: String, state: UploadItemState, attempts: Int? = nil,
    nextRetryAt: Date? = nil, lastError: String? = nil, serverAssetId: String? = nil
  ) async throws {
    try await dbQueue.write { db in
      guard var row = try UploadQueueRecord.fetchOne(db, key: id) else { return }
      row.state = state.rawValue
      if let attempts { row.attempts = attempts }
      // Failed rows carry the caller's backoff gate; every other transition clears it.
      row.nextRetryAt = nextRetryAt
      if let lastError { row.lastError = lastError }
      if let serverAssetId { row.serverAssetId = serverAssetId }
      try row.update(db)
    }
  }

  public func setUploadLivePhotoVideoId(id: String, livePhotoVideoId: String) async throws {
    try await dbQueue.write { db in
      guard var row = try UploadQueueRecord.fetchOne(db, key: id) else { return }
      row.livePhotoVideoId = livePhotoVideoId
      try row.update(db)
    }
  }

  public func removeUpload(id: String) async throws {
    try await dbQueue.write { db in
      _ = try UploadQueueRecord.deleteOne(db, key: id)
    }
  }

  public func pruneFinishedUploads(keepingLastErrored: Bool = true) async throws {
    try await dbQueue.write { db in
      _ = try UploadQueueRecord.filter(
        Column("state") == UploadItemState.done.rawValue
          || Column("state") == UploadItemState.duplicate.rawValue
      ).deleteAll(db)
      if !keepingLastErrored {
        _ = try UploadQueueRecord.filter(Column("state") == UploadItemState.failed.rawValue)
          .deleteAll(db)
      }
    }
  }

  /// Persistent PhotoKit change-history token per scope (e.g. "photokit"), for incremental scans.
  public func backupChangeToken(scope: String) async throws -> Data? {
    try await dbQueue.read { db in
      try BackupChangeTokenRecord.fetchOne(db, key: scope)?.tokenData
    }
  }

  public func saveBackupChangeToken(scope: String, token: Data?) async throws {
    try await dbQueue.write { db in
      try BackupChangeTokenRecord(scope: scope, tokenData: token, updatedAt: Date())
        .save(db)
    }
  }
}
