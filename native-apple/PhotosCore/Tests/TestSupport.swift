import Foundation
@testable import LocalStore
@testable import SyncEngine

/// Loads a recorded JSON-lines sync-stream fixture (A0 Architecture: "Fixtures: `PhotosCore/Tests/
/// Fixtures/` holds recorded JSON-lines sync streams... tests never hit a real server").
enum FixtureLoader {
  static func lines(_ name: String) throws -> [Data] {
    guard let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures") else {
      throw FixtureError.notFound(name)
    }
    let text = try String(contentsOf: url, encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: true).map { Data($0.utf8) }
  }
}

enum FixtureError: Error { case notFound(String) }

/// Replays a fixture stream through `SyncLineParser` + `PhotosLocalStore.apply`, the same pipeline
/// `SyncCoordinator` drives from the network — the only thing swapped out for tests is the transport.
enum FixtureReplay {
  static func run(_ name: String, into store: PhotosLocalStore, currentUserId: String) async throws {
    for line in try FixtureLoader.lines(name) {
      switch try SyncLineParser.parse(line) {
      case .changes(let changes):
        try await store.apply(changes, currentUserId: currentUserId)
      case .reset:
        try await store.wipe()
        try await store.clearSyncAcks()
      case .complete:
        break
      }
    }
  }
}
