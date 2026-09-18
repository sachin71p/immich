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
    app.launchForUIAutomation()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(el("sidebar").waitForExistence(timeout: 30), "sidebar renders")
    XCTAssertTrue(el("asset-grid").waitForExistence(timeout: 30), "grid renders")
    // The default 1400px window collapses trailing toolbar items (Favorite,
    // Select, Sync, Manage) into the overflow menu where AX cannot reach them:
    // ⌥-click the green button so the window fills the display and the full
    // grid toolbar renders before any test touches it.
    let zoom = app.windows.firstMatch.buttons["_XCUI:FullScreenWindow"]
    XCTAssertTrue(zoom.waitForExistence(timeout: 10), "zoom button renders")
    XCUIElement.perform(withKeyModifiers: .option) { zoom.click() }
    XCTAssertTrue(
      el("favorite-button").waitForExistence(timeout: 10), "toolbar unfurls after zoom")
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

  /// Menu-bar and sheet controls are label lookups (AX ids arrive with WP-C);
  /// always wait for them instead of clicking blind — T0 flake fix.
  @discardableResult
  private func menuItem(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
    // firstMatch: "Delete" exists in both the Edit menu and the context-menu
    // surface; the menu-bar instance is the one the suite drives.
    let item = app.menuBars.menuItems[title].firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 10), "menu item \(title)", file: file, line: line)
    item.click()
    return item
  }

  private func sheetButton(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
    let button = app.sheets.buttons[title]
    XCTAssertTrue(button.waitForExistence(timeout: 10), "sheet button \(title)", file: file, line: line)
    button.click()
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

  // MARK: - WP-F F3: signed-in launch never shows connect

  /// The fixture seed signs in synchronously (`MacAppState.seeded`), so from the
  /// first poll `connect.form` must never exist, and the footer must never read
  /// "0 Photos" while content loads (spinner or cached counts instead).
  /// Runs via `verify.sh mac-ui` on the host (main session owns device foreground).
  func testSignedInLaunchNeverShowsConnect() {
    app.launchForUIAutomation()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    // Poll every ~16 ms for the first 3 s: the connect form must never appear.
    let deadline = Date().addingTimeInterval(3)
    var sawConnect = false
    while Date() < deadline {
      if el("connect.form").exists {
        sawConnect = true
        break
      }
      usleep(16_000)
    }
    XCTAssertFalse(sawConnect, "connect.form rendered for a signed-in launch")
    XCTAssertTrue(el("sidebar").waitForExistence(timeout: 30), "sidebar renders")
    XCTAssertTrue(el("asset-grid").waitForExistence(timeout: 30), "grid renders")
    // "0 Photos" is only legal once loading finished (a genuinely empty library);
    // while loading, the footer shows the spinner.
    if el("library-loading").exists {
      XCTAssertFalse(
        el("library-sync-status").staticTexts["0 Photos, 0 Videos"].exists,
        "footer flashed 0 Photos while loading")
    }
  }

  // MARK: - Step 3: move sheet + ⌘Q

  /// Move sheet opens for a keyboard selection; Cancel closes, Escape closes, and ⌘Q
  /// quits the app while the sheet is open (quit guard: no upload/move in progress).
  func testMoveSheetCancelEscapeAndQuit() {
    // Self-quit well past the Cancel/Escape cycles below (the app exits through the
    // real terminate path while the reopened sheet is open).
    app.launchArguments += ["-HeirloomTerminateAfter=45"]
    launchAndWaitForLibrary()

    let firstCell = el("grid-cell-asset-personal-1")
    XCTAssertTrue(firstCell.waitForExistence(timeout: 10))
    firstCell.click()
    app.typeKey("a", modifierFlags: .command)
    menuItem("Move to…")
    XCTAssertTrue(el("move-sheet-title").waitForExistence(timeout: 10), "move sheet opens")

    // Cancel closes.
    sheetButton("Cancel")
    assertClosed("move-sheet-title", "move sheet Cancel closes")

    // Escape closes.
    menuItem("Move to…")
    XCTAssertTrue(el("move-sheet-title").waitForExistence(timeout: 10), "move sheet reopens")
    app.typeKey(.escape, modifierFlags: [])
    assertClosed("move-sheet-title", "move sheet Escape closes")

    // ⌘Q quits with the sheet open (no in-progress guard in fixture mode). The
    // launch-arg timer quits the app while this reopened sheet is open.
    menuItem("Move to…")
    XCTAssertTrue(el("move-sheet-title").waitForExistence(timeout: 10), "move sheet reopens")
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 40), "quit with sheet open")
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
    sheetButton("Cancel")
    assertClosed("new-space-name", "new-space Cancel closes")
  }

  func testNewAlbumSheetCancelAndEscape() {
    launchAndWaitForLibrary()
    el("sidebar-new-album").click()
    XCTAssertTrue(el("new-album-name").waitForExistence(timeout: 10), "new-album sheet opens")
    sheetButton("Cancel")
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
    menuItem("Add to Album…")
    XCTAssertTrue(
      el("add-to-album-album-trip").waitForExistence(timeout: 10), "add-to-album sheet opens")
    sheetButton("Cancel")
    assertClosed("add-to-album-album-trip", "add-to-album Cancel closes")
    menuItem("Add to Album…")
    XCTAssertTrue(
      el("add-to-album-album-trip").waitForExistence(timeout: 10), "add-to-album sheet reopens")
    app.typeKey(.escape, modifierFlags: [])
    assertClosed("add-to-album-album-trip", "add-to-album Escape closes")
  }

  func testManageSpaceSheetDoneAndEscape() {
    launchAndWaitForLibrary()
    // Space rows render from the async spaces refresh, and Manage additionally
    // needs the space selection applied — wait for both, never click blind.
    XCTAssertTrue(
      el("sidebar-space-space-family").waitForExistence(timeout: 10), "space row renders")
    el("sidebar-space-space-family").click()
    XCTAssertEqual(windowTitle(), "Family")
    XCTAssertTrue(
      el("space-manage-button").waitForExistence(timeout: 10), "manage button renders")
    el("space-manage-button").click()
    XCTAssertTrue(el("space-save").waitForExistence(timeout: 10), "manage sheet opens")
    // Done carries `.cancelAction` (closes without saving); Escape does the same.
    sheetButton("Done")
    assertClosed("space-save", "manage Done closes")
    XCTAssertTrue(
      el("space-manage-button").waitForExistence(timeout: 10), "manage button renders")
    el("space-manage-button").click()
    XCTAssertTrue(el("space-save").waitForExistence(timeout: 10), "manage sheet reopens")
    app.typeKey(.escape, modifierFlags: [])
    assertClosed("space-save", "manage Escape closes")
  }

  func testCameraImportSheetDismisses() {
    launchAndWaitForLibrary()
    menuItem("Import from Camera…")
    XCTAssertTrue(
      app.sheets.element(boundBy: 0).waitForExistence(timeout: 10), "camera sheet opens")
    // Done carries `.cancelAction` in both the device and the no-device layouts.
    sheetButton("Done")
    XCTAssertEqual(app.sheets.count, 0, "camera Done closes")
    menuItem("Import from Camera…")
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
    // The ⌘-click rebuilds selection-driven UI including the toolbar: prove the
    // new selection flushed through (menus rebuild on the same state) before
    // touching the toolbar.
    waitForSelectionMenus()
    XCTAssertTrue(
      el("favorite-button").waitForExistence(timeout: 10), "favorite button renders")
    el("favorite-button").click()
    el("sidebar-favorites").click()
    XCTAssertEqual(windowTitle(), "Favorites")
    XCTAssertTrue(
      el("grid-cell-asset-personal-2").waitForExistence(timeout: 10),
      "first favorited item in Favorites")
    XCTAssertTrue(
      el("grid-cell-asset-space-shot").waitForExistence(timeout: 10),
      "second favorited item in Favorites")
    // personal-1 ships favorited in the seed; the sized small fixture adds
    // generated favorites too, so this is a floor, not an exact count.
    XCTAssertGreaterThanOrEqual(
      gridCellCount(), 3, "Favorites holds the seed favorite plus the 2 new ones")
  }

  // MARK: - Step 3: fixture-mode trash without a full reload

  /// Trash in fixture mode: the item leaves the grid (grid element itself persists —
  /// no full reload) and appears in Recently Deleted.
  func testTrashRemovesWithoutFullReload() {
    launchAndWaitForLibrary()
    let doomed = el("grid-cell-asset-personal-2")
    XCTAssertTrue(doomed.waitForExistence(timeout: 10))
    // No visible-count assertion: the grid virtualizes (visible cells are
    // viewport-sized, not library-sized), so trashing one of 2k rows cannot move
    // the count. Gone-from-grid + renders-in-Trash is the removal proof.
    doomed.click()
    waitForSelectionMenus()
    // Image > Delete owns the ⌘⌫ shortcut (MacMenus): send the keystroke rather
    // than clicking through the menu bar, which is timing-fragile under automation.
    app.typeKey(.delete, modifierFlags: .command)
    XCTAssertTrue(el("toast").waitForExistence(timeout: 10), "trash toast shows")
    XCTAssertTrue(el("asset-grid").exists, "grid persists (no full reload)")
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: el("grid-cell-asset-personal-2"))
    XCTAssertEqual(
      XCTWaiter.wait(for: [gone], timeout: 10), .completed, "trashed item leaves the grid")
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

  /// The destination name renders exactly once: as the window title via the centered
  /// `.navigationTitle`. (The leading toolbar block shows only the subtitle — the
  /// single-title fix — so XCUITest finds no title staticText inside `app.toolbars`;
  /// the window titlebar carries it.) Covers one full-toolbar page (Library) and
  /// one minimal-toolbar page (Map).
  func testPageTitleAppearsOncePerToolbar() {
    launchAndWaitForLibrary()
    for (row, title) in [("sidebar-library", "Library"), ("sidebar-map", "Map")] {
      el(row).click()
      XCTAssertEqual(windowTitle(), title, "window keeps the resolved title for \(title)")
      let toolbarTitles = app.toolbars.descendants(matching: .staticText)
        .matching(NSPredicate(format: "label == %@", title))
      XCTAssertEqual(toolbarTitles.count, 0, "\(title) is not duplicated in the toolbar")
    }
  }

  // MARK: - Gesture viewer (owner request: no chevron buttons)

  /// Inline viewer pages with no Previous/Next chevron buttons, and vertical
  /// scroll does not page. Paging is driven by arrow keys: XCUITest synthetic
  /// swipes carry momentum, which the paging tracker deliberately ignores (they
  /// pass through unhandled), and a press-drag never becomes a scrollWheel event —
  /// so no synthetic gesture can page. Arrows ride the same `page(by:)` path
  /// (`.onKeyPress` in MacViewerView).
  func testViewerGesturePaging() {
    launchAndWaitForLibrary()

    // Double-click opens the inline viewer on the photo.
    let cell = el("grid-cell-asset-personal-1")
    XCTAssertTrue(cell.waitForExistence(timeout: 10), "photo cell renders")
    cell.doubleClick()

    let buttons = app.descendants(matching: .button)
    XCTAssertTrue(
      buttons["Back"].waitForExistence(timeout: 10), "viewer opens with Back affordance")
    XCTAssertFalse(buttons["Previous"].exists, "prev chevron removed")
    XCTAssertFalse(buttons["Next"].exists, "next chevron removed")

    // The window title is the photo's capture date: left arrow pages to a
    // different photo (title changes), right arrow returns (title restores).
    // Focus doesn't follow into the viewer automatically: click it first.
    let before = windowTitle()
    let viewer = app.windows.firstMatch
    viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    app.typeKey(.leftArrow, modifierFlags: [])
    XCTAssertTrue(
      waitForTitle(changeFrom: before, timeout: 10), "left arrow pages to the next photo")
    app.typeKey(.rightArrow, modifierFlags: [])
    XCTAssertTrue(
      waitForTitle(equalTo: before, timeout: 10), "right arrow pages back")

    // Vertical scroll must not page: within 2 s the title must NOT change
    // (a timed-out "title changed" expectation, not a sleep + re-read).
    // (Momentum scrolls pass through the tracker unhandled by design.)
    viewer.swipeUp()
    let stayedPut = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "title != %@", before),
      object: app.windows.firstMatch)
    XCTAssertEqual(
      XCTWaiter.wait(for: [stayedPut], timeout: 2), .timedOut,
      "vertical scroll does not page")
  }

  /// V1 pixels (Gate-1 black-viewer regression): the opened viewer must show a
  /// content image with a real frame. Chrome-only assertions (Back button,
  /// titles) passed while every page stayed blank, because the pager never
  /// demanded its initial page — so this asserts pixels, not chrome.
  func testViewerShowsImageOnOpen() {
    launchAndWaitForLibrary()

    let cell = el("grid-cell-asset-personal-1")
    XCTAssertTrue(cell.waitForExistence(timeout: 10), "photo cell renders")
    cell.doubleClick()
    XCTAssertTrue(el("viewer").waitForExistence(timeout: 10), "viewer opens")

    // Toolbar icons are ~12 px images; the content image fills the viewer.
    let images = app.descendants(matching: .image)
    var found = false
    let deadline = Date().addingTimeInterval(15)
    while !found, Date() < deadline {
      for i in 0..<min(images.count, 12) {
        let im = images.element(boundBy: i)
        if im.exists, im.frame.width > 200 { found = true; break }
      }
      if !found { Thread.sleep(forTimeInterval: 0.5) }
    }
    XCTAssertTrue(found, "viewer shows a content image on open")
  }

  /// Waits (sleep-free, via predicate expectations) until the window title
  /// differs from `before` or returns to `match`.
  private func waitForTitle(changeFrom before: String? = nil, equalTo match: String? = nil, timeout: TimeInterval) -> Bool {
    let predicate: NSPredicate
    if let match {
      predicate = NSPredicate(format: "title == %@", match)
    } else if let before {
      predicate = NSPredicate(format: "title != %@", before)
    } else {
      return false
    }
    let changed = XCTNSPredicateExpectation(predicate: predicate, object: app.windows.firstMatch)
    return XCTWaiter.wait(for: [changed], timeout: timeout) == .completed
  }
}
