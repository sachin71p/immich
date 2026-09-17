import Foundation

// MARK: - main-thread stall watchdog (WP1 perf gate)

/// Records main-thread stalls over 100 ms during a scripted flick-scroll run, plus the
/// loader/layout timings the signpost harness also emits. A watchdog thread pings the
/// main queue every 20 ms: a ping answered within 100 ms is healthy; a ping that times
/// out counts one stall, and the next answered ping's latency sets the max.
///
/// Only runs under `-gridPerfRun` (the flick-scroll UI test) — zero overhead otherwise.
/// `summary()` renders the one-line `grid-perf-summary` value the UI test asserts on.
final class GridStallMonitor: @unchecked Sendable {
  private let lock = NSLock()
  private var _stalls = 0
  private var _maxStallMs: Double = 0
  private var _pings = 0
  /// "ping:phase" per stall (capped) — the test windows these against warmup; the
  /// phase names the main-thread work item running when the stall fired (triage).
  private var _stallMarks: [String] = []
  /// Set (main thread only) at the entry of each grid hot path. Read racily by the
  /// watchdog — attribution, not accounting.
  nonisolated(unsafe) var currentPhase = "boot"
  private var running = false

  /// Latest loader/layout timings (set from the main actor; read under lock).
  var gridLoadMs: Double = 0
  var snapshotBuildMs: Double = 0
  var snapshotApplyMs: Double = 0
  var layoutPrepareMs: Double = 0
  var firstPaintMs: Double?

  static let runsInThisProcess: Bool = ProcessInfo.processInfo.arguments.contains("-gridPerfRun")

  func start() {
    lock.withLock {
      guard !running else { return }
      running = true
    }
    Thread.detachNewThread { [weak self] in self?.watch() }
  }

  func stop() {
    lock.withLock { running = false }
  }

  private func watch() {
    while lock.withLock({ running }) {
      let start = DispatchTime.now()
      let done = DispatchSemaphore(value: 0)
      DispatchQueue.main.async { done.signal() }
      // 20 ms cadence: a healthy main thread answers in ~0 ms; anything past 100 ms is
      // a stall the gate counts. Each stall records its ping index so the UI test can
      // separate warmup (shader compile, first-window paging) from steady-state scroll.
      let outcome = done.wait(timeout: .now() + .milliseconds(100))
      let latencyMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
      lock.withLock {
        _pings += 1
        if outcome == .timedOut {
          _stalls += 1
          _maxStallMs = max(_maxStallMs, latencyMs)
          if _stallMarks.count < 50 { _stallMarks.append("\(_pings):\(currentPhase)") }
        } else {
          _maxStallMs = max(_maxStallMs, min(latencyMs, 100))
        }
      }
      Thread.sleep(forTimeInterval: 0.02)
    }
  }

  func summary() -> String {
    lock.withLock {
      var parts = [
        "stalls=\(_stalls)", String(format: "maxStall=%.0fms", _maxStallMs), "pings=\(_pings)",
        "marks=\(_stallMarks.joined(separator: ","))",
      ]
      if let first = firstPaintMs { parts.append(String(format: "firstPaint=%.0fms", first)) }
      parts.append(String(format: "gridLoad=%.0fms", gridLoadMs))
      parts.append(String(format: "snapshotBuild=%.0fms", snapshotBuildMs))
      parts.append(String(format: "snapshotApply=%.0fms", snapshotApplyMs))
      parts.append(String(format: "layoutPrepare=%.0fms", layoutPrepareMs))
      return parts.joined(separator: " ")
    }
  }

  var stallCount: Int { lock.withLock { _stalls } }
  var maxStallMs: Double { lock.withLock { _maxStallMs } }
}
