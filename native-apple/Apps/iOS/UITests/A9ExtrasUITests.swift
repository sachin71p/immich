import XCTest

/// A9 UI smoke: Collections → Memories and Collections → Places render from the fixture
/// DB. Runs on the host via `native-apple/scripts/verify.sh ios`; never in the sandbox.
final class A9ExtrasUITests: XCTestCase {
  func testMemoriesAndPlacesRender() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-useFixtureStore"]
    app.launch()

    app.buttons["tab-collections"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["collections"].waitForExistence(timeout: 30),
      "collections should render from the fixture DB")

    // Memories section header (WP4) navigates to the memories cards page.
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Memories'")).firstMatch
        .waitForExistence(timeout: 10),
      "memories section header should render")
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Memories'")).firstMatch.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["memories"].waitForExistence(timeout: 10),
      "memories list should render")
    app.navigationBars.buttons.firstMatch.tap()

    // Places tile navigates to the clustered map.
    for _ in 0..<5 {
      if app.descendants(matching: .any)["places-tile"].waitForExistence(timeout: 5) { break }
      app.swipeUp()
    }
    app.descendants(matching: .any)["places-tile"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["places-map"].waitForExistence(timeout: 10),
      "clustered places map should render")
  }
}
