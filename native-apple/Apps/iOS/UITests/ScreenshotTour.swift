import XCTest

/// WP0 screenshot tour: with fixture data, visits every tab, sheet and menu listed in
/// `01-controls.md` and attaches a screenshot per stop (`XCTAttachment`, `.keepAlways`).
/// Runs on the host via `native-apple/scripts/verify.sh ios` as part of the
/// `Heirloom-iOS-UITests` bundle. Read-only: nothing here taps a destructive action, and fixture
/// mode (`-useFixtureStore`) runs against an in-memory store with no server.
///
/// W2 work packages extend this tour for their restyled screens.
final class ScreenshotTourUITests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments += ["-useFixtureStore"]
    app.launch()
  }

  func testScreenshotTour() throws {
    // Matched by label: identifier propagation onto tab-bar buttons is flaky (seen
    // in-tree — SyncUITests uses the same pattern). 60 s for cold install + seed.
    XCTAssertTrue(
      app.tabBars.buttons["Library"].waitForExistence(timeout: 60),
      "library tab should render from the fixture DB")

    tourLibrary()
    tourViewer()
    tourCollections()
    tourSearch()
    tourAccount()
  }

  // MARK: - helpers

  /// Screenshot the current screen into the result bundle.
  func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Tap when present; returns whether the tap happened.
  @discardableResult
  func tap(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
    guard element.waitForExistence(timeout: timeout) else { return false }
    element.tap()
    return true
  }

  /// Switches tabs by label (identifiers are flaky on tab bars) and verifies arrival:
  /// a tap can be swallowed resigning keyboard focus, so retry, then fail loudly rather
  /// than screenshotting the wrong screen.
  func goTab(_ label: String, expect: XCUIElement) {
    for i in 0..<3 {
      app.tabBars.buttons[label].tap()
      if expect.waitForExistence(timeout: 5) { return }
      // Diagnostic: which tab (if any) is selected on this attempt.
      let sel = app.tabBars.buttons.matching(NSPredicate(format: "selected == YES")).firstMatch
      let selLabel = sel.exists ? sel.label : "<none>"
      let att = XCTAttachment(screenshot: app.screenshot())
      att.name = "diag-tab-\(label)-\(i)-sel-\(selLabel)"
      att.lifetime = .keepAlways
      add(att)
    }
    XCTFail("tab \(label) did not open")
  }

  /// Dismisses the software keyboard if present — it overlaps the tab bar, so tab
  /// taps land on keys instead of switching. Return re-submits the (unchanged) query,
  /// which is idempotent, and resigns the single-line field.
  func dismissKeyboard() {
    // Gate on hittability: tapping mid-animation raises kAXErrorFailure
    // ("failed to scroll to visible"), which fails the tour outright.
    let keyboard = app.keyboards.firstMatch
    guard keyboard.waitForExistence(timeout: 3) else { return }
    let ret = keyboard.buttons["return"]
    guard ret.waitForExistence(timeout: 3), ret.isHittable else { return }
    ret.tap()
    sleep(1)
  }

  /// Tap, scrolling the current list up to a few times for rows below the fold.
  @discardableResult
  func tapScrolling(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    for _ in 0..<5 {
      if element.waitForExistence(timeout: timeout) {
        element.tap()
        return true
      }
      app.swipeUp()
    }
    return false
  }

  /// The viewer's Close button. The search field's clear (x) button also carries the
  /// label "Close", so scope by excluding its `xmark.circle.fill` identifier.
  @discardableResult
  func closeViewer() -> Bool {
    let close = app.buttons.matching(
      NSPredicate(format: "label == 'Close' AND identifier != 'xmark.circle.fill'")
    ).firstMatch
    guard tap(close, timeout: 10) else { return false }
    // Fall back to the app's own swipe-down dismiss gesture.
    if app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 2) {
      app.swipeDown()
      sleep(1)
    }
    return true
  }

  func back() {
    // Every pushed screen here lives in a NavigationStack with a back button.
    tap(app.navigationBars.buttons.firstMatch, timeout: 5)
  }

  /// Dismisses a detent sheet (Info panel): a plain swipeDown only bounces between
  /// detents, so drag the sheet from near its grabber to the bottom instead.
  func dismissSheet() {
    let sheet = app.sheets.firstMatch
    guard sheet.waitForExistence(timeout: 5) else { return }
    let top = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
    let bottom = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
    top.press(forDuration: 0.1, thenDragTo: bottom)
    sleep(1)
    if sheet.waitForExistence(timeout: 2) {
      top.press(forDuration: 0.1, thenDragTo: bottom)
      sleep(1)
    }
  }

  // MARK: - Library tab

  func tourLibrary() {
    // Zoom persists across runs — normalize to All before expecting the grid.
    goTab("Library", expect: app.descendants(matching: .any)["library-zoom"])
    if tap(app.buttons["All Photos"], timeout: 10) {
      sleep(1)
    }
    XCTAssertTrue(
      app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 30))
    shot("01-library-all")

    // Filter menu (Sort / Filter: / Media Types / Library View / View Options).
    let filterMenu = app.descendants(matching: .any)["library-filter-menu"]
    if tap(filterMenu, timeout: 10) {
      sleep(1)
      shot("02-library-filter-menu")
      // Dismiss by picking the already-current filter (a no-op reload).
      if !tap(app.buttons["filter-all-items"], timeout: 5) {
        tap(filterMenu, timeout: 5)
      }
    }

    // Zoom levels (glass Years · Months · All in the tab-bar accessory) + drill-down.
    if tap(app.buttons["Years"], timeout: 5) {
      sleep(1)
      shot("03a-library-years")
      let yearCard = app.descendants(matching: .any).matching(
        NSPredicate(format: "identifier BEGINSWITH 'year-card-'")
      ).firstMatch
      if tap(yearCard, timeout: 10) {
        sleep(1)
        shot("03b-library-months")
        let dayCard = app.descendants(matching: .any).matching(
          NSPredicate(format: "identifier BEGINSWITH 'day-card-'")
        ).firstMatch
        if tap(dayCard, timeout: 10) {
          sleep(1)
          shot("03c-library-day-to-all")
        }
      }
    }

    // Select mode: top filter + … + ✕, bottom Share / N Selected / Trash.
    if tap(app.buttons["Select"], timeout: 10) {
      sleep(1)
      shot("04-library-select-mode")
      tap(app.collectionViews.cells.firstMatch, timeout: 10)
      sleep(1)
      shot("05-library-selected-one")
      // "…" menu (bulk actions) then Move sheet (Rules.MoveTargets).
      if tap(app.descendants(matching: .any)["select-more-menu"], timeout: 10) {
        sleep(1)
        shot("05b-library-select-more-menu")
        if tap(app.descendants(matching: .any)["select-action-move-to"], timeout: 10) {
          XCTAssertTrue(
            app.descendants(matching: .any)["move-targets"].waitForExistence(timeout: 10))
          shot("06-library-move-sheet")
          tap(app.buttons["Close"], timeout: 10)
        }
      }
      tap(app.descendants(matching: .any)["select-exit"], timeout: 10)
    }

    // Timeline Sources sheet (filter menu → Library View group → "Show in Timeline…",
    // scrolling the tall menu if the row is below the fold).
    if tap(filterMenu, timeout: 10) {
      var openedSources = tap(
        app.descendants(matching: .any)["libraryview-show-in-timeline"], timeout: 5)
      if !openedSources {
        // Coordinate drag: the menu isn't always `menus`-typed, and `swipeUp`
        // doesn't move menu content anyway.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7)).press(
          forDuration: 0.05,
          thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3)))
        openedSources = tap(
          app.descendants(matching: .any)["libraryview-show-in-timeline"], timeout: 5)
      }
      if openedSources {
        XCTAssertTrue(
          app.descendants(matching: .any)["timeline-sources"].waitForExistence(timeout: 10))
        shot("07-library-timeline-sources")
        tap(app.buttons["Done"], timeout: 10)
      } else if !tap(app.buttons["filter-all-items"], timeout: 5) {
        tap(filterMenu, timeout: 5)
      }
    }
  }

  // MARK: - Viewer

  func tourViewer() {
    goTab("Library", expect: app.descendants(matching: .any)["library-grid"])
    XCTAssertTrue(app.collectionViews.cells.firstMatch.waitForExistence(timeout: 10))
    app.collectionViews.cells.firstMatch.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10),
      "tapping a grid cell should open the viewer")
    sleep(1)
    shot("08-viewer-photo")

    // Info panel (read-only sheet).
    if tap(app.buttons["Info"], timeout: 10) {
      sleep(1)
      shot("09-viewer-info")
      dismissSheet()
    }

    // "…" menu (Move to… / Add to Album / Archive / …). Best effort: the toolbar Menu
    // carries no stable identifier, so find it by its ellipsis label — but only when no
    // sheet is covering the viewer (a covered tap would hit the wrong element).
    if !app.sheets.firstMatch.exists {
      let more = app.buttons.matching(NSPredicate(format: "label CONTAINS 'More'")).firstMatch
      if more.waitForExistence(timeout: 5) {
        more.tap()
        sleep(1)
        shot("10-viewer-more-menu")
        more.tap()
      } else {
        XCTContext.runActivity(named: "viewer-more-menu skipped (no identifier)") { _ in }
      }
    }

    closeViewer()
  }

  // MARK: - Collections tab

  func tourCollections() {
    goTab("Collections", expect: app.descendants(matching: .any)["collections"])
    XCTAssertTrue(
      app.descendants(matching: .any)["collections"].waitForExistence(timeout: 10),
      "collections screen should open (viewer must be closed by now)")
    shot("11-collections")

    // Album detail: fixture album "Trip" has two members, so it lives under
    // "Shared Albums" (the top-level list only shows single-member albums).
    if tap(app.buttons["Shared Albums"], timeout: 10),
      tap(app.buttons["Trip"], timeout: 10)
    {
      sleep(1)
      shot("12-collections-album-detail")
      back()
      back()
    }

    // People row (fixture person "Bob").
    if tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Bob'")).firstMatch, timeout: 10)
    {
      sleep(1)
      shot("13-collections-person-detail")
      back()
    }

    // Memories.
    if tap(app.descendants(matching: .any)["collections-memories"], timeout: 10) {
      sleep(1)
      shot("14-collections-memories")
      back()
    }

    // Map (Places).
    if tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Map'")).firstMatch, timeout: 10)
    {
      sleep(1)
      shot("15-collections-places")
      back()
    }

    // Favorites list.
    if tap(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Favorites'")).firstMatch,
      timeout: 10)
    {
      sleep(1)
      shot("16-collections-favorites")
      back()
    }

    // Recently Deleted (trash scope, read-only; below the fold — scroll to it).
    if tapScrolling(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recently Deleted'")).firstMatch)
    {
      sleep(1)
      shot("17-collections-recently-deleted")
      back()
    }
  }

  // MARK: - Search tab

  func tourSearch() {
    goTab("Search", expect: app.descendants(matching: .any)["search-view"])
    XCTAssertTrue(
      app.descendants(matching: .any)["search-view"].waitForExistence(timeout: 10))
    shot("18-search")

    // Type into the system search field (300 ms debounce, no submit button) and
    // open the first hit in the viewer.
    let field = app.searchFields.firstMatch
    if tap(field, timeout: 10) {
      field.typeText("IMG")
      sleep(3)
      shot("19-search-typed")
      XCTAssertTrue(
        app.descendants(matching: .any)["search-results"].waitForExistence(timeout: 10))
      shot("20-search-results")
      if app.collectionViews.cells.firstMatch.waitForExistence(timeout: 5) {
        app.collectionViews.cells.firstMatch.tap()
        if app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10) {
          shot("21-search-result-viewer")
          closeViewer()
        }
      }
      // Clearing the query returns to idle, where the just-recorded "IMG"
      // recent appears as an image card.
      if field.buttons["Clear text"].waitForExistence(timeout: 5) {
        field.buttons["Clear text"].tap()
        sleep(2)
        XCTAssertTrue(
          app.descendants(matching: .any)["search-recents"].staticTexts["IMG"]
            .waitForExistence(timeout: 10),
          "the just-run query should appear as a Recents card")
        shot("22-search-recents")
      }
      dismissKeyboard()
    }
  }

  // MARK: - Account sheet (WP5; reached from the Search toolbar until WP4 wires
  // the Collections avatar)

  func tourAccount() {
    goTab("Search", expect: app.descendants(matching: .any)["search-view"])
    XCTAssertTrue(
      tap(app.buttons["account-button"], timeout: 10),
      "account button should be in the Search toolbar")
    XCTAssertTrue(
      app.descendants(matching: .any)["account-sheet"].waitForExistence(timeout: 10))

    // A name, never the raw user id.
    let name = app.descendants(matching: .any)["account-name"]
    XCTAssertTrue(name.waitForExistence(timeout: 10))
    XCTAssertFalse(name.label.isEmpty, "account sheet should show a name")
    XCTAssertNotEqual(name.label, "u1", "account sheet must not show the raw user id")
    shot("23-account-sheet")

    // Sign Out shows its confirmation; cancel it so the tour keeps its session.
    // The button sits at the bottom of the sheet list — scroll to it.
    XCTAssertTrue(tapScrolling(app.buttons["account-signout"]))
    XCTAssertTrue(
      app.alerts.firstMatch.waitForExistence(timeout: 5),
      "sign out should ask for confirmation")
    shot("24-account-signout-confirm")
    app.alerts.buttons["Cancel"].tap()
    tap(app.buttons["Done"], timeout: 10)
  }
}
