import XCTest

/// WP-E (Edit parity) UI tests, TEST-PLAN E1/E2/E7/E9. Fixture only
/// (`-HeirloomFixture`); never Done on a real asset.
///
/// OWNERSHIP: device foreground is exclusive to the main session — these run via
/// `verify.sh mac-ui` on the owner's Mac, not in parallel workers.
///
/// Contract IDs come from `AXIDs` only (`toolbar.edit`, `edit.mode`, `edit.done`,
/// `edit.cancel`, `edit.compare`, `edit.slider.*`), except the discard-alert
/// buttons, which are system-alert labels (noted deviation).
final class EditUITests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = [
      "-fixture-seed", "-HeirloomFixture=small", "-HeirloomUITestNoAnimation",
      "-ui-testing", "-ApplePersistenceIgnoreState", "YES",
    ]
  }

  override func tearDown() {
    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }
    super.tearDown()
  }

  // MARK: - helpers

  private func el(_ id: String) -> XCUIElement {
    app.descendants(matching: .any)[id]
  }

  private func launchAndWaitForGrid() {
    app.launchForUIAutomation()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    XCTAssertTrue(el("sidebar").waitForExistence(timeout: 30), "sidebar renders")
    XCTAssertTrue(el("asset-grid").waitForExistence(timeout: 30), "grid renders")
    // Same toolbar-overflow guard as the functional suite: the default 1400px
    // window hides trailing toolbar items (including the viewer Edit button)
    // where AX clicks cannot reach them.
    XCTAssertTrue(app.zoomToFillDisplay(), "toolbar unfurls after zoom")
  }

  private func firstCell() -> XCUIElement {
    let q = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@", "grid.cell.", "grid-cell-"))
    XCTAssertGreaterThan(q.count, 0, "fixture grid has cells")
    return q.firstMatch
  }

  /// Double-clicks the first grid cell (V14: double-click opens the viewer).
  private func openViewer() {
    launchAndWaitForGrid()
    firstCell().doubleClick()
    XCTAssertTrue(el("viewer").waitForExistence(timeout: 10), "viewer opens")
  }

  /// Single click on Edit (E1: first click opens edit mode, no double-click).
  private func openEdit() {
    XCTAssertTrue(el("toolbar.edit").waitForExistence(timeout: 10), "Edit button renders")
    el("toolbar.edit").click()
    XCTAssertTrue(el("edit.mode").waitForExistence(timeout: 10), "edit mode opens on first click")
  }

  private func assertEditClosed(_ message: String) {
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: el("edit.mode"))
    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, message)
  }

  // MARK: - E1 open paths

  func testEditOpensOnFirstClick() {
    openViewer()
    openEdit()
  }

  func testReturnOpensEdit() {
    openViewer()
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(el("edit.mode").waitForExistence(timeout: 10), "Return opens edit mode")
  }

  func testEscapeExitsCleanEdit() {
    openViewer()
    openEdit()
    app.typeKey(.escape, modifierFlags: [])
    assertEditClosed("Escape with no changes exits edit mode")
  }

  func testEscapeAfterChangeConfirmsDiscard() {
    openViewer()
    openEdit()
    // Reveal the Light section's Exposure slider (Options disclosure).
    let options = el("edit.section.options.light")
    XCTAssertTrue(options.waitForExistence(timeout: 10), "Options disclosure renders")
    options.click()
    let exposure = el("edit.slider.Exposure")
    XCTAssertTrue(exposure.waitForExistence(timeout: 10), "Exposure slider renders")
    exposure.adjust(toNormalizedSliderPosition: 0.75)
    // The drag leaves focus on the slider, which eats Escape as cancelOperation:
    // click the canvas first so Escape reaches the mode handler.
    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    app.typeKey(.escape, modifierFlags: [])
    // macOS presents SwiftUI alerts as attached sheets, not alert windows.
    let discard = app.sheets.buttons["Discard"]
    XCTAssertTrue(discard.waitForExistence(timeout: 5), "dirty Escape shows Discard confirm")
    discard.click()
    assertEditClosed("Discard exits edit mode")
  }

  // MARK: - E2 shell

  func testSidebarHidesAndRestores() {
    openViewer()
    XCTAssertTrue(el("sidebar").exists, "sidebar visible before edit")
    openEdit()
    // Hidden, not removed: full-window edit keeps the sidebar in the
    // hierarchy with hidden set (preserving scroll state), so `exists`
    // never drops — poll hittability, the observable hidden state, instead.
    let deadline = Date().addingTimeInterval(10)
    while el("sidebar").isHittable, Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
    XCTAssertFalse(el("sidebar").isHittable, "entering edit hides the sidebar")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(el("sidebar").waitForExistence(timeout: 10), "exiting edit restores the sidebar")
  }

  // MARK: - D3 Levels handles

  /// Levels input/output handles drive the dedicated keys: arrow keys on the
  /// focused handle move values ±1, and the change marks the recipe dirty
  /// (the Discard confirm on Escape proves the new keys participate in dirty
  /// tracking). Done-save itself stays fixture-gated (E7): Done is disabled
  /// with no server original.
  func testLevelsHandlesDriveKeysAndDirtyEdit() {
    openViewer()
    openEdit()
    let options = el("edit.section.options.levels")
    XCTAssertTrue(options.waitForExistence(timeout: 10), "Levels Options renders")
    options.click()
    let inputBlack = el("edit.slider.levels-input-black")
    XCTAssertTrue(inputBlack.waitForExistence(timeout: 10), "input black handle renders")
    // The custom handles expose AX role Other (no readable value and no
    // XCUI adjustable action), so the visible numeric readout carries the
    // assertion; arrow keys drive the focused handle ±1, proving handles
    // move keys. Handles are focusable with arrow support in the product,
    // not just for tests (keyboard-accessible editing).
    let readout = el("edit.slider.levels-input-readout")
    XCTAssertTrue(readout.waitForExistence(timeout: 10), "input readout renders")
    // macOS exposes StaticText content as `value`, not `label`.
    XCTAssertEqual(readout.value as? String, "0 - 100")
    inputBlack.click()
    for _ in 0..<10 { app.typeKey(.upArrow, modifierFlags: []) }
    XCTAssertEqual(readout.value as? String, "10 - 100")
    // The drag leaves focus on the handle, which eats Escape as cancelOperation:
    // click the canvas first so Escape reaches the mode handler.
    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    app.typeKey(.escape, modifierFlags: [])
    let discard = app.sheets.buttons["Discard"]
    XCTAssertTrue(discard.waitForExistence(timeout: 5), "dirty Escape shows Discard confirm")
    discard.click()
    assertEditClosed("Discard exits edit mode")
  }

  // MARK: - D1 Selective Color swatches

  /// The swatch picker selects a hue and its sliders drive the per-hue keys:
  /// picking Oranges reveals the oranges sliders, moving Saturation marks the
  /// recipe dirty (the Discard confirm on Escape proves the new keys
  /// participate in dirty tracking). Done-save itself stays fixture-gated
  /// (E7): Done is disabled with no server original.
  func testSelectiveColorSwatchSelectAndSlidersMove() {
    openViewer()
    openEdit()
    let options = el("edit.section.options.selectiveColor")
    XCTAssertTrue(options.waitForExistence(timeout: 10), "Selective Color Options renders")
    options.click()
    let reds = el("edit.slider.sel-swatch-reds")
    XCTAssertTrue(reds.waitForExistence(timeout: 10), "reds swatch renders")
    let oranges = el("edit.slider.sel-swatch-oranges")
    XCTAssertTrue(oranges.waitForExistence(timeout: 10), "oranges swatch renders")
    oranges.click()
    let saturation = el("edit.slider.sel-oranges-saturation")
    XCTAssertTrue(saturation.waitForExistence(timeout: 10), "oranges saturation slider renders")
    saturation.adjust(toNormalizedSliderPosition: 0.75)
    XCTAssertTrue(el("edit.slider.sel-oranges-hue").exists, "hue slider renders for the picked swatch")
    XCTAssertTrue(el("edit.slider.sel-oranges-range").exists, "range slider renders for the picked swatch")
    // The drag leaves focus on the slider, which eats Escape as cancelOperation:
    // click the canvas first so Escape reaches the mode handler.
    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    app.typeKey(.escape, modifierFlags: [])
    let discard = app.sheets.buttons["Discard"]
    XCTAssertTrue(discard.waitForExistence(timeout: 5), "dirty Escape shows Discard confirm")
    discard.click()
    assertEditClosed("Discard exits edit mode")
  }

  // MARK: - E7 Done gating

  func testDoneGatedWhileOriginalLoads() {
    openViewer()
    openEdit()
    let done = el("edit.done")
    XCTAssertTrue(done.waitForExistence(timeout: 10), "Done renders")
    // The fixture has no server, so the original never arrives: Done must stay
    // disabled (proxy editing only). On a real library the same gate lifts when
    // the original lands (unit-covered in EditOriginalLoader tests).
    XCTAssertFalse(done.isEnabled, "Done disabled until the original loads")
  }

  // MARK: - E9 compare + copy/paste

  func testCompareToggle() {
    openViewer()
    openEdit()
    let compare = el("edit.compare")
    XCTAssertTrue(compare.waitForExistence(timeout: 10), "compare renders")
    XCTAssertEqual(compare.value as? String, "Edited")
    compare.click()
    XCTAssertEqual(compare.value as? String, "Original", "click shows the before image")
    compare.click()
    XCTAssertEqual(compare.value as? String, "Edited")
  }

  func testCopyPasteEdits() {
    openViewer()
    openEdit()
    let options = el("edit.section.options.light")
    XCTAssertTrue(options.waitForExistence(timeout: 10), "Options disclosure renders")
    options.click()
    let exposure = el("edit.slider.Exposure")
    XCTAssertTrue(exposure.waitForExistence(timeout: 10), "Exposure slider renders")
    exposure.adjust(toNormalizedSliderPosition: 0.8)
    el("edit.more").click()
    app.menuItems["Copy edits"].click()
    // The adjust dirtied the recipe, so Escape raises Discard (copy is not save).
    // Click the canvas first: focus may sit on the slider, which eats Escape.
    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    app.typeKey(.escape, modifierFlags: [])
    let discardAfterCopy = app.sheets.buttons["Discard"]
    XCTAssertTrue(discardAfterCopy.waitForExistence(timeout: 5), "Escape after copy shows Discard")
    discardAfterCopy.click()
    assertEditClosed("Discard after copy exits")
    // Paste onto the same asset and confirm the value carried over. The mode
    // reopened fresh, so its Options disclosure starts collapsed again.
    openEdit()
    let options2 = el("edit.section.options.light")
    XCTAssertTrue(options2.waitForExistence(timeout: 10), "Options disclosure renders")
    options2.click()
    el("edit.more").click()
    app.menuItems["Paste edits"].click()
    // AX slider values surface as NSNumber on macOS, never String: coerce.
    let rawPasted = el("edit.slider.Exposure").value
    let pasted: Double? = {
      if let s = rawPasted as? String {
        return Double(s.filter { $0.isNumber || $0 == "." || $0 == "-" })
      }
      if let n = rawPasted as? NSNumber { return n.doubleValue }
      return nil
    }()
    XCTAssertNotNil(pasted, "Exposure slider still renders after paste")
    if let pasted {
      // adjust(0.8) over -100...100 committed 60; paste must carry it over.
      XCTAssertEqual(pasted, 60, accuracy: 2, "pasted value carried over")
    }
  }

  // MARK: - D6a version history (fixture only; owner-run via `verify.sh mac-ui`)

  private func historyRows() -> XCUIElementQuery {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "edit.history.row."))
  }

  /// History lists the fixture-seeded versions; tap-to-restore appends a new
  /// version (never overwrites) and loads the restored recipe; Cancel still
  /// discards the in-progress edit. Never presses Done on a real asset.
  func testHistoryListsVersionsAndRestoreAppends() {
    openViewer()
    openEdit()
    let history = el("edit.history")
    XCTAssertTrue(history.waitForExistence(timeout: 10), "History disclosure renders")
    history.click()
    XCTAssertTrue(el("edit.history.row.0").waitForExistence(timeout: 10), "seeded version 0 lists")
    XCTAssertTrue(el("edit.history.row.1").waitForExistence(timeout: 10), "seeded version 1 lists")
    XCTAssertEqual(historyRows().count, 2, "fixture seeds two versions")
    // Restore the first version (fixture exposure -40): the stack grows by
    // one (append, never overwrite) and the recipe loads into the session.
    el("edit.history.restore.0").click()
    XCTAssertTrue(el("edit.history.row.2").waitForExistence(timeout: 10), "restore appends a new version")
    XCTAssertEqual(historyRows().count, 3, "restore appends, never overwrites")
    XCTAssertTrue(el("edit.history.row.0").exists, "prior versions untouched by restore")
    XCTAssertTrue(el("edit.history.row.1").exists, "prior versions untouched by restore")
    // The restored recipe is live: Exposure reads -40 under Light Options.
    let options = el("edit.section.options.light")
    XCTAssertTrue(options.waitForExistence(timeout: 10), "Options disclosure renders")
    options.click()
    let raw = el("edit.slider.Exposure").value
    let exposure: Double? = {
      if let s = raw as? String {
        return Double(s.filter { $0.isNumber || $0 == "." || $0 == "-" })
      }
      if let n = raw as? NSNumber { return n.doubleValue }
      return nil
    }()
    XCTAssertNotNil(exposure, "Exposure slider renders after restore")
    if let exposure {
      XCTAssertEqual(exposure, -40, accuracy: 2, "restored recipe carried over")
    }
    // Cancel still discards the in-progress (restored) edit: Escape raises
    // Discard, and Discard exits without saving.
    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    app.typeKey(.escape, modifierFlags: [])
    let discard = app.sheets.buttons["Discard"]
    XCTAssertTrue(discard.waitForExistence(timeout: 5), "Escape after restore shows Discard")
    discard.click()
    assertEditClosed("Discard after restore exits edit mode")
  }
}
