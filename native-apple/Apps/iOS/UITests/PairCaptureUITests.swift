import XCTest

/// WP-X pair re-capture: one launch against the REAL library (no fixture
/// flag), fifteen read-only stops mirroring `assets/pairs/01..15`. Tolerant by
/// design — a stop that cannot navigate records a `miss-<stop>` diagnostic and
/// moves on, so one renamed label cannot void the other fourteen captures.
///
/// READ-ONLY CONTRACT (§0.5): editors open and Cancel (never Done/Save, no
/// slider drags, no style taps); the long-press menu is photographed, never
/// actioned; search is opened, never typed into; sign-out is never confirmed.
/// The grid pinch (03) restores itself with a reverse pinch.
final class PairCaptureUITests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = true
    app = XCUIApplication()
    app.launch()
  }

  /// Focused retry for the two video stops (09/10) without re-shooting 01–08/11–15.
  func testPairCaptureVideos() throws {
    XCTAssertTrue(
      app.tabBars.buttons["Library"].waitForExistence(timeout: 120),
      "library tab should render from the real library")
    stop09VideoViewer()
    stop10VideoEditor()
  }

  func testPairCapture() throws {
    XCTAssertTrue(
      app.tabBars.buttons["Library"].waitForExistence(timeout: 120),
      "library tab should render from the real library")
    stop01Library()
    stop02FilterPills()
    stop03PinchedGrid()
    stop04Viewer()
    stop05InfoPanel()
    stop06EditorPhoto()
    stop07EditorStyles()
    stop08EditorCrop()
    stop09VideoViewer()
    stop10VideoEditor()
    stop11Account()
    stop12Settings()
    stop13Search()
    stop14Collections()
    stop15LongPress()
  }

  // MARK: - helpers

  func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func miss(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "miss-\(name)"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @discardableResult
  func tap(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
    guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
    element.tap()
    return true
  }

  func goTab(_ label: String, expect: XCUIElement) -> Bool {
    for _ in 0..<3 {
      app.tabBars.buttons[label].tap()
      if expect.waitForExistence(timeout: 5) { return true }
    }
    return false
  }

  /// Vertical scroll that starts at the left edge (x=0.08), clear of the
  /// horizontal carousels that eat center-screen swipes on Collections.
  func edgeScroll(up: Bool, times: Int = 1) {
    for _ in 0..<times {
      let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: up ? 0.6 : 0.25))
      let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: up ? 0.2 : 0.6))
      from.press(forDuration: 0.05, thenDragTo: to)
    }
  }

  /// The Videos pill by identifier, link-button label, then bare text —
  /// whichever is hittable gets the tap.
  @discardableResult
  func tapVideosPill(timeout: TimeInterval = 1) -> Bool {
    let byId = app.descendants(matching: .any)["utility-Videos"]
    if byId.waitForExistence(timeout: timeout), byId.isHittable {
      byId.tap()
      return true
    }
    let byLabel = app.buttons.matching(
      NSPredicate(format: "label CONTAINS 'Videos'")).firstMatch
    if byLabel.waitForExistence(timeout: timeout), byLabel.isHittable {
      byLabel.tap()
      return true
    }
    let byText = app.descendants(matching: .any)["collections-section-mediaTypes"]
      .staticTexts["Videos"].firstMatch
    if byText.waitForExistence(timeout: timeout), byText.isHittable {
      byText.tap()
      return true
    }
    return false
  }

  func closeViewer() {
    if tap(app.buttons["viewer-back"], timeout: 5) { sleep(1); return }
    app.swipeDown()
    sleep(1)
  }

  func cancelEditor() {
    // Cancel discards (nothing was edited); never tap Done/Save here.
    if tap(app.buttons["Cancel"], timeout: 5) { sleep(1); return }
    miss("editor-cancel")
  }

  // MARK: - stops

  func stop01Library() {
    guard goTab("Library", expect: app.descendants(matching: .any)["library-grid"]) else {
      miss("01-library"); return
    }
    sleep(2)
    shot("pair-01-library")
  }

  func stop02FilterPills() {
    // Filter affordance: menu button, pills row, or toolbar filter entry.
    let menu = app.descendants(matching: .any)["library-filter-menu"]
    if tap(menu, timeout: 5) {
      sleep(1)
      shot("pair-02-library-pills")
      app.tap()
      sleep(1)
      return
    }
    let pills = app.descendants(matching: .any)["library-filter-pills"]
    if pills.waitForExistence(timeout: 5) {
      shot("pair-02-library-pills")
    } else {
      miss("02-library-pills")
    }
  }

  func stop03PinchedGrid() {
    guard goTab("Library", expect: app.descendants(matching: .any)["library-grid"]) else {
      miss("03-grid-pinched"); return
    }
    let grid = app.collectionViews.firstMatch
    guard grid.waitForExistence(timeout: 10) else { miss("03-grid-pinched"); return }
    grid.pinch(withScale: 0.4, velocity: -1)
    sleep(2)
    shot("pair-03-grid-pinched")
    grid.pinch(withScale: 2.5, velocity: 1)
    sleep(2)
  }

  func stop04Viewer() {
    guard goTab("Library", expect: app.descendants(matching: .any)["library-grid"]) else {
      miss("04-viewer"); return
    }
    guard tap(app.collectionViews.cells.firstMatch, timeout: 30) else { miss("04-viewer"); return }
    guard app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10) else {
      miss("04-viewer"); return
    }
    sleep(1)
    shot("pair-04-viewer")
  }

  func stop05InfoPanel() {
    guard app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 5) else {
      miss("05-info-panel"); return
    }
    if tap(app.buttons["Info"], timeout: 10) {
      sleep(1)
      shot("pair-05-info-panel")
      _ = tap(app.buttons["Info"], timeout: 5)
      sleep(1)
    } else {
      // Fallback: swipe up opens the sheet on Photos-parity builds.
      app.swipeUp()
      sleep(1)
      if app.descendants(matching: .any)["viewer-info-panel"].waitForExistence(timeout: 5) {
        shot("pair-05-info-panel")
        app.swipeDown()
        sleep(1)
      } else {
        miss("05-info-panel")
      }
    }
  }

  func stop06EditorPhoto() {
    guard app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 5) else {
      miss("06-editor-photo"); return
    }
    var opened = false
    for label in ["Adjust", "Edit", "Tune"] {
      if tap(app.buttons[label], timeout: 3) { opened = true; break }
    }
    guard opened, app.descendants(matching: .any)["editor-chrome"].waitForExistence(timeout: 10) else {
      miss("06-editor-photo"); return
    }
    sleep(1)
    shot("pair-06-editor-photo")
  }

  func stop07EditorStyles() {
    guard app.descendants(matching: .any)["editor-chrome"].waitForExistence(timeout: 5) else {
      miss("07-editor-styles"); return
    }
    if tap(app.descendants(matching: .any)["editor-tab-styles"], timeout: 10) {
      sleep(1)
      shot("pair-07-editor-styles")
    } else {
      miss("07-editor-styles")
    }
  }

  func stop08EditorCrop() {
    guard app.descendants(matching: .any)["editor-chrome"].waitForExistence(timeout: 5) else {
      miss("08-editor-crop"); return
    }
    if tap(app.descendants(matching: .any)["editor-tab-crop"], timeout: 10) {
      sleep(1)
      shot("pair-08-editor-crop")
    } else {
      miss("08-editor-crop")
    }
    cancelEditor()
    closeViewer()
  }

  func stop09VideoViewer() {
    // Deterministic route: Collections › Videos utility is a videos-only grid,
    // so its first cell opens the viewer on a video — no timeline hunt.
    guard goTab("Collections", expect: app.descendants(matching: .any)["collections"]) else {
      miss("09-video-viewer"); return
    }
    // Media Types sits far below the fold and flings overshoot (center-screen
    // swipes land on the carousels and go nowhere — edge scroll). Sweep down
    // past it, then back up: the pill renders while on screen.
    var atVideos = false
    for _ in 0..<14 {
      if tapVideosPill() { atVideos = true; break }
      edgeScroll(up: true)
    }
    for _ in 0..<14 where !atVideos {
      if tapVideosPill() { atVideos = true; break }
      edgeScroll(up: false)
    }
    // The loop's last scroll has no trailing check — one final look where it landed.
    if !atVideos {
      if tapVideosPill(timeout: 3) { atVideos = true }
    }
    guard atVideos,
      app.descendants(matching: .any)["detail-grid"].waitForExistence(timeout: 10),
      tap(app.collectionViews.cells.firstMatch, timeout: 30),
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10)
    else {
      miss("09-video-viewer"); return
    }
    sleep(2)
    if app.descendants(matching: .any)["video-page"].exists
      || app.descendants(matching: .any)["video-scrubber"].exists
    {
      shot("pair-09-video-viewer")
    } else {
      miss("09-video-viewer")
    }
  }

  func stop10VideoEditor() {
    guard app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 5) else {
      miss("10-video-editor"); return
    }
    // Only meaningful on a video page — never mislabel a photo editor.
    guard app.descendants(matching: .any)["video-page"].exists
      || app.descendants(matching: .any)["video-scrubber"].exists
    else {
      miss("10-video-editor"); closeViewer(); return
    }
    var opened = false
    for label in ["Adjust", "Edit", "Tune"] {
      if tap(app.buttons[label], timeout: 3) { opened = true; break }
    }
    guard opened, app.descendants(matching: .any)["editor-chrome"].waitForExistence(timeout: 10) else {
      miss("10-video-editor"); return
    }
    sleep(1)
    shot("pair-10-video-editor")
    cancelEditor()
    closeViewer()
  }

  func stop11Account() {
    guard goTab("Search", expect: app.descendants(matching: .any)["search-view"]) else {
      miss("11-account"); return
    }
    guard tap(app.buttons["account-button"], timeout: 10) else { miss("11-account"); return }
    guard app.descendants(matching: .any)["account-sheet"].waitForExistence(timeout: 10) else {
      miss("11-account"); return
    }
    sleep(1)
    shot("pair-11-account")
  }

  func stop12Settings() {
    // Settings lives behind the account sheet (P1–P4 merge); shooter tolerates
    // either a pushed settings list or a settings section in the sheet.
    if tap(app.descendants(matching: .any)["account-settings"], timeout: 5)
      || tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Settings'")).firstMatch, timeout: 5)
    {
      sleep(1)
      shot("pair-12-settings-list")
      if tap(app.navigationBars.buttons.firstMatch, timeout: 5) { sleep(1) }
    } else if app.descendants(matching: .any)["account-sheet"].waitForExistence(timeout: 3) {
      shot("pair-12-settings-list")
    } else {
      miss("12-settings-list")
    }
    // Leave the sheet however it stands: Done dismisses, back pops.
    if !tap(app.buttons["Done"], timeout: 3) {
      _ = tap(app.navigationBars.buttons.firstMatch, timeout: 3)
    }
    sleep(1)
  }

  func stop13Search() {
    guard goTab("Search", expect: app.descendants(matching: .any)["search-view"]) else {
      miss("13-search"); return
    }
    sleep(2)
    shot("pair-13-search")
  }

  func stop14Collections() {
    guard goTab("Collections", expect: app.descendants(matching: .any)["collections"]) else {
      miss("14-collections"); return
    }
    sleep(2)
    shot("pair-14-collections")
  }

  func stop15LongPress() {
    guard goTab("Library", expect: app.descendants(matching: .any)["library-grid"]) else {
      miss("15-longpress"); return
    }
    let cell = app.collectionViews.cells.firstMatch
    guard cell.waitForExistence(timeout: 30) else { miss("15-longpress"); return }
    cell.press(forDuration: 0.8)
    sleep(1)
    // Custom preview+actions view (grid-context-menu), not a system menu/sheet.
    if app.descendants(matching: .any)["grid-context-menu"].waitForExistence(timeout: 5) {
      shot("pair-15-longpress")
    } else {
      miss("15-longpress")
    }
    // Dismiss without actioning anything: tap clear of the menu/sheet.
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    sleep(1)
  }
}
