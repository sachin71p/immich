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
