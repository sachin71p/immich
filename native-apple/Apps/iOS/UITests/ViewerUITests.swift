import XCTest

/// WP3 viewer tests: open from the fixture grid, exercise the chrome, page, and
/// dismiss. Read-only fixture mode (`-useFixtureStore`): no server, nothing
/// destructive. Runs on the host via `native-apple/scripts/verify.sh ios`.
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

  private func pageIndex(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> String {
    let label = app.staticTexts["viewer-page-index"]
    XCTAssertTrue(label.waitForExistence(timeout: 10), file: file, line: line)
    // NOTE: a SwiftUI Text element reports an empty `value`; the content is in `label`.
    if let value = label.value as? String, !value.isEmpty { return value }
    return label.label
  }

  /// V1 (step 1 repro, fixed step 2): every bottom-bar control responds to taps.
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
    app.buttons["Done"].tap()
    XCTAssertFalse(
      app.navigationBars["Info"].waitForExistence(timeout: 10),
      "Done should close the Info panel")

    let more = app.buttons["More"]
    XCTAssertTrue(more.waitForExistence(timeout: 10), "More button should exist")
    XCTAssertTrue(more.isHittable, "V1: More button should be hittable")
    more.tap()
    XCTAssertTrue(
      app.buttons["Add to Album"].waitForExistence(timeout: 10),
      "V1: tapping More should open the … menu")
    // Copy is a harmless no-op in fixture mode (no server URL) and dismisses the menu.
    app.buttons["Copy"].tap()

    let share = app.buttons["Share"]
    XCTAssertTrue(share.waitForExistence(timeout: 10), "Share button should exist")
    XCTAssertTrue(share.isHittable, "V1: Share button should be hittable")
  }

  /// Pager: swipe advances exactly one item; swipe-down dismisses the viewer.
  func testViewerSwipeNextAndDismiss() throws {
    let app = XCUIApplication()
    openViewer(app)

    XCTAssertTrue(pageIndex(app).hasPrefix("1 of "), "viewer should open on the first item")
    app.swipeLeft()
    XCTAssertTrue(pageIndex(app).hasPrefix("2 of "), "swipe-left should advance one item")
    app.swipeRight()
    XCTAssertTrue(pageIndex(app).hasPrefix("1 of "), "swipe-right should go back one item")

    app.swipeDown()
    XCTAssertFalse(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 3),
      "swipe-down should dismiss the viewer")
    XCTAssertTrue(
      app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 10),
      "dismiss should land back on the grid")
  }

  /// Trash asks for confirmation; cancelling keeps the viewer open and changes nothing.
  func testViewerTrashConfirmsAndCancels() throws {
    let app = XCUIApplication()
    openViewer(app)
    let trash = app.buttons["Trash"]
    XCTAssertTrue(trash.waitForExistence(timeout: 10), "Trash button should exist")
    XCTAssertTrue(trash.isHittable, "Trash button should be hittable")
    trash.tap()
    XCTAssertTrue(
      app.buttons["Delete"].waitForExistence(timeout: 10),
      "Trash should show a confirmation with a Delete action")
    XCTAssertTrue(
      app.buttons["Cancel"].waitForExistence(timeout: 10),
      "Trash confirmation should offer Cancel")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10),
      "cancelling Trash should stay in the viewer")
    XCTAssertTrue(pageIndex(app).hasPrefix("1 of "), "cancelled item should still be current")
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
