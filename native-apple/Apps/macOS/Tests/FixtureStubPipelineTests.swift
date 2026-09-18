import CoreModel
import Foundation
import Media
import XCTest

/// WP-E root-cause regression (runs via `verify.sh mac-unit`): the fixture stub must
/// serve Nuke media loads through the injected per-session protocol classes. Before the
/// fix, `stream` hit real DNS for `fixture.invalid` and yielded no tier, so the viewer
/// `image` stayed nil and edit mode never opened (`app.images.count == 0` app-wide).
final class FixtureStubPipelineTests: XCTestCase {
  func testStubServesPreviewTierForNilThumbhashAsset() async throws {
    FixtureSeed.activateStubServer()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let cache = TieredMediaCache(rootDirectory: root)
    let server = MediaServer(baseURL: URL(string: "https://fixture.invalid/api")!)
    let pipeline = MediaPipeline.makeDefault(
      diskCache: cache, server: server, protocolClasses: [FixtureStubURLProtocol.self])
    // Same shape as the curated base rows (e.g. asset-personal-1): no thumbhash, so no
    // placeholder step is possible and the tier below can only come from the stub.
    let asset = Asset(
      id: "asset-personal-1", ownerId: FixtureSeed.userId, originalFileName: "IMG_0001.HEIC",
      checksum: "checksum-asset-personal-1", type: .image)
    var sawTier = false
    do {
      for try await step in await pipeline.stream(asset: asset, tier: .preview) {
        if case .tier = step.content { sawTier = true }
      }
    } catch {
      XCTFail("preview stream threw instead of serving the stub tier: \(error)")
    }
    XCTAssertTrue(sawTier, "fixture stub serves the preview tier through Nuke")
  }
}
