import XCTest

/// A3 UI smoke test (brief Tests + TESTING.md AP-07): launches with the fixture DB, then drives
/// grid → viewer → select + move sheet. Runs on the host via `native-apple/scripts/verify.sh ios`;
/// never runs in the agent sandbox (no simulator there).
final class A3SmokeUITests: XCTestCase {
  func testGridViewerAndMoveSheet() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-useFixtureStore"]
    app.launch()

    // Grid renders from the fixture DB.
    XCTAssertTrue(
      app.buttons["library-switcher"].waitForExistence(timeout: 30),
      "library switcher (and grid) should render from the fixture DB")

    // Open the viewer by tapping the first grid cell.
    let firstCell = app.collectionViews.cells.firstMatch
    XCTAssertTrue(firstCell.waitForExistence(timeout: 10))
    firstCell.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10),
      "tapping a grid cell should open the viewer")
    // WP3 chrome: the ✕ Close became a glass back chevron (swipe-down also works).
    if !app.buttons["viewer-back"].waitForExistence(timeout: 10) {
      app.swipeDown()
    } else {
      app.buttons["viewer-back"].tap()
    }

    // Select + move sheet lists the Rules.MoveTargets for the selection.
    app.buttons["Select"].tap()
    app.collectionViews.cells.firstMatch.tap()
    app.buttons["Move to…"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["move-targets"].waitForExistence(timeout: 10),
      "move sheet should list correct targets for the selection")
    // The fixture's second member space is an eligible target for the personal asset.
    XCTAssertTrue(app.descendants(matching: .any)["Camera"].waitForExistence(timeout: 10))
  }
}
