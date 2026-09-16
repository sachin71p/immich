import CoreModel
import Foundation
import GRDB
import Testing
@testable import LocalStore
@testable import SyncEngine

/// Server `duration` arrives in **milliseconds**; the local column is whole seconds (WP3 badge `m:ss`).
@Suite struct DurationMsTests {
  private func decode(durationFragment: String?) throws -> Asset {
    var json = """
      {"id":"a1","ownerId":"u1","originalFileName":"clip.mp4","checksum":"c1","type":"VIDEO",\
      "isFavorite":false,"visibility":"timeline","isEdited":false
      """
    if let fragment = durationFragment { json += ",\"duration\":\(fragment)" }
    json += "}"
    return try WireDecoding.decoder.decode(WireAsset.self, from: Data(json.utf8)).model
  }

  @Test("wire milliseconds convert to whole seconds") func wireMsToSeconds() throws {
    #expect(try decode(durationFragment: "90000").durationSeconds == 90)
  }

  @Test("wire sub-second values truncate") func wireSubSecond() throws {
    #expect(try decode(durationFragment: "1500").durationSeconds == 1)
    #expect(try decode(durationFragment: "500").durationSeconds == 0)
  }

  @Test("wire missing duration stays nil") func wireNilStaysNil() throws {
    #expect(try decode(durationFragment: nil).durationSeconds == nil)
  }

  @Test("v4 migration divides seeded ms values; NULL stays NULL") func migrationBackfill() throws {
    let dbQueue = try DatabaseQueue()
    let migrator = Schema.makeMigrator()
    // Simulate a pre-fix library: schema without v4, rows holding raw millisecond values.
    try migrator.migrate(dbQueue, upTo: "v3_timeline_cover_index")
    try dbQueue.write { db in
      try db.execute(
        sql: "INSERT INTO asset (id, ownerId, originalFileName, checksum, type, durationSeconds) VALUES ('v1', 'u1', 'a.mp4', 'c1', 'VIDEO', 90000)")
      try db.execute(
        sql: "INSERT INTO asset (id, ownerId, originalFileName, checksum, type, durationSeconds) VALUES ('v2', 'u1', 'b.mp4', 'c2', 'VIDEO', 1500)")
      try db.execute(
        sql: "INSERT INTO asset (id, ownerId, originalFileName, checksum, type) VALUES ('s1', 'u1', 'c.jpg', 'c3', 'IMAGE')")
    }
    try migrator.migrate(dbQueue)
    let (count, v1, v2, s1): (Int?, Int?, Int?, Int?) = try dbQueue.read { db in
      (
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM asset"),
        try Int.fetchOne(db, sql: "SELECT durationSeconds FROM asset WHERE id = 'v1'"),
        try Int.fetchOne(db, sql: "SELECT durationSeconds FROM asset WHERE id = 'v2'"),
        try Int.fetchOne(db, sql: "SELECT durationSeconds FROM asset WHERE id = 's1'")
      )
    }
    #expect(count == 3)
    #expect(v1 == 90)
    #expect(v2 == 1)
    #expect(s1 == nil)
  }
}
