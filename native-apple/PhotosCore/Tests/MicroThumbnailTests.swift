import CoreGraphics
import Foundation
import Testing
@testable import Media

/// WP-F F5: the micro tier serves the 13- and 21-column mosaic levels, decodes
/// off-main, and velocity-aware prefetch skips cells passing within 100 ms.
/// New infrastructure: green on arrival; absent on base.
@Suite struct MicroThumbnailTests {
  private static func testImage(width: Int = 256, height: Int = 128) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }

  @Test("micro tier is used for the 13- and 21-column mosaic levels only")
  func mosaicLevels() {
    #expect(MicroThumbnail.usesMicroTier(columnCount: 13))
    #expect(MicroThumbnail.usesMicroTier(columnCount: 21))
    #expect(!MicroThumbnail.usesMicroTier(columnCount: 5))
    #expect(!MicroThumbnail.usesMicroTier(columnCount: 8))
    #expect(MediaTier.micro.defaultPixelSize == 64)
  }

  @Test("micro never leaks into higher-tier fallback chains")
  func fallbackIsolation() {
    #expect(MediaTier.fallbackOrder(from: .micro) == [.micro])
    #expect(!MediaTier.fallbackOrder(from: .thumbnail).contains(.micro))
    #expect(!MediaTier.orderedHighToLow.contains(.micro))
  }

  @Test("velocity gate skips cells passing within 100 ms")
  func velocityGate() {
    // Stationary or already-visible cells always decode.
    #expect(MicroThumbnail.shouldDecode(distanceToViewportPts: 500, velocityPtsPerSec: 0))
    #expect(MicroThumbnail.shouldDecode(distanceToViewportPts: 0, velocityPtsPerSec: 4000))
    #expect(MicroThumbnail.shouldDecode(distanceToViewportPts: -10, velocityPtsPerSec: 4000))
    // 2000 pts/s: a cell 100 pts away arrives in 50 ms — skip.
    #expect(!MicroThumbnail.shouldDecode(distanceToViewportPts: 100, velocityPtsPerSec: 2000))
    // Same speed, 400 pts away (200 ms) — decode.
    #expect(MicroThumbnail.shouldDecode(distanceToViewportPts: 400, velocityPtsPerSec: 2000))
    // Boundary: exactly 100 ms still decodes.
    #expect(MicroThumbnail.shouldDecode(distanceToViewportPts: 200, velocityPtsPerSec: 2000))
  }

  @Test("downsample fits 64 px preserving aspect ratio")
  func downsampleFits() {
    let micro = MicroThumbnail.downsample(Self.testImage())
    #expect(micro?.width == 64)
    #expect(micro?.height == 32)
  }

  @Test("downsample leaves small images untouched")
  func downsamplePassthrough() {
    let small = Self.testImage(width: 48, height: 32)
    let result = MicroThumbnail.downsample(small)
    #expect(result?.width == 48)
    #expect(result?.height == 32)
  }

  @Test("off-main downsample matches the sync path")
  func offMainDownsample() async {
    let source = Self.testImage()
    let micro = await MicroThumbnail.downsampleOffMain(source)
    #expect(micro?.width == 64)
    #expect(micro?.height == 32)
  }

  @Test("micro images round-trip through the memory cache")
  func memoryCacheRoundTrip() {
    let memory = MediaMemoryCache(costLimit: 32 * 1024 * 1024)
    let micro = MicroThumbnail.downsample(Self.testImage())!
    #expect(memory.cached(id: "a", tier: .micro, edited: false) == nil)
    memory.store(micro, id: "a", tier: .micro, edited: false)
    #expect(memory.cached(id: "a", tier: .micro, edited: false) != nil)
    // Micro entries never satisfy thumbnail probes.
    #expect(memory.cached(id: "a", tier: .thumbnail, edited: false) == nil)
  }
}
