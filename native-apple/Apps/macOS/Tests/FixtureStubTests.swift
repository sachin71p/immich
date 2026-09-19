import Foundation
import XCTest

/// WP-T T0: the stub server answers every fixture route with deterministic
/// bytes and enforces the auth contract. The session pins the stub protocol
/// class, so no traffic reaches the network. Runs via `verify.sh mac-unit`.
final class FixtureStubTests: XCTestCase {
  private func stubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixtureStubURLProtocol.self]
    return URLSession(configuration: config)
  }

  private func get(_ path: String, token: String? = "fixture-token") async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: URL(string: "https://fixture.invalid/\(path)")!)
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (data, response) = try await stubSession().data(for: request)
    return (data, try XCTUnwrap(response as? HTTPURLResponse))
  }

  func testThumbnailServesDeterministicPNG() async throws {
    let (first, response) = try await get("assets/asset-personal-1/thumbnail?size=thumbnail")
    XCTAssertEqual(response.statusCode, 200)
    XCTAssertEqual(first, FixtureMedia.pngData(seed: "asset-personal-1"), "served bytes are the synthetic render")
    let (second, _) = try await get("assets/asset-personal-1/thumbnail?size=thumbnail")
    XCTAssertEqual(first, second, "stable across requests")
  }

  func testOriginalAndPersonThumbnailServePNG() async throws {
    let (original, originalResponse) = try await get("assets/asset-personal-1/original")
    XCTAssertEqual(originalResponse.statusCode, 200)
    XCTAssertFalse(original.isEmpty)
    let (person, personResponse) = try await get("people/person-mom/thumbnail")
    XCTAssertEqual(personResponse.statusCode, 200)
    XCTAssertFalse(person.isEmpty)
  }

  func testVideoPlaybackServesMP4() async throws {
    let (data, response) = try await get("assets/asset-space-video/video/playback")
    XCTAssertEqual(response.statusCode, 200)
    // ftyp box appears in the first bytes of a valid MP4.
    let head = data.prefix(12)
    XCTAssertTrue(head.range(of: Data("ftyp".utf8)) != nil, "valid MP4 container")
  }

  func testSearchRequiresAuthAndServesBeachIDs() async throws {
    let (_, denied) = try await get("search/smart", token: nil)
    XCTAssertEqual(denied.statusCode, 401, "missing Bearer is rejected")
    let (data, response) = try await get("search/smart")
    XCTAssertEqual(response.statusCode, 200)
    let decoded = try JSONDecoder().decode(SearchStubResponse.self, from: data)
    let ids = decoded.assets.items.map(\.id)
    XCTAssertFalse(ids.isEmpty)
    for beach in FixtureSeed.baseBeachAssetIDs {
      XCTAssertTrue(ids.contains(beach), "stub serves base beach id \(beach)")
    }
    let (meta, metaResponse) = try await get("search/metadata")
    XCTAssertEqual(metaResponse.statusCode, 200)
    XCTAssertEqual(
      try JSONDecoder().decode(SearchStubResponse.self, from: meta).assets.items.map(\.id), ids,
      "metadata serves the same beach list")
  }

  func testUnknownRouteIs404() async throws {
    let (_, response) = try await get("nope/nothing")
    XCTAssertEqual(response.statusCode, 404)
  }

  private struct SearchStubResponse: Decodable {
    struct Assets: Decodable {
      struct Item: Decodable { var id: String }
      var items: [Item]
    }
    var assets: Assets
  }
}
