import Foundation

// MARK: - viewer route (WP1 §8, W2 contract)

/// How the grid opens the viewer (WP3): a start id plus an index provider resolving the
/// ordered id list on demand — never an array copy of all ids per tap or per SwiftUI
/// update. Plain `Sendable` so any layer can carry it; the provider reads the loader's
/// lock-mirrored id list and is safe from any thread.
struct ViewerRoute: Sendable {
  let startId: String
  private let provider: @Sendable () -> [String]

  /// Opens `startId` inside the loader's current order (library, album and search grids).
  init(startId: String, provider: @escaping @Sendable () -> [String]) {
    self.startId = startId
    self.provider = provider
  }

  /// Opens `startId` inside a fixed small list (previews, single-album shortcuts).
  init(startId: String, ids: [String]) {
    self.startId = startId
    self.provider = { ids }
  }

  /// The ordered ids around `startId`, resolved once per navigation (O(n) by design —
  /// WP3's pager consumes this lazily instead).
  func resolveIds() -> [String] { provider() }
}
