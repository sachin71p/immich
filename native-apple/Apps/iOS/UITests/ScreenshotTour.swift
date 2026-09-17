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
    tourShared()
    tourSettings()
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

  /// Bidirectional variant for the WP4 Collections tour: sections above the
  /// current offset are missed by swipe-up-only scrolling, so sweep up first
  /// (content below) then down (content above), tapping when hittable.
  @discardableResult
  func tapScrollingEither(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    for _ in 0..<3 {
      if element.waitForExistence(timeout: timeout), element.isHittable {
        element.tap()
        return true
      }
      app.swipeUp()
    }
    for _ in 0..<8 {
      if element.waitForExistence(timeout: 2), element.isHittable {
        element.tap()
        return true
      }
      app.swipeDown()
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
    goTab("Library", expect: app.descendants(matching: .any)["library-grid"])
    shot("01-library-all")

    // Library switcher menu (Both / Personal / spaces / libraries / Show in Timeline…).
    if tap(app.buttons["library-switcher"], timeout: 10) {
      sleep(1)
      shot("02-library-switcher-menu")
      // While the menu is open its label leaves the hierarchy, so dismiss by picking
      // the already-current source (a no-op reload) with a toggle fallback.
      if !tap(app.buttons["Both Libraries"], timeout: 5) {
        tap(app.buttons["library-switcher"], timeout: 5)
      }
    }

    // Zoom levels (segmented picker buttons; Days was removed in WP1).
    for level in ["Years", "Months", "All Photos"] {
      if tap(app.buttons[level], timeout: 5) {
        sleep(1)
        shot("03-library-zoom-\(level.lowercased().replacingOccurrences(of: " ", with: "-"))")
      }
    }
    tap(app.buttons["Months"], timeout: 5)

    // Select mode + selection action bar.
    if tap(app.buttons["Select"], timeout: 10) {
      sleep(1)
      shot("04-library-select-mode")
      tap(app.collectionViews.cells.firstMatch, timeout: 10)
      sleep(1)
      shot("05-library-selected-one")
      // Move sheet (lists Rules.MoveTargets; Camera is eligible for the personal asset).
      if tap(app.buttons["Move to…"], timeout: 10) {
        XCTAssertTrue(
          app.descendants(matching: .any)["move-targets"].waitForExistence(timeout: 10))
        shot("06-library-move-sheet")
        tap(app.buttons["Close"], timeout: 10)
      }
      tap(app.buttons["Done"], timeout: 10)
    }

    // Timeline Sources sheet (from the switcher menu's "Show in Timeline…" row).
    if tap(app.buttons["library-switcher"], timeout: 10) {
      if tap(app.buttons["Show in Timeline…"], timeout: 10) {
        XCTAssertTrue(
          app.descendants(matching: .any)["timeline-sources"].waitForExistence(timeout: 10))
        shot("07-library-timeline-sources")
        tap(app.buttons["Done"], timeout: 10)
      } else if !tap(app.buttons["Both Libraries"], timeout: 5) {
        tap(app.buttons["library-switcher"], timeout: 5)
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

  // MARK: - Collections tab (WP4: every section + every detail type)

  func tourCollections() {
    goTab("Collections", expect: app.descendants(matching: .any)["collections"])
    XCTAssertTrue(
      app.descendants(matching: .any)["collections"].waitForExistence(timeout: 10),
      "collections screen should open (viewer must be closed by now)")

    // Every section shell renders (scroll each into view).
    for section in [
      "memories", "pinned", "albums", "people", "sharedAlbums", "spaces",
      "recentDays", "mediaTypes", "utilities", "places",
    ] {
      XCTAssertTrue(
        tapScrollingEither(
          app.descendants(matching: .any)["collections-section-\(section)"]),
        "collections section \(section) should render")
    }
    // Toolbar: overflow menu + WP5 placeholder avatar.
    XCTAssertTrue(
      app.descendants(matching: .any)["account-placeholder"].waitForExistence(timeout: 5),
      "account placeholder should sit in the Collections toolbar")
    shot("11-collections")

    // Memories page (fixture has no saved memories: empty state + tour shot).
    if tapScrollingEither(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Memories'")).firstMatch) {
      XCTAssertTrue(
        app.descendants(matching: .any)["memories"].waitForExistence(timeout: 10),
        "memories page should open")
      sleep(1)
      shot("12-collections-memories")
      back()
    }

    // Albums › page: Personal/Shared segments, then the fixture album.
    if tapScrollingEither(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Albums'")).firstMatch) {
      XCTAssertTrue(
        app.descendants(matching: .any)["albums-list"].waitForExistence(timeout: 10),
        "albums list should open")
      shot("13-collections-albums")
      // Fixture album "Trip" is shared (two members): flip the segment.
      let segments = app.segmentedControls["albums-segment"]
      if segments.waitForExistence(timeout: 5) {
        segments.buttons["Shared"].tap()
        sleep(1)
        shot("13b-collections-albums-shared")
      }
      if tap(app.descendants(matching: .any)["album-Trip"], timeout: 10) {
        XCTAssertTrue(
          app.descendants(matching: .any)["detail-grid"].waitForExistence(timeout: 10),
          "album grid should open")
        sleep(1)
        shot("14-collections-album-detail")
        back()
      }
      back()
    }

    // People › page (fixture person "Bob") + person detail.
    if tapScrollingEither(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'People'")).firstMatch) {
      XCTAssertTrue(
        app.descendants(matching: .any)["people-list"].waitForExistence(timeout: 10),
        "people list should open")
      shot("15-collections-people")
      if tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Bob'")).firstMatch, timeout: 10) {
        sleep(2)
        shot("15b-collections-person-detail")
        back()
      }
      back()
    }

    // Pinned Edit sheet (reorder; cancel via Done).
    if tap(app.descendants(matching: .any)["pinned-edit"], timeout: 10) {
      sleep(1)
      shot("16-collections-pinned-edit")
      tap(app.buttons["Done"], timeout: 5)
    }

    // Utility pills: Favorites, Recently Deleted, Hidden, Videos, Captured by Me.
    for (pill, shotName) in [
      ("utility-Favorites", "17-collections-favorites"),
      ("utility-Recently Deleted", "17b-collections-recently-deleted"),
      ("utility-Hidden", "17c-collections-hidden"),
      ("utility-Videos", "17d-collections-videos"),
      ("utility-Captured by Me", "17e-collections-captured"),
      ("utility-Archive", "17f-collections-archive"),
    ] {
      if tapScrollingEither(app.descendants(matching: .any)[pill]) {
        if app.descendants(matching: .any)["detail-grid"].waitForExistence(timeout: 10) {
          sleep(1)
          shot(shotName)
        }
        back()
      }
    }

    // Locked: simulator has no enrolled biometrics, so auth fails fast into the
    // denied view (or a system prompt appears — cancel it and move on).
    if tapScrollingEither(app.descendants(matching: .any)["utility-Locked"]) {
      sleep(2)
      if app.alerts.firstMatch.waitForExistence(timeout: 3) {
        app.alerts.firstMatch.buttons.firstMatch.tap()
      }
      shot("17g-collections-locked")
      back()
    }

    // Duplicates (server-backed; fixture mode shows unavailable/empty — still a stop).
    if tapScrollingEither(app.descendants(matching: .any)["utility-Duplicates"]) {
      sleep(1)
      shot("17h-collections-duplicates")
      back()
    }

    // Space detail (fixture space "Family", grid sorted date desc).
    if tapScrollingEither(app.descendants(matching: .any)["space-Family"]) {
      XCTAssertTrue(
        app.descendants(matching: .any)["detail-grid"].waitForExistence(timeout: 10),
        "space grid should open")
      sleep(1)
      shot("18-collections-space-detail")
      back()
    }

    // Map (Places).
    if tapScrollingEither(app.descendants(matching: .any)["places-tile"]) {
      sleep(1)
      shot("19-collections-places")
      back()
    }

    // Collapse toggle: hiding Shared Albums removes its tiles.
    goTab("Library", expect: app.descendants(matching: .any)["library-grid"])
    goTab("Collections", expect: app.descendants(matching: .any)["collections"])
    if tapScrollingEither(app.descendants(matching: .any)["collections-collapse-sharedAlbums"]) {
      sleep(1)
      XCTAssertFalse(
        app.descendants(matching: .any)["album-Trip"].exists,
        "collapsing Shared Albums should hide its tiles")
      shot("20-collections-collapsed")
      tapScrollingEither(app.descendants(matching: .any)["collections-collapse-sharedAlbums"])
    }

    // Reorder sheet.
    if tapScrollingEither(app.descendants(matching: .any)["collections-reorder"]) {
      sleep(1)
      shot("21-collections-reorder")
      tap(app.buttons["Done"], timeout: 5)
    }
  }

  // MARK: - Search tab

  func tourSearch() {
    goTab("Search", expect: app.descendants(matching: .any)["search-view"])
    XCTAssertTrue(
      app.descendants(matching: .any)["search-view"].waitForExistence(timeout: 10))
    shot("18-search")

    // Query the fixture filenames, submit, and open the first hit in the viewer.
    if tap(app.textFields["search-field"], timeout: 10) {
      app.textFields["search-field"].typeText("IMG")
      shot("19-search-typed")
      tap(app.buttons["search-submit"], timeout: 10)
      sleep(2)
      shot("20-search-results")
      if app.collectionViews.cells.firstMatch.waitForExistence(timeout: 5) {
        app.collectionViews.cells.firstMatch.tap()
        if app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10) {
          shot("21-search-result-viewer")
          closeViewer()
        }
      }
      dismissKeyboard()
    }
  }

  // MARK: - Shared tab

  func tourShared() {
    goTab("Shared", expect: app.buttons["Family"])
    sleep(1)
    shot("22-shared")

    // Space detail (fixture space "Family").
    if tapScrolling(app.buttons["Family"]) {
      sleep(1)
      shot("23-shared-space-detail")
      back()
    }

    // New Shared Library sheet (cancel it — creation needs a server).
    if tapScrolling(app.buttons.matching(NSPredicate(format: "label CONTAINS 'New Shared'")).firstMatch) {
      sleep(1)
      shot("24-shared-create-sheet")
      if !tap(app.buttons["Cancel"], timeout: 5) {
        app.swipeDown()
      }
    }
  }

  // MARK: - Settings tab

  func tourSettings() {
    goTab("Settings", expect: app.descendants(matching: .any)["settings"])
    XCTAssertTrue(
      app.descendants(matching: .any)["settings"].waitForExistence(timeout: 10))
    shot("25-settings")

    // Timeline Sources sheet.
    if tapScrolling(app.buttons["Timeline Sources…"]) {
      XCTAssertTrue(
        app.descendants(matching: .any)["timeline-sources"].waitForExistence(timeout: 10))
      shot("26-settings-timeline-sources")
      tap(app.buttons["Done"], timeout: 10)
    }

    // Free Up Space.
    if tapScrolling(app.descendants(matching: .any)["settings-freeup"]) {
      sleep(1)
      shot("27-settings-free-up-space")
      back()
    }

    // Sign Out is intentionally not tapped: the current build signs out without a
    // confirmation alert, which would end the session mid-tour.
  }
}
