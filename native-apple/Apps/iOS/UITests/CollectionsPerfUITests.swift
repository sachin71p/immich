import XCTest

/// WP4 perf gate: Collections first paint with 100k fixture assets. Section shells
/// paint synchronously (the loader fills counts/covers lazily), so the last section
/// shell appearing bounds first paint; the person tile ("Bob" rides the generated
/// world's first asset) bounds the people stage. Times are printed for the report —
/// the simulator inflates XCUITest round-trips, so these bound, not equal, device
/// paint. Read-only: fixture mode, no destructive actions.
final class CollectionsPerfUITests: XCTestCase {
  func testCollectionsFirstPaintOn100kFixture() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-useFixtureStore", "-fixtureSeedCount=100000"]
    app.launch()

    // Seeding 100k rows through apply() dominates cold launch; the Library tab
    // proves the app is up.
    XCTAssertTrue(
      app.tabBars.buttons["Library"].waitForExistence(timeout: 180),
      "library tab should render from the 100k fixture DB")

    let start = Date()
    app.tabBars.buttons["Collections"].tap()
    let shells = app.descendants(matching: .any)["collections-section-utilities"]
      .waitForExistence(timeout: 60)
    let firstPaintMs = Date().timeIntervalSince(start) * 1000
    print("collections-first-paint-ms=\(Int(firstPaintMs))")
    XCTAssertTrue(shells, "all collections section shells should paint")

    let peopleStart = Date()
    let bob = app.descendants(matching: .any)["person-Bob"]
      .waitForExistence(timeout: 60)
    let peopleMs = Date().timeIntervalSince(peopleStart) * 1000
    print("collections-people-tile-ms=\(Int(peopleMs))")
    XCTAssertTrue(bob, "people stage should fill (fixture person Bob)")
  }
}
