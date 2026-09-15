import Foundation
import Testing
@testable import Media

private let server = URL(string: "https://photos.example.ts.net")!
private let assetID = "11111111-2222-4333-8555-666666666666"
private let motionID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"

@Suite struct MediaEndpointTests {
  @Test("[A2-01] still tiers map to viewAsset sizes and the downloadAsset path")
  func stillTierURLs() {
    let endpoint = MediaEndpoint(serverURL: server, assetID: assetID)
    #expect(endpoint.url(for: .thumbnail).absoluteString == "\(server)/assets/\(assetID)/thumbnail?size=thumbnail")
    #expect(endpoint.url(for: .preview).absoluteString == "\(server)/assets/\(assetID)/thumbnail?size=preview")
    #expect(endpoint.url(for: .fullsize).absoluteString == "\(server)/assets/\(assetID)/thumbnail?size=fullsize")
    #expect(endpoint.url(for: .original).absoluteString == "\(server)/assets/\(assetID)/original")
  }

  @Test("[A2-01] edited=true selects the edited variant on both view and original routes")
  func editedVariant() {
    let endpoint = MediaEndpoint(serverURL: server, assetID: assetID)
    #expect(
      endpoint.url(for: .preview, edited: true).absoluteString
        == "\(server)/assets/\(assetID)/thumbnail?size=preview&edited=true")
    #expect(
      endpoint.url(for: .original, edited: true).absoluteString
        == "\(server)/assets/\(assetID)/original?edited=true")
    // Unedited URLs stay canonical (no redundant flag).
    #expect(endpoint.url(for: .original).absoluteString.contains("edited") == false)
  }

  @Test("[A2-01] video playback and live-photo motion resolve to playAssetVideo routes")
  func videoAndLivePhoto() {
    let endpoint = MediaEndpoint(serverURL: server, assetID: assetID)
    #expect(endpoint.videoPlaybackURL().absoluteString == "\(server)/assets/\(assetID)/video/playback")
    #expect(
      endpoint.livePhotoMotionURL(motionAssetID: motionID).absoluteString
        == "\(server)/assets/\(motionID)/video/playback")
  }
}

@Suite struct MediaTierTests {
  @Test("[A2-02] fallback order tries the requested tier first, then each lower tier")
  func fallbackOrder() {
    #expect(MediaTier.fallbackOrder(from: .original) == [.original, .fullsize, .preview, .thumbnail])
    #expect(MediaTier.fallbackOrder(from: .fullsize) == [.fullsize, .preview, .thumbnail])
    #expect(MediaTier.fallbackOrder(from: .preview) == [.preview, .thumbnail])
    #expect(MediaTier.fallbackOrder(from: .thumbnail) == [.thumbnail])
  }

  @Test("[A2-02] grid tiers downsample; zoom tiers load full resolution")
  func defaultPixelSizes() {
    #expect(MediaTier.thumbnail.defaultPixelSize == 512)
    #expect(MediaTier.preview.defaultPixelSize == 2048)
    #expect(MediaTier.fullsize.defaultPixelSize == nil)
    #expect(MediaTier.original.defaultPixelSize == nil)
  }
}
