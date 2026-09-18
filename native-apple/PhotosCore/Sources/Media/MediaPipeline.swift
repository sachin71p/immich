import CoreGraphics
import CoreModel
import Foundation
import ImageIO
import Nuke

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Server handle for media loads: base URL plus an async bearer-token source (the app layer
/// reads the Keychain/`TokenStore`; the pipeline never stores credentials itself).
public struct MediaServer: Sendable {
  public var baseURL: URL
  public var tokenProvider: @Sendable () async -> String?

  public init(baseURL: URL, tokenProvider: @Sendable @escaping () async -> String? = { nil }) {
    self.baseURL = baseURL
    self.tokenProvider = tokenProvider
  }
}

/// The Nuke seam — `data(for:)` is the only network primitive the thumbnail/preview path
/// uses (WP1 §4.2: one fetch, then local decode). `image(for:)` remains for callers that
/// need Nuke's decoder, but the pipeline itself no longer calls it on the grid path.
public protocol MediaImageService: Sendable {
  func image(for request: ImageRequest) async throws -> PlatformImage
  func data(for request: ImageRequest) async throws -> Data
}

public struct NukeMediaImageService: MediaImageService {
  public var pipeline: ImagePipeline

  public init(pipeline: ImagePipeline = .shared) {
    self.pipeline = pipeline
  }

  public func image(for request: ImageRequest) async throws -> PlatformImage {
    try await pipeline.image(for: request)
  }

  public func data(for request: ImageRequest) async throws -> Data {
    try await pipeline.data(for: request).0
  }
}

public enum MediaError: Error, Sendable, Equatable {
  /// Offline with nothing usable cached (or the cached file gone) — the UI state from task 4.
  case unavailableOffline(requested: MediaTier, bestCached: MediaTier?)
  case nothingLoaded
}

/// One step of the progressive chain: thumbhash placeholder → cached tier → network tiers.
public struct MediaLoadedImage: Sendable {
  public enum Content: Sendable {
    case placeholder(PlatformImage)
    case tier(MediaTier, PlatformImage, fromCache: Bool)
  }

  public var content: Content
  public var dynamicRange: MediaFormatInfo.DynamicRange

  public init(content: Content, dynamicRange: MediaFormatInfo.DynamicRange) {
    self.content = content
    self.dynamicRange = dynamicRange
  }
}

/// Progressive image pipeline — brief task 2: thumbhash placeholder → thumbnail → preview →
/// original (on zoom or explicit), with device-sized memory cache, per-tier disk
/// cache underneath, request priorities + cancellation for fast scroll, and a grid prefetcher.
///
/// WP1 §4 changes: single network fetch per tier (`data` then local `decodeImage` — never
/// `service.image` on the thumbnail/preview path), a synchronous `MediaMemoryCache` for
/// cell configuration, a thumbhash placeholder cache, in-flight de-duplication between
/// visible and prefetch consumers, and a lazy `TieredMediaCache` index.
public actor MediaPipeline {
  private let service: any MediaImageService
  private let diskCache: TieredMediaCache
  private let server: MediaServer
  private var offline: Bool

  /// Synchronous decoded-image store — cells hit this on the main thread via `cachedImage`.
  public nonisolated let memory: MediaMemoryCache

  /// In-flight fetch shared by visible and prefetch consumers of the same bytes.
  private struct InFlightEntry {
    var task: Task<CGImage, any Error>
    var visible: Int
    var prefetch: Bool
    var id: String
    var epoch: UInt64
  }

  private var inFlight: [String: InFlightEntry] = [:]
  private var epochCounter: UInt64 = 0

  /// Negative cache for permanent fetch failures (HTTP 400–499): id+tier → hold expiry.
  /// A 404ing thumbnail would otherwise be refetched on every prefetch pass and every cell
  /// configure — the Gate-3 flood (138 404s for 899 ids during pure idle). Holds last
  /// `negativeCacheTTL`; transient failures (5xx, timeouts, cancellations) are never held.
  private var negativeCache: [String: Date] = [:]
  private static let negativeCacheTTL: TimeInterval = 600

  /// Collapses identical failure logs to one error per id per minute (Gate-3's single id
  /// logging dozens of 404s per millisecond): message key → last error-log time. Repeats
  /// inside the window go to debug.
  private var failureLogState: [String: Date] = [:]
  private static let failureLogThrottle: TimeInterval = 60

  public init(
    service: any MediaImageService,
    diskCache: TieredMediaCache,
    server: MediaServer,
    offline: Bool = false,
    memory: MediaMemoryCache = MediaMemoryCache(costLimit: memoryCacheCostLimit())
  ) {
    self.service = service
    self.diskCache = diskCache
    self.server = server
    self.offline = offline
    self.memory = memory
  }

  /// Default pipeline: a dedicated Nuke pipeline whose memory cache is sized to the device.
  ///
  /// - parameter protocolClasses: extra `URLProtocol` classes prepended to the private
  ///   `URLSession` Nuke loads through. A global `URLProtocol.registerClass` does NOT
  ///   intercept a session Nuke creates itself, so the fixture stub must be injected here —
  ///   otherwise every fixture media load fails DNS, the stream yields no tier, and the
  ///   viewer (and grid) stays imageless.
  public static func makeDefault(
    diskCache: TieredMediaCache,
    server: MediaServer,
    protocolClasses: [AnyClass] = []
  ) -> MediaPipeline {
    var configuration = ImagePipeline.Configuration()
    configuration.imageCache = ImageCache(costLimit: memoryCacheCostLimit())
    if !protocolClasses.isEmpty {
      let sessionConfiguration = DataLoader.defaultConfiguration
      sessionConfiguration.protocolClasses =
        protocolClasses + (sessionConfiguration.protocolClasses ?? [])
      configuration.dataLoader = DataLoader(configuration: sessionConfiguration)
    }
    let pipeline = ImagePipeline(configuration: configuration)
    return MediaPipeline(
      service: NukeMediaImageService(pipeline: pipeline), diskCache: diskCache, server: server)
  }

  /// Memory cache budget: 15% of RAM clamped to 32–256 MB.
  public static func memoryCacheCostLimit(
    physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
  ) -> Int {
    let fifteenPercent = Double(physicalMemoryBytes) * 0.15
    return min(256 * 1024 * 1024, max(32 * 1024 * 1024, Int(fifteenPercent)))
  }

  public func setOffline(_ offline: Bool) {
    self.offline = offline
  }

  // MARK: - synchronous cache probes (main-thread cell configuration)

  /// Decoded-image hit without suspending — `nil` means "start (or join) a `stream`".
  public nonisolated func cachedImage(id: String, tier: MediaTier, edited: Bool = false) -> CGImage? {
    memory.cached(id: id, tier: tier, edited: edited)
  }

  /// Thumbhash-placeholder hit without suspending.
  public nonisolated func cachedPlaceholder(id: String) -> CGImage? {
    memory.cachedPlaceholder(id: id)
  }

  /// Decodes (then memoizes) the thumbhash placeholder for `id`.
  public func placeholder(id: String, thumbhash: String?) async -> CGImage? {
    if let hit = memory.cachedPlaceholder(id: id) { return hit }
    guard let thumbhash,
      let decoded = try? ThumbHash.decode(base64: thumbhash),
      let cgImage = decoded.makeCGImage()
    else { return nil }
    memory.storePlaceholder(cgImage, id: id)
    return cgImage
  }

  // MARK: - loading

  /// Progressive steps for an asset: instant thumbhash placeholder (when present), then the best
  /// cached tier, then network tiers from the requested one downward. Breaking out of the
  /// iteration cancels the in-flight fetch (fast-scroll reuse).
  public func stream(
    asset: Asset,
    tier requested: MediaTier,
    edited: Bool = false,
    pixelSize: Int? = nil,
    format: MediaFormatInfo? = nil
  ) -> AsyncThrowingStream<MediaLoadedImage, any Error> {
    let format = format ?? MediaFormatInfo.classify(fileName: asset.originalFileName)
    return stream(
      id: asset.id, thumbhash: asset.thumbhash, tier: requested, edited: edited,
      pixelSize: pixelSize, format: format)
  }

  /// Row-based progressive steps — needs no full `Asset`, so WP2's cells load from
  /// `TimelineRow` fields alone (R9: "cells need a full Asset to load").
  public func stream(
    id: String,
    thumbhash: String?,
    tier requested: MediaTier,
    edited: Bool = false,
    pixelSize: Int? = nil,
    format: MediaFormatInfo = .standardDefault
  ) -> AsyncThrowingStream<MediaLoadedImage, any Error> {
    let pipeline = self
    let pixelSize = pixelSize ?? requested.defaultPixelSize
    return AsyncThrowingStream { continuation in
      let task = Task.detached {
        do {
          if let image = await pipeline.placeholder(id: id, thumbhash: thumbhash) {
            continuation.yield(
              MediaLoadedImage(
                content: .placeholder(Self.platformImage(cgImage: image)),
                dynamicRange: format.dynamicRange))
          }

          if let hit = pipeline.memory.cached(id: id, tier: requested, edited: edited) {
            continuation.yield(
              MediaLoadedImage(
                content: .tier(requested, Self.platformImage(cgImage: hit), fromCache: true),
                dynamicRange: format.dynamicRange))
            continuation.finish()
            return
          }

          let offline = await pipeline.isOffline
          if offline {
            let cached = await pipeline.diskCache.cachedTiers(assetID: id, edited: edited)
            guard let best = cached.first else {
              throw MediaError.unavailableOffline(requested: requested, bestCached: nil)
            }
            guard
              let data = await pipeline.diskCache.retrieve(
                assetID: id, tier: best, edited: edited),
              let cgImage = await Self.decodeOffActor(data, pixelSize: pixelSize)
            else {
              throw MediaError.unavailableOffline(requested: requested, bestCached: best)
            }
            pipeline.memory.store(cgImage, id: id, tier: best, edited: edited)
            continuation.yield(
              MediaLoadedImage(
                content: .tier(best, Self.platformImage(cgImage: cgImage), fromCache: true),
                dynamicRange: format.dynamicRange))
            continuation.finish()
            return
          }

          let order = MediaTier.fallbackOrder(from: requested)
          var yielded: Set<MediaTier> = []
          let cached = await pipeline.diskCache.cachedTiers(assetID: id, edited: edited)
            .filter { order.contains($0) }
          if let best = cached.first,
            let data = await pipeline.diskCache.retrieve(assetID: id, tier: best, edited: edited),
            let cgImage = await Self.decodeOffActor(data, pixelSize: pixelSize)
          {
            pipeline.memory.store(cgImage, id: id, tier: best, edited: edited)
            continuation.yield(
              MediaLoadedImage(
                content: .tier(best, Self.platformImage(cgImage: cgImage), fromCache: true),
                dynamicRange: format.dynamicRange))
            yielded.insert(best)
            if best == requested {
              continuation.finish()
              return
            }
          }

          var lastError: (any Error)?
          for tier in order {
            // Anything at or below the already-shown cached tier adds nothing.
            if let best = cached.first, tier.rank <= best.rank, yielded.contains(best) { continue }
            if yielded.contains(tier) { continue }
            try Task.checkCancellation()
            do {
              let size = tier == requested ? pixelSize : tier.defaultPixelSize
              let url = MediaEndpoint(
                serverURL: await pipeline.serverBaseURL, assetID: id
              ).url(for: tier, edited: edited)
              let cgImage = try await pipeline.fetchTier(
                cacheID: id, id: id, url: url, tier: tier, edited: edited,
                pixelSize: size, priority: .high, asPrefetch: false)
              continuation.yield(
                MediaLoadedImage(
                  content: .tier(tier, Self.platformImage(cgImage: cgImage), fromCache: false),
                  dynamicRange: format.dynamicRange))
              continuation.finish()
              return
            } catch let error as CancellationError {
              throw error
            } catch is NegativeCacheHit {
              // Under a negative-cache hold: skip the tier without network work and without
              // poisoning `lastError` — a lower tier may still serve.
              continue
            } catch {
              lastError = error
            }
          }
          if yielded.isEmpty {
            throw lastError ?? MediaError.nothingLoaded
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Person thumbnail for the People grid — same cache path as assets (memory → disk →
  /// network) with tier `.thumbnail` and cache key prefix `person:`, served from
  /// `GET /people/{id}/thumbnail`.
  public func personThumbnail(id: String) -> AsyncThrowingStream<MediaLoadedImage, any Error> {
    let pipeline = self
    let cacheID = "person:\(id)"
    return AsyncThrowingStream { continuation in
      let task = Task.detached {
        do {
          if let hit = pipeline.memory.cached(id: cacheID, tier: .thumbnail, edited: false) {
            continuation.yield(
              MediaLoadedImage(
                content: .tier(.thumbnail, Self.platformImage(cgImage: hit), fromCache: true),
                dynamicRange: .sdr))
            continuation.finish()
            return
          }
          if await pipeline.isOffline {
            guard
              let data = await pipeline.diskCache.retrieve(
                assetID: cacheID, tier: .thumbnail),
              let cgImage = await Self.decodeOffActor(
                data, pixelSize: MediaTier.thumbnail.defaultPixelSize)
            else {
              throw MediaError.unavailableOffline(requested: .thumbnail, bestCached: nil)
            }
            pipeline.memory.store(cgImage, id: cacheID, tier: .thumbnail, edited: false)
            continuation.yield(
              MediaLoadedImage(
                content: .tier(.thumbnail, Self.platformImage(cgImage: cgImage), fromCache: true),
                dynamicRange: .sdr))
            continuation.finish()
            return
          }
          if let data = await pipeline.diskCache.retrieve(assetID: cacheID, tier: .thumbnail),
            let cgImage = await Self.decodeOffActor(
              data, pixelSize: MediaTier.thumbnail.defaultPixelSize)
          {
            pipeline.memory.store(cgImage, id: cacheID, tier: .thumbnail, edited: false)
            continuation.yield(
              MediaLoadedImage(
                content: .tier(.thumbnail, Self.platformImage(cgImage: cgImage), fromCache: true),
                dynamicRange: .sdr))
            continuation.finish()
            return
          }
          try Task.checkCancellation()
          let url = MediaEndpoint.personThumbnailURL(
            serverURL: await pipeline.serverBaseURL, personID: id)
          let cgImage = try await pipeline.fetchTier(
            cacheID: cacheID, id: id, url: url, tier: .thumbnail, edited: false,
            pixelSize: MediaTier.thumbnail.defaultPixelSize, priority: .high, asPrefetch: false)
          continuation.yield(
            MediaLoadedImage(
              content: .tier(.thumbnail, Self.platformImage(cgImage: cgImage), fromCache: false),
              dynamicRange: .sdr))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Convenience for zoom/viewer: the final (best) step of `stream`.
  public func load(
    asset: Asset,
    tier: MediaTier,
    edited: Bool = false,
    pixelSize: Int? = nil,
    format: MediaFormatInfo? = nil
  ) async throws -> MediaLoadedImage {
    var last: MediaLoadedImage?
    for try await step in stream(
      asset: asset, tier: tier, edited: edited, pixelSize: pixelSize, format: format
    ) {
      last = step
    }
    // A cancelled consumer ends the iteration with no error of its own — surface it.
    try Task.checkCancellation()
    guard let last else { throw MediaError.nothingLoaded }
    return last
  }

  // MARK: - prefetch (grid)

  /// Warms the memory and disk caches for upcoming grid cells. Work is capped at 8
  /// concurrent network loads; `cancelPrefetch(keeping:)` drops the rest. Prefetch loads
  /// run at `.low` priority while visible loads run `.high`, and a cell that scrolls into
  /// view joins an in-flight prefetch task instead of starting a new fetch.
  public func prefetch(_ items: [(id: String, thumbhash: String?)], tier: MediaTier) async {
    await withTaskGroup(of: Void.self) { group in
      var active = 0
      for item in items {
        if Task.isCancelled { break }
        if active >= 8 {
          await group.next()
          active -= 1
        }
        group.addTask { await self.prefetchOne(id: item.id, tier: tier, edited: false) }
        active += 1
      }
    }
  }

  /// Cancels prefetch work for every id outside `keeping` — the grid calls this as the
  /// visible window moves. Tasks with a visible consumer are kept (their prefetch hold is
  /// just released); shared visible+prefetch tasks survive until the cell cancels.
  public func cancelPrefetch(keeping ids: Set<String>) {
    for (key, entry) in inFlight where entry.prefetch && !ids.contains(entry.id) {
      if entry.visible == 0 {
        entry.task.cancel()
        inFlight.removeValue(forKey: key)
      } else {
        inFlight[key]?.prefetch = false
      }
    }
  }

  /// Remembers the last issued prefetch window so the grid's `prefetchPass` no-ops when the
  /// settled visible-id window is unchanged since the last pass. Lives in PhotosCore (not the
  /// app target) so the storm gate is unit-testable — the macOS app has no unit-test target.
  /// The snapshot generation is part of the key: a reload re-issues even for the same window.
  public struct PrefetchWindowTracker: Sendable {
    private var lastWindow: Set<String> = []
    private var lastGeneration: Int = -1
    private var hasIssued = false

    public init() {}

    /// Returns false (and records nothing) for empty windows or exact repeats; otherwise records
    /// the window and returns true.
    public mutating func shouldIssue(window: Set<String>, generation: Int) -> Bool {
      guard !window.isEmpty else { return false }
      if hasIssued, window == lastWindow, generation == lastGeneration { return false }
      lastWindow = window
      lastGeneration = generation
      hasIssued = true
      return true
    }
  }

  /// Pre-WP1 entry points, kept until WP2/WP3 migrate (the app still calls `prefetch(ids:)`).
  /// Now routed through the same dedup/memory/disk path as the grid prefetcher.
  public func prefetch(ids: [String], tier: MediaTier, edited: Bool = false) async {
    await withTaskGroup(of: Void.self) { group in
      var active = 0
      for id in ids {
        if Task.isCancelled { break }
        if active >= 8 {
          await group.next()
          active -= 1
        }
        group.addTask { await self.prefetchOne(id: id, tier: tier, edited: edited) }
        active += 1
      }
    }
  }

  public func cancelPrefetch() {
    cancelPrefetch(keeping: [])
  }

  // MARK: - offline keeps (pinning)

  /// Keeps full originals on device for an album/space/library/favorites id list — task 3.
  /// Missing bytes download once, then the pin protects them from every eviction.
  public func pin(assetIDs: [String], tier: MediaTier = .original, edited: Bool = false) async throws {
    for id in assetIDs {
      try Task.checkCancellation()
      if await diskCache.retrieve(assetID: id, tier: tier, edited: edited) == nil {
        if offline { throw MediaError.unavailableOffline(requested: tier, bestCached: nil) }
        let request = await Self.networkRequest(
          server: server, assetID: id, tier: tier, edited: edited,
          priority: .low, pixelSize: nil
        )
        let data = try await service.data(for: request)
        try await diskCache.store(data, assetID: id, tier: tier, edited: edited)
      }
      await diskCache.setPinned(true, assetID: id, tier: tier, edited: edited)
    }
  }

  public func unpin(assetIDs: [String], tier: MediaTier = .original, edited: Bool = false) async {
    for id in assetIDs {
      await diskCache.setPinned(false, assetID: id, tier: tier, edited: edited)
    }
  }

  // MARK: - budget policy (A6 surface)

  public func setBudget(_ bytes: Int?, for tier: MediaTier) async {
    await diskCache.setBudget(bytes, for: tier)
  }

  public func usage() async -> [MediaTier: Int] {
    await diskCache.usage()
  }

  @discardableResult
  public func evict(freeing byteCount: Int, from tier: MediaTier) async -> Int {
    await diskCache.evict(freeing: byteCount, from: tier)
  }

  // MARK: - deduped fetch

  private var isOffline: Bool { offline }

  private var serverBaseURL: URL { server.baseURL }

  // MARK: - failure classification + negative cache

  /// Thrown by `fetchTier` instead of network work when the id+tier is under a negative-cache
  /// hold. Callers treat it as a silent tier miss (prefetch drops it, `stream` tries the next
  /// lower tier); it is never error-logged.
  struct NegativeCacheHit: Error {
    var id: String
  }

  /// How a fetch failure is handled: cancellations log at debug, permanent HTTP failures
  /// (4xx except 401, which must survive a silent token refresh) take a 10-minute
  /// negative-cache hold, everything else just logs (throttled).
  enum FetchFailureClass: Equatable {
    case cancelled
    case permanent(statusCode: Int)
    case transient
  }

  /// Classifies a fetch error without touching the network. Real 404s arrive wrapped as
  /// `ImagePipeline.Error.dataLoadingFailed(DataLoader.Error.statusCodeUnacceptable(404))`;
  /// Nuke task cancellations can arrive as `ImagePipeline.Error.cancelled` rather than a
  /// Swift `CancellationError`, so both are treated as cancellation.
  static func classify(_ error: Error) -> FetchFailureClass {
    if error is CancellationError { return .cancelled }
    if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
    if let pipelineError = error as? ImagePipeline.Error, case .cancelled = pipelineError {
      return .cancelled
    }
    if let code = httpStatusCode(of: error) {
      // 401 is transient: an in-place token refresh must retry within the hold window
      // instead of staying suppressed until expiry/rebuild.
      return code != 401 && (400..<500).contains(code) ? .permanent(statusCode: code) : .transient
    }
    return .transient
  }

  /// Extracts an HTTP status code from Nuke's error wrappers, unwrapping one level of
  /// `NSUnderlyingErrorKey` chaining (typed-throws `data(for:)` wraps the `DataLoader` error
  /// in `ImagePipeline.Error.dataLoadingFailed`).
  static func httpStatusCode(of error: Error) -> Int? {
    if let loaderError = error as? DataLoader.Error,
      case .statusCodeUnacceptable(let code) = loaderError
    {
      return code
    }
    if let pipelineError = error as? ImagePipeline.Error,
      let underlying = pipelineError.dataLoadingError,
      let loaderError = underlying as? DataLoader.Error,
      case .statusCodeUnacceptable(let code) = loaderError
    {
      return code
    }
    let ns = error as NSError
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
      return httpStatusCode(of: underlying)
    }
    return nil
  }

  private func negativeCacheKey(cacheID: String, tier: MediaTier, edited: Bool) -> String {
    "\(cacheID)|\(tier.rawValue)|\(edited)"
  }

  /// Consulted by `fetchTier` — the single choke point both `prefetch` and the cell `stream`
  /// path funnel through — before any network work is issued.
  private func isNegativeCached(cacheID: String, tier: MediaTier, edited: Bool) -> Bool {
    let key = negativeCacheKey(cacheID: cacheID, tier: tier, edited: edited)
    guard let expiry = negativeCache[key] else { return false }
    if expiry > Date() { return true }
    negativeCache.removeValue(forKey: key)
    return false
  }

  private func recordNegative(cacheID: String, tier: MediaTier, edited: Bool) {
    if negativeCache.count > 20_000 {
      let now = Date()
      negativeCache = negativeCache.filter { $0.value > now }
    }
    negativeCache[negativeCacheKey(cacheID: cacheID, tier: tier, edited: edited)] =
      Date().addingTimeInterval(Self.negativeCacheTTL)
  }

  /// Cancellation is routine (fast scroll, reuse, superseded passes) — debug, never error.
  /// Anything else logs at error at most once per id per minute; repeats go to debug so one
  /// bad asset can never flood the log again.
  private func logFetchFailure(id: String, tier: MediaTier, error: Error) {
    switch Self.classify(error) {
    case .cancelled:
      HeirloomLog.media.debug(
        "fetch cancelled for \(id, privacy: .public) tier \(tier.rawValue, privacy: .public)")
      return
    case .permanent, .transient:
      break
    }
    let key = "\(id)|\(tier.rawValue)|\(String(describing: error))"
    let now = Date()
    if let last = failureLogState[key], now.timeIntervalSince(last) < Self.failureLogThrottle {
      HeirloomLog.media.debug(
        "fetch failed (repeat, throttled) for \(id, privacy: .public) tier \(tier.rawValue, privacy: .public)"
      )
      return
    }
    if failureLogState.count > 5000 {
      failureLogState = failureLogState.filter { now.timeIntervalSince($0.value) < Self.failureLogThrottle }
    }
    failureLogState[key] = now
    HeirloomLog.media.error(
      "fetch failed for \(id, privacy: .public) tier \(tier.rawValue, privacy: .public): \(error, privacy: .public)"
    )
  }

  private func prefetchOne(id: String, tier: MediaTier, edited: Bool) async {
    // Memory hits need no work; a disk hit still warms the memory cache for the cell.
    if memory.cached(id: id, tier: tier, edited: edited) != nil { return }
    if let data = await diskCache.retrieve(assetID: id, tier: tier, edited: edited),
      let cgImage = await Self.decodeOffActor(data, pixelSize: tier.defaultPixelSize)
    {
      memory.store(cgImage, id: id, tier: tier, edited: edited)
      return
    }
    if offline { return }
    let url = MediaEndpoint(serverURL: server.baseURL, assetID: id).url(
      for: tier, edited: edited)
    do {
      _ = try await fetchTier(
        cacheID: id, id: id, url: url, tier: tier, edited: edited,
        pixelSize: tier.defaultPixelSize, priority: .low, asPrefetch: true)
    } catch is CancellationError {
      // Scrolled past or superseded — routine, not a failure.
      HeirloomLog.media.debug("prefetch cancelled for \(id, privacy: .public)")
    } catch is NegativeCacheHit {
      // Under a negative-cache hold after a permanent failure: no network issued, nothing to log.
    } catch {
      // Network/decode failures are already (throttle-)logged inside `fetchTier`; logging here
      // too would double every prefetch failure.
    }
  }

  /// Fetches one tier through the in-flight table: a visible cell joins an existing
  /// prefetch task for the same bytes instead of starting a new fetch.
  private func fetchTier(
    cacheID: String, id: String, url: URL, tier: MediaTier, edited: Bool,
    pixelSize: Int?, priority: ImageRequest.Priority, asPrefetch: Bool
  ) async throws -> CGImage {
    let service = self.service
    let diskCache = self.diskCache
    let server = self.server
    let memory = self.memory
    // Permanent failures hold the id+tier for 10 minutes: every prefetch pass and cell
    // configure funnels through here, so without this a single 404ing thumbnail refetches
    // (and error-logs) forever.
    if isNegativeCached(cacheID: cacheID, tier: tier, edited: edited) {
      throw NegativeCacheHit(id: id)
    }
    let key = "\(cacheID)|\(tier.rawValue)|\(edited)|\(pixelSize ?? -1)"
    return try await fetchDeduped(key: key, id: id, asPrefetch: asPrefetch) {
      do {
        try Task.checkCancellation()
        var urlRequest = URLRequest(url: url)
        if let token = await server.tokenProvider() {
          urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // The Resize processor downsamples to the target pixel size at decode time so full
        // files never inflate to full bitmaps for grid cells. Prefetch runs `.low`,
        // visible loads `.high`.
        var processors: [any ImageProcessing] = []
        if let pixelSize {
          processors.append(
            ImageProcessors.Resize(
              size: CGSize(width: pixelSize, height: pixelSize), unit: .pixels,
              contentMode: .aspectFit))
        }
        let request = ImageRequest(
          urlRequest: urlRequest, processors: processors, priority: priority)
        let data = try await HeirloomSignpost.interval(HeirloomSignpost.thumbnailFetch) {
          try await service.data(for: request)
        }
        // Single network fetch (WP1 §4.2): bytes go to disk, then decode locally — the old
        // `service.image(for:)` second fetch is gone.
        try await diskCache.store(data, assetID: cacheID, tier: tier, edited: edited)
        guard let cgImage = await Self.decodeOffActor(data, pixelSize: pixelSize) else {
          throw MediaError.nothingLoaded
        }
        memory.store(cgImage, id: cacheID, tier: tier, edited: edited)
        return cgImage
      } catch {
        // Single logging site for every fetch failure (throttled to one error per id per
        // minute; cancellations at debug): `prefetchOne` and `stream` stay silent so failures
        // are never double-logged. Permanent HTTP failures also take a negative-cache hold.
        if case .permanent = Self.classify(error) {
          await self.recordNegative(cacheID: cacheID, tier: tier, edited: edited)
        }
        await self.logFetchFailure(id: id, tier: tier, error: error)
        throw error
      }
    }
  }

  /// Joins the in-flight task for `key`, or starts it. Cancellation only cancels the
  /// shared task once the last visible consumer goes away *and* no prefetch holds it
  /// (reference count). Completion removes the entry; stragglers holding the task handle
  /// still get its value. `epoch` guards against a new entry reusing the key mid-flight.
  private func fetchDeduped(
    key: String, id: String, asPrefetch: Bool,
    work: @Sendable @escaping () async throws -> CGImage
  ) async throws -> CGImage {
    let task: Task<CGImage, any Error>
    let epoch: UInt64
    if var entry = inFlight[key] {
      task = entry.task
      epoch = entry.epoch
      if asPrefetch {
        entry.prefetch = true
      } else {
        entry.visible += 1
      }
      inFlight[key] = entry
    } else {
      epochCounter += 1
      epoch = epochCounter
      task = Task.detached(priority: asPrefetch ? .low : .userInitiated, operation: work)
      inFlight[key] = InFlightEntry(
        task: task, visible: asPrefetch ? 0 : 1, prefetch: asPrefetch, id: id, epoch: epoch)
    }
    do {
      let image = try await withTaskCancellationHandler(operation: { try await task.value }) {
        Task { await self.releaseLoad(key: key, epoch: epoch, asPrefetch: asPrefetch) }
      }
      completeLoad(key: key, epoch: epoch)
      return image
    } catch {
      completeLoad(key: key, epoch: epoch)
      throw error
    }
  }

  private func releaseLoad(key: String, epoch: UInt64, asPrefetch: Bool) {
    guard var entry = inFlight[key], entry.epoch == epoch else { return }
    if asPrefetch {
      entry.prefetch = false
    } else {
      entry.visible = max(0, entry.visible - 1)
    }
    if entry.visible == 0, !entry.prefetch {
      entry.task.cancel()
      inFlight.removeValue(forKey: key)
    } else {
      inFlight[key] = entry
    }
  }

  private func completeLoad(key: String, epoch: UInt64) {
    if inFlight[key]?.epoch == epoch {
      inFlight.removeValue(forKey: key)
    }
  }

  // MARK: - requests & decoding

  static func networkRequest(
    server: MediaServer,
    assetID: String,
    tier: MediaTier,
    edited: Bool,
    priority: ImageRequest.Priority,
    pixelSize: Int?
  ) async -> ImageRequest {
    var urlRequest = URLRequest(
      url: MediaEndpoint(serverURL: server.baseURL, assetID: assetID).url(for: tier, edited: edited))
    if let token = await server.tokenProvider() {
      urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    // Nuke decodes off the caller's thread; the Resize processor downsamples to the target
    // pixel size at decode time so full files never inflate to full bitmaps for grid cells.
    var processors: [any ImageProcessing] = []
    if let pixelSize {
      processors.append(
        ImageProcessors.Resize(
          size: CGSize(width: pixelSize, height: pixelSize), unit: .pixels, contentMode: .aspectFit))
    }
    return ImageRequest(urlRequest: urlRequest, processors: processors, priority: priority)
  }

  /// ImageIO thumbnail decode on a non-actor background task (never the main thread):
  /// applies EXIF orientation and downsamples to the target pixel size without inflating
  /// the full bitmap. Returns `nil` for undecodable bytes (treated as a tier miss).
  static func decodeOffActor(_ data: Data, pixelSize: Int?) async -> CGImage? {
    await Task.detached(priority: .userInitiated) {
      HeirloomSignpost.interval(HeirloomSignpost.thumbnailDecode) {
        Self.decodeImage(data, pixelSize: pixelSize)
      }
    }.value
  }

  /// Local-file decode path (disk hits, offline): ImageIO thumbnailing applies EXIF orientation
  /// and downsamples to the target pixel size without inflating the full bitmap.
  static func decodeImage(_ data: Data, pixelSize: Int?) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: CFDictionary =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: pixelSize ?? 4096,
        kCGImageSourceCreateThumbnailWithTransform: true,
      ] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
  }

  static func platformImage(cgImage: CGImage) -> PlatformImage {
    #if canImport(UIKit)
    return UIImage(cgImage: cgImage)
    #elseif canImport(AppKit)
    return NSImage(cgImage: cgImage, size: NSZeroSize)
    #endif
  }
}
