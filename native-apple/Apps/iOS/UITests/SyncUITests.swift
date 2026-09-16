import XCTest

/// Sync UI tests (heirloom-ios-sync plan, Verification §2): pull-to-refresh on the grid runs
/// `refreshAll` and the refresh control ends (in fixture mode `sync` is nil, so the control must
/// still return to idle), and the Settings Sync Now row exists. Runs on the host via
/// `native-apple/scripts/verify.sh ios`; never in the sandbox.
final class SyncUITests: XCTestCase {
  func testPullToRefreshEnds() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-useFixtureStore"]
    app.launch()

    XCTAssertTrue(
      app.buttons["library-switcher"].waitForExistence(timeout: 30),
      "library switcher (and grid) should render from the fixture DB")

    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 10))

    let refresh = app.descendants(matching: .any)["pull-to-refresh"]
    XCTAssertTrue(
      refresh.waitForExistence(timeout: 10),
      "grid should expose a pull-to-refresh control")

    grid.swipeDown()

    // The control reports "refreshing" while `refreshAll` runs and must return to "idle".
    // (Polled directly: `waitForExpectations` is MainActor-isolated in this SDK and the test
    // case isn't Sendable under Swift 6 strict concurrency.)
    let deadline = Date().addingTimeInterval(30)
    var settled = false
    while !settled && Date() < deadline {
      settled = (refresh.value as? String) == "idle"
      if !settled { Thread.sleep(forTimeInterval: 0.5) }
    }
    XCTAssertTrue(settled, "refresh control should run refreshAll and return to idle")

    // The refresh cycle must leave a working grid behind.
    XCTAssertTrue(app.buttons["library-switcher"].exists)
    XCTAssertGreaterThan(app.collectionViews.cells.count, 0)
  }

  func testSettingsSyncNowRowExists() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-useFixtureStore"]
    app.launch()

    XCTAssertTrue(
      app.buttons["library-switcher"].waitForExistence(timeout: 30),
      "library switcher (and grid) should render from the fixture DB")

    app.buttons["tab-settings"].tap()
    let syncNow = app.buttons["settings-sync-now"]
    XCTAssertTrue(
      syncNow.waitForExistence(timeout: 10),
      "Settings should offer a Sync Now row")
    // Fixture mode has no sync coordinator: tapping must be a harmless no-op.
    syncNow.tap()
    XCTAssertTrue(syncNow.exists)
    XCTAssertTrue(
      app.descendants(matching: .any)["settings-last-synced"].waitForExistence(timeout: 10),
      "Settings should show the last-synced row")
  }
}
