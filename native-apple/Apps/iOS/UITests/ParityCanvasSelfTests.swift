import XCTest

/// WP-T self-check for the TEST-PLAN §2.1 oracle itself: constructs images in
/// code (no app needed) and pins the black-vs-content decision boundary.
/// GREEN on any machine — it validates the instrument the red-first gap tests
/// measure with, and must stay green. Runs on the Simulator.
final class ParityCanvasSelfTests: XCTestCase {
  private func solidImage(gray: UInt8, size: Int = 64) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    for i in 0..<(size * size) {
      pixels[i * 4] = gray
      pixels[i * 4 + 1] = gray
      pixels[i * 4 + 2] = gray
      pixels[i * 4 + 3] = 255
    }
    let data = Data(pixels) as CFData
    let provider = CGDataProvider(data: data)!
    return CGImage(
      width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: size * 4, space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false,
      intent: .defaultIntent)!
  }

  private func noisyImage(size: Int = 64) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    for i in 0..<(size * size) {
      let v = UInt8((i * 37) % 256)
      pixels[i * 4] = v
      pixels[i * 4 + 1] = UInt8((i * 91) % 256)
      pixels[i * 4 + 2] = v / 2
      pixels[i * 4 + 3] = 255
    }
    let data = Data(pixels) as CFData
    let provider = CGDataProvider(data: data)!
    return CGImage(
      width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: size * 4, space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false,
      intent: .defaultIntent)!
  }

  func test_blackFrame_detectedAsBlack() {
    XCTAssertFalse(
      ParityCanvas.isNonBlack(solidImage(gray: 0)),
      "uniform black must read as black")
  }

  func test_contentFrame_detectedAsContent() {
    XCTAssertTrue(
      ParityCanvas.isNonBlack(noisyImage()),
      "a varying frame must read as content")
  }

  func test_uniformNearBlack_detectedAsBlack() {
    // Calibration boundary, documented: a *uniform* near-black frame reads as
    // black (mean < 8 AND stddev < 3). A real dark photo varies and clears the
    // stddev gate instead.
    XCTAssertFalse(
      ParityCanvas.isNonBlack(solidImage(gray: 4)),
      "uniform near-black must read as black")
    XCTAssertTrue(
      ParityCanvas.isNonBlack(noisyImage()),
      "dark varying content must not be mistaken for a black canvas")
  }
}
