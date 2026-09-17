import XCTest

extension XCUIApplication {
  /// `launch()` starts the macOS target but does not reliably transfer focus away from
  /// the UI-test runner.  In that state the app's initial window can remain minimized
  /// until somebody clicks its Dock icon, leaving the test unable to interact with it.
  ///
  /// Explicit activation is the programmatic equivalent of that Dock click.  Keep it in
  /// the test harness so normal app launches continue to respect the user's focus.
  func launchForUIAutomation() {
    launch()
    activate()
  }
}
