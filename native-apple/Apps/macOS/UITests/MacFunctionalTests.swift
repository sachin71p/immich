import XCTest

/// WP4 Step 3 (brief: XCUITest under `--fixture-seed`, never the real library):
/// sidebar destinations + resolved titles, every sheet's Cancel/Escape, ⌘Q with a
/// sheet open, favorite-two (asserted via Favorites membership — the cell heart badge
/// exposes no distinct accessibility value; see WP4-REPORT deviations), fixture-mode
/// trash without a full reload, and the minimal toolbar on Map/People/Memories.
/// Runs on the host via `make test-macos-ui` (Apple tier — never PASS from the sandbox).
final class MacFunctionalTests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app = XCUIApplication()
    // Same fresh-state guard as MacSmokeTests: a previous run's restored window races
    // the fixture-seeded content on repeat launches within one test session.
    app.launchArguments = ["--fixture-seed", "-ApplePersistenceIgnoreState", "YES"]
  }

  override func tearDown() {
    // The ⌘Q test quits the app itself; anything still alive (e.g. a sheet blocked a
    // launch) must not leak into the next test's fresh launch.
    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }
    super.tearDown()
  }

  // MARK: - helpers

  private func el(_ id: String) -> XCUIElement {
    app.descendants(matching: .any)[id]
  }

  private func launchAndWaitForLibrary() {
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(el("sidebar").waitForExistence(timeout: 30), "sidebar renders")
    XCTAssertTrue(el("asset-grid").waitForExistence(timeout: 30), "grid renders")
  }

  private func windowTitle() -> String {
    app.windows.firstMatch.title
  }

  /// Asserts an element (sheet marker) disappears — i.e. the sheet closed.
  private func assertClosed(_ id: String, _ message: String) {
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: el(id))
    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, message)
  }

  private func gridCellCount() -> Int {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "grid-cell-")
    ).count
  }

  // MARK: - Step 3: destinations + resolved titles

  /// Every sidebar destination opens and the window title shows its resolved name
  /// (U24/U25: Family/Trip/Archive, not "Shared Library"/"Album"/"External Library").
  func testSidebarDestinationsShowResolvedTitles() {
    launchAndWaitForLibrary()
    let cases: [(row: String, title: String)] = [
      ("sidebar-library", "Library"),
      ("sidebar-collections", "Collections"),
      ("sidebar-search", "Search"),
      ("sidebar-favorites", "Favorites"),
      ("sidebar-recently-saved", "Recently Saved"),
      ("sidebar-map", "Map"),
      ("sidebar-people", "People"),
      ("sidebar-memories", "Memories"),
      ("sidebar-photos", "Photos"),
      ("sidebar-videos", "Videos"),
      ("sidebar-screenshots", "Screenshots"),
      ("sidebar-space-space-family", "Family"),
      ("sidebar-extlib-library-archive", "Archive"),
      ("sidebar-album-album-trip", "Trip"),
      ("sidebar-all-albums", "All Albums"),
      ("sidebar-imports", "Imports"),
      ("sidebar-recently-deleted", "Recently Deleted"),
      ("sidebar-duplicates", "Duplicates"),
      ("sidebar-captured-by-me", "Captured by Me"),
      ("sidebar-hidden", "Hidden"),
      ("sidebar-archive", "Archive"),
      ("sidebar-locked", "Locked"),
    ]
    for (row, title) in cases {
      let rowEl = el(row)
      XCTAssertTrue(rowEl.waitForExistence(timeout: 10), "sidebar row \(row) renders")
      rowEl.click()
      XCTAssertEqual(windowTitle(), title, "title for \(row)")
    }
  }

  // MARK: - Step 3: move sheet + ⌘Q

  /// Move sheet opens for a keyboard selection; Cancel closes, Escape closes, and ⌘Q
  /// quits the app while the sheet is open (quit guard: no upload/move in progress).
  func testMoveSheetCancelEscapeAndQuit() {
    launchAndWaitForLibrary()

    let firstCell = el("grid-cell-asset-personal-1")
    XCTAssertTrue(firstCell.waitForExistence(timeout: 10))
    firstCell.click()
    app.typeKey("a", modifierFlags: .command)
    app.menuBars.menuItems["Move to…"].click()
    XCTAssertTrue(el("move-sheet-title").waitForExistence(timeout: 10), "move sheet opens")

    // Cancel closes.
    app.sheets.buttons["Cancel"].click()
    assertClosed("move-sheet-title", "move sheet Cancel closes")

    // Escape closes.
    app.menuBars.menuItems["Move to…"].click()
    XCTAssertTrue(el("move-sheet-title").waitForExistence(timeout: 10), "move sheet reopens")
    app.typeKey(.escape, modifierFlags: [])
    assertClosed("move-sheet-title", "move sheet Escape closes")

    // ⌘Q quits with the sheet open (no in-progress guard in fixture mode).
    app.menuBars.menuItems["Move to…"].click()
    XCTAssertTrue(el("move-sheet-title").waitForExistence(timeout: 10), "move sheet reopens")
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "⌘Q quits with sheet open")
  }

  // MARK: - Step 3: every sheet's Cancel + Escape

  func testNewSpaceSheetCancelAndEscape() {
    launchAndWaitForLibrary()
    el("sidebar-new-space").click()
    XCTAssertTrue(el("new-space-name").waitForExistence(timeout: 10), "new-space sheet opens")
    app.typeKey(.escape, modifierFlags: [])
    assertClosed("new-space-name", "new-space Escape closes")
    el("sidebar-new-space").click()
    XCTAssertTrue(el("new-space-name").waitForExistence(timeout: 10), "new-space sheet reopens")
    app.sheets.buttons["Cancel"].click()
    assertClosed("new-space-name", "new-space Cancel closes")
  }

  func testNewAlbumSheetCancelAndEscape() {
    launchAndWaitForLibrary()
    el("sidebar-new-album").click()
    XCTAssertTrue(el("new-album-name").waitForExistence(timeout: 10), "new-album sheet opens")
    app.sheets.buttons["Cancel"].click()
    assertClosed("new-album-name", "new-album Cancel closes")
    el("sidebar-new-album").click()
    XCTAssertTrue(el("new-album-name").waitForExistence(timeout: 10), "new-album sheet reopens")
    app.typeKey(.escape, modifierFlags: [])
    assertClosed("new-album-name", "new-album Escape closes")
  }

  func testAddToAlbumSheetCancelAndEscape() {
    launchAndWaitForLibrary()
    let firstCell = el("grid-cell-asset-personal-1")
    XCTAssertTrue(firstCell.waitForExistence(timeout: 10))
    firstCell.click()
    app.menuBars.menuItems["Add to Album…"].click()
    XCTAssertTrue(
      el("add-to-album-album-trip").waitForExistence(timeout: 10), "add-to-album sheet opens")
    app.sheets.buttons["Cancel"].click()
    assertClosed("add-to-album-album-trip", "add-to-album Cancel closes")
    app.menuBars.menuItems["Add to Album…"].click()
    XCTAssertTrue(
      el("add-to-album-album-trip").waitForExistence(timeout: 10), "add-to-album sheet reopens")
    app.typeKey(.escape, modifierFlags: [])
    assertClosed("add-to-album-album-trip", "add-to-album Escape closes")
  }

  func testManageSpaceSheetDoneAndEscape() {
    launchAndWaitForLibrary()
    el("sidebar-space-space-family").click()
    XCTAssertEqual(windowTitle(), "Family")
    el("space-manage-button").click()
    XCTAssertTrue(el("space-save").waitForExistence(timeout: 10), "manage sheet opens")
    // Done carries `.cancelAction` (closes without saving); Escape does the same.
    app.sheets.buttons["Done"].click()
    assertClosed("space-save", "manage Done closes")
    el("space-manage-button").click()
    XCTAssertTrue(el("space-save").waitForExistence(timeout: 10), "manage sheet reopens")
    app.typeKey(.escape, modifierFlags: [])
    assertClosed("space-save", "manage Escape closes")
  }

  func testCameraImportSheetDismisses() {
    launchAndWaitForLibrary()
    app.menuBars.menuItems["Import from Camera…"].click()
    XCTAssertTrue(
      app.sheets.element(boundBy: 0).waitForExistence(timeout: 10), "camera sheet opens")
    // Done carries `.cancelAction` in both the device and the no-device layouts.
    app.sheets.buttons["Done"].click()
    XCTAssertEqual(app.sheets.count, 0, "camera Done closes")
    app.menuBars.menuItems["Import from Camera…"].click()
    XCTAssertTrue(
      app.sheets.element(boundBy: 0).waitForExistence(timeout: 10), "camera sheet reopens")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertEqual(app.sheets.count, 0, "camera Escape closes")
  }

  // MARK: - Step 3: favorite two

  /// Select 2 items, favorite via the toolbar, then both render in Favorites.
  /// (The cell heart badge exposes no distinct accessibility value — heart vs
  /// heart.fill share one image description — so membership is the assertion;
  /// see WP4-REPORT deviations for the one-line hook that would enable a direct
  /// badge-value check.)
  func testFavoriteTwoShowsThemInFavorites() {
    launchAndWaitForLibrary()
    let cell1 = el("grid-cell-asset-personal-2")
    let cell2 = el("grid-cell-asset-space-shot")
    XCTAssertTrue(cell1.waitForExistence(timeout: 10))
    XCTAssertTrue(cell2.waitForExistence(timeout: 10))
    // Multi-select via a ⌘-held second click (order-independent: both targets are
    // named explicitly, so grid sort order cannot affect which two get favorited).
    cell1.click()
    XCUIElement.perform(withKeyModifiers: .command) { cell2.click() }
    el("favorite-button").click()
    el("sidebar-favorites").click()
    XCTAssertEqual(windowTitle(), "Favorites")
    XCTAssertTrue(
      el("grid-cell-asset-personal-2").waitForExistence(timeout: 10),
      "first favorited item in Favorites")
    XCTAssertTrue(
      el("grid-cell-asset-space-shot").waitForExistence(timeout: 10),
      "second favorited item in Favorites")
    // personal-1 ships favorited in the seed: exactly 3 cells, no reload involved.
    XCTAssertEqual(gridCellCount(), 3, "Favorites holds the seed favorite plus the 2 new ones")
  }

  // MARK: - Step 3: fixture-mode trash without a full reload

  /// Trash in fixture mode: the item leaves the grid (count drops by one, grid element
  /// itself persists — no full reload) and appears in Recently Deleted.
  func testTrashRemovesWithoutFullReload() {
    launchAndWaitForLibrary()
    let doomed = el("grid-cell-asset-personal-2")
    XCTAssertTrue(doomed.waitForExistence(timeout: 10))
    let before = gridCellCount()
    XCTAssertGreaterThan(before, 1)
    doomed.click()
    app.menuBars.menuItems["Delete"].click()
    XCTAssertTrue(el("toast").waitForExistence(timeout: 10), "trash toast shows")
    XCTAssertTrue(el("asset-grid").exists, "grid persists (no full reload)")
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: el("grid-cell-asset-personal-2"))
    XCTAssertEqual(
      XCTWaiter.wait(for: [gone], timeout: 10), .completed, "trashed item leaves the grid")
    XCTAssertEqual(gridCellCount(), before - 1, "remaining count drops by exactly one")
    el("sidebar-recently-deleted").click()
    XCTAssertEqual(windowTitle(), "Recently Deleted")
    XCTAssertTrue(
      el("grid-cell-asset-personal-2").waitForExistence(timeout: 10),
      "trashed item renders in Recently Deleted")
  }

  // MARK: - Step 3: minimal toolbar off-grid

  /// Map/People/Memories hide the grid toolbar (U15/U16/U18): no grouping, zoom,
  /// switcher, sort, filter or grid actions — only title, Sync and Search.
  func testMinimalToolbarOnMapPeopleMemories() {
    launchAndWaitForLibrary()
    // Control: the Library grid shows the full toolbar.
    XCTAssertTrue(el("grouping-segmented").exists)
    XCTAssertTrue(el("library-switcher").exists)
    let gridOnly = [
      "grouping-segmented", "grid-size-controls", "library-switcher",
      "thumbnail-display-toggle", "timeline-sort-menu", "timeline-filter-menu",
      "share-button", "favorite-button", "timeline-select-button",
    ]
    for (row, title) in [
      ("sidebar-map", "Map"), ("sidebar-people", "People"), ("sidebar-memories", "Memories"),
    ] {
      el(row).click()
      XCTAssertEqual(windowTitle(), title)
      for id in gridOnly {
        XCTAssertFalse(el(id).exists, "\(id) hidden on \(title)")
      }
      XCTAssertTrue(el("sync-button").exists, "Sync stays on \(title)")
      XCTAssertTrue(el("toolbar-search").exists, "Search stays on \(title)")
    }
  }

  // MARK: - Single page title per toolbar

  /// The destination name renders exactly once: the centered `.navigationTitle`.
  /// (The leading toolbar block now shows only the subtitle, so no second title
  /// may appear anywhere in the toolbar.) Covers one full-toolbar page (Library)
  /// and one minimal-toolbar page (Map). Host-only: needs a rendering app, which
  /// the sandbox sidebar-render gate blocks — not run green in this environment.
  func testPageTitleAppearsOncePerToolbar() {
    launchAndWaitForLibrary()
    for (row, title) in [("sidebar-library", "Library"), ("sidebar-map", "Map")] {
      el(row).click()
      XCTAssertEqual(windowTitle(), title, "window keeps the resolved title for \(title)")
      let toolbarTitles = app.toolbars.descendants(matching: .staticText)
        .matching(NSPredicate(format: "label == %@", title))
      XCTAssertEqual(toolbarTitles.count, 1, "\(title) appears exactly once in the toolbar")
    }
  }

  // MARK: - Gesture viewer (owner request: no chevron buttons)

  /// Inline viewer pages by horizontal scroll (swipeLeft/swipeRight) with no
  /// Previous/Next chevron buttons, and vertical scroll does not page.
  /// Honest gates: written for the host (`make test-macos-ui`) — cannot go green
  /// in this environment (known sidebar-render gate). macOS XCUITest has no
  /// pinch API (verified: `pinch` is not a member of macOS XCUIElement), so pinch
  /// zoom itself is not scripted — it rides native NSScrollView magnification
  /// (clamped 1–8× in `ViewerPagingScrollView`); the suite guards the paging
  /// direction contract instead.
  func testViewerGesturePaging() {
    launchAndWaitForLibrary()

    // Double-click opens the inline viewer on the newest photo.
    let cell = el("grid-cell-asset-personal-1")
    XCTAssertTrue(cell.waitForExistence(timeout: 10), "photo cell renders")
    cell.doubleClick()

    let buttons = app.descendants(matching: .button)
    XCTAssertTrue(
      buttons["Back"].waitForExistence(timeout: 10), "viewer opens with Back affordance")
    XCTAssertFalse(buttons["Previous"].exists, "prev chevron removed")
    XCTAssertFalse(buttons["Next"].exists, "next chevron removed")

    // The window title is the photo's capture date: swipe left pages to a
    // different photo (title changes), swipe right returns (title restores).
    let before = windowTitle()
    let viewer = app.windows.firstMatch
    viewer.swipeLeft()
    XCTAssertTrue(
      waitForTitle(changeFrom: before, timeout: 10), "swipe left pages to the next photo")
    viewer.swipeRight()
    XCTAssertTrue(
      waitForTitle(equalTo: before, timeout: 10), "swipe right pages back")

    // Vertical scroll must not page (title stays put).
    viewer.swipeUp()
    Thread.sleep(forTimeInterval: 1.0)
    XCTAssertEqual(windowTitle(), before, "vertical scroll does not page")
  }

  /// Polls the window title until it differs from (or returns to) a value.
  private func waitForTitle(changeFrom before: String? = nil, equalTo match: String? = nil, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let title = windowTitle()
      if let before, title != before { return true }
      if let match, title == match { return true }
      Thread.sleep(forTimeInterval: 0.5)
    }
    return false
  }
}
