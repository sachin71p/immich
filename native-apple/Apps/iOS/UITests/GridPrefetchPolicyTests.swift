import XCTest

/// WP-F (F5) red-first unit tests for the thumbnail-prefetch policy.
///
/// Framing (PLAN §5a): grid frame pacing already passes — black tiles are frames
/// rendered on time with no image content, a prefetch/throughput gap, not a
/// rendering gap. These tests pin the policy that trades *stale* prefetch work
/// for *current-window* work: unchanged fling windows are dropped, scroll-event
/// cancellation keeps the look-ahead window, and fan-out stays capped.
///
/// Base behaviour these fail against (no policy): every `prefetchItemsAt` event
/// spawns a full task group against the pipeline's fixed-concurrency budget
/// (nothing is dropped), and scroll cancellation keeps the visible set only
/// (look-ahead work is killed the moment the viewport moves).
///
/// Runs in-process in the `Heirloom-iOS-UITests` bundle — no XCUI, no device
/// photo pipeline. `GridPrefetchPolicy.swift` is Foundation-only and compiled
/// into both the app and UITest targets. The on-device pixel test
/// (`test_libraryGrid_fastScroll_tilesHaveContent`, TEST-PLAN.md) stays the
/// sign-off for visible content; this file pins the logic underneath it.
final class GridPrefetchPolicyTests: XCTestCase {
  // MARK: - normalize (fan-out cap + priority order)

  func test_normalize_dedupesPreservingPriorityOrder() {
    XCTAssertEqual(GridPrefetchPolicy.normalize(["c", "a", "b", "a", "c"]), ["c", "a", "b"])
  }

  func test_normalize_capsFanOutAtControllerLimit() {
    let ids = (0..<200).map { "id-\($0)" }
    let out = GridPrefetchPolicy.normalize(ids)
    XCTAssertEqual(out.count, GridPrefetchPolicy.maxForwardedIds)
    XCTAssertEqual(out, Array(ids.prefix(GridPrefetchPolicy.maxForwardedIds)))
  }

  func test_normalize_emptyStaysEmpty() {
    XCTAssertEqual(GridPrefetchPolicy.normalize([]), [])
  }

  // MARK: - keepSet (scroll-event cancellation keeps look-ahead)

  func test_keepSet_protectsLookAheadFromScrollCancellation() {
    let visible: Set = ["v1", "v2"]
    let keep = GridPrefetchPolicy.keepSet(visible: visible, prefetched: ["v2", "p1", "p2"])
    XCTAssertTrue(keep.isSuperset(of: visible))
    XCTAssertTrue(keep.contains("p1") && keep.contains("p2"))
  }

  func test_keepSet_visibleOnlyWhenNoLookAhead() {
    let visible: Set = ["v1"]
    XCTAssertEqual(GridPrefetchPolicy.keepSet(visible: visible, prefetched: []), visible)
  }

  func test_keepSet_respectsLookAheadLimit() {
    let visible: Set<String> = []
    let prefetched = (0..<500).map { "p-\($0)" }
    let keep = GridPrefetchPolicy.keepSet(visible: visible, prefetched: prefetched, lookAheadLimit: 10)
    XCTAssertEqual(keep.count, 10)
    XCTAssertEqual(keep, Set(prefetched.prefix(10)))
  }

  func test_keepSet_boundedForConcurrencyBudget() {
    let visible = Set((0..<200).map { "v-\($0)" })
    let prefetched = (0..<500).map { "p-\($0)" }
    let keep = GridPrefetchPolicy.keepSet(visible: visible, prefetched: prefetched)
    XCTAssertLessThanOrEqual(keep.count, visible.count + GridPrefetchPolicy.lookAheadLimit)
  }

  // MARK: - PrefetchWindowGate (fling coalescing)

  func test_gate_forwardsFirstWindowOnceThenSuppressesRepeats() {
    var gate = PrefetchWindowGate()
    let first = gate.idsToForward(["a", "b", "c"])
    XCTAssertEqual(first, ["a", "b", "c"])
    // Same window, different order: same set, dropped.
    XCTAssertNil(gate.idsToForward(["c", "b", "a", "a"]))
  }

  func test_gate_forwardsChangedWindow() {
    var gate = PrefetchWindowGate()
    XCTAssertNotNil(gate.idsToForward(["a", "b"]))
    XCTAssertNotNil(gate.idsToForward(["a", "b", "c"]))
  }

  func test_gate_ignoresEmptyWindows() {
    var gate = PrefetchWindowGate()
    XCTAssertNil(gate.idsToForward([]))
    // Empty records nothing: the next real window still forwards.
    XCTAssertNotNil(gate.idsToForward(["a"]))
  }

  func test_gate_resetReenablesForwarding() {
    var gate = PrefetchWindowGate()
    XCTAssertNotNil(gate.idsToForward(["a"]))
    XCTAssertNil(gate.idsToForward(["a"]))
    gate.reset()
    XCTAssertNotNil(gate.idsToForward(["a"]))
  }

  // MARK: - VisibleWindowGate (row-paging churn)

  func test_visibleGate_pagesFirstWindowSkipsRepeats() {
    var gate = VisibleWindowGate()
    XCTAssertTrue(gate.shouldPage(visible: ["a", "b"]))
    XCTAssertFalse(gate.shouldPage(visible: ["b", "a"]))
    XCTAssertTrue(gate.shouldPage(visible: ["a", "b", "c"]))
  }

  func test_visibleGate_neverPagesEmpty() {
    var gate = VisibleWindowGate()
    XCTAssertFalse(gate.shouldPage(visible: []))
    XCTAssertTrue(gate.shouldPage(visible: ["a"]))
  }

  func test_visibleGate_resetReenablesPaging() {
    var gate = VisibleWindowGate()
    XCTAssertTrue(gate.shouldPage(visible: ["a"]))
    gate.reset()
    XCTAssertTrue(gate.shouldPage(visible: ["a"]))
  }
}
