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

  /// ⌥-clicks the green zoom button until the grid toolbar unfurls. The
  /// default 1400px window collapses trailing toolbar items (Favorite,
  /// Select, Sync, Manage) into the overflow menu where AX cannot reach
  /// them, so tests zoom to fill the display first. A slow (press-and-hold)
  /// synthesized click opens the Tile menu instead of zooming — common under
  /// VM load — leaving the window small with the menu eating later clicks.
  /// Retries dismiss the menu between attempts. Returns whether the toolbar
  /// unfurled; callers assert with context so a zoom failure fails fast
  /// instead of cascading into confusing downstream failures.
  @discardableResult
  func zoomToFillDisplay() -> Bool {
    // A filled modern display is well past the 1400px default window; below
    // that the toolbar stays collapsed whatever AX reports.
    let isWide = { self.windows.firstMatch.frame.width >= 1500 }
    let toolbarReady = { self.descendants(matching: .any)["favorite-button"].isHittable }
    let zoom = windows.firstMatch.buttons["_XCUI:FullScreenWindow"]
    guard zoom.waitForExistence(timeout: 10) else { return false }
    // Already there: don't touch the button (a redundant ⌥-click un-zooms).
    if isWide() && toolbarReady() { return true }
    for _ in 0..<3 {
      // Dismiss the Tile menu first: a previous held click may have opened it
      // instead of zooming, and it eats subsequent clicks while open.
      typeKey(.escape, modifierFlags: [])
      XCUIElement.perform(withKeyModifiers: .option) { zoom.click() }
      Thread.sleep(forTimeInterval: 2)
      if isWide() && toolbarReady() { return true }
    }
    return isWide() && toolbarReady()
  }
}
