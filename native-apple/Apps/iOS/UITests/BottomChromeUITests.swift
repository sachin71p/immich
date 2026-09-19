import XCTest

/// TRACK G bottom-chrome two-state tests (Photos behavior, owner screenshots):
/// (a) scroll-at-top: ONE floating glass bar [Library|Collections] + a separate
/// search circle (replacing the stacked pills-row-above-tab-bar);
/// (b) scrolled: single floating segmented pill [icon|Years|Months|All|magnifier].
/// Transitions follow scroll position. Fixture mode only (`-useFixtureStore`).
/// Owned by TRACK G; `LibraryChromeUITests.swift` is untouched.
final class BottomChromeUITests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
    XCUIApplication().terminate()
    app = XCUIApplication()
    // 2000 assets: the 12-asset default world fits on screen and cannot
    // scroll, so scroll-driven chrome could never be exercised in it.
    app.launchArguments += ["-useFixtureStore", "-fixtureSeedCount=2000"]
    app.launch()
    normalizeToAllGrid()
    XCTAssertTrue(
      app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 60),
      "library grid should render from the fixture DB")
  }

  // MARK: - helpers

  /// Zoom persists across runs: normalize to All. A non-All level always shows
  /// the zoom pill (it is the only way back), so `All` is tappable there; on
  /// All the grid renders directly.
  func normalizeToAllGrid() {
    let grid = app.descendants(matching: .any)["library-grid"]
    if grid.waitForExistence(timeout: 10) { return }
    let allPhotos = app.buttons["All"]
    if allPhotos.waitForExistence(timeout: 5) { allPhotos.tap() }
  }

  var bar: XCUIElement { app.descendants(matching: .any)["chrome-floating-bar"] }

  /// Absence probe, scoped to the bar subtree with a single snapshot read.
  /// A full-tree `waitForExistence` poll for a missing id walks the whole
  /// grid AX tree every pass and kills the runner (verified in the VM).
  func isAbsentInBar(_ id: String) -> Bool {
    guard bar.waitForExistence(timeout: 10) else { return false }
    return !bar.descendants(matching: .any)[id].exists
  }

  /// Full-height fling back toward the top (coordinate drags cover too
  /// little ground for a 400-row seeded grid to climb back in a few strokes).
  func flingDown() {
    app.collectionViews.firstMatch.swipeDown()
  }

  // MARK: - (a) scroll-at-top: tab switcher + search circle

  func test_bottomChrome_atTop_showsTabSwitcherNotZoom() throws {
    XCTAssertTrue(
      bar.waitForExistence(timeout: 10),
      "G(a): floating bar should exist at scroll-top")
    XCTAssertTrue(
      app.descendants(matching: .any)["chrome-tab-switcher"].waitForExistence(timeout: 10),
      "G(a): [Library|Collections] switcher should show at scroll-top")
    XCTAssertTrue(
      bar.buttons["Library"].waitForExistence(timeout: 5),
      "G(a): switcher should offer Library")
    XCTAssertTrue(
      bar.buttons["Collections"].waitForExistence(timeout: 5),
      "G(a): switcher should offer Collections")
    XCTAssertTrue(
      app.descendants(matching: .any)["chrome-search-circle"].waitForExistence(timeout: 5),
      "G(a): separate search circle should show at scroll-top")
    XCTAssertTrue(
      isAbsentInBar("library-zoom"),
      "G(a): Years/Months/All pill should be hidden at scroll-top")
    XCTAssertFalse(
      app.tabBars.firstMatch.waitForExistence(timeout: 3),
      "G(a): system tab bar should stay hidden under the floating switcher")
  }

  // MARK: - (b) scrolled: zoom pill

  func test_bottomChrome_scrolled_showsZoomPill() throws {
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    grid.swipeUp()
    grid.swipeUp()
    XCTAssertTrue(
      bar.waitForExistence(timeout: 10),
      "G(b): floating bar should exist while scrolled")
    XCTAssertTrue(
      app.descendants(matching: .any)["library-zoom"].waitForExistence(timeout: 10),
      "G(b): Years/Months/All pill should show while scrolled")
    XCTAssertTrue(
      app.descendants(matching: .any)["chrome-search-circle"].waitForExistence(timeout: 5),
      "G(b): search circle should stay reachable while scrolled")
    XCTAssertTrue(
      isAbsentInBar("chrome-tab-switcher"),
      "G(b): [Library|Collections] switcher should hide while scrolled")
    XCTAssertFalse(
      app.tabBars.firstMatch.waitForExistence(timeout: 3),
      "G(b): system tab bar should stay hidden under the zoom pill")
  }

  // MARK: - transition follows scroll position

  func test_bottomChrome_scrollBackToTop_restoresSwitcher() throws {
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 10))
    grid.swipeUp()
    grid.swipeUp()
    XCTAssertTrue(
      app.descendants(matching: .any)["library-zoom"].waitForExistence(timeout: 10),
      "G: swipe up should reveal the zoom pill first")
    var restored = false
    for _ in 0..<10 {
      if app.descendants(matching: .any)["chrome-tab-switcher"].waitForExistence(timeout: 2) {
        restored = true
        break
      }
      flingDown()
    }
    XCTAssertTrue(restored, "G: scrolling back to top should restore the tab switcher")
    XCTAssertTrue(
      isAbsentInBar("library-zoom"),
      "G: zoom pill should hide again at scroll-top")
  }

  // MARK: - switcher drives the WP5 tab contract

  func test_bottomChrome_collectionsSegment_switchesTab() throws {
    XCTAssertTrue(bar.waitForExistence(timeout: 10))
    let collections = bar.buttons["Collections"]
    XCTAssertTrue(
      collections.waitForExistence(timeout: 10),
      "G: switcher should offer Collections at scroll-top")
    collections.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["collections"].waitForExistence(timeout: 10),
      "G: tapping Collections should land on the Collections tab (requestedTab contract)")
    app.tabBars.buttons["Library"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 30),
      "G: tapping the Library tab should return to the grid")
  }

  // MARK: - search stays icon-only (pins the skipped-test invariant)

  func test_bottomChrome_searchCircle_isIconOnly() throws {
    XCTAssertTrue(bar.waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.descendants(matching: .any)["chrome-search-circle"].waitForExistence(timeout: 5),
      "G: search circle should exist")
    // No visible "Search" text inside the bar (button AX labels pick up the
    // SF Symbol's auto-generated "Search" voice-over name — verified red on
    // a buttons-label query — so the pin is on rendered text, like the
    // skipped sibling test's "no labeled Search entry").
    XCTAssertEqual(
      bar.descendants(matching: .staticText).matching(
        NSPredicate(format: "label CONTAINS %@", "Search")).count, 0,
      "G: floating bar must not show a labeled Search entry (Photos uses an icon-only circle)")
  }
}
