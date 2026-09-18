import XCTest

/// WP2 Library chrome tests (PLAN WP2 Done): every filter item, Library View
/// switch and View Options item; zoom switches; Years → Months → All drill-down;
/// select-3 + … menu + Trash-confirm-cancel. Fixture mode only
/// (`-useFixtureStore`, in-memory store, no server) — destructive flows are
/// verified here, never against the real library.
final class LibraryChromeUITests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
    // Clear residue from jetsam-killed runs: a leftover app instance answers AX
    // queries and confuses matchers (duplicate hits, phantom alerts).
    XCUIApplication().terminate()
    app = XCUIApplication()
    app.launchArguments += ["-useFixtureStore"]
    app.launch()
    // Zoom persists across runs: a probe or killed run may have left Years/Months
    // (no grid). Normalize to All only when the grid is actually missing, so the
    // common case performs no extra toolbar taps before menu tests.
    let grid = app.descendants(matching: .any)["library-grid"]
    if !grid.waitForExistence(timeout: 10) {
      let allPhotos = app.buttons["All"]
      if allPhotos.waitForExistence(timeout: 10) { allPhotos.tap() }
    }
    XCTAssertTrue(
      grid.waitForExistence(timeout: 60),
      "library grid should render from the fixture DB")
  }

  // MARK: - helpers

  /// Taps the filter button (best effort; the open is verified by the item
  /// appearing, never by container type — iOS 27 doesn't always expose the
  /// menu as a `menus`-typed element).
  func openFilterMenu() {
    tap(app.descendants(matching: .any)["library-filter-menu"], timeout: 5)
  }

  @discardableResult
  func tap(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
    guard element.waitForExistence(timeout: timeout) else { return false }
    element.tap()
    return true
  }

  /// Opens the filter menu and taps an item, scrolling the (tall) menu until the
  /// item is exposed — rows below the fold are absent from the AX hierarchy.
  /// Menu taps dismiss, so every call reopens first. The reopen tap can land
  /// while the grid is still applying the previous pick (tap eaten, no menu),
  /// so opening is verified and retried.
  /// Last-attempt diagnostics for menu forensics (see WP2 report).
  var lastMenuDiag = ""

  /// Drag-scrolls the menu region upward by coordinates (never by container
  /// type: the menu isn't always `menus`-typed). If the menu is closed the
  /// drag harmlessly scrolls the grid behind it; no test taps grid cells by
  /// position after a menu interaction, so that's safe.
  func scrollMenuUp() {
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7)).press(
      forDuration: 0.05,
      thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3)))
  }

  /// Parent drill-in submenu row for a leaf item id, if any. Sort and Filter
  /// rows sit top-level; Media Types / Library View / View Options live inside
  /// nested `Menu` drill-in rows (stable `submenu-*` identifiers).
  func submenuFor(_ id: String) -> String? {
    if id.hasPrefix("mediatype-") { return "submenu-media-types" }
    if id.hasPrefix("libraryview-") { return "submenu-library-view" }
    if id.hasPrefix("viewoptions-") { return "submenu-view-options" }
    return nil
  }

  /// Visible label of a submenu leaf. Rows inside a drilled-in submenu lose
  /// their accessibility identifiers on iOS 27 (verified by AX dump: the
  /// submenu header and leaves expose labels only), so drilled-in leaves are
  /// located by these stable labels. Every id keeps its identifier in code.
  func submenuItemLabel(_ id: String) -> String? {
    switch id {
    case "viewoptions-zoom-in": return "Zoom In"
    case "viewoptions-zoom-out": return "Zoom Out"
    case "viewoptions-aspect-fit": return "Aspect Ratio Grid"
    case "viewoptions-show-screenshots": return "Show Screenshots"
    case "viewoptions-show-shared": return "Show Shared with You"
    case "mediatype-videos": return "Videos"
    case "mediatype-livePhotos": return "Live Photos"
    case "mediatype-screenshots": return "Screenshots"
    case "mediatype-panoramas": return "Panoramas"
    case "libraryview-both": return "Both Libraries"
    case "libraryview-personal": return "Personal Library"
    case "libraryview-show-in-timeline": return "Show in Timeline\u{2026}"
    default: return nil
    }
  }

  @discardableResult
  func tapMenuItem(_ id: String, timeout: TimeInterval = 5) -> Bool {
    if submenuFor(id) != nil {
      return tapSubmenuLeaf(id, timeout: timeout)
    }
    let item = app.descendants(matching: .any)[id]
    for _ in 0..<3 {
      // Already open from a previous round: take it.
      if item.waitForExistence(timeout: 2) {
        item.tap()
        return true
      }
      openFilterMenu()
      for _ in 0..<4 {
        if item.waitForExistence(timeout: timeout) {
          item.tap()
          return true
        }
        lastMenuDiag = "item=\(id) found=false"
        scrollMenuUp()
      }
    }
    return false
  }

  /// Opens the filter menu, drills into the parent submenu row (waiting for
  /// existence first: the submenu opens asynchronously and tapping early is
  /// flaky), then taps the leaf by its visible label. Each round first
  /// re-checks the leaf in case a previous round already drilled in (menu taps
  /// dismiss, so every call reopens first when nothing is showing).
  @discardableResult
  func tapSubmenuLeaf(_ id: String, timeout: TimeInterval = 5) -> Bool {
    guard let parent = submenuFor(id) else { return false }
    guard let label = submenuItemLabel(id) else {
      lastMenuDiag = "item=\(id) has no label mapping"
      return false
    }
    let leafQuery = app.descendants(matching: .button).matching(
      NSPredicate(format: "label == %@", label))
    for _ in 0..<3 {
      if leafQuery.firstMatch.waitForExistence(timeout: 2) {
        leafQuery.firstMatch.tap()
        return true
      }
      openFilterMenu()
      let parentRow = app.descendants(matching: .any)[parent]
      guard parentRow.waitForExistence(timeout: timeout) else {
        lastMenuDiag = "item=\(id) parent=\(parent) found=false"
        continue
      }
      parentRow.tap()
      if leafQuery.firstMatch.waitForExistence(timeout: timeout) {
        leafQuery.firstMatch.tap()
        return true
      }
      lastMenuDiag = "item=\(id) label=\(label) found=false"
    }
    return false
  }

  func gridExists(_ message: String) {
    XCTAssertTrue(
      app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 10), message)
  }

  // MARK: - filter items

  func testFilterItems() throws {
    // (menu label, accessibility id): tapping applies the filter, grid stays up.
    let items = [
      ("Favorites", "filter-favorites"),
      ("Edited", "filter-edited"),
      ("Shared with You", "filter-shared-with-you"),
      ("Captured by Me", "filter-captured-by-me"),
      ("Not in an Album", "filter-not-in-album"),
    ]
    for (label, id) in items {
      XCTAssertTrue(
        tapMenuItem(id),
        "filter menu should offer \(label)")
      gridExists("grid should reload with the \(label) filter")
    }
    // Back to All Items.
    XCTAssertTrue(tapMenuItem("filter-all-items"), "filter menu should offer All Items")
    gridExists("grid should reload with All Items")
  }

  func testSortAndMediaTypes() throws {
    XCTAssertTrue(tapMenuItem("sort-added"), "sort menu should offer Added")
    gridExists("grid should reload sorted by Added")
    XCTAssertTrue(tapMenuItem("sort-captured"), "sort menu should offer Captured")
    gridExists("grid should reload sorted by Captured")

    for kind in ["mediatype-videos", "mediatype-livePhotos", "mediatype-screenshots", "mediatype-panoramas"] {
      XCTAssertTrue(tapMenuItem(kind), "media types should offer \(kind)")
      gridExists("grid should reload with \(kind)")
      // Clear the kind again so the next iteration starts unfiltered.
      XCTAssertTrue(tapMenuItem(kind))
    }
    gridExists("grid should be back after clearing media kinds")
  }

  // MARK: - Library View switch

  func testLibraryViewSwitch() throws {
    XCTAssertTrue(tapMenuItem("libraryview-personal"), "library view should offer Personal Library")
    gridExists("grid should reload for Personal Library")
    XCTAssertTrue(tapMenuItem("libraryview-both"), "library view should offer Both Libraries")
    gridExists("grid should reload for Both Libraries")
  }

  // MARK: - View Options

  func testViewOptions() throws {
    XCTAssertTrue(
      tapMenuItem("viewoptions-zoom-in"),
      "view options should offer Zoom In [\(lastMenuDiag)]")
    gridExists("grid should survive Zoom In")
    XCTAssertTrue(tapMenuItem("viewoptions-zoom-out"), "view options should offer Zoom Out")
    gridExists("grid should survive Zoom Out")
    XCTAssertTrue(tapMenuItem("viewoptions-aspect-fit"), "view options should offer Aspect Ratio Grid")
    gridExists("grid should survive Aspect Ratio Grid")
    XCTAssertTrue(
      tapMenuItem("viewoptions-show-screenshots"),
      "view options should offer Show Screenshots")
    gridExists("grid should survive hiding screenshots")
    XCTAssertTrue(
      tapMenuItem("viewoptions-show-shared"),
      "view options should offer Show Shared with You")
    gridExists("grid should survive hiding shared assets")
    // Restore both Show toggles + aspect fit for later tests (@AppStorage persists).
    XCTAssertTrue(tapMenuItem("viewoptions-show-screenshots"))
    XCTAssertTrue(tapMenuItem("viewoptions-show-shared"))
    XCTAssertTrue(tapMenuItem("viewoptions-aspect-fit"))
  }

  // MARK: - zoom switches + drill-down

  func testZoomDrillDown() throws {
    XCTAssertTrue(tap(app.buttons["Years"]), "zoom control should offer Years")
    XCTAssertTrue(
      app.descendants(matching: .any)["years-view"].waitForExistence(timeout: 10),
      "years view should appear")
    let yearCard = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH 'year-card-'")
    ).firstMatch
    XCTAssertTrue(yearCard.waitForExistence(timeout: 10), "years view should have year cards")
    yearCard.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["months-view"].waitForExistence(timeout: 10),
      "tapping a year should open Months")
    let dayCard = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH 'day-card-'")
    ).firstMatch
    XCTAssertTrue(dayCard.waitForExistence(timeout: 10), "months view should have day cards")
    dayCard.tap()
    gridExists("tapping a day should open All")
  }

  // MARK: - select 3 + … menu + Trash confirm-cancel

  func testSelectThreeMoreMenuTrashCancel() throws {
    XCTAssertTrue(tap(app.buttons["Select"]), "select button should enter select mode")
    XCTAssertTrue(
      app.descendants(matching: .any)["select-count"].waitForExistence(timeout: 10),
      "bottom toolbar should show the selection count")
    let cells = app.collectionViews.cells
    XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10))
    cells.element(boundBy: 0).tap()
    cells.element(boundBy: 1).tap()
    cells.element(boundBy: 2).tap()
    let count = app.descendants(matching: .any)["select-count"]
    XCTAssertTrue(count.waitForExistence(timeout: 10))
    XCTAssertTrue(
      count.label.contains("3"), "selecting 3 items should show '3 Selected' (saw '\(count.label)')")

    XCTAssertTrue(
      tap(app.descendants(matching: .any)["select-more-menu"]),
      "… menu should open in select mode")
    XCTAssertTrue(
      app.descendants(matching: .any)["select-action-favorite"].waitForExistence(timeout: 5)
        || app.descendants(matching: .any)["select-action-copy"].waitForExistence(timeout: 5)
        || app.descendants(matching: .any)["select-action-archive"].waitForExistence(timeout: 5),
      "… menu should list bulk actions")
    // Dismiss the menu by tapping it closed, then let it settle: a tap
    // synthesized mid-dismiss can land on the departing menu.
    tap(app.descendants(matching: .any)["select-more-menu"])
    sleep(1)

    XCTAssertTrue(
      tap(app.descendants(matching: .any)["select-trash"]),
      "bottom toolbar should offer Trash")
    sleep(1)
    let alert = app.alerts.firstMatch
    XCTAssertTrue(
      alert.waitForExistence(timeout: 30),
      "trash confirmation should appear")
    // firstMatch: the alert region can expose the Cancel action twice under AX.
    alert.buttons.matching(NSPredicate(format: "label == 'Cancel'")).firstMatch.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["select-count"].waitForExistence(timeout: 10),
      "cancelling trash should stay in select mode (nothing deleted)")
    tap(app.descendants(matching: .any)["select-exit"])
  }
}
