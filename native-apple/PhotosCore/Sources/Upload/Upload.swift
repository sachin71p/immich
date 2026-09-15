import CoreModel
import CryptoKit
import Foundation
import ImmichAPI
import LocalStore

/// Durable upload queue and target resolution (A5).
///
/// Conventions scouted from the upstream Flutter app (`mobile/lib/services/background_upload.service.dart`,
/// full note in `.claude/plans/shared-libraries/handoff/A5-scout.md`):
/// - checksum = hex SHA1 (`AssetBulkUploadCheckItem.checksum` accepts "Base64 or hex encoded SHA1");
/// - dedupe via `POST /assets/bulk-upload-check` (`accept`/`reject` + `duplicate` reason);
/// - live photos upload the motion part first, then the still links it via `livePhotoVideoId`;
/// - the still-photo part uploads with `visibility=hidden` so the server skips regular jobs on it.
public enum PhotosUpload {}

/// Per-source destination rule: explicit target wins, else the user's default, else personal.
/// Returns the space id to upload into, or nil for the personal library.
public enum UploadTargetResolver {
  public enum ExplicitTarget: Sendable, Hashable {
    case inherit
    case personal
    case space(String)
  }

  public static func resolve(
    explicit: ExplicitTarget, defaultTarget: SharedLibraryPrefs.UploadTarget
  ) -> String? {
    switch explicit {
    case .inherit:
      switch defaultTarget {
      case .personal: return nil
      case .space(let id): return id
      }
    case .personal: return nil
    case .space(let id): return id
    }
  }
}

/// Point-in-time network snapshot; the app layer fills it (NWPathMonitor / low-power observer),
/// so this policy stays pure and unit-testable.
public struct NetworkSnapshot: Sendable, Hashable {
  public var isConnected: Bool
  public var isWifi: Bool
  public var isLowPower: Bool

  public init(isConnected: Bool, isWifi: Bool, isLowPower: Bool) {
    self.isConnected = isConnected
    self.isWifi = isWifi
    self.isLowPower = isLowPower
  }
}

public enum UploadNetworkPolicy {
  public static func allows(
    snapshot: NetworkSnapshot, isVideo: Bool, prefs: SharedLibraryPrefs
  ) -> Bool {
    guard snapshot.isConnected else { return false }
    if snapshot.isLowPower, !prefs.allowLowPowerUploads { return false }
    if snapshot.isWifi { return true }
    return isVideo ? prefs.useCellularForVideos : prefs.useCellularForPhotos
  }
}

/// Deterministic exponential backoff: 30s, 1m, 2m, … capped at 30m. No jitter (queue order
/// must survive relaunch identically; a single device uploading needs no thundering-herd guard).
public enum UploadRetry {
  public static let baseSeconds = 30.0
  public static let capSeconds = 1800.0

  public static func delay(afterFailures count: Int) -> TimeInterval {
    guard count > 0 else { return 0 }
    return min(capSeconds, baseSeconds * pow(2.0, Double(count - 1)))
  }

  public static func nextRetryAt(afterFailures count: Int, now: Date = Date()) -> Date {
    now.addingTimeInterval(delay(afterFailures: count))
  }
}

public enum UploadSHA1 {
  public static func hex(of data: Data) -> String {
    Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public static func hexOfFile(at url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = Insecure.SHA1()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

/// One file handed to the enqueue planner. Checksums may be precomputed by the scanner;
/// missing ones are hashed from disk at enqueue time.
public struct FileUploadSpec: Sendable, Hashable {
  public var fileURL: URL
  public var fileName: String
  public var checksum: String?
  public var fileCreatedAt: Date?
  public var fileModifiedAt: Date?
  public var isFavorite: Bool
  public var durationMs: Int?
  public var isVideo: Bool
  public var localIdentifier: String?
  public var explicitTarget: UploadTargetResolver.ExplicitTarget

  public init(
    fileURL: URL, fileName: String, checksum: String? = nil,
    fileCreatedAt: Date? = nil, fileModifiedAt: Date? = nil,
    isFavorite: Bool = false, durationMs: Int? = nil, isVideo: Bool = false,
    localIdentifier: String? = nil,
    explicitTarget: UploadTargetResolver.ExplicitTarget = .inherit
  ) {
    self.fileURL = fileURL
    self.fileName = fileName
    self.checksum = checksum
    self.fileCreatedAt = fileCreatedAt
    self.fileModifiedAt = fileModifiedAt
    self.isFavorite = isFavorite
    self.durationMs = durationMs
    self.isVideo = isVideo
    self.localIdentifier = localIdentifier
    self.explicitTarget = explicitTarget
  }
}

/// Builds the ordered queue rows for each backup shape. Every row carries the resolved `spaceId`
/// so the uploader never re-derives targets mid-drain.
public enum UploadEnqueuePlan {
  public static func single(
    _ spec: FileUploadSpec, kind: UploadItemKind = .original,
    pairId: String? = nil, prefs: SharedLibraryPrefs, now: Date = Date()
  ) throws -> QueuedUpload {
    QueuedUpload(
      pairId: pairId, kind: kind,
      localIdentifier: spec.localIdentifier,
      filePath: spec.fileURL.path,
      checksum: try checksum(for: spec),
      fileName: spec.fileName,
      fileCreatedAt: spec.fileCreatedAt, fileModifiedAt: spec.fileModifiedAt,
      isFavorite: spec.isFavorite, durationMs: spec.durationMs, isVideo: spec.isVideo,
      spaceId: UploadTargetResolver.resolve(
        explicit: spec.explicitTarget, defaultTarget: prefs.defaultUploadTarget),
      createdAt: now
    )
  }

  /// Decided A5 #1, original-only or original+edit: two records sharing a `pairId`
  /// (reconciled as a stack/pair where the server supports it, otherwise two assets).
  public static func originalPlusEdit(
    original: FileUploadSpec, edit: FileUploadSpec,
    prefs: SharedLibraryPrefs, now: Date = Date()
  ) throws -> [QueuedUpload] {
    guard prefs.uploadOriginalPlusEdit else {
      return [try single(original, prefs: prefs, now: now)]
    }
    let pairId = UUID().uuidString
    return [
      try single(original, kind: .original, pairId: pairId, prefs: prefs, now: now),
      try single(edit, kind: .edit, pairId: pairId, prefs: prefs, now: now),
    ]
  }

  /// Live photo: motion row first, still second. The still's `livePhotoVideoId` is filled in
  /// from the motion upload's returned id before the still uploads (see `UploadQueue.drain`).
  public static func livePair(
    motion: FileUploadSpec, still: FileUploadSpec,
    prefs: SharedLibraryPrefs, now: Date = Date()
  ) throws -> [QueuedUpload] {
    let pairId = UUID().uuidString
    return [
      try single(motion, kind: .motion, pairId: pairId, prefs: prefs, now: now),
      try single(still, kind: .still, pairId: pairId, prefs: prefs, now: now),
    ]
  }

  private static func checksum(for spec: FileUploadSpec) throws -> String {
    if let checksum = spec.checksum, !checksum.isEmpty { return checksum.lowercased() }
    return try UploadSHA1.hexOfFile(at: spec.fileURL)
  }
}

/// Bulk-check verdict per client id.
public struct BulkCheckVerdict: Sendable, Hashable {
  public enum Action: Sendable, Hashable { case accept, reject }

  public var action: Action
  public var reason: String?
  public var assetId: String?
  public var isTrashed: Bool

  public init(action: Action, reason: String? = nil, assetId: String? = nil, isTrashed: Bool = false) {
    self.action = action
    self.reason = reason
    self.assetId = assetId
    self.isTrashed = isTrashed
  }
}

public struct UploadOutcome: Sendable, Hashable {
  public var assetId: String
  public var isDuplicate: Bool

  public init(assetId: String, isDuplicate: Bool) {
    self.assetId = assetId
    self.isDuplicate = isDuplicate
  }
}

public enum UploadTransportError: Error, Sendable {
  case missingFile(String)
  case unexpectedResponse(String)
}

/// Network seam behind `UploadQueue`: bulk-check + multipart upload. `ImmichUploadTransport`
/// is the live implementation; tests inject a fake.
public protocol UploadTransport: Sendable {
  func checkBulk(checksums: [(id: String, checksum: String)]) async throws -> [String: BulkCheckVerdict]
  func upload(item: QueuedUpload, progress: @Sendable (Double) -> Void) async throws -> UploadOutcome
}

/// Live transport: bulk-check via the generated OpenAPI client, multipart upload via URLSession
/// (mirroring upstream's field-based POST to `/assets`, which also keeps this path working for
/// background `URLSession` configurations the generated client does not expose).
public struct ImmichUploadTransport: UploadTransport {
  public let connection: ImmichConnection

  public init(connection: ImmichConnection) {
    self.connection = connection
  }

  public func checkBulk(checksums: [(id: String, checksum: String)]) async throws -> [String: BulkCheckVerdict] {
    let input = Operations.checkBulkUpload.Input(
      body: .json(.init(assets: checksums.map {
        Components.Schemas.AssetBulkUploadCheckItem(checksum: $0.checksum, id: $0.id)
      })))
    let output = try await connection.client.checkBulkUpload(input)
    guard case let .ok(response) = output, case let .json(body) = response.body else {
      throw UploadTransportError.unexpectedResponse("checkBulkUpload")
    }
    var verdicts: [String: BulkCheckVerdict] = [:]
    for result in body.results {
      let action: BulkCheckVerdict.Action =
        result.action.rawValue == "reject" ? .reject : .accept
      verdicts[result.id] = BulkCheckVerdict(
        action: action, reason: result.reason?.rawValue,
        assetId: result.assetId, isTrashed: result.isTrashed ?? false)
    }
    return verdicts
  }

  public func upload(
    item: QueuedUpload, progress: @Sendable (Double) -> Void
  ) async throws -> UploadOutcome {
    let url = URL(string: "/assets", relativeTo: connection.serverURL)!
    let boundary = "PhotosFork-\(UUID().uuidString)"
    var body = Data()
    func field(_ name: String, _ value: String) {
      body.append("--\(boundary)\r\n".data(using: .utf8)!)
      body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
      body.append("\(value)\r\n".data(using: .utf8)!)
    }
    let fileURL = URL(fileURLWithPath: item.filePath)
    guard FileManager.default.fileExists(atPath: item.filePath) else {
      throw UploadTransportError.missingFile(item.filePath)
    }
    let fileData = try Data(contentsOf: fileURL)
    let attributes = try FileManager.default.attributesOfItem(atPath: item.filePath)
    let createdAt = item.fileCreatedAt ?? (attributes[.creationDate] as? Date) ?? Date()
    let modifiedAt = item.fileModifiedAt ?? (attributes[.modificationDate] as? Date) ?? Date()
    let iso = ISO8601DateFormatter()
    field("filename", item.fileName)
    field("fileCreatedAt", iso.string(from: createdAt))
    field("fileModifiedAt", iso.string(from: modifiedAt))
    field("isFavorite", item.isFavorite ? "true" : "false")
    if let durationMs = item.durationMs { field("duration", String(durationMs)) }
    if let spaceId = item.spaceId { field("spaceId", spaceId) }
    if let livePhotoVideoId = item.livePhotoVideoId { field("livePhotoVideoId", livePhotoVideoId) }
    // Upstream hides the still part so the server skips regular jobs on it.
    if item.kind == .still { field("visibility", "hidden") }
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append(
      "Content-Disposition: form-data; name=\"assetData\"; filename=\"\(item.fileName)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
    body.append(fileData)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(item.checksum, forHTTPHeaderField: "x-immich-checksum")
    if let token = await connection.tokenStore.get() {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    progress(0.05)
    let (data, response) = try await URLSession.shared.upload(for: request, from: body)
    progress(1.0)
    guard let http = response as? HTTPURLResponse, (200...201).contains(http.statusCode) else {
      throw UploadTransportError.unexpectedResponse(
        "uploadAsset HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
    }
    struct UploadResponse: Decodable { var id: String; var status: String }
    let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
    return UploadOutcome(assetId: decoded.id, isDuplicate: decoded.status == "duplicate")
  }

  /// Post-upload reconcile for pairs (decided A5 #1): confirms the still links its motion part.
  public func assetLivePhotoVideoId(id: String) async throws -> String? {
    let output = try await connection.client.getAssetInfo(.init(path: .init(id: id)))
    guard case let .ok(response) = output, case let .json(body) = response.body else {
      throw UploadTransportError.unexpectedResponse("getAssetInfo")
    }
    return body.livePhotoVideoId
  }
}

public struct UploadDrainResult: Sendable {
  public var uploaded: Int
  public var duplicates: Int
  public var failed: Int
  public var waitingOnNetwork: Bool

  public init(uploaded: Int = 0, duplicates: Int = 0, failed: Int = 0, waitingOnNetwork: Bool = false) {
    self.uploaded = uploaded
    self.duplicates = duplicates
    self.failed = failed
    self.waitingOnNetwork = waitingOnNetwork
  }
}

/// Sequential queue runner. Re-entrant across launches: state lives in `PhotosLocalStore`,
/// so a kill mid-upload just leaves the row `uploading`, which the next drain resets to pending.
public actor UploadQueue {
  public let store: PhotosLocalStore
  public let transport: any UploadTransport
  public var networkSnapshot: NetworkSnapshot
  public var onProgress: (@Sendable (String, Double) -> Void)?

  public init(
    store: PhotosLocalStore, transport: any UploadTransport,
    networkSnapshot: NetworkSnapshot = NetworkSnapshot(
      isConnected: true, isWifi: true, isLowPower: false)
  ) {
    self.store = store
    self.transport = transport
    self.networkSnapshot = networkSnapshot
  }

  public func setNetworkSnapshot(_ snapshot: NetworkSnapshot) {
    networkSnapshot = snapshot
  }

  @discardableResult
  public func drain(prefs: SharedLibraryPrefs, now: Date = Date()) async -> UploadDrainResult {
    // A crash/termination may have left rows `uploading`; reclaim them first.
    for row in (try? await store.uploadQueueSnapshot()) ?? [] where row.state == .uploading {
      try? await store.setUploadState(id: row.id, state: .pending)
    }
    var result = UploadDrainResult()
    while let item = try? await store.nextUploadable(now: now), shouldAttempt(item, prefs: prefs) {
      await uploadOne(item, prefs: prefs, result: &result)
    }
    // If rows remain but none were actionable, the network policy is the gate.
    if let remaining = try? await store.pendingUploadCount(), remaining > 0,
      result.uploaded == 0, result.duplicates == 0, result.failed == 0
    {
      result.waitingOnNetwork = true
    }
    return result
  }

  private func shouldAttempt(_ item: QueuedUpload, prefs: SharedLibraryPrefs) -> Bool {
    UploadNetworkPolicy.allows(snapshot: networkSnapshot, isVideo: item.isVideo, prefs: prefs)
  }

  private func uploadOne(
    _ item: QueuedUpload, prefs: SharedLibraryPrefs, result: inout UploadDrainResult
  ) async {
    // Bulk-check dedupe first (cheap; also heals rows enqueued before a server-side upload).
    if let verdict = try? await transport.checkBulk(checksums: [(item.id, item.checksum)])[
      item.id], verdict.action == .reject
    {
      try? await store.setUploadState(
        id: item.id, state: .duplicate, serverAssetId: verdict.assetId)
      result.duplicates += 1
      return
    }
    try? await store.setUploadState(id: item.id, state: .uploading)
    let progress = onProgress
    do {
      let outcome = try await transport.upload(item: item) { fraction in
        progress?(item.id, fraction)
      }
      if outcome.isDuplicate {
        try? await store.setUploadState(
          id: item.id, state: .duplicate, serverAssetId: outcome.assetId)
        result.duplicates += 1
      } else {
        try? await store.setUploadState(
          id: item.id, state: .done, serverAssetId: outcome.assetId)
        result.uploaded += 1
      }
      await linkPairIfMotionDone(item, serverAssetId: outcome.assetId)
    } catch {
      let attempts = item.attempts + 1
      try? await store.setUploadState(
        id: item.id, state: .failed, attempts: attempts,
        nextRetryAt: UploadRetry.nextRetryAt(afterFailures: attempts),
        lastError: String(describing: error))
      result.failed += 1
    }
  }

  /// Motion finished: stamp its server id onto the paired still so the still links on upload.
  private func linkPairIfMotionDone(_ item: QueuedUpload, serverAssetId: String) async {
    guard item.kind == .motion, let pairId = item.pairId else { return }
    let snapshot = (try? await store.uploadQueueSnapshot()) ?? []
    for row in snapshot where row.pairId == pairId && row.kind == .still {
      try? await store.setUploadLivePhotoVideoId(id: row.id, livePhotoVideoId: serverAssetId)
    }
  }
}
