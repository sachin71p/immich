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

/// In-memory `MediaImageService`: canned image, per-URL data/failures, full request log.
/// The WP1 pipeline never calls `image(for:)` on the thumbnail/preview path (single fetch +
/// local decode), so tests assert `imageRequests` stays empty and seed decodable PNG bytes
/// per URL for the data path.
private actor StubImageService: MediaImageService {
  var dataRequests: [ImageRequest] = []
  var imageRequests: [ImageRequest] = []
  var dataByURL: [String: Data] = [:]
  var failingURLs: Set<String> = []
  /// URL → HTTP status: throws the exact Nuke error chain the real pipeline produces for HTTP
  /// failures (`ImagePipeline.Error.dataLoadingFailed(DataLoader.Error.statusCodeUnacceptable)`),
  /// so negative-cache/classifier tests exercise the production unwrapping path.
  var statusFailures: [String: Int] = [:]
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

  func failWithStatus(url: String, status: Int) {
    statusFailures[url] = status
  }

  func setDelay(_ nanoseconds: UInt64) {
    delayNanoseconds = nanoseconds
  }

  func seed(data: Data, url: String) {
    dataByURL[url] = data
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
    if let status = statusFailures[url] {
      throw ImagePipeline.Error.dataLoadingFailed(
        error: DataLoader.Error.statusCodeUnacceptable(status))
    }
    if failingURLs.contains(url) { throw StubError.failed }
    return dataByURL[url] ?? Data("bytes-for-\(url)".utf8)
  }
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

  /// Seeds decodable PNG bytes for a network URL — the pipeline decodes `data` locally,
  /// so unseeded URLs (arbitrary bytes) fail the tier like corrupt downloads.
  func seedPNG(url: String) async throws {
    let png = try pngData(ThumbHash.decode(base64: "1fsDBYBKeI97iIh4eIiIdweIdIBI"))
    await service.seed(data: png, url: url)
  }

  func thumbnailURL(id: String = "asset-1") -> String {
    "https://photos.example.ts.net/assets/\(id)/thumbnail?size=thumbnail"
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
    try await h.seedPNG(url: h.thumbnailURL())
    let loaded = try await h.pipeline.load(asset: h.asset(), tier: .thumbnail)

    #expect(tierOf(loaded) == TierStep(tier: .thumbnail, fromCache: false))
    let dataRequests = await h.service.dataRequests
    #expect(dataRequests.count == 1)
    // WP1 §4.2: one network fetch — the old second `service.image` call is gone.
    #expect(await h.service.imageRequests.isEmpty)
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
    // Bytes landed in the disk tier for offline use, and the decoded image in memory.
    #expect(await h.cache.retrieve(assetID: "asset-1", tier: .thumbnail) != nil)
    #expect(h.pipeline.cachedImage(id: "asset-1", tier: .thumbnail) != nil)
  }

  @Test("[A2-04] progressive chain serves the cached tier first, then the requested network tier")
  func progressiveCachedThenNetwork() async throws {
    let h = try await Harness.make()
    let previewPNG = try pngData(ThumbHash.decode(base64: "1fsDBYBKeI97iIh4eIiIdweIdIBI"))
    try await h.cache.store(previewPNG, assetID: "asset-1", tier: .preview)
    try await h.seedPNG(url: "https://photos.example.ts.net/assets/asset-1/original")

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
    try await h.seedPNG(url: "https://photos.example.ts.net/assets/asset-1/thumbnail?size=fullsize")

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

  @Test("[WP1] prefetch warms disk+memory at low priority without touching image()")
  func prefetch() async throws {
    let h = try await Harness.make()
    for id in ["a", "b", "c"] {
      try await h.seedPNG(url: h.thumbnailURL(id: id))
    }
    let items: [(id: String, thumbhash: String?)] = [
      (id: "a", thumbhash: nil), (id: "b", thumbhash: nil), (id: "c", thumbhash: nil),
    ]
    await h.pipeline.prefetch(items, tier: .thumbnail)
    let dataRequests = await h.service.dataRequests
    #expect(dataRequests.count == 3)
    #expect(await h.service.imageRequests.isEmpty)
    for request in dataRequests {
      #expect(request.priority == .low)
      #expect(request.url?.absoluteString.hasSuffix("/thumbnail?size=thumbnail") == true)
    }
    // Prefetch wrote both caches, so visible cells hit synchronously.
    for id in ["a", "b", "c"] {
      #expect(await h.cache.retrieve(assetID: id, tier: .thumbnail) != nil)
      #expect(h.pipeline.cachedImage(id: id, tier: .thumbnail) != nil)
    }
    await h.pipeline.cancelPrefetch(keeping: [])
  }

  @Test("[WP1] concurrent visible loads share one network fetch (in-flight dedup)")
  func dedup() async throws {
    let h = try await Harness.make()
    try await h.seedPNG(url: h.thumbnailURL())
    async let first = h.pipeline.load(asset: h.asset(), tier: .thumbnail)
    async let second = h.pipeline.load(asset: h.asset(), tier: .thumbnail)
    let (loaded1, loaded2) = try await (first, second)
    #expect(tierOf(loaded1) == TierStep(tier: .thumbnail, fromCache: false))
    #expect(tierOf(loaded2) == TierStep(tier: .thumbnail, fromCache: false))
    #expect(await h.service.dataRequests.count == 1)
    #expect(await h.service.imageRequests.isEmpty)
  }

  @Test("[WP1] cancelPrefetch drops prefetch work outside the kept window")
  func cancelPrefetchKeeping() async throws {
    let h = try await Harness.make()
    await h.service.setDelay(5_000_000_000)
    let prefetchTask = Task {
      let items: [(id: String, thumbhash: String?)] = [(id: "gone", thumbhash: nil)]
      await h.pipeline.prefetch(items, tier: .thumbnail)
    }
    // Wait until the fetch is actually in flight (poll, not a fixed sleep).
    var waited = 0
    while await h.service.dataRequests.isEmpty, waited < 50 {
      try await Task.sleep(nanoseconds: 100_000_000)
      waited += 1
    }
    #expect(await h.service.dataRequests.count == 1)
    await h.pipeline.cancelPrefetch(keeping: [])
    await prefetchTask.value
    // The cancelled fetch was dropped: a later visible load refetches.
    await h.service.setDelay(0)
    try await h.seedPNG(url: h.thumbnailURL(id: "gone"))
    _ = try await h.pipeline.load(asset: h.asset(id: "gone"), tier: .thumbnail)
    #expect(await h.service.dataRequests.count == 2)
  }

  @Test("[WP1] row-based stream loads from TimelineRow fields with no Asset")
  func rowBasedStream() async throws {
    let h = try await Harness.make()
    try await h.seedPNG(url: h.thumbnailURL())
    var steps: [MediaLoadedImage] = []
    for try await step in await h.pipeline.stream(id: "asset-1", thumbhash: nil, tier: .thumbnail) {
      steps.append(step)
    }
    #expect(steps.count == 1)
    #expect(tierOf(steps[0]) == TierStep(tier: .thumbnail, fromCache: false))
    #expect(await h.service.dataRequests.count == 1)
    #expect(await h.service.imageRequests.isEmpty)
  }

  @Test("[WP1] personThumbnail uses the people route and the shared cache path")
  func personThumbnail() async throws {
    let h = try await Harness.make()
    let url = "https://photos.example.ts.net/people/p1/thumbnail"
    try await h.seedPNG(url: url)
    var steps: [MediaLoadedImage] = []
    for try await step in await h.pipeline.personThumbnail(id: "p1") {
      steps.append(step)
    }
    #expect(steps.count == 1)
    #expect(tierOf(steps[0]) == TierStep(tier: .thumbnail, fromCache: false))
    let dataRequests = await h.service.dataRequests
    #expect(dataRequests.count == 1)
    #expect(dataRequests.first?.url?.absoluteString == url)
    // Second open serves the memory tier with no new fetch.
    var cached: [MediaLoadedImage] = []
    for try await step in await h.pipeline.personThumbnail(id: "p1") {
      cached.append(step)
    }
    #expect(cached.count == 1)
    #expect(tierOf(cached[0]) == TierStep(tier: .thumbnail, fromCache: true))
    #expect(await h.service.dataRequests.count == 1)
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
    try await h.seedPNG(url: h.thumbnailURL())
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

  @Test("[WP1] thumbhash placeholders decode once and memoize per id")
  func placeholderMemoized() async throws {
    let h = try await Harness.make()
    #expect(h.pipeline.cachedPlaceholder(id: "asset-1") == nil)
    let image = try #require(
      await h.pipeline.placeholder(id: "asset-1", thumbhash: "1fsDBYBKeI97iIh4eIiIdweIdIBI"))
    #expect(h.pipeline.cachedPlaceholder(id: "asset-1") != nil)
    // A second call hits the cache (same pixels), with no network involved.
    let again = try #require(
      await h.pipeline.placeholder(id: "asset-1", thumbhash: "1fsDBYBKeI97iIh4eIiIdweIdIBI"))
    #expect(again.width == image.width && again.height == image.height)
    #expect(await h.service.dataRequests.isEmpty)
    #expect(await h.pipeline.placeholder(id: "missing", thumbhash: nil) == nil)
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

  @Test("[WP3FIX] classify: cancellations stay below Error, 4xx permanent, 5xx/timeout transient")
  func failureClassification() {
    // Cancelled completions log at debug, never error — all three cancellation carriers.
    #expect(MediaPipeline.classify(CancellationError()) == .cancelled)
    #expect(MediaPipeline.classify(URLError(.cancelled)) == .cancelled)
    #expect(MediaPipeline.classify(ImagePipeline.Error.cancelled) == .cancelled)
    // Permanent failures, bare and through the typed-throws `data(for:)` wrapper.
    #expect(
      MediaPipeline.classify(DataLoader.Error.statusCodeUnacceptable(404)) == .permanent(statusCode: 404))
    #expect(
      MediaPipeline.classify(
        ImagePipeline.Error.dataLoadingFailed(
          error: DataLoader.Error.statusCodeUnacceptable(403))) == .permanent(statusCode: 403))
    // Transient failures are never negatively cached.
    #expect(MediaPipeline.classify(DataLoader.Error.statusCodeUnacceptable(500)) == .transient)
    #expect(MediaPipeline.classify(URLError(.timedOut)) == .transient)
    #expect(MediaPipeline.classify(StubError.failed) == .transient)
  }

  @Test("[WP3FIX] 404 thumbnails are negatively cached: repeat prefetch + stream issue zero network")
  func negativeCache404() async throws {
    let h = try await Harness.make()
    await h.service.failWithStatus(url: h.thumbnailURL(id: "gone"), status: 404)
    await h.pipeline.prefetch([(id: "gone", thumbhash: nil)], tier: .thumbnail)
    #expect(await h.service.dataRequests.count == 1)
    // A second prefetch pass for the same id issues zero network requests.
    await h.pipeline.prefetch([(id: "gone", thumbhash: nil)], tier: .thumbnail)
    #expect(await h.service.dataRequests.count == 1)
    // The cell stream path consults the same hold: zero new requests, tier miss, no 404 refetch.
    var steps: [MediaLoadedImage] = []
    await #expect(throws: MediaError.nothingLoaded) {
      for try await step in await h.pipeline.stream(id: "gone", thumbhash: nil, tier: .thumbnail) {
        steps.append(step)
      }
    }
    #expect(steps.isEmpty)
    #expect(await h.service.dataRequests.count == 1)
  }

  @Test("[WP3FIX] transient failures (5xx) are NOT negatively cached")
  func noNegativeCacheTransient() async throws {
    let h = try await Harness.make()
    await h.service.failWithStatus(url: h.thumbnailURL(id: "flaky"), status: 500)
    await h.pipeline.prefetch([(id: "flaky", thumbhash: nil)], tier: .thumbnail)
    await h.pipeline.prefetch([(id: "flaky", thumbhash: nil)], tier: .thumbnail)
    #expect(await h.service.dataRequests.count == 2)
  }

  @Test("[WP3FIX] cancelPrefetch never cancels a task with a live visible consumer")
  func cancelPrefetchKeepsVisible() async throws {
    let h = try await Harness.make()
    try await h.seedPNG(url: h.thumbnailURL(id: "v"))
    await h.service.setDelay(1_000_000_000)
    let prefetchTask = Task {
      await h.pipeline.prefetch([(id: "v", thumbhash: nil)], tier: .thumbnail)
    }
    // Wait until the fetch is actually in flight (poll, not a fixed sleep).
    var waited = 0
    while await h.service.dataRequests.isEmpty, waited < 50 {
      try await Task.sleep(nanoseconds: 50_000_000)
      waited += 1
    }
    #expect(await h.service.dataRequests.count == 1)
    // A cell scrolling into view joins the in-flight prefetch (same bytes, visible refcount);
    // the window then moves, releasing the prefetch hold but keeping the visible consumer. The
    // sleep lets the visible task reach the in-flight join (microseconds + one local disk probe)
    // well inside the 1 s network delay, so the cancel below tests the joined state, not a race.
    let visibleTask = Task { try await h.pipeline.load(asset: h.asset(id: "v"), tier: .thumbnail) }
    try await Task.sleep(nanoseconds: 300_000_000)
    await h.pipeline.cancelPrefetch(keeping: [])
    let loaded = try await visibleTask.value
    await prefetchTask.value
    #expect(tierOf(loaded) == TierStep(tier: .thumbnail, fromCache: false))
    #expect(await h.service.dataRequests.count == 1)
  }

  @Test("[WP3FIX] PrefetchWindowTracker: same settled window no-ops, moves and reloads re-issue")
  func prefetchWindowTracker() {
    var tracker = MediaPipeline.PrefetchWindowTracker()
    #expect(tracker.shouldIssue(window: ["a", "b"], generation: 1) == true)
    #expect(tracker.shouldIssue(window: ["a", "b"], generation: 1) == false)
    #expect(tracker.shouldIssue(window: ["b", "a"], generation: 1) == false)
    #expect(tracker.shouldIssue(window: ["a", "c"], generation: 1) == true)
    #expect(tracker.shouldIssue(window: ["a", "c"], generation: 1) == false)
    #expect(tracker.shouldIssue(window: ["a", "c"], generation: 2) == true)
    #expect(tracker.shouldIssue(window: [], generation: 2) == false)
  }
}
