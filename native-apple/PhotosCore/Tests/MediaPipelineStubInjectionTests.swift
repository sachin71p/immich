import CoreModel
import Foundation
import Media
import Testing

/// A globally-registered `URLProtocol` stub does NOT intercept Nuke's private session
/// (fixture viewer/grid stayed imageless because of exactly this), so `makeDefault`
/// takes the stub classes to inject per-session. These tests pin that contract using
/// only public API.
private final class InjectionStubURLProtocol: URLProtocol {
  /// Hardcoded 1x1 PNG — no image-framework dependency in the stub itself.
  private static let png = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )!

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "stub-injection.invalid"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    let png = Self.png
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "image/png", "Content-Length": "\(png.count)"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: png)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Test("makeDefault injects protocol classes into Nuke's session")
func stubInjectionServesPreviewTier() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let cache = TieredMediaCache(rootDirectory: root, budgets: CacheBudgets(bytes: [:]))
  let server = MediaServer(
    baseURL: URL(string: "https://stub-injection.invalid/api")!, tokenProvider: { nil })
  let pipeline = MediaPipeline.makeDefault(
    diskCache: cache, server: server, protocolClasses: [InjectionStubURLProtocol.self])
  // Nil thumbhash like the curated fixture base rows: no placeholder step is possible,
  // so the tier step below can only come from the stubbed network path.
  let asset = Asset(
    id: "asset-stub-1", ownerId: "u1", originalFileName: "IMG_0001.HEIC",
    checksum: "checksum-asset-stub-1", type: .image)
  var sawNetworkTier = false
  for try await step in await pipeline.stream(asset: asset, tier: .preview) {
    if case .tier(_, _, let fromCache) = step.content, !fromCache {
      sawNetworkTier = true
    }
  }
  #expect(sawNetworkTier, "injected stub serves the preview tier through Nuke")
}
