import CoreGraphics
import CoreModel
import Foundation
import ImageIO
import Nuke
import Testing
@testable import Media

private enum StubError: Error {
  case failed
}

/// Lock-protected log for the fire-and-forget prefetch calls, which the actor stub must
/// serve from `nonisolated` protocol witnesses.
private final class EventLog: @unchecked Sendable {
  private let lock = NSLock()
  private var _prefetched: [[ImageRequest]] = []
  private var _stopPrefetchCalls = 0

  func recordPrefetch(_ requests: [ImageRequest]) { lock.withLock { _prefetched.append(requests) } }
  func recordStop() { lock.withLock { _stopPrefetchCalls += 1 } }
  var prefetched: [[ImageRequest]] { lock.withLock { _prefetched } }
  var stopPrefetchCalls: Int { lock.withLock { _stopPrefetchCalls } }
}

/// In-memory `MediaImageService`: canned image, per-URL data/failures, full request log.
private actor StubImageService: MediaImageService {
  nonisolated let events = EventLog()
  var dataRequests: [ImageRequest] = []
  var imageRequests: [ImageRequest] = []
  var dataByURL: [String: Data] = [:]
  var failingURLs: Set<String> = []
  var delayNanoseconds: UInt64 = 0
  let cannedImage: PlatformImage

  init() throws {
    // A real 1x1 bitmap without touching AppKit/UIKit in the test.
    let golden = try ThumbHash.decode(base64: "1fsDBYBKeI97iIh4eIiIdweIdIBI")
    self.cannedImage = try #require(golden.makePlatformImage())
  }

  func fail(urls: [String]) {
    failingURLs.formUnion(urls)
  }

  func setDelay(_ nanoseconds: UInt64) {
    delayNanoseconds = nanoseconds
  }

  func image(for request: ImageRequest) async throws -> PlatformImage {
    imageRequests.append(request)
    if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
    if let url = request.url?.absoluteString, failingURLs.contains(url) { throw StubError.failed }
    return cannedImage
  }

  func data(for request: ImageRequest) async throws -> Data {
    dataRequests.append(request)
    if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
    guard let url = request.url?.absoluteString else { throw StubError.failed }
    if failingURLs.contains(url) { throw StubError.failed }
    return dataByURL[url] ?? Data("bytes-for-\(url)".utf8)
  }

  nonisolated func prefetch(_ requests: [ImageRequest]) {
    events.recordPrefetch(requests)
  }

  nonisolated func stopPrefetching() {
    events.recordStop()
  }

  var prefetched: [[ImageRequest]] { events.prefetched }
  var stopPrefetchCalls: Int { events.stopPrefetchCalls }
}

private struct Harness {
  var pipeline: MediaPipeline
  var cache: TieredMediaCache
  var service: StubImageService
  var server: MediaServer

  static func make(token: String? = "tok") async throws -> Harness {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let cache = TieredMediaCache(rootDirectory: root, budgets: CacheBudgets(bytes: [:]))
    let service = try StubImageService()
    let server = MediaServer(
      baseURL: URL(string: "https://photos.example.ts.net")!, tokenProvider: { token })
    return Harness(
      pipeline: MediaPipeline(service: service, diskCache: cache, server: server),
      cache: cache, service: service, server: server)
  }

  func asset(id: String = "asset-1", thumbhash: String? = nil) -> Asset {
    Asset(
      id: id, ownerId: "u1", originalFileName: "IMG_001.heic", thumbhash: thumbhash,
      checksum: "chk", type: .image)
  }
}

/// Valid PNG bytes for seeding disk tiers (decoded through the real ImageIO path).
private func pngData(_ image: ThumbHashImage) throws -> Data {
  let cgImage = try #require(image.makeCGImage())
  let data = NSMutableData()
  guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
    throw StubError.failed
  }
  CGImageDestinationAddImage(dest, cgImage, nil)
  guard CGImageDestinationFinalize(dest) else { throw StubError.failed }
  return data as Data
}

private struct TierStep: Equatable {
  var tier: MediaTier
  var fromCache: Bool
}

private func tierOf(_ loaded: MediaLoadedImage) -> TierStep? {
  guard case let .tier(tier, _, fromCache) = loaded.content else { return nil }
  return TierStep(tier: tier, fromCache: fromCache)
}

@Suite struct MediaPipelineTests {
  @Test("[A2-04] online miss builds an authenticated, downsampled, high-priority request and caches it")
  func onlineMiss() async throws {
    let h = try await Harness.make()
    let loaded = try await h.pipeline.load(asset: h.asset(), tier: .thumbnail)

    #expect(tierOf(loaded) == TierStep(tier: .thumbnail, fromCache: false))
    let dataRequests = await h.service.dataRequests
    #expect(dataRequests.count == 1)
    let request = try #require(dataRequests.first)
    #expect(
      request.url?.absoluteString
        == "https://photos.example.ts.net/assets/asset-1/thumbnail?size=thumbnail")
    #expect(request.priority == .high)
    #expect(request.urlRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    let resize = try #require(request.processors.first as? ImageProcessors.Resize)
    #expect(
      resize
        == ImageProcessors.Resize(
          size: CGSize(width: 512, height: 512), unit: .pixels, contentMode: .aspectFit))
    // Bytes landed in the disk tier for offline use.
    #expect(await h.cache.retrieve(assetID: "asset-1", tier: .thumbnail) != nil)
  }

  @Test("[A2-04] progressive chain serves the cached tier first, then the requested network tier")
  func progressiveCachedThenNetwork() async throws {
    let h = try await Harness.make()
    let previewPNG = try pngData(ThumbHash.decode(base64: "1fsDBYBKeI97iIh4eIiIdweIdIBI"))
    try await h.cache.store(previewPNG, assetID: "asset-1", tier: .preview)

    var steps: [MediaLoadedImage] = []
    for try await step in await h.pipeline.stream(asset: h.asset(), tier: .original) {
      steps.append(step)
    }
    #expect(steps.count == 2)
    #expect(tierOf(steps[0]) == TierStep(tier: .preview, fromCache: true))
    #expect(tierOf(steps[1]) == TierStep(tier: .original, fromCache: false))
  }

  @Test("[A2-04] network failure falls back to the next lower tier")
  func networkFallback() async throws {
    let h = try await Harness.make()
    let originalURL = "https://photos.example.ts.net/assets/asset-1/original"
    await h.service.fail(urls: [originalURL])

    let loaded = try await h.pipeline.load(asset: h.asset(), tier: .original)
    #expect(tierOf(loaded) == TierStep(tier: .fullsize, fromCache: false))
  }

  @Test("[A2-04] cancelling a load cancels the in-flight fetch")
  func cancellation() async throws {
    let h = try await Harness.make()
    await h.service.setDelay(5_000_000_000)
    let task = Task { try await h.pipeline.load(asset: h.asset(), tier: .thumbnail) }
    try await Task.sleep(nanoseconds: 100_000_000)
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await h.service.imageRequests.isEmpty)
    #expect(await h.service.dataRequests.count == 1)
  }

  @Test("[A2-04] prefetch fans out at the lowest priority; cancel stops it")
  func prefetch() async throws {
    let h = try await Harness.make()
    await h.pipeline.prefetch(ids: ["a", "b", "c"], tier: .thumbnail)
    let batches = await h.service.prefetched
    #expect(batches.count == 1)
    #expect(batches.first?.count == 3)
    for request in batches.first ?? [] {
      #expect(request.priority == .veryLow)
      #expect(request.url?.absoluteString.hasSuffix("/thumbnail?size=thumbnail") == true)
    }
    await h.pipeline.cancelPrefetch()
    #expect(await h.service.stopPrefetchCalls == 1)
  }

  @Test("[A2-04] offline serves the best cached tier and reports when nothing is cached")
  func offline() async throws {
    let h = try await Harness.make()
    let thumbPNG = try pngData(ThumbHash.decode(base64: "1fsDBYBKeI97iIh4eIiIdweIdIBI"))
    try await h.cache.store(thumbPNG, assetID: "asset-1", tier: .thumbnail)
    await h.pipeline.setOffline(true)

    // Requested original, only thumbnail cached → thumbnail served, no network.
    let served = try await h.pipeline.load(asset: h.asset(), tier: .original)
    #expect(tierOf(served) == TierStep(tier: .thumbnail, fromCache: true))
    #expect(await h.service.dataRequests.isEmpty)

    // Nothing cached at all → the UI-facing unavailable state.
    await #expect(throws: MediaError.unavailableOffline(requested: .original, bestCached: nil)) {
      try await h.pipeline.load(asset: h.asset(id: "uncached"), tier: .original)
    }
  }

  @Test("[A2-04] pin downloads the original once and shields it from eviction")
  func pin() async throws {
    let h = try await Harness.make()
    try await h.pipeline.pin(assetIDs: ["asset-1"])
    #expect(await h.cache.isPinned(assetID: "asset-1", tier: .original))
    #expect(await h.cache.retrieve(assetID: "asset-1", tier: .original) != nil)
    let pinRequest = try #require(await h.service.dataRequests.first)
    #expect(pinRequest.url?.absoluteString == "https://photos.example.ts.net/assets/asset-1/original")
    #expect(pinRequest.processors.isEmpty)

    await h.pipeline.setBudget(1, for: .original)
    #expect(await h.cache.retrieve(assetID: "asset-1", tier: .original) != nil)
    await h.pipeline.unpin(assetIDs: ["asset-1"])
    #expect(await h.cache.isPinned(assetID: "asset-1", tier: .original) == false)
  }

  @Test("[A2-04] placeholder leads the chain when a thumbhash is present")
  func placeholderFirst() async throws {
    let h = try await Harness.make()
    var steps: [MediaLoadedImage] = []
    for try await step in await h.pipeline.stream(
      asset: h.asset(thumbhash: "1fsDBYBKeI97iIh4eIiIdweIdIBI"), tier: .thumbnail
    ) {
      steps.append(step)
    }
    #expect(steps.count == 2)
    guard case .placeholder = steps[0].content else {
      Issue.record("first step should be the thumbhash placeholder")
      return
    }
    #expect(tierOf(steps[1]) == TierStep(tier: .thumbnail, fromCache: false))
  }

  @Test("[A2-04] memory cache budget scales with device RAM inside fixed clamps")
  func memoryCacheSizing() {
    #expect(MediaPipeline.memoryCacheCostLimit(physicalMemoryBytes: 0) == 32 * 1024 * 1024)
    #expect(
      MediaPipeline.memoryCacheCostLimit(physicalMemoryBytes: 1_099_511_627_776)
        == 256 * 1024 * 1024)
    #expect(MediaPipeline.memoryCacheCostLimit(physicalMemoryBytes: 1_000_000_000) == 150_000_000)
    #expect(MediaPipeline.memoryCacheCostLimit(physicalMemoryBytes: 8_000_000_000) == 256 * 1024 * 1024)
    let host = MediaPipeline.memoryCacheCostLimit()
    #expect(host >= 32 * 1024 * 1024 && host <= 256 * 1024 * 1024)
  }
}
