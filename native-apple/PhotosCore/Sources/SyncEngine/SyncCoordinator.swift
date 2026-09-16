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

  /// Outcome of one sync session: whether it ran, and whether it changed the local mirror.
  /// `appliedChanges` is the cheapest such signal — it counts `PhotosLocalStore.apply`/`wipe`
  /// calls, not row diffs. The macOS grid keys its reload off it (`MacAppState.syncNow` bumps
  /// `timelineVersion` only when a session applied something or the user asked), so idle
  /// no-change syncs no longer rebuild the grid, re-issue prefetches, and hang the main thread.
  public struct SyncResult: Sendable {
    /// False when the call was dropped because a session was already running.
    public var didRun: Bool
    /// True when the session applied at least one change batch (or a reset wipe) to the store.
    public var appliedChanges: Bool

    public init(didRun: Bool, appliedChanges: Bool) {
      self.didRun = didRun
      self.appliedChanges = appliedChanges
    }

    /// Grid reloads only when the session ran AND (it changed the mirror OR the user asked):
    /// timer-driven no-change syncs skip the reload; dropped syncs never reload.
    public func shouldReloadTimeline(userInitiated: Bool) -> Bool {
      didRun && (appliedChanges || userInitiated)
    }
  }

  /// Runs one full sync session. Safe to call repeatedly (foreground, pull-to-refresh, timer); concurrent
  /// calls while a session is already running are dropped. Kept for existing callers (iOS
  /// `AppSession`, `syncOnDemand`); new callers that gate UI reloads want `syncWithResult`.
  @discardableResult
  public func syncNow(reset: Bool = false) async throws -> Bool {
    try await syncWithResult(reset: reset).didRun
  }

  /// Same session as `syncNow`, additionally reporting whether anything was applied.
  public func syncWithResult(reset: Bool = false) async throws -> SyncResult {
    guard !isSyncing else { return SyncResult(didRun: false, appliedChanges: false) }
    isSyncing = true
    defer { isSyncing = false }

    var appliedChanges = false
    let currentUserId = try await connection.currentUserId()
    if reset {
      try await localStore.wipe()
      try await localStore.clearSyncAcks()
      appliedChanges = true
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
        // server keeps streaming a full resync on the same connection afterwards. A wipe visibly
        // changes the mirror even if the resync that follows is empty.
        batch = SyncBatch()
        try await localStore.wipe()
        try await localStore.clearSyncAcks()
        appliedChanges = true
      case .complete:
        if try await flush(&batch, currentUserId: currentUserId) > 0 { appliedChanges = true }
      }

      if batch.pending.count >= batchSize || Date().timeIntervalSince(batch.lastFlush) >= batchInterval {
        if try await flush(&batch, currentUserId: currentUserId) > 0 { appliedChanges = true }
      }
    }
    if try await flush(&batch, currentUserId: currentUserId) > 0 { appliedChanges = true }
    return SyncResult(didRun: true, appliedChanges: appliedChanges)
  }

  private struct SyncBatch {
    var pending: [SyncChange] = []
    var pendingAcks: [String] = []
    var lastFlush = Date()
  }

  /// Applies the pending batch, returning the applied change count (0 when the batch was
  /// empty). `syncWithResult` sums these into `SyncResult.appliedChanges`.
  @discardableResult
  private func flush(_ batch: inout SyncBatch, currentUserId: String) async throws -> Int {
    guard !batch.pending.isEmpty else { return 0 }
    let applied = batch.pending.count
    try await localStore.apply(batch.pending, currentUserId: currentUserId)
    batch.pending.removeAll(keepingCapacity: true)
    if !batch.pendingAcks.isEmpty {
      try await postAcks(batch.pendingAcks)
      batch.pendingAcks.removeAll(keepingCapacity: true)
    }
    batch.lastFlush = Date()
    return applied
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
