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

    // Memories section navigates to the stories + On-this-day list.
    app.descendants(matching: .any)["collections-memories"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["memories"].waitForExistence(timeout: 10),
      "memories list should render")
    app.navigationBars.buttons.firstMatch.tap()

    // Places section navigates to the clustered map.
    app.staticTexts["Map"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["places-map"].waitForExistence(timeout: 10),
      "clustered places map should render")
  }
}
