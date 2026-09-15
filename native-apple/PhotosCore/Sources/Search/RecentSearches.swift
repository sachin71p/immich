import CoreModel
import Foundation
import LocalStore

/// Recent searches (A7 task 2, orchestrator-decided): stored per user in LocalStore
/// `userMetadata` under `photosfork.recentSearches` as JSON `[SearchFilter]`, most recent
/// first, capped at `maxCount`. Re-selecting a filter moves it to the front; duplicates compare
/// by serialized form so equivalent filters collapse.
public struct RecentSearchStore: Sendable {
  public static let metadataKey = "photosfork.recentSearches"
  public static let maxCount = 20

  public var store: PhotosLocalStore
  public var userId: String

  public init(store: PhotosLocalStore, userId: String) {
    self.store = store
    self.userId = userId
  }

  public func recents() async throws -> [SearchFilter] {
    guard
      let json = try await store.metadataValue(userId: userId, key: Self.metadataKey),
      let data = json.data(using: .utf8)
    else { return [] }
    return (try? JSONDecoder().decode([SearchFilter].self, from: data)) ?? []
  }

  public func record(_ filter: SearchFilter) async throws {
    var current = try await recents()
    current.removeAll { $0.serialized == filter.serialized }
    current.insert(filter, at: 0)
    let trimmed = Array(current.prefix(Self.maxCount))
    let data = try JSONEncoder().encode(trimmed)
    try await store.setMetadataValue(String(decoding: data, as: UTF8.self), userId: userId, key: Self.metadataKey)
  }

  public func clear() async throws {
    try await store.setMetadataValue("[]", userId: userId, key: Self.metadataKey)
  }
}
