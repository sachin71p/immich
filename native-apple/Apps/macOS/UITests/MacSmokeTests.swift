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
    // T0: the sized small fixture (~2k rows) + no-animation contract flag.
    // Booleans are SINGLE-DASH: a `--` flag swallows the next argv token and the
    // stranded token kills the initial scene (zero windows); `-ui-testing` also
    // enables the test-only AppKit foreground presenter (299a76c73).
    // T0: the sized small fixture (~2k rows) + no-animation contract flag.
    // Booleans are SINGLE-DASH and values ride `-Key=Value`: a bare value token
    // reaches AppKit as an open-documents event that kills the initial scene
    // (zero windows); `-ui-testing` also enables the test-only AppKit foreground
    // presenter (299a76c73).
    app.launchArguments = [
      "-fixture-seed", "-HeirloomFixture=small", "-HeirloomUITestNoAnimation",
      "-ui-testing", "-ApplePersistenceIgnoreState", "YES",
    ]
  }

  /// Selection-dependent menu items capture the focused grid actions when Commands
  /// rebuilds: after a selection click, wait until the selection-gated "Move to…"
  /// enables, proving the new selection reached the menus before clicking any
  /// menu item (otherwise the fired closure still carries the previous selection).
  private func waitForSelectionMenus(file: StaticString = #filePath, line: UInt = #line) {
    let item = app.menuBars.menuItems["Move to…"]
    XCTAssertTrue(item.waitForExistence(timeout: 10), "menu item Move to…", file: file, line: line)
    let deadline = Date().addingTimeInterval(10)
    while !item.isEnabled && Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
    XCTAssertTrue(item.isEnabled, "selection reaches the menus", file: file, line: line)
  }

  /// Menu-bar items are label lookups (AX ids arrive with WP-C); always wait for
  /// them instead of clicking blind — the menu tree populates asynchronously.
  private func menuItem(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
    let item = app.menuBars.menuItems[title]
    XCTAssertTrue(item.waitForExistence(timeout: 10), "menu item \(title)", file: file, line: line)
    return item
  }

  /// Sidebar + grid render from the fixture DB.
  func testSidebarAndGridRender() {
    app.launchForUIAutomation()
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

    // Toolbar: grid size stepper, Years/Months/All segmented control, library switcher.
    // ("zoom-slider" predates the stepper redesign; the app exposes "grid-size-controls".)
    XCTAssertTrue(app.descendants(matching: .any)["grid-size-controls"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["grouping-segmented"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["library-switcher"].waitForExistence(timeout: 10))
  }

  /// Regression: macOS can launch a UI-test target with its first window minimized.
  /// The test-only AppKit presenter must make the window frontmost and hittable before
  /// any automation starts interacting with its contents.
  func testLaunchMakesMainWindowAccessible() {
    app.launchForUIAutomation()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

    let mainWindow = app.windows.firstMatch
    XCTAssertTrue(mainWindow.waitForExistence(timeout: 30), "main window is created")
    XCTAssertTrue(mainWindow.isHittable, "main window is frontmost and not minimized")
    XCTAssertTrue(app.descendants(matching: .any)["sidebar"].waitForExistence(timeout: 30))
    XCTAssertFalse(app.descendants(matching: .any)["toast"].exists, "fixture launch does not attempt a network sync")
  }

  /// Representative multi-select then Move to… lists the allowed targets (AP-04: move
  /// sheet targets equal the `Rules.MoveTargets` expectations for the selection).
  /// One cell per container (personal + space + external library): the asserted union
  /// is identical to a select-all union, at a fraction of the target-computation cost.
  func testKeyboardSelectionAndMoveTargets() {
    app.launchForUIAutomation()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(app.descendants(matching: .any)["asset-grid"].waitForExistence(timeout: 30))

    // Multi-select: focus the grid with a click (the container is fully covered by
    // its cells, so XCUITest has no free pixel to click on it directly), then
    // extend across containers — keyboard selection via ⌘-held clicks.
    let firstCell = app.descendants(matching: .any)["grid-cell-asset-personal-1"].firstMatch
    XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "personal cell renders")
    firstCell.click()
    let spaceCell = app.descendants(matching: .any)["grid-cell-asset-space-video"].firstMatch
    let libCell = app.descendants(matching: .any)["grid-cell-asset-library-1"].firstMatch
    XCTAssertTrue(spaceCell.waitForExistence(timeout: 10), "space cell renders")
    XCTAssertTrue(libCell.waitForExistence(timeout: 10), "external-library cell renders")
    // One modified click per perform, mirroring the passing favorite-two shape.
    XCUIElement.perform(withKeyModifiers: .command) { spaceCell.click() }
    XCUIElement.perform(withKeyModifiers: .command) { libCell.click() }

    // Move sheet via the Image menu (menus own the shortcut — MacMenus).
    waitForSelectionMenus()
    menuItem("Move to…").click()

    let sheet = app.descendants(matching: .any)["move-sheet-title"]
    XCTAssertTrue(sheet.waitForExistence(timeout: 10), "move sheet opens for the selection")

    // Union across the seeded selection (personal + space + external-library assets):
    // every container the user can access is offered (DECISIONS §6 rules 2–4).
    XCTAssertTrue(app.descendants(matching: .any)["move-target-personal"].waitForExistence(timeout: 10), "personal target offered")
    XCTAssertTrue(app.descendants(matching: .any)["move-target-space-space-family"].exists, "family target offered")
    XCTAssertTrue(app.descendants(matching: .any)["move-target-library-library-archive"].exists, "archive target offered")

    app.typeKey(.escape, modifierFlags: [])
  }

  /// Library switcher filters the grid to one container (same options as iOS).
  func testLibrarySwitcherFiltersGrid() {
    app.launchForUIAutomation()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(app.descendants(matching: .any)["asset-grid"].waitForExistence(timeout: 30))

    XCTAssertTrue(app.descendants(matching: .any)["library-switcher"].waitForExistence(timeout: 10))
    app.descendants(matching: .any)["library-switcher"].click()
    // The SwiftUI Menu popup keeps its items out of the XCUITest tree
    // (`app.menuItems` only sees the menu bar), so drive it by type-select: the
    // open menu takes focus and matches the typed prefix, Return commits.
    Thread.sleep(forTimeInterval: 1.0)
    app.typeText("Family")
    app.typeKey(.enter, modifierFlags: [])

    // Space-scoped: space assets render; the personal asset is gone.
    XCTAssertTrue(
      app.descendants(matching: .any)["grid-cell-asset-space-video"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.descendants(matching: .any)["grid-cell-asset-personal-1"].exists)
  }
}
