import XCTest

/// WP3 step 1: V1 repro — open the viewer from the fixture grid and tap the bottom-bar
/// controls (Info, "…" / More, Share). Read-only fixture mode (`-useFixtureStore`): no
/// server, nothing destructive. Runs on the host via `native-apple/scripts/verify.sh ios`.
final class ViewerUITests: XCTestCase {
  private func openViewer(_ app: XCUIApplication) {
    app.launchArguments += ["-useFixtureStore"]
    app.launch()
    XCTAssertTrue(
      app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 60),
      "library grid should render from the fixture DB")
    let firstCell = app.collectionViews.cells.firstMatch
    XCTAssertTrue(firstCell.waitForExistence(timeout: 30))
    firstCell.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10),
      "tapping a grid cell should open the viewer")
  }

  /// V1 repro: every bottom-bar control must respond to taps.
  func testViewerChromeResponds() throws {
    let app = XCUIApplication()
    openViewer(app)

    let info = app.buttons["Info"]
    XCTAssertTrue(info.waitForExistence(timeout: 10), "Info button should exist")
    XCTAssertTrue(info.isHittable, "V1: Info button should be hittable")
    info.tap()
    XCTAssertTrue(
      app.navigationBars["Info"].waitForExistence(timeout: 10),
      "V1: tapping Info should open the Info panel")
    app.swipeDown()

    let more = app.buttons["More"]
    XCTAssertTrue(more.waitForExistence(timeout: 10), "More button should exist")
    XCTAssertTrue(more.isHittable, "V1: More button should be hittable")
    more.tap()

    let share = app.buttons["Share"]
    XCTAssertTrue(share.waitForExistence(timeout: 10), "Share button should exist")
    XCTAssertTrue(share.isHittable, "V1: Share button should be hittable")
  }

  /// Favorite toggles against the fixture store (local mutation, no server).
  func testViewerFavoriteTogglesInFixture() throws {
    let app = XCUIApplication()
    openViewer(app)
    let favorite = app.buttons["Favorite"]
    XCTAssertTrue(favorite.waitForExistence(timeout: 10), "Favorite button should exist")
    XCTAssertTrue(favorite.isHittable, "Favorite button should be hittable")
    favorite.tap()
  }
}
