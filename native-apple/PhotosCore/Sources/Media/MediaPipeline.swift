import CoreModel
import CoreGraphics
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

/// The Nuke seam — brief task 2 runs on Nuke (memory cache, request coalescing, priorities,
/// prefetching, cancellation). Production is `NukeMediaImageService`; tests inject a stub.
public protocol MediaImageService: Sendable {
  func image(for request: ImageRequest) async throws -> PlatformImage
  func data(for request: ImageRequest) async throws -> Data
  func prefetch(_ requests: [ImageRequest])
  func stopPrefetching()
}

public struct NukeMediaImageService: MediaImageService {
  public var pipeline: ImagePipeline
  public var prefetcher: ImagePrefetcher

  public init(pipeline: ImagePipeline = .shared, prefetcher: ImagePrefetcher? = nil) {
    self.pipeline = pipeline
    self.prefetcher = prefetcher ?? ImagePrefetcher(pipeline: pipeline)
  }

  public func image(for request: ImageRequest) async throws -> PlatformImage {
    try await pipeline.image(for: request)
  }

  public func data(for request: ImageRequest) async throws -> Data {
    try await pipeline.data(for: request).0
  }

  public func prefetch(_ requests: [ImageRequest]) {
    prefetcher.startPrefetching(with: requests)
  }

  public func stopPrefetching() {
    prefetcher.stopPrefetching()
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
/// original (on zoom or explicit), Nuke-backed with device-sized memory cache, per-tier disk
/// cache underneath, request priorities + cancellation for fast scroll, and a grid prefetcher.
public actor MediaPipeline {
  private let service: any MediaImageService
  private let diskCache: TieredMediaCache
  private let server: MediaServer
  private var offline: Bool

  public init(
    service: any MediaImageService,
    diskCache: TieredMediaCache,
    server: MediaServer,
    offline: Bool = false
  ) {
    self.service = service
    self.diskCache = diskCache
    self.server = server
    self.offline = offline
  }

  /// Default pipeline: a dedicated Nuke pipeline whose memory cache is sized to the device.
  public static func makeDefault(diskCache: TieredMediaCache, server: MediaServer) -> MediaPipeline {
    var configuration = ImagePipeline.Configuration()
    configuration.imageCache = ImageCache(costLimit: memoryCacheCostLimit())
    let pipeline = ImagePipeline(configuration: configuration)
    let service = NukeMediaImageService(pipeline: pipeline, prefetcher: ImagePrefetcher(pipeline: pipeline))
    return MediaPipeline(service: service, diskCache: diskCache, server: server)
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

  // MARK: - loading

  /// Progressive steps for an asset: instant thumbhash placeholder (when present), then the best
  /// cached tier, then network tiers from the requested one downward. Breaking out of the
  /// iteration cancels the in-flight Nuke work (fast-scroll reuse).
  public func stream(
    asset: Asset,
    tier requested: MediaTier,
    edited: Bool = false,
    pixelSize: Int? = nil,
    format: MediaFormatInfo? = nil
  ) -> AsyncThrowingStream<MediaLoadedImage, any Error> {
    let service = self.service
    let diskCache = self.diskCache
    let server = self.server
    let offline = self.offline
    let pixelSize = pixelSize ?? requested.defaultPixelSize
    let format = format ?? MediaFormatInfo.classify(fileName: asset.originalFileName)
    return AsyncThrowingStream { continuation in
      let task = Task.detached {
        do {
          if let thumbhash = asset.thumbhash,
            let decoded = try? ThumbHash.decode(base64: thumbhash),
            let cgImage = decoded.makeCGImage()
          {
            continuation.yield(
              MediaLoadedImage(
                content: .placeholder(Self.platformImage(cgImage: cgImage)),
                dynamicRange: format.dynamicRange
              ))
          }

          if offline {
            // Task 4: serve the best cached tier regardless of which tier was requested.
            let cached = await diskCache.cachedTiers(assetID: asset.id, edited: edited)
            guard let best = cached.first else {
              throw MediaError.unavailableOffline(requested: requested, bestCached: nil)
            }
            guard let data = await diskCache.retrieve(assetID: asset.id, tier: best, edited: edited),
              let cgImage = Self.decodeImage(data, pixelSize: pixelSize)
            else {
              throw MediaError.unavailableOffline(requested: requested, bestCached: best)
            }
            continuation.yield(
              MediaLoadedImage(
                content: .tier(best, Self.platformImage(cgImage: cgImage), fromCache: true),
                dynamicRange: format.dynamicRange
              ))
            continuation.finish()
            return
          }

          let order = MediaTier.fallbackOrder(from: requested)
          var yielded: Set<MediaTier> = []
          let cached = await diskCache.cachedTiers(assetID: asset.id, edited: edited)
            .filter { order.contains($0) }
          if let best = cached.first,
            let data = await diskCache.retrieve(assetID: asset.id, tier: best, edited: edited),
            let cgImage = Self.decodeImage(data, pixelSize: pixelSize)
          {
            continuation.yield(
              MediaLoadedImage(
                content: .tier(best, Self.platformImage(cgImage: cgImage), fromCache: true),
                dynamicRange: format.dynamicRange
              ))
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
              let request = await Self.networkRequest(
                server: server, assetID: asset.id, tier: tier, edited: edited,
                priority: .high, pixelSize: size
              )
              let data = try await service.data(for: request)
              try await diskCache.store(data, assetID: asset.id, tier: tier, edited: edited)
              let image = try await service.image(for: request)
              continuation.yield(
                MediaLoadedImage(
                  content: .tier(tier, image, fromCache: false),
                  dynamicRange: format.dynamicRange
                ))
              continuation.finish()
              return
            } catch {
              if error is CancellationError { throw error }
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

  /// Warms Nuke's memory cache for upcoming grid cells at the lowest priority — task 2.
  public func prefetch(ids: [String], tier: MediaTier, edited: Bool = false) async {
    var requests: [ImageRequest] = []
    for id in ids {
      requests.append(
        await Self.networkRequest(
          server: server, assetID: id, tier: tier, edited: edited,
          priority: .veryLow, pixelSize: tier.defaultPixelSize
        ))
    }
    service.prefetch(requests)
  }

  public func cancelPrefetch() {
    service.stopPrefetching()
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
