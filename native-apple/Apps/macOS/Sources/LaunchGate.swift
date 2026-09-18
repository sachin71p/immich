import Foundation

/// WP-F F3 synchronous launch gate (unit-tested in `LaunchGateTests`).
///
/// The signed-in decision must not wait on async work: `HeirloomMacOSApp` evaluates
/// `isSignedIn` from persisted values before the first scene renders, so a signed-in
/// user never sees `MacConnectView` flash. All inputs are already in memory at that
/// point (shared defaults + a Keychain presence check the app performs once).
enum LaunchGate {
  /// Synchronous signed-in decision. All three signals are required: a persisted
  /// server URL with a host, a persisted user id from the last login, and a
  /// Keychain token present right now.
  static func isSignedIn(
    serverURLString: String?, tokenPresent: Bool, userID: String?
  ) -> Bool {
    guard tokenPresent,
      let serverURLString, !serverURLString.isEmpty,
      let userID, !userID.isEmpty,
      let url = URL(string: serverURLString), url.host != nil
    else { return false }
    return true
  }

  /// Launch-gate timeout: bounds an async launch operation (server session
  /// validation) so a blackholed network degrades to the offline path instead of
  /// stalling launch on URLSession's own 60 s+ timeouts. The loser is cancelled;
  /// a win by the sleeper throws `TimeoutError.timedOut`.
  enum TimeoutError: Error {
    case timedOut
  }

  static func withLaunchTimeout<T: Sendable>(
    seconds: Double, operation: @Sendable @escaping () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(for: .seconds(seconds))
        throw TimeoutError.timedOut
      }
      guard let first = try await group.next() else { throw TimeoutError.timedOut }
      group.cancelAll()
      return first
    }
  }

  /// Footer counts text, or nil when the footer must show a spinner instead.
  /// The footer never reads "0 Photos" while the first snapshot is still loading:
  /// with no rows yet and a load in flight there is no count to report — only the
  /// disk-cached snapshot (which arrives as rows) or a spinner.
  static func footerCountsText(
    photos: Int, videos: Int, phaseIsLoading: Bool, hasRows: Bool
  ) -> String? {
    guard !phaseIsLoading || hasRows else { return nil }
    return "\(photos) Photo\(photos == 1 ? "" : "s"), \(videos) Video\(videos == 1 ? "" : "s")"
  }
}
