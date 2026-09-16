import Foundation

/// L2: `CancellationError` (and `URLError.cancelled`) is never a user-facing error.
///
/// `.task(id:)` restarts, scrolled-past loads and app foregrounding all surface cancellations;
/// every `lastError`/`actionError` site in the iOS app filters through `Error.isCancellation`
/// instead of showing the "The operation couldn't be completed (Swift.CancellationError…)"
/// banner. `isCancellationMessage` matches the displayed text of such an error so a stale
/// banner can be cleared on launch.
enum ErrorFilter {
  /// True for `CancellationError` and cancelled `URLError`s (Swift or ObjC-bridged).
  static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    let ns = error as NSError
    return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
  }

  /// True when `text` looks like the displayed form of a cancellation: Swift's
  /// `CancellationError` description, any "cancelled" wording, or `NSURLErrorDomain -999`.
  static func isCancellationMessage(_ text: String) -> Bool {
    let lower = text.lowercased()
    return lower.contains("cancellationerror") || lower.contains("cancelled")
      || lower.contains("error -999")
  }

  /// Drops a stale cancellation banner (e.g. left by a pre-relaunch `.task(id:)` restart).
  @MainActor
  static func clearStaleCancellation(in session: AppSession) {
    if let text = session.lastError, isCancellationMessage(text) {
      session.lastError = nil
    }
  }
}

extension Error {
  /// L2 helper: `catch { if !error.isCancellation { … = error.localizedDescription } }`.
  var isCancellation: Bool { ErrorFilter.isCancellation(self) }
}

extension String {
  /// L2 helper for `onError(String)` closures: drop cancellation text before showing an alert.
  var isCancellationMessage: Bool { ErrorFilter.isCancellationMessage(self) }
}
