import AppKit
import Foundation
import XCTest

/// WP-T T4/T5: synthetic scroll events round-trip their phase and delta values;
/// gesture inputs are pure value types with product-of-deltas zoom math.
/// Runs via `verify.sh mac-unit` (no window server interaction — events are
/// constructed, never posted).
final class GestureInputTests: XCTestCase {
  // MARK: - T4 round-trip

  func testScrollEventRoundTripsPhaseAndDeltas() {
    let event = SyntheticEvents.scrollEvent(dx: -24, dy: 8, phase: .changed)
    guard let unwrapped = event else {
      XCTFail("synthetic scroll event construction failed")
      return
    }
    XCTAssertEqual(unwrapped.phase, .changed)
    XCTAssertEqual(unwrapped.momentumPhase, NSEvent.Phase(rawValue: 0))
    XCTAssertEqual(unwrapped.scrollingDeltaX, -24, accuracy: 0.001)
    XCTAssertEqual(unwrapped.scrollingDeltaY, 8, accuracy: 0.001)
  }

  func testAllScrollPhasesRoundTrip() {
    for phase in [
      SyntheticEvents.ScrollPhase.mayBegin, .began, .changed, .ended, .cancelled,
    ] {
      guard let event = SyntheticEvents.scrollEvent(dx: 5, phase: phase) else {
        XCTFail("event construction failed for \(phase)")
        continue
      }
      let expected: NSEvent.Phase
      switch phase {
      case .mayBegin: expected = .mayBegin
      case .began: expected = .began
      case .changed: expected = .changed
      case .ended: expected = .ended
      case .cancelled: expected = .cancelled
      }
      XCTAssertEqual(event.phase, expected, "phase \(phase) round-trips")
    }
  }

  func testMomentumTailCarriesMomentumPhases() {
    let tail = SyntheticEvents.momentumTail(dx: -60)
    XCTAssertGreaterThan(tail.count, 2)
    XCTAssertEqual(tail.first?.momentumPhase, .began)
    XCTAssertEqual(tail.last?.momentumPhase, .ended)
    XCTAssertTrue(tail.dropFirst().dropLast().allSatisfy { $0.momentumPhase == .changed })
  }

  func testSwipeTotalsMatchRequestedDelta() {
    func changedTotal(_ events: [NSEvent]) -> CGFloat {
      events.filter { $0.phase == .changed }.map(\.scrollingDeltaX).reduce(0, +)
    }
    XCTAssertEqual(changedTotal(SyntheticEvents.swipe(dx: -300)), -300, accuracy: 0.01)
    XCTAssertEqual(changedTotal(SyntheticEvents.partialSwipe(dx: -300)), -90, accuracy: 0.01)
    XCTAssertEqual(changedTotal(SyntheticEvents.flick(dx: -300)), -45, accuracy: 0.01)
  }

  func testSwipeIsBracketedByBeganAndEnded() {
    let swipe = SyntheticEvents.swipe(dx: -300)
    XCTAssertEqual(swipe.first?.phase, .mayBegin)
    XCTAssertEqual(swipe.dropFirst().first?.phase, .began)
    XCTAssertEqual(swipe.last?.phase, .ended)
  }

  // MARK: - T5 value types

  func testMagnifyTotalIsProductOfDeltas() {
    let inputs = [
      MagnifyInput(phase: .began, magnificationDelta: 1.1),
      MagnifyInput(phase: .changed, magnificationDelta: 1.2),
      MagnifyInput(phase: .ended, magnificationDelta: 1.0),
    ]
    XCTAssertEqual(MagnifyInput.totalMagnification(inputs), 1.32, accuracy: 0.0001)
  }

  func testGestureInputsAreEquatableValues() {
    XCTAssertEqual(
      SmartMagnifyInput(location: CGPoint(x: 10, y: 20)),
      SmartMagnifyInput(location: CGPoint(x: 10, y: 20)))
    XCTAssertNotEqual(
      MagnifyInput(phase: .began, magnificationDelta: 1.1),
      MagnifyInput(phase: .changed, magnificationDelta: 1.1))
  }
}
