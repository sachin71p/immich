import CoreModel
import Foundation
import Testing
@testable import LocalStore

/// WP-F F3: the persisted snapshot round-trips and a version mismatch triggers a
/// rebuild (load returns nil). New infrastructure: green on arrival; absent on base.
@Suite struct TimelineDiskSnapshotTests {
  private static func directory() throws -> URL {
    try FileManager.default.url(
      for: .itemReplacementDirectory, in: .userDomainMask,
      appropriateFor: FileManager.default.temporaryDirectory, create: true)
      .appendingPathComponent("disk-snap-\(UUID().uuidString)", isDirectory: true)
  }

  private static func makeSnapshot() -> TimelineGridSnapshot {
    let rows = [
      TimelineRow(
        id: "a", thumbhash: "xx", aspectRatio: 1.5, mediaKind: .photo, isFavorite: true,
        isTrashed: false, isArchived: false,
        localDateTime: Date(timeIntervalSince1970: 1_700_000_000)),
      TimelineRow(
        id: "b", thumbhash: nil, aspectRatio: 0.75, mediaKind: .video, isFavorite: false,
        isTrashed: false, isArchived: false, localDateTime: nil),
    ]
    return TimelineGridSnapshot.build(
      sections: [TimelineSourceSection(kind: .none, rows: rows)],
      order: .newestFirst, include: { _ in true }, generation: 7)
  }

  @Test("persisted snapshot round-trips rows, counts, and scope")
  func roundTrip() throws {
    let dir = try Self.directory()
    let disk = TimelineDiskSnapshot(snapshot: Self.makeSnapshot(), scopeID: "library")
    try disk.save(scopeID: "library", directory: dir)
    let loaded = try #require(TimelineDiskSnapshot.load(scopeID: "library", directory: dir))
    #expect(loaded.photoCount == disk.photoCount)
    #expect(loaded.videoCount == disk.videoCount)
    #expect(loaded.rows.count == 2)
    #expect(loaded.rows[0].id == "a")
    #expect(loaded.rows[0].thumbhash == "xx")
    #expect(loaded.rows[0].aspectRatio == 1.5)
    #expect(loaded.rows[0].isFavorite == true)
    let rebuilt = loaded.snapshot()
    #expect(rebuilt.rows.map(\.id) == ["a", "b"])
    #expect(rebuilt.photoCount == disk.photoCount)
  }

  @Test("missing file loads as nil (rebuild path)")
  func missingLoadsNil() throws {
    #expect(TimelineDiskSnapshot.load(scopeID: "library", directory: try Self.directory()) == nil)
  }

  @Test("version mismatch loads as nil (rebuild path)")
  func versionMismatchLoadsNil() throws {
    let dir = try Self.directory()
    let disk = TimelineDiskSnapshot(snapshot: Self.makeSnapshot(), scopeID: "library")
    try disk.save(scopeID: "library", directory: dir)
    let url = TimelineDiskSnapshot.fileURL(scopeID: "library", directory: dir)
    // Rewrite the payload with a future version by round-tripping the model.
    var decoded = try #require(try? JSONDecoder().decode(
      TimelineDiskSnapshot.self, from: Data(contentsOf: url)))
    decoded.version = TimelineDiskSnapshot.version + 1
    try JSONEncoder().encode(decoded).write(to: url, options: .atomic)
    #expect(TimelineDiskSnapshot.load(scopeID: "library", directory: dir) == nil)
  }

  @Test("corrupt payload loads as nil")
  func corruptLoadsNil() throws {
    let dir = try Self.directory()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("not-a-snapshot".utf8).write(
      to: TimelineDiskSnapshot.fileURL(scopeID: "library", directory: dir), options: .atomic)
    #expect(TimelineDiskSnapshot.load(scopeID: "library", directory: dir) == nil)
  }

  @Test("scope mismatch loads as nil")
  func scopeMismatchLoadsNil() throws {
    let dir = try Self.directory()
    try TimelineDiskSnapshot(snapshot: Self.makeSnapshot(), scopeID: "library")
      .save(scopeID: "library", directory: dir)
    #expect(TimelineDiskSnapshot.load(scopeID: "favorites", directory: dir) == nil)
  }

  @Test("scope ids sanitize to one filename shape")
  func fileNameSanitized() throws {
    let dir = try Self.directory()
    let url = TimelineDiskSnapshot.fileURL(scopeID: "user:me/library 1", directory: dir)
    #expect(url.lastPathComponent == "timeline-user_me_library_1.bin")
  }
}
