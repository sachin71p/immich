import XCTest

/// A4 UI smoke (brief Tests): launch with the seeded fixture DB → sidebar + grid render;
/// keyboard selection; move sheet targets. Runs on the host via `verify.sh mac`
/// (Apple tier — TESTING.md §8: never PASS from the sandbox).
final class MacSmokeTests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app = XCUIApplication()
    // Prevent AppKit from restoring a previous run's saved window state, which otherwise
    // races the fresh fixture-seeded content on repeat launches within one test session.
    app.launchArguments = ["--fixture-seed", "-ApplePersistenceIgnoreState", "YES"]
  }

  /// Sidebar + grid render from the fixture DB.
  func testSidebarAndGridRender() {
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

    let sidebar = app.descendants(matching: .any)["sidebar"]
    XCTAssertTrue(sidebar.waitForExistence(timeout: 30), "sidebar renders")

    // Brief §1 sections: spot-check Library, a space, an external library, an album, a utility.
    for id in [
      "sidebar-library", "sidebar-space-space-family", "sidebar-extlib-library-archive",
      "sidebar-album-album-trip", "sidebar-recently-deleted",
    ] {
      XCTAssertTrue(
        app.descendants(matching: .any)[id].waitForExistence(timeout: 10),
        "sidebar row \(id) renders"
      )
    }

    let grid = app.descendants(matching: .any)["asset-grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 30), "grid renders")

    // Seeded Library scope (default switcher = all containers in timeline): personal favorites,
    // space assets and the external-library asset all render as cells.
    for id in ["grid-cell-asset-personal-1", "grid-cell-asset-space-video", "grid-cell-asset-library-1"] {
      XCTAssertTrue(
        app.descendants(matching: .any)[id].waitForExistence(timeout: 10),
        "cell \(id) renders"
      )
    }

    // Toolbar: zoom slider, Years/Months/All segmented control, library switcher.
    XCTAssertTrue(app.descendants(matching: .any)["zoom-slider"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["grouping-segmented"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["library-switcher"].exists)
  }

  /// Keyboard selection (⌘A) then Move to… lists the allowed targets (AP-04: move sheet
  /// targets equal the `Rules.MoveTargets` expectations for the selection).
  func testKeyboardSelectionAndMoveTargets() {
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(app.descendants(matching: .any)["asset-grid"].waitForExistence(timeout: 30))

    // Keyboard selection: focus the grid and select all. Click a cell rather than the
    // grid container itself — the container is fully covered by its cells, so XCUITest
    // has no free pixel to click on it directly.
    let firstCell = app.descendants(matching: .any)["grid-cell-asset-personal-1"].firstMatch
    XCTAssertTrue(firstCell.waitForExistence(timeout: 10))
    firstCell.click()
    app.typeKey("a", modifierFlags: .command)

    // Move sheet via the Image menu (menus own the shortcut — MacMenus).
    app.menuBars.menuItems["Move to…"].click()

    let sheet = app.descendants(matching: .any)["move-sheet-title"]
    XCTAssertTrue(sheet.waitForExistence(timeout: 10), "move sheet opens for the selection")

    // Union across the seeded selection (personal + space + external-library assets):
    // every container the user can access is offered (DECISIONS §6 rules 2–4).
    XCTAssertTrue(app.descendants(matching: .any)["move-target-personal"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["move-target-space-space-family"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["move-target-library-library-archive"].exists)

    app.typeKey(.escape, modifierFlags: [])
  }

  /// Library switcher filters the grid to one container (same options as iOS).
  func testLibrarySwitcherFiltersGrid() {
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(app.descendants(matching: .any)["asset-grid"].waitForExistence(timeout: 30))

    app.descendants(matching: .any)["library-switcher"].click()
    app.menuItems["Family"].click()

    // Space-scoped: space assets render; the personal asset is gone.
    XCTAssertTrue(
      app.descendants(matching: .any)["grid-cell-asset-space-video"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.descendants(matching: .any)["grid-cell-asset-personal-1"].exists)
  }
}
