import Foundation

// MARK: - grid prefetch policy (WP-F: thumbnail throughput, F4–F5)
//
// Pure, UI-free policy for the grid prefetch pipeline. Deliberately
// Foundation-only so the rules stay unit-testable without a host app: the
// collection-view controller owns the viewport, the pipeline owns the network
// budget, and this file owns the decisions between them.
//
// Framing (PLAN §5a): grid frame pacing already passes — black tiles are
// frames rendered on time with no image content, a prefetch/throughput gap,
// not a rendering gap. These policies trade *stale* prefetch work for
// *current-window* work. The renderer is untouched.

/// Prefetch window policy: what the grid keeps, forwards, and cancels.
enum GridPrefetchPolicy: Sendable {
  /// Maximum ids forwarded per prefetch event (matches the controller's fan-out cap).
  static let maxForwardedIds = 60
  /// Look-ahead ids protected from cancellation while scrolling.
  static let lookAheadLimit = 120

  /// The cancel-keep set for a scroll event: the visible window PLUS the ids the
  /// collection view just asked to prefetch. Cancelling with the visible set alone
  /// kills look-ahead work the moment the viewport moves, so prefetch never gets
  /// in front of a fling and tiles configure with no image content (F5).
  static func keepSet(
    visible: Set<String>,
    prefetched: [String],
    lookAheadLimit: Int = lookAheadLimit
  ) -> Set<String> {
    guard !prefetched.isEmpty, lookAheadLimit > 0 else { return visible }
    var keep = visible
    keep.reserveCapacity(visible.count + min(prefetched.count, lookAheadLimit))
    for id in prefetched.prefix(lookAheadLimit) { keep.insert(id) }
    return keep
  }

  /// Normalises one prefetch event: dedupes preserving priority order, caps fan-out.
  static func normalize(_ ids: [String], limit: Int = maxForwardedIds) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    out.reserveCapacity(min(ids.count, limit))
    for id in ids {
      guard out.count < limit else { break }
      if seen.insert(id).inserted { out.append(id) }
    }
    return out
  }
}

/// Change gate for prefetch windows: forwards a window once, then no-ops until the
/// id set changes. A fling delivers many overlapping `prefetchItemsAt` events for
/// nearly the same window; without this every event spawns a full task group
/// against the pipeline's fixed-concurrency budget and stale windows crowd out
/// the current one (F5). Pair with cancel-and-replace of the in-flight task.
struct PrefetchWindowGate: Sendable {
  private var lastForwarded: Set<String> = []
  private var hasForwarded = false

  /// Ordered ids to forward, or nil when the window is unchanged since the last
  /// forward. Empty windows forward nothing and record nothing.
  mutating func idsToForward(_ ids: [String]) -> [String]? {
    let normalized = GridPrefetchPolicy.normalize(ids)
    guard !normalized.isEmpty else { return nil }
    let window = Set(normalized)
    guard !hasForwarded || window != lastForwarded else { return nil }
    lastForwarded = window
    hasForwarded = true
    return normalized
  }

  mutating func reset() {
    lastForwarded = []
    hasForwarded = false
  }
}

/// Change gate for visible-window row paging: `pageVisibleRows` runs on every
/// scroll event, but the `assetsLite` store query only helps when the visible
/// set actually moved. Unchanged windows skip the query (F5: query churn during
/// a fling competes with thumbnail decode for the store).
struct VisibleWindowGate: Sendable {
  private var lastVisible: Set<String> = []
  private var hasPaged = false

  /// True when `visible` differs from the last paged window (the first call always
  /// pages). Empty windows never page.
  mutating func shouldPage(visible: Set<String>) -> Bool {
    guard !visible.isEmpty else { return false }
    guard hasPaged, visible == lastVisible else {
      lastVisible = visible
      hasPaged = true
      return true
    }
    return false
  }

  mutating func reset() {
    lastVisible = []
    hasPaged = false
  }
}
