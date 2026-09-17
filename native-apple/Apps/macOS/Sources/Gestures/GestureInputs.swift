import CoreGraphics
import Foundation

/// Injectable gesture inputs (WP-T, TEST-PLAN T5).
///
/// Zoom, pinch-close and grid-pinch logic live in pure controllers owned by
/// WP-V / WP-G that take these value types. The AppKit overrides
/// (`magnify(with:)`, `smartMagnify(with:)`) only translate and forward, so the
/// controllers are unit-testable without a window server.
enum MagnifyPhase: Sendable, Equatable {
  case began
  case changed
  case ended
  case cancelled
}

struct MagnifyInput: Sendable, Equatable {
  var phase: MagnifyPhase
  /// Multiplicative delta since the previous event (1.0 = no change).
  var magnificationDelta: CGFloat
  var locationInView: CGPoint
  var timestamp: TimeInterval

  init(
    phase: MagnifyPhase,
    magnificationDelta: CGFloat = 1.0,
    locationInView: CGPoint = .zero,
    timestamp: TimeInterval = 0
  ) {
    self.phase = phase
    self.magnificationDelta = magnificationDelta
    self.locationInView = locationInView
    self.timestamp = timestamp
  }

  /// Total magnification over a gesture: the product of per-event deltas.
  static func totalMagnification(_ inputs: [MagnifyInput]) -> CGFloat {
    inputs.reduce(1.0) { $0 * $1.magnificationDelta }
  }
}

struct SmartMagnifyInput: Sendable, Equatable {
  var location: CGPoint

  init(location: CGPoint = .zero) {
    self.location = location
  }
}
