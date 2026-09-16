import Foundation
import Testing
@testable import CoreModel
@testable import LocalStore
@testable import SyncEngine

/// Video-duration ms→s fix: the server syncs `duration` as integer milliseconds; CoreModel keeps seconds.
@Suite struct DurationFixTests {
  private static func assetSeconds(forDuration duration: String) throws -> Int? {
    let line = """
      {"type": "AssetV2", "data": {"id": "v1", "ownerId": "u1", \
      "originalFileName": "VID_1.MOV", "thumbhash": null, "checksum": "c1", \
      "fileCreatedAt": null, "fileModifiedAt": null, "createdAt": null, \
      "localDateTime": null, "duration": \(duration), "type": "VIDEO", "deletedAt": null, \
      "isFavorite": false, "visibility": "timeline", "livePhotoVideoId": null, "stackId": null, \
      "libraryId": null, "spaceId": null, "width": null, "height": null, \
      "isEdited": false}, "ack": "AssetsV2|ack-1"}
      """
    let outcome = try SyncLineParser.parse(Data(line.utf8))
    guard case .changes(let changes) = outcome else {
      Issue.record("expected changes, got \(outcome)")
      return nil
    }
    for change in changes {
      if case .asset(let asset) = change { return asset.durationSeconds }
    }
    Issue.record("no asset change in \(changes)")
    return nil
  }

  @Test("wire duration 110708ms maps to 111s") func msToSeconds() async throws {
    #expect(try Self.assetSeconds(forDuration: "110708") == 111)
  }

  @Test("wire duration 1300ms rounds to 1s") func roundsToNearest() async throws {
    #expect(try Self.assetSeconds(forDuration: "1300") == 1)
  }

  @Test("wire duration 0 maps to 0") func zero() async throws {
    #expect(try Self.assetSeconds(forDuration: "0") == 0)
  }

  @Test("wire duration null maps to nil") func nilStaysNil() async throws {
    #expect(try Self.assetSeconds(forDuration: "null") == nil)
  }

  @Test("formatter: 5s -> 0:05") func short() {
    #expect(VideoDurationFormat.string(seconds: 5) == "0:05")
  }

  @Test("formatter: 111s -> 1:51") func minute() {
    #expect(VideoDurationFormat.string(seconds: 111) == "1:51")
  }

  @Test("formatter: 3903s -> 1:05:03") func hour() {
    #expect(VideoDurationFormat.string(seconds: 3903) == "1:05:03")
  }

  @Test("formatter: non-positive clamps to 0:00 (positive durations show >= 0:01)") func minimum() {
    #expect(VideoDurationFormat.string(seconds: 0) == "0:00")
    #expect(VideoDurationFormat.string(seconds: 1) == "0:01")
  }
}
