import Foundation
import Testing
@testable import Media

private struct GoldenVector: Decodable {
  var name: String
  var hashBase64: String
  var decodedWidth: Int
  var decodedHeight: Int
  var aspectRatio: Double
  var rgbaHex: String
}

private func goldenVectors() throws -> [GoldenVector] {
  guard
    let url = Bundle.module.url(forResource: "thumbhash-vectors", withExtension: "json", subdirectory: "Fixtures")
  else { throw FixtureError.notFound("thumbhash-vectors") }
  return try JSONDecoder().decode([GoldenVector].self, from: Data(contentsOf: url))
}

private func bytes(hex: String) -> [UInt8] {
  stride(from: 0, to: hex.count, by: 2).map { i in
    let start = hex.index(hex.startIndex, offsetBy: i)
    let end = hex.index(start, offsetBy: 2)
    return UInt8(hex[start..<end], radix: 16)!
  }
}

@Suite struct ThumbHashTests {
  @Test("[A2-05] decoder matches the reference implementation byte-for-byte on every golden")
  func matchesReferenceGoldens() throws {
    for vector in try goldenVectors() {
      let decoded = try ThumbHash.decode(base64: vector.hashBase64)
      #expect(decoded.width == vector.decodedWidth, "width for \(vector.name)")
      #expect(decoded.height == vector.decodedHeight, "height for \(vector.name)")
      #expect(
        decoded.rgba == bytes(hex: vector.rgbaHex),
        "pixels for \(vector.name)")
      #expect(
        abs(try ThumbHash.approximateAspectRatio(base64: vector.hashBase64) - vector.aspectRatio) < 1e-12,
        "aspect ratio for \(vector.name)")
    }
  }

  @Test("[A2-05] decoded bytes back a real bitmap usable as a grid placeholder")
  func placeholderBitmap() throws {
    let vectors = try goldenVectors()
    for vector in vectors {
      let decoded = try ThumbHash.decode(base64: vector.hashBase64)
      let cgImage = try #require(decoded.makeCGImage(), "CGImage for \(vector.name)")
      #expect(cgImage.width == vector.decodedWidth)
      #expect(cgImage.height == vector.decodedHeight)
      #expect(decoded.makePlatformImage() != nil)
    }
  }

  @Test("[A2-05] corrupt input throws instead of yielding garbage pixels")
  func invalidInput() {
    #expect(throws: ThumbHashError.invalidBase64) { try ThumbHash.decode(base64: "A") }
    #expect(throws: ThumbHashError.truncated) { try ThumbHash.decode(base64: "") }
    #expect(throws: ThumbHashError.truncated) { try ThumbHash.decode(base64: "AAAA") }
    #expect(throws: ThumbHashError.truncated) { try ThumbHash.decode(bytes: [1, 2, 3]) }
  }
}
