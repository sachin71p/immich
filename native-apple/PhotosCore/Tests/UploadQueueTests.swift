import CoreModel
import Foundation
import LocalStore
import Testing
import Upload

/// A5 Tests: queue persistence/resume, dedupe, target resolution precedence, live-pair ordering.
/// Network-touching paths run against a fake `UploadTransport`; only pure + LocalStore seams
/// are exercised here (server round-trips belong to the host e2e tiers).
@Suite struct UploadQueueTests {
  private func prefs(
    target: SharedLibraryPrefs.UploadTarget = .personal,
    cellularPhotos: Bool = false, cellularVideos: Bool = false,
    lowPower: Bool = false, plusEdit: Bool = false
  ) -> SharedLibraryPrefs {
    SharedLibraryPrefs(
      defaultUploadTarget: target,
      useCellularForPhotos: cellularPhotos, useCellularForVideos: cellularVideos,
      allowLowPowerUploads: lowPower, uploadOriginalPlusEdit: plusEdit)
  }

  private func spec(
    name: String = "IMG_001.heic", checksum: String = "aa",
    target: UploadTargetResolver.ExplicitTarget = .inherit
  ) -> FileUploadSpec {
    FileUploadSpec(
      fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name,
      checksum: checksum, explicitTarget: target)
  }

  // MARK: - target resolution precedence

  @Test("[A5] explicit source rule beats the user default")
  func explicitBeatsDefault() throws {
    let prefs = prefs(target: .space("default-space"))
    let personal = try UploadEnqueuePlan.single(
      spec(target: .personal), prefs: prefs)
    #expect(personal.spaceId == nil)
    let space = try UploadEnqueuePlan.single(
      spec(target: .space("explicit-space")), prefs: prefs)
    #expect(space.spaceId == "explicit-space")
  }

  @Test("[A5] inherit falls back to user default, then personal")
  func inheritFallsBack() throws {
    let toSpace = try UploadEnqueuePlan.single(
      spec(), prefs: prefs(target: .space("s-1")))
    #expect(toSpace.spaceId == "s-1")
    let toPersonal = try UploadEnqueuePlan.single(spec(), prefs: prefs())
    #expect(toPersonal.spaceId == nil)
  }

  // MARK: - network rules

  @Test("[A5] wifi uploads everything; cellular follows per-kind prefs; offline and low-power gate")
  func networkPolicy() {
    let p = prefs()
    let wifi = NetworkSnapshot(isConnected: true, isWifi: true, isLowPower: false)
    #expect(UploadNetworkPolicy.allows(snapshot: wifi, isVideo: true, prefs: p))
    let cell = NetworkSnapshot(isConnected: true, isWifi: false, isLowPower: false)
    #expect(!UploadNetworkPolicy.allows(snapshot: cell, isVideo: false, prefs: p))
    #expect(!UploadNetworkPolicy.allows(snapshot: cell, isVideo: true, prefs: p))
    let cellPhotos = prefs(cellularPhotos: true)
    #expect(UploadNetworkPolicy.allows(snapshot: cell, isVideo: false, prefs: cellPhotos))
    #expect(!UploadNetworkPolicy.allows(snapshot: cell, isVideo: true, prefs: cellPhotos))
    let off = NetworkSnapshot(isConnected: false, isWifi: false, isLowPower: false)
    #expect(!UploadNetworkPolicy.allows(snapshot: off, isVideo: false, prefs: p))
    let low = NetworkSnapshot(isConnected: true, isWifi: true, isLowPower: true)
    #expect(!UploadNetworkPolicy.allows(snapshot: low, isVideo: false, prefs: p))
    #expect(UploadNetworkPolicy.allows(snapshot: low, isVideo: false, prefs: prefs(lowPower: true)))
  }

  // MARK: - retry backoff

  @Test("[A5] backoff is 30s doubling, capped at 30m")
  func backoffSchedule() {
    #expect(UploadRetry.delay(afterFailures: 0) == 0)
    #expect(UploadRetry.delay(afterFailures: 1) == 30)
    #expect(UploadRetry.delay(afterFailures: 2) == 60)
    #expect(UploadRetry.delay(afterFailures: 3) == 120)
    #expect(UploadRetry.delay(afterFailures: 10) == 1800)
    #expect(UploadRetry.delay(afterFailures: 100) == 1800)
  }

  // MARK: - checksum

  @Test("[A5] SHA1 hex matches the known vector")
  func sha1Vector() {
    // True SHA-1("abc") per FIPS 180-1 (verified against hashlib, 40 hex chars).
    #expect(UploadSHA1.hex(of: Data("abc".utf8)) == "a9993e364706816aba3e25717850c26c9cd0d89d")
  }

  // MARK: - edit policy

  @Test("[A5] original-only by default; paired two-record enqueue when enabled")
  func editPolicy() throws {
    let single = try UploadEnqueuePlan.originalPlusEdit(
      original: spec(name: "a.heic", checksum: "c1"),
      edit: spec(name: "a-edit.heic", checksum: "c2"), prefs: prefs())
    #expect(single.count == 1 && single[0].kind == .original)
    let pair = try UploadEnqueuePlan.originalPlusEdit(
      original: spec(name: "a.heic", checksum: "c1"),
      edit: spec(name: "a-edit.heic", checksum: "c2"), prefs: prefs(plusEdit: true))
    #expect(pair.count == 2)
    #expect(pair[0].kind == .original && pair[1].kind == .edit)
    #expect(pair[0].pairId != nil && pair[0].pairId == pair[1].pairId)
  }

  // MARK: - live-pair ordering + persistence/resume + dedupe

  // Live-photo assembly on synthetic fixtures (motion-first ordering + still
  // linking); the `@personal live.heic/.mov` half needs personal fixtures,
  // absent — see e2e/fork-assets/personal/README.md.
  @Test("[AP-06] motion uploads first and the still links its server id")
  func livePairOrdering() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    let fake = FakeTransport()
    let queue = UploadQueue(store: store, transport: fake)
    let rows = try UploadEnqueuePlan.livePair(
      motion: spec(name: "m.mov", checksum: "motion-sha"),
      still: spec(name: "s.heic", checksum: "still-sha"), prefs: prefs())
    #expect(rows[0].kind == .motion && rows[1].kind == .still)
    _ = try await store.enqueueUploads(rows)
    // Still is blocked while motion is live.
    let first = try await store.nextUploadable()
    #expect(first?.kind == .motion)
    let result = await queue.drain(prefs: prefs())
    #expect(result.uploaded == 2 && result.failed == 0)
    #expect(fake.order == [.motion, .still])
    let stillUpload = try #require(fake.seenLivePhotoIds.last)
    #expect(stillUpload == fake.motionServerId)
  }

  @Test("[A5] re-enqueue of a live checksum is skipped; bulk-check rejects mark duplicates")
  func dedupe() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    let once = try UploadEnqueuePlan.single(spec(checksum: "dup-sha"), prefs: prefs())
    #expect(try await store.enqueueUploads([once]).count == 1)
    #expect(try await store.enqueueUploads([once]).isEmpty)
    let fake = FakeTransport(rejectChecksums: ["dup-sha": "asset-1"])
    let queue = UploadQueue(store: store, transport: fake)
    let result = await queue.drain(prefs: prefs())
    #expect(result.duplicates == 1 && result.uploaded == 0)
    let snapshot = try await store.uploadQueueSnapshot()
    #expect(snapshot.first?.state == .duplicate)
    #expect(snapshot.first?.serverAssetId == "asset-1")
  }

  @Test("[A5] failed rows back off and resume after the gate; crash rows reset to pending")
  func retryAndResume() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    let fake = FakeTransport(failFirst: true)
    let queue = UploadQueue(store: store, transport: fake)
    let row = try UploadEnqueuePlan.single(spec(checksum: "flaky"), prefs: prefs())
    _ = try await store.enqueueUploads([row])
    let r1 = await queue.drain(prefs: prefs())
    #expect(r1.failed == 1)
    // Gated: immediate redrain attempts nothing new and reports waiting.
    let r2 = await queue.drain(prefs: prefs())
    #expect(r2.failed == 0 && r2.uploaded == 0 && r2.waitingOnNetwork)
    // Crash simulation: failed+expired rows re-enter and succeed.
    try await store.setUploadState(id: row.id, state: .failed, nextRetryAt: .distantPast)
    let r3 = await queue.drain(prefs: prefs())
    #expect(r3.uploaded == 1)
  }
}

/// In-memory fake: optional first-attempt failure, optional bulk-check rejects, records order.
final class FakeTransport: UploadTransport, @unchecked Sendable {
  var failFirst: Bool
  var rejectChecksums: [String: String]
  var seen = false
  var order: [UploadItemKind] = []
  var seenLivePhotoIds: [String?] = []
  let motionServerId = "motion-asset-id"

  init(failFirst: Bool = false, rejectChecksums: [String: String] = [:]) {
    self.failFirst = failFirst
    self.rejectChecksums = rejectChecksums
  }

  func checkBulk(checksums: [(id: String, checksum: String)]) async throws -> [String: BulkCheckVerdict] {
    var out: [String: BulkCheckVerdict] = [:]
    for (id, checksum) in checksums {
      if let assetId = rejectChecksums[checksum] {
        out[id] = BulkCheckVerdict(action: .reject, reason: "duplicate", assetId: assetId)
      } else {
        out[id] = BulkCheckVerdict(action: .accept)
      }
    }
    return out
  }

  func upload(item: QueuedUpload, progress: @Sendable (Double) -> Void) async throws -> UploadOutcome {
    if failFirst, !seen {
      seen = true
      throw UploadTransportError.unexpectedResponse("boom")
    }
    order.append(item.kind)
    seenLivePhotoIds.append(item.livePhotoVideoId)
    if item.kind == .motion {
      return UploadOutcome(assetId: motionServerId, isDuplicate: false)
    }
    return UploadOutcome(assetId: "still-asset-id", isDuplicate: false)
  }
}
