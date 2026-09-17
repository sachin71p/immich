import Foundation
import GRDB
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

  @Test("v4 migration rescales stored ms to s") func migration() throws {
    let queue = try DatabaseQueue()
    try queue.write { db in
      // Pre-migration `asset` table (v1 shape from Schema.swift).
      try db.create(table: "asset") { t in
        t.primaryKey("id", .text)
        t.column("ownerId", .text).notNull()
        t.column("originalFileName", .text).notNull()
        t.column("thumbhash", .text)
        t.column("checksum", .text).notNull()
        t.column("fileCreatedAt", .datetime)
        t.column("fileModifiedAt", .datetime)
        t.column("createdAt", .datetime)
        t.column("localDateTime", .datetime)
        t.column("durationSeconds", .integer)
        t.column("type", .text).notNull()
        t.column("deletedAt", .datetime)
        t.column("isFavorite", .boolean).notNull().defaults(to: false)
        t.column("visibility", .text).notNull().defaults(to: "timeline")
        t.column("livePhotoVideoId", .text)
        t.column("stackId", .text)
        t.column("libraryId", .text)
        t.column("spaceId", .text)
        t.column("width", .integer)
        t.column("height", .integer)
        t.column("isEdited", .boolean).notNull().defaults(to: false)
        t.column("localIdentifier", .text)
      }
      try db.execute(
        sql: """
          INSERT INTO asset (id, ownerId, originalFileName, checksum, durationSeconds, type)
          VALUES ('v1', 'u1', 'VID.MOV', 'c1', 110708, 'VIDEO'), ('s1', 'u1', 'IMG.HEIC', 'c2', NULL, 'IMAGE')
          """)
      // Pretend every migration up to the new one already ran, so the migrator only applies v4.
      try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
      for id in [
        "v1_users_partners", "v1_assets_exif", "v1_albums", "v1_stacks", "v1_spaces_libraries",
        "v1_people_faces", "v1_memories", "v1_prefs_sync_cache", "v2_album_sharing_type",
        "v2_upload_queue", "v2_livephoto_video_index", "v3_timeline_cover_index",
      ] {
        try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)", arguments: [id])
      }
    }
    try Schema.makeMigrator().migrate(queue)
    let seconds: Int? = try queue.read { db in
      try Int.fetchOne(db, sql: "SELECT durationSeconds FROM asset WHERE id = 'v1'")
    }
    #expect(seconds == 111)
    let still: Int? = try queue.read { db in
      try Int.fetchOne(db, sql: "SELECT durationSeconds FROM asset WHERE id = 's1'")
    }
    #expect(still == nil)
  }
}
