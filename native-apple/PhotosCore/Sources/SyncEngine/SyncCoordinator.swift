import Foundation
import ImmichAPI
import LocalStore

/// Drives one `/sync/stream` session end to end (brief task 2): streams lines, batches them into
/// transactions, posts acks, and handles `SyncResetV1`/`SyncCompleteV1`/backfill completion/container
/// removal. One `SyncCoordinator` per signed-in connection; the app layer owns *when* to call `syncNow`
/// (triggers below).
public actor SyncCoordinator {
  private let connection: ImmichConnection
  private let localStore: PhotosLocalStore
  private let batchSize: Int
  private let batchInterval: TimeInterval

  private var isSyncing = false
  private var activeTimerTask: Task<Void, Never>?

  public init(
    connection: ImmichConnection,
    localStore: PhotosLocalStore,
    batchSize: Int = 500,
    batchInterval: TimeInterval = 2
  ) {
    self.connection = connection
    self.localStore = localStore
    self.batchSize = batchSize
    self.batchInterval = batchInterval
  }

  /// Runs one full sync session. Safe to call repeatedly (foreground, pull-to-refresh, timer); concurrent
  /// calls while a session is already running are dropped.
  @discardableResult
  public func syncNow(reset: Bool = false) async throws -> Bool {
    guard !isSyncing else { return false }
    isSyncing = true
    defer { isSyncing = false }

    let currentUserId = try await connection.currentUserId()
    if reset {
      try await localStore.wipe()
      try await localStore.clearSyncAcks()
    }

    let client = SyncStreamClient(connection: connection)
    var batch = SyncBatch()

    for try await line in client.lines(types: SyncRequestTypes.all, reset: reset) {
      guard !line.isEmpty else { continue }
      switch try SyncLineParser.parse(line) {
      case .changes(let changes):
        batch.pending.append(contentsOf: changes)
        for change in changes {
          if case .ack(_, let value) = change { batch.pendingAcks.append(value) }
        }
      case .reset:
        // A mid-stream reset: discard whatever we haven't durably applied yet and start clean; the
        // server keeps streaming a full resync on the same connection afterwards.
        batch = SyncBatch()
        try await localStore.wipe()
        try await localStore.clearSyncAcks()
      case .complete:
        try await flush(&batch, currentUserId: currentUserId)
      }

      if batch.pending.count >= batchSize || Date().timeIntervalSince(batch.lastFlush) >= batchInterval {
        try await flush(&batch, currentUserId: currentUserId)
      }
    }
    try await flush(&batch, currentUserId: currentUserId)
    return true
  }

  private struct SyncBatch {
    var pending: [SyncChange] = []
    var pendingAcks: [String] = []
    var lastFlush = Date()
  }

  private func flush(_ batch: inout SyncBatch, currentUserId: String) async throws {
    guard !batch.pending.isEmpty else { return }
    try await localStore.apply(batch.pending, currentUserId: currentUserId)
    batch.pending.removeAll(keepingCapacity: true)
    if !batch.pendingAcks.isEmpty {
      try await postAcks(batch.pendingAcks)
      batch.pendingAcks.removeAll(keepingCapacity: true)
    }
    batch.lastFlush = Date()
  }

  private func postAcks(_ acks: [String]) async throws {
    // `SyncAckSetDto.acks` caps at 1000 (server/src/dtos/sync.dto.ts); chunk defensively even though our
    // own batches are far smaller.
    for chunk in acks.chunked(into: 1000) {
      let input = Operations.sendSyncAck.Input(body: .json(.init(acks: chunk)))
      _ = try await connection.client.sendSyncAck(input)
    }
  }

  // MARK: - Triggers (brief task 2: "app foreground, pull to refresh, timer while active")

  /// Call on app foreground / pull-to-refresh.
  public func syncOnDemand() async throws {
    try await syncNow()
  }

  /// Starts a periodic sync while the app is active; call `stopActiveTimer()` on background. No websocket
  /// trigger (brief: "optional, skip if not trivial" — the raw-stream transport above has no generated
  /// event-socket counterpart to hook into trivially).
  public func startActiveTimer(interval: TimeInterval = 30) {
    stopActiveTimer()
    activeTimerTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { return }
        _ = try? await syncNow()
      }
    }
  }

  public func stopActiveTimer() {
    activeTimerTask?.cancel()
    activeTimerTask = nil
  }
}

extension Array {
  fileprivate func chunked(into size: Int) -> [[Element]] {
    guard size > 0 else { return [self] }
    return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
}
