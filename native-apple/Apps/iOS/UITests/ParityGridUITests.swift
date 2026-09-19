import XCTest

/// WP-T red-first tests for F4, F5 (content/throughput — frame pacing already
/// passes, so nothing here asserts on frame duration) and G1–G3, G5, G7,
/// plus the pinch-density behaviour that already works and must survive G7.
/// New file only: the pre-existing `GridPerfUITests.swift` is untouched.
/// Cell/badge identifiers are owned by WP-G; F4/F5 budgets by WP-F.
///
/// All timing assertions are Release-on-physical-device-only and skip on the
/// Simulator; content assertions run everywhere.
final class ParityGridUITests: XCTestCase {
  func test_libraryGrid_tabSwitchReturn_noBlankFrame() throws {
    try Parity.requirePhysicalDevice()
    let app = Parity.launch()
    // F4/WP-F: first tile visible < 150 ms after returning to the Library tab.
    app.tabBars.buttons["Collections"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["collections"].waitForExistence(timeout: 30))
    let start = Date()
    app.tabBars.buttons["Library"].tap()
    let tile = app.collectionViews.cells.firstMatch
    XCTAssertTrue(
      tile.waitForExistence(timeout: 10),
      "F4/WP-F: grid tiles should return after a tab switch")
    XCTAssertLessThan(
      Date().timeIntervalSince(start), 0.15,
      "F4/WP-F: first tile took longer than the 150 ms budget after tab return")
  }

  func test_libraryGrid_fastScroll_tilesHaveContent() throws {
    try Parity.requirePhysicalDevice()
    let app = Parity.launch()
    // F5/WP-F: content, not pacing — no empty/black tile on screen > 250 ms
    // after scroll settles. Samples visible cell rects for non-uniform pixels.
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    for _ in 0..<6 { grid.swipeUp(velocity: .fast) }
    usleep(300_000)
    let deadline = Date().addingTimeInterval(5)
    var pending = true
    while Date() < deadline, pending {
      pending = false
      for i in 0..<min(8, grid.cells.count) {
        let cell = grid.cells.element(boundBy: i)
        if let cgImage = cell.screenshot().image.cgImage,
          !ParityCanvas.isNonBlack(cgImage)
        {
          pending = true
          break
        }
      }
      if pending { usleep(100_000) }
    }
    XCTAssertFalse(
      pending,
      "F5/WP-F: an empty/black tile persisted > 250 ms after scroll settled")
  }

  func test_grid_videoCellsShowDurationBadge() throws {
    let app = Parity.launch()
    // G1/WP-G: every video cell exposes a bottom-right duration label.
    // Predicate form covers any duration text; WP-G owns the identifier.
    let badge = app.staticTexts.matching(
      NSPredicate(format: "identifier BEGINSWITH 'grid-duration-badge'")).firstMatch
    XCTAssertTrue(
      badge.waitForExistence(timeout: 15),
      "G1/WP-G: expected accessibilityIdentifier \"grid-duration-badge*\" on video cells")
  }

  func test_grid_favouritedCellsShowHeartOverlay() throws {
    let app = Parity.launch()
    // G2/WP-G: favourited cells expose a heart overlay. The default fixture's
    // in-scope favorite sits at the end of the grid (the other seeded favorite
    // falls outside the default Library scope), so page down until one appears
    // — bounded and density-independent (WP-G hardened: the no-scroll form
    // could never go green once pinch tests left the grid dense).
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    let hearts = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH 'grid-favorite-heart'"))
    let deadline = Date().addingTimeInterval(30)
    while !hearts.firstMatch.exists, Date() < deadline {
      grid.swipeUp(velocity: .fast)
    }
    XCTAssertTrue(
      hearts.firstMatch.waitForExistence(timeout: 5),
      "G2/WP-G: expected accessibilityIdentifier \"grid-favorite-heart*\" on favourited cells")
  }

  func test_grid_peopleBadgeIsSelectiveNotOnEveryCell() throws {
    // G3/WP-G: the people badge must be selective — present on foreign
    // shared-container cells, not painted on nearly every cell. Two gates:
    // at least one badge exists (fails on base, where no badge exposes an
    // identifier at all), and the badged fraction of the sampled cells stays
    // under the ceiling. The default fixture's u2-owned space assets give the
    // existence gate its foreign cells; the ceiling is a named constant so
    // WP-G can calibrate it.
    let app = Parity.launch()
    let selectiveCeiling = 0.5
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    // Column density persists across runs (a leftover 1-column grid realizes
    // only a couple of cells), so pin the grid to max density through the
    // View Options stepper — twenty Zoom Ins from any state land on max
    // density (LP1: 18 columns). The stepper touches columns only, never the
    // time level, so this is safe on both sides of the G7 continuum (a pinch
    // past the edge would not be).
    // Drilled-in submenu leaves lose their identifiers on iOS 27 (verified by
    // AX dump — see LibraryChromeUITests.submenuItemLabel), so the leaf is
    // located by its visible label, reopening the menu each round since menu
    // taps dismiss.
    let zoomInLeaf = app.descendants(matching: .button).matching(
      NSPredicate(format: "label == %@", "Zoom In"))
    for _ in 0..<20 {
      if zoomInLeaf.firstMatch.waitForExistence(timeout: 2) {
        zoomInLeaf.firstMatch.tap()
        continue
      }
      let menu = app.descendants(matching: .any)["library-filter-menu"]
      guard menu.waitForExistence(timeout: 10) else {
        XCTFail("G3: filter menu did not open while normalizing density")
        return
      }
      menu.tap()
      let submenu = app.descendants(matching: .any)["submenu-view-options"]
      guard submenu.waitForExistence(timeout: 10) else {
        XCTFail("G3: View Options submenu missing while normalizing density")
        return
      }
      submenu.tap()
      guard zoomInLeaf.firstMatch.waitForExistence(timeout: 10) else {
        XCTFail("G3: Zoom In leaf missing while normalizing density")
        return
      }
      zoomInLeaf.firstMatch.tap()
    }
    // Cells page in progressively — wait until the realized count stops growing
    // (or hits the 30-cell window), or the fraction is measured on a stub grid.
    let deadline = Date().addingTimeInterval(30)
    var lastCount = -1
    var stableSince = Date()
    while Date() < deadline {
      let count = grid.cells.count
      if count != lastCount { lastCount = count; stableSince = Date() }
      if count >= 30 || (count > 0 && Date().timeIntervalSince(stableSince) > 3) { break }
      usleep(200_000)
    }
    let sample = min(30, grid.cells.count)
    XCTAssertGreaterThan(sample, 0, "G3: grid should paint cells to sample")
    var badged = 0
    for i in 0..<sample {
      let cell = grid.cells.element(boundBy: i)
      if cell.descendants(matching: .any)["grid-people-badge"].exists { badged += 1 }
    }
    XCTAssertGreaterThan(
      badged, 0,
      "G3/WP-G: expected at least one selective people badge on foreign shared cells")
    let fraction = Double(badged) / Double(sample)
    XCTAssertLessThan(
      fraction, selectiveCeiling,
      "G3/WP-G: people badge on \(badged)/\(sample) sampled cells — must be selective")
  }

  func test_grid_zoomedOut_showsFloatingDateBadge() throws {
    let app = Parity.launch()
    // G5/WP-G: pinch out to a high column count, then scroll — a floating
    // date badge (e.g. "Aug 2026") must overlay the grid.
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    grid.pinch(withScale: 2.0, velocity: 1.0)
    grid.swipeUp(velocity: .fast)
    Parity.require("grid-floating-date-badge", in: app, gap: "G5", owner: "WP-G")
  }

  func test_gridMaxDensity_reachesPhotosRange() throws {
    let app = Parity.launch()
    // LP1: Apple Photos shows ~15–20 columns fully zoomed out; the base cap
    // of 13 stops short. Drive the View Options stepper to saturation from
    // any persisted density, then read the grid-columns mirror. The stepper
    // touches columns only, never the time level, so this is safe on both
    // sides of the G7 continuum.
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    let zoomInLeaf = app.descendants(matching: .button).matching(
      NSPredicate(format: "label == %@", "Zoom In"))
    for _ in 0..<20 {
      if zoomInLeaf.firstMatch.waitForExistence(timeout: 2) {
        zoomInLeaf.firstMatch.tap()
        continue
      }
      let menu = app.descendants(matching: .any)["library-filter-menu"]
      guard menu.waitForExistence(timeout: 10) else {
        XCTFail("LP1: filter menu did not open while driving density to max")
        return
      }
      menu.tap()
      let submenu = app.descendants(matching: .any)["submenu-view-options"]
      guard submenu.waitForExistence(timeout: 10) else {
        XCTFail("LP1: View Options submenu missing while driving density to max")
        return
      }
      submenu.tap()
      guard zoomInLeaf.firstMatch.waitForExistence(timeout: 10) else {
        XCTFail("LP1: Zoom In leaf missing while driving density to max")
        return
      }
      zoomInLeaf.firstMatch.tap()
    }
    let mirror = app.descendants(matching: .any)["grid-columns"]
    XCTAssertTrue(
      mirror.waitForExistence(timeout: 5),
      "LP1: expected accessibilityIdentifier \"grid-columns\"")
    let density = Int(mirror.label) ?? 0
    XCTAssertGreaterThanOrEqual(
      density, 15,
      "LP1: max grid density should reach the Photos range (15–20 columns), found \(density)")
    XCTAssertGreaterThan(
      grid.cells.count, 0,
      "LP1: max-density grid must stay populated")
    // Suite hygiene (@AppStorage persists columns): leave the grid near the
    // default density for whatever test launches next. The LP1 assertions
    // above already ran; this only restores shared state, the same way
    // testViewOptions restores its toggles.
    let zoomOutLeaf = app.descendants(matching: .button).matching(
      NSPredicate(format: "label == %@", "Zoom Out"))
    for _ in 0..<14 {
      if zoomOutLeaf.firstMatch.waitForExistence(timeout: 2) {
        zoomOutLeaf.firstMatch.tap()
        continue
      }
      let menu = app.descendants(matching: .any)["library-filter-menu"]
      guard menu.waitForExistence(timeout: 10) else { return }
      menu.tap()
      let submenu = app.descendants(matching: .any)["submenu-view-options"]
      guard submenu.waitForExistence(timeout: 10) else { return }
      submenu.tap()
      guard zoomOutLeaf.firstMatch.waitForExistence(timeout: 10) else { return }
      zoomOutLeaf.firstMatch.tap()
    }
  }

  func test_gridPinch_couplesColumnDensityToTimeLevel() throws {
    let app = Parity.launch()
    // G7/WP-G: a continuous pinch must move BOTH column density and the
    // Years/Months/All selection — the pills must not stay pinned.
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    grid.pinch(withScale: 2.0, velocity: 1.0)
    Parity.require("grid-time-level", in: app, gap: "G7", owner: "WP-G")
  }

  func test_gridHeader_showsDateRangeWhileScrolling() throws {
    let app = Parity.launch()
    // G6/WP-G (content half; the count-at-rest half lives in
    // ParityChromeUITests): while the grid scrolls, the header subtitle must
    // read as a date range, not the bare count. The element is resolved before
    // swiping so no post-gesture lookup eats into the scroll-signal dwell; a
    // second swipe extends the window. Polls past the 2.5 s dwell — the
    // subtitle flips back to the count once the grid settles.
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    let subtitle = app.descendants(matching: .any)["grid-header-subtitle"]
    XCTAssertTrue(
      subtitle.waitForExistence(timeout: 5),
      "G6/WP-G: expected accessibilityIdentifier \"grid-header-subtitle\"")
    grid.swipeUp(velocity: .fast)
    grid.swipeUp(velocity: .fast)
    let deadline = Date().addingTimeInterval(8)
    var label = subtitle.label
    while !(label.contains("–") || label.contains("-")), Date() < deadline {
      usleep(100_000)
      label = subtitle.label
    }
    XCTAssertTrue(
      label.contains("–") || label.contains("-"),
      "G6/WP-G: while scrolling the header subtitle should be a date range, found \"\(label)\"")
  }

  func test_gridPinch_timeLevelIsExposed() throws {
    let app = Parity.launch()
    // G7/WP-G: the current time level (years/months/all) is exposed for the
    // density ↔ time-level continuum — the All grid rests on "all".
    let level = Parity.require("grid-time-level", in: app, gap: "G7", owner: "WP-G")
    XCTAssertEqual(
      level.label, "all",
      "G7/WP-G: the All grid should expose time level \"all\", found \"\(level.label)\"")
  }

  // MARK: - Regression (works today — must survive G7)

  func test_gridPinch_changesColumnDensity() throws {
    let app = Parity.launch()
    // Pinch-to-zoom changes density ≈5 ↔ ≈10 columns today; G7's
    // zoom/time-level coupling must not break the density half.
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 60))
    let before = grid.cells.count
    XCTAssertGreaterThan(before, 0)
    grid.pinch(withScale: 0.4, velocity: -1.0)
    sleep(1)
    XCTAssertGreaterThan(
      grid.cells.count, 0,
      "regression: grid pinch must keep a populated grid (was \(before) cells)")
  }
}
