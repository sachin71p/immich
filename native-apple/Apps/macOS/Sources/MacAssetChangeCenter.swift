import Foundation

/// What changed about assets, fanned out to grid loaders.
///
/// Why a dedicated center instead of NotificationCenter: mutations already run on the
/// main actor, so a small typed fan-out keeps the payloads structural (id sets, not
/// userInfo dictionaries) and lets each subscriber consume them off-main. WP4 and WP5
/// post from their files; the grid loader subscribes in a task owned by the view.
enum MacAssetChange: Sendable {
  /// Favorite flag flipped; cells patch in place (except unfavoriting inside Favorites).
  case favorite(ids: Set<String>, isFavorite: Bool)
  /// Trash, lock, hide, archive, or move out of a library — rows leave every context.
  case removedFromCurrentContexts(ids: Set<String>)
  /// Rotation/edit saved — thumbnails must refresh.
  case edited(ids: Set<String>)
  /// Album membership changed; only matters for the Not-in-Album filter / album pages.
  case albumsChanged
}

/// Typed fan-out for `MacAssetChange`. Posting with no subscribers is a no-op.
@MainActor
final class MacAssetChangeCenter {
  static let shared = MacAssetChangeCenter()

  private var continuations: [UUID: AsyncStream<MacAssetChange>.Continuation] = [:]

  func post(_ change: MacAssetChange) {
    for continuation in continuations.values {
      continuation.yield(change)
    }
  }

  func changes() -> AsyncStream<MacAssetChange> {
    AsyncStream { [weak self] continuation in
      guard let self else {
        continuation.finish()
        return
      }
      let id = UUID()
      continuations[id] = continuation
      continuation.onTermination = { _ in
        Task { @MainActor [weak self] in
          self?.continuations.removeValue(forKey: id)
        }
      }
    }
  }
}
