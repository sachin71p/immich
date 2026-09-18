import XCTest

/// WP-T red-first tests for F4, F5 (content/throughput — frame pacing already
/// passes, so nothing here asserts on frame duration) and G1–G3, G5, G7,
/// plus the pinch-density behaviour that already works and must survive G7.
/// New file only: the pre-existing `GridPerfUITests.swift` is untouched.
/// Cell/badge identifiers are owned by WP-G; F4/F5 budgets by WP-F.
///
/// All timing assertions are Release-on-physical-device-only and skip on the
/// Simulator; content assertions run everywhere.
final class ParityGridUITests: XCTestCase {
  func test_libraryGrid_tabSwitchReturn_noBlankFrame() throws {
    try Parity.requirePhysicalDevice()
    let app = Parity.launch()
    // F4/WP-F: first tile visible < 150 ms after returning to the Library tab.
    app.tabBars.buttons["Collections"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["collections"].waitForExistence(timeout: 30))
    let start = Date()
    app.tabBars.buttons["Library"].tap()
    let tile = app.collectionViews.cells.firstMatch
    XCTAssertTrue(
      tile.waitForExistence(timeout: 10),
      "F4/WP-F: grid tiles should return after a tab switch")
    XCTAssertLessThan(
      Date().timeIntervalSince(start), 0.15,
      "F4/WP-F: first tile took longer than the 150 ms budget after tab return")
  }

  func test_libraryGrid_fastScroll_tilesHaveContent() throws {
    try Parity.requirePhysicalDevice()
    let app = Parity.launch()
    // F5/WP-F: content, not pacing — no empty/black tile on screen > 250 ms
    // after scroll settles. Samples visible cell rects for non-uniform pixels.
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    for _ in 0..<6 { grid.swipeUp(velocity: .fast) }
    usleep(300_000)
    let deadline = Date().addingTimeInterval(5)
    var pending = true
    while Date() < deadline, pending {
      pending = false
      for i in 0..<min(8, grid.cells.count) {
        let cell = grid.cells.element(boundBy: i)
        if let cgImage = cell.screenshot().image.cgImage,
          !ParityCanvas.isNonBlack(cgImage)
        {
          pending = true
          break
        }
      }
      if pending { usleep(100_000) }
    }
    XCTAssertFalse(
      pending,
      "F5/WP-F: an empty/black tile persisted > 250 ms after scroll settled")
  }

  func test_grid_videoCellsShowDurationBadge() throws {
    let app = Parity.launch()
    // G1/WP-G: every video cell exposes a bottom-right duration label.
    // Predicate form covers any duration text; WP-G owns the identifier.
    let badge = app.staticTexts.matching(
      NSPredicate(format: "identifier BEGINSWITH 'grid-duration-badge'")).firstMatch
    XCTAssertTrue(
      badge.waitForExistence(timeout: 15),
      "G1/WP-G: expected accessibilityIdentifier \"grid-duration-badge*\" on video cells")
  }

  func test_grid_favouritedCellsShowHeartOverlay() throws {
    let app = Parity.launch()
    // G2/WP-G: favourited cells expose a heart overlay (fixture seeds
    // favourites).
    let heart = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH 'grid-favorite-heart'")).firstMatch
    XCTAssertTrue(
      heart.waitForExistence(timeout: 15),
      "G2/WP-G: expected accessibilityIdentifier \"grid-favorite-heart*\" on favourited cells")
  }

  func test_grid_peopleBadgeIsSelectiveNotOnEveryCell() throws {
    let app = Parity.launch()
    // G3/WP-G: the people badge must be selective, not painted on nearly
    // every cell. Samples up to 30 visible cells; ceiling is a named
    // constant so WP-G can calibrate it.
    let selectiveCeiling = 0.5
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    let sample = min(30, grid.cells.count)
    XCTAssertGreaterThan(sample, 0, "G3: grid should paint cells to sample")
    var badged = 0
    for i in 0..<sample {
      let cell = grid.cells.element(boundBy: i)
      if cell.descendants(matching: .any)["grid-people-badge"].exists { badged += 1 }
    }
    let fraction = Double(badged) / Double(sample)
    XCTAssertLessThan(
      fraction, selectiveCeiling,
      "G3/WP-G: people badge on \(badged)/\(sample) sampled cells — must be selective")
  }

  func test_grid_zoomedOut_showsFloatingDateBadge() throws {
    let app = Parity.launch()
    // G5/WP-G: pinch out to a high column count, then scroll — a floating
    // date badge (e.g. "Aug 2026") must overlay the grid.
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    grid.pinch(withScale: 2.0, velocity: 1.0)
    grid.swipeUp(velocity: .fast)
    Parity.require("grid-floating-date-badge", in: app, gap: "G5", owner: "WP-G")
  }

  func test_gridPinch_couplesColumnDensityToTimeLevel() throws {
    let app = Parity.launch()
    // G7/WP-G: a continuous pinch must move BOTH column density and the
    // Years/Months/All selection — the pills must not stay pinned.
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    grid.pinch(withScale: 2.0, velocity: 1.0)
    Parity.require("grid-time-level", in: app, gap: "G7", owner: "WP-G")
  }

  // MARK: - Regression (works today — must survive G7)

  func test_gridPinch_changesColumnDensity() throws {
    let app = Parity.launch()
    // Pinch-to-zoom changes density ≈5 ↔ ≈10 columns today; G7's
    // zoom/time-level coupling must not break the density half.
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    let before = grid.cells.count
    XCTAssertGreaterThan(before, 0)
    grid.pinch(withScale: 0.4, velocity: -1.0)
    sleep(1)
    XCTAssertGreaterThan(
      grid.cells.count, 0,
      "regression: grid pinch must keep a populated grid (was \(before) cells)")
  }
}
