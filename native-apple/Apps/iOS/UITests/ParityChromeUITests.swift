import XCTest

/// WP-T red-first tests for C1–C4 and G6. New file only: the pre-existing
/// `LibraryChromeUITests.swift` is untouched. Chrome identifiers are owned
/// by WP-C (header subtitle behaviour by WP-G for G6).
final class ParityChromeUITests: XCTestCase {
  func test_chrome_isSingleFloatingBar() throws {
    let app = Parity.launch()
    // Two-state chrome: at scroll-top the bar holds the tab switcher (Photos
    // behavior) — scroll once to reveal the zoom pill, then assert.
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 10), "grid should exist")
    grid.swipeUp()
    // C1/WP-C: library/segmented-control/search render in one bar element —
    // not a pills row above a separate tab bar.
    let bar = Parity.require("chrome-floating-bar", in: app, gap: "C1", owner: "WP-C")
    // The bar must actually contain the three slots, not be an empty shell.
    XCTAssertTrue(
      bar.descendants(matching: .any)["library-zoom"].exists,
      "C1/WP-C: the floating bar should contain the Years/Months/All control")
    XCTAssertTrue(
      bar.descendants(matching: .any)["chrome-search-circle"].exists,
      "C1/WP-C: the floating bar should contain the search circle")
  }

  func test_chrome_allSegmentLabel_isAll() throws {
    let app = Parity.launch()
    // Two-state chrome: scroll once to reveal the zoom pill (see above).
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 10), "grid should exist")
    grid.swipeUp()
    // C2/WP-C: the segment label reads exactly "All", not "All Photos".
    // (The A3 smoke test taps a button labelled "All Photos" today — red.)
    let all = app.buttons["All"]
    XCTAssertTrue(
      all.waitForExistence(timeout: 10),
      "C2/WP-C: expected a segment labelled exactly \"All\"")
  }

  func test_tabBar_persistentNotCollapsed() throws {
    let app = Parity.launch()
    // C3/WP-C: Library/Collections tabs visible without a prior tap, plus a
    // separate search circle. (Tab-bar buttons expose labels, not
    // identifiers, per the A9 comment — assert labels.)
    XCTAssertTrue(
      app.tabBars.buttons["Library"].waitForExistence(timeout: 10),
      "C3/WP-C: Library tab should be visible without a prior tap")
    XCTAssertTrue(
      app.tabBars.buttons["Collections"].waitForExistence(timeout: 10),
      "C3/WP-C: Collections tab should be visible without a prior tap")
    Parity.require("chrome-search-circle", in: app, gap: "C3", owner: "WP-C")
  }

  func test_chrome_itemCount_inHeaderNotPersistentLine() throws {
    let app = Parity.launch()
    // C4/WP-C: the item count lives in the header element; no separate
    // persistent count line under the pills.
    Parity.require("chrome-header-count", in: app, gap: "C4", owner: "WP-C")
    XCTAssertFalse(
      app.descendants(matching: .any)["library-count"].exists,
      "C4/WP-C: the standalone \"library-count\" line under the pills must go away")
  }

  func test_gridHeader_showsCountAtRestAndDateRangeWhileScrolling() throws {
    let app = Parity.launch()
    // G6/WP-G: header subtitle is the item count at rest, swaps to a date
    // range during scroll.
    let subtitle = Parity.require(
      "grid-header-subtitle", in: app, gap: "G6", owner: "WP-G")
    XCTAssertTrue(
      subtitle.label.contains("Items") || subtitle.label.rangeOfCharacter(from: .decimalDigits) != nil,
      "G6/WP-G: header subtitle should show the item count at rest, found \"\(subtitle.label)\"")
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    grid.swipeUp(velocity: .fast)
    XCTAssertTrue(
      app.descendants(matching: .any)["grid-header-subtitle"].waitForExistence(timeout: 5),
      "G6/WP-G: header subtitle should persist (as a date range) during scroll")
  }
}
