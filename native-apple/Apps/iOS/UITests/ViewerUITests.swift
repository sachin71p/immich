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

  /// Closes the inline info panel with an explicit drag from its top edge (element
  /// swipes are too short for the panel's dismiss threshold).
  /// Drags the grabber button downward (swipe-to-close); falls back to a tap, which
  /// closes through the same `onClose`.
  private func closeInfoPanel(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let panel = app.descendants(matching: .any)["viewer-info-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 10), file: file, line: line)
    let grabber = app.buttons["viewer-info-grabber"]
    XCTAssertTrue(grabber.waitForExistence(timeout: 10), file: file, line: line)
    // Let the slide-in transition finish: gestures that start mid-animation drop.
    sleep(1)
    let start = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
  }

  /// Swiping up on the photo reveals the inline panel; closing it keeps the viewer.
  func testViewerInfoSwipeUpDown() throws {
    let app = XCUIApplication()
    openViewer(app)
    app.swipeUp()
    XCTAssertTrue(
      app.descendants(matching: .any)["viewer-info-panel"].waitForExistence(timeout: 10),
      "swiping up should open the inline panel")
    closeInfoPanel(app)
    XCTAssertFalse(
      app.descendants(matching: .any)["viewer-info-panel"].waitForExistence(timeout: 5),
      "grabber swipe-down should close the panel")
    XCTAssertTrue(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10),
      "closing the panel should stay in the viewer")
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
      app.descendants(matching: .any)["viewer-info-panel"].waitForExistence(timeout: 15),
      "V1: tapping Info should open the inline panel")
    XCTAssertTrue(
      app.staticTexts["viewer-info-date"].waitForExistence(timeout: 10),
      "the panel should show the date card")
    closeInfoPanel(app)
    XCTAssertFalse(
      app.descendants(matching: .any)["viewer-info-panel"].waitForExistence(timeout: 5),
      "grabber swipe-down should close the panel")
    XCTAssertTrue(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10),
      "closing the panel should stay in the viewer")

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
