import Foundation

/// Proxy-first edit-open state machine (WP-E E2/E7, TEST-PLAN E7).
///
/// The edit chrome shows the preview proxy at once; the original loads in the
/// background with a spinner. Export uses the original only, and Done stays
/// disabled until it arrives. The stubbed-original test delays 2 s; production
/// passes the real downloader.
public final class EditOriginalLoader: @unchecked Sendable {
  public enum State: Sendable, Equatable {
    /// Proxy is on screen; the original has not been requested yet.
    case proxyReady
    /// Original fetch is in flight (spinner visible).
    case loadingOriginal
    /// Original arrived; re-render done; Done is enabled.
    case ready
    /// Original failed; the user can keep editing the proxy or retry.
    case failed
  }

  private let lock = NSLock()
  private var _state: State = .proxyReady
  private var _originalData: Data?
  private var _didRerender = false

  public init() {}

  public var state: State {
    lock.withLock { _state }
  }

  public var originalData: Data? {
    lock.withLock { _originalData }
  }

  /// True once the canvas re-rendered from the original (not the proxy).
  public var didRerender: Bool {
    lock.withLock { _didRerender }
  }

  /// Done is enabled only when the original has loaded (spec E2).
  public var isDoneEnabled: Bool { state == .ready }

  /// Marks the fetch in flight (proxyReady -> loadingOriginal). Callers fetch with
  /// their own loader (avoiding cross-isolation closure sends under Swift 6) and
  /// then report via `complete(with:)` / `fail(_:)`.
  public func beginLoading() {
    lock.withLock { _state = .loadingOriginal }
  }

  /// Records the arrived original (loadingOriginal -> ready) and flags the re-render.
  public func complete(with data: Data) {
    lock.withLock {
      _originalData = data
      _didRerender = true
      _state = .ready
    }
  }

  /// Records a fetch failure (loadingOriginal -> failed).
  public func fail() {
    lock.withLock { _state = .failed }
  }
}
