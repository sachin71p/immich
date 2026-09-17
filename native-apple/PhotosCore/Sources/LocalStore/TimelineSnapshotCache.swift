import CoreModel
import Foundation

/// WP-F F1: built-snapshot cache keyed by (scope, filter, grouping, sort).
///
/// The loader returns the cached snapshot synchronously on navigation (no store I/O),
/// then revalidates in the background only when the change center or a sync delta
/// marked the key dirty. Lives in LocalStore (not the app target) so the eviction and
/// invalidation rules are unit-testable — the macOS app hosts it inside `MacGridLoader`.
///
/// Key components are plain strings so app-level enums (`SidebarDestination`,
/// `TimelineGrouping`, presentation filters) map in without cross-module coupling.
/// Thread-safe via a lock; snapshots are immutable reference types, so hits are O(1).
///
/// `@unchecked Sendable` is safe because every mutable state is only touched while
/// holding `lock` (the same shape as `MediaMemoryCache`); the observer token is set
/// once at `init` and only read in `deinit`.
public final class TimelineSnapshotCache: @unchecked Sendable {
  /// Cache key: (scope, filter, grouping, sort) — all caller-provided strings.
  public struct Key: Hashable, Sendable {
    public var scope: String
    public var filter: String
    public var grouping: String
    public var sort: String

    public init(scope: String, filter: String, grouping: String, sort: String) {
      self.scope = scope
      self.filter = filter
      self.grouping = grouping
      self.sort = sort
    }
  }

  /// LRU capacity (WP-F F1: 6 entries).
  public static let capacity = 6

  /// Posted to `NotificationCenter.default` on memory pressure in the app host;
  /// the cache purges on receipt. Tests post it directly or call `purge()`.
  public static let memoryPressureNotification = Notification.Name(
    "TimelineSnapshotCacheMemoryPressure")

  private struct Entry {
    var snapshot: TimelineGridSnapshot
    var dirty: Bool
  }

  private let lock = NSLock()
  private var entries: [Key: Entry] = [:]
  private var lruOrder: [Key] = []
  private var observer: NSObjectProtocol?

  public init() {
    observer = NotificationCenter.default.addObserver(
      forName: Self.memoryPressureNotification, object: nil, queue: nil
    ) { [weak self] _ in self?.purge() }
  }

  deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  /// Synchronous hit — never touches the store. Returns nil on miss or when the
  /// entry was invalidated; the `dirty` flag tells the loader whether a clean hit
  /// still needs background revalidation.
  public func snapshot(for key: Key) -> (snapshot: TimelineGridSnapshot, dirty: Bool)? {
    lock.withLock {
      guard let entry = entries[key] else { return nil }
      touch(key)
      return (entry.snapshot, entry.dirty)
    }
  }

  public func store(_ snapshot: TimelineGridSnapshot, for key: Key) {
    lock.withLock {
      entries[key] = Entry(snapshot: snapshot, dirty: false)
      touch(key)
      evictLocked()
    }
  }

  /// Marks keys matching `predicate` dirty (revalidate on next navigation) without
  /// evicting them — a dirty hit still renders synchronously, then refreshes.
  public func markDirty(where predicate: (Key) -> Bool) {
    lock.withLock {
      for key in entries.keys where predicate(key) {
        entries[key]?.dirty = true
      }
    }
  }

  public func markAllDirty() {
    lock.withLock {
      for key in entries.keys { entries[key]?.dirty = true }
    }
  }

  /// Drops keys matching `predicate` (rows are gone everywhere — a stale hit must
  /// never render).
  public func invalidate(where predicate: (Key) -> Bool) {
    lock.withLock {
      for key in entries.keys where predicate(key) {
        entries.removeValue(forKey: key)
        lruOrder.removeAll { $0 == key }
      }
    }
  }

  public func invalidateAll() {
    lock.withLock {
      entries.removeAll()
      lruOrder.removeAll()
    }
  }

  /// Memory-pressure purge: drops every entry.
  public func purge() {
    invalidateAll()
  }

  public var count: Int {
    lock.withLock { entries.count }
  }

  private func touch(_ key: Key) {
    lruOrder.removeAll { $0 == key }
    lruOrder.append(key)
  }

  private func evictLocked() {
    while lruOrder.count > Self.capacity, let oldest = lruOrder.first {
      lruOrder.removeFirst()
      entries.removeValue(forKey: oldest)
    }
  }
}
