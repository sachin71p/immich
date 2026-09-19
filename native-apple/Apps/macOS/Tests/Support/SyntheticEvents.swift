import AppKit
import CoreGraphics

/// Synthetic trackpad scroll events for unit tests (WP-T, TEST-PLAN T4).
///
/// Builds `CGEvent`s with trackpad phases and delivers them **directly** via
/// `view.scrollWheel(with:)` — nothing is posted, so no Accessibility permission
/// is needed. Scroll-phase raw values follow `CGScrollPhase` (mayBegin 128,
/// began 1, changed 2, ended 4, cancelled 8); momentum-phase values follow
/// `CGMomentumScrollPhase` (none 0, begin 1, continue 2, end 3). Note these
/// differ from `NSEvent.Phase` (an option set: began 1, stationary 2, changed 4,
/// ended 8, cancelled 16, mayBegin 32) — `NSEvent(cgEvent:)` translates.
enum SyntheticEvents {
  /// Raw CG scroll-phase values.
  enum ScrollPhase: Int64 {
    case mayBegin = 128
    case began = 1
    case changed = 2
    case ended = 4
    case cancelled = 8
  }

  /// Raw CG momentum-phase values (`CGMomentumScrollPhase`).
  enum MomentumPhase: Int64 {
    case none = 0
    case began = 1
    case changed = 2
    case ended = 3
  }

  /// One continuous horizontal scroll event with `dx` pixel delta.
  static func scrollEvent(
    dx: CGFloat,
    dy: CGFloat = 0,
    phase: ScrollPhase = .changed,
    momentum: MomentumPhase = .none
  ) -> NSEvent? {
    guard let cg = CGEvent(
      scrollWheelEvent2Source: nil, units: .pixel,
      wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0)
    else { return nil }
    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
    cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum.rawValue)
    cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(dy))
    cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(dx))
    return NSEvent(cgEvent: cg)
  }

  /// A swipe of total `dx` split into `steps` changed events bracketed by
  /// began/ended (optionally led by mayBegin, like a real trackpad gesture).
  /// Shares are whole pixels distributed by cumulative rounding: the event
  /// pipeline quantizes fractional deltas, so fractional shares would not sum
  /// back to `dx` (the changed events total exactly `round(dx)`).
  static func swipe(dx: CGFloat, steps: Int = 10, mayBegin: Bool = true) -> [NSEvent] {
    var events: [NSEvent] = []
    if mayBegin, let e = scrollEvent(dx: 0, phase: .mayBegin) { events.append(e) }
    if let e = scrollEvent(dx: 0, phase: .began) { events.append(e) }
    let n = max(steps, 1)
    var prev = 0
    for i in 1...n {
      let cur = Int((dx * CGFloat(i) / CGFloat(n)).rounded())
      if let e = scrollEvent(dx: CGFloat(cur - prev)) { events.append(e) }
      prev = cur
    }
    if let e = scrollEvent(dx: 0, phase: .ended) { events.append(e) }
    return events
  }

  /// A slow short swipe (30% of `dx`, more steps): must not commit a page.
  static func partialSwipe(dx: CGFloat) -> [NSEvent] {
    swipe(dx: dx * 0.3, steps: 14)
  }

  /// A fast short swipe (15% of `dx`, few steps) with high implied velocity:
  /// must commit a page.
  static func flick(dx: CGFloat) -> [NSEvent] {
    swipe(dx: dx * 0.15, steps: 3, mayBegin: false)
  }

  /// Momentum tail after the finger lifts: ended scroll phase with momentum
  /// began → changed* → ended.
  static func momentumTail(dx: CGFloat, steps: Int = 6) -> [NSEvent] {
    var events: [NSEvent] = []
    if let e = scrollEvent(dx: dx * 0.4, momentum: .began) { events.append(e) }
    for i in 0..<steps {
      let decay = dx * 0.4 * pow(0.6, Double(i + 1))
      if let e = scrollEvent(dx: decay, momentum: .changed) { events.append(e) }
    }
    if let e = scrollEvent(dx: 0, momentum: .ended) { events.append(e) }
    return events
  }

  /// Delivers events straight to the view (no posting, no permissions).
  /// Main-actor: `NSView.scrollWheel(with:)` is main-actor-isolated.
  @MainActor
  static func deliver(_ events: [NSEvent], to view: NSView) {
    for event in events { view.scrollWheel(with: event) }
  }
}
