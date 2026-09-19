import XCTest

/// WP-T red-first tests for G4 (P0 grid long-press), V6 (viewer long-press),
/// and C5 (select-mode toolbar). Menu item identifiers are owned by WP-M.
///
/// §0.5: the Delete action is asserted *present* but never tapped — automation
/// must keep destructive controls away from automated paths.
final class ContextMenuUITests: XCTestCase {
  func test_grid_longPress_showsContextMenuNotViewer() throws {
    let app = Parity.launch()
    // G4/WP-M: long-press presents preview + the Photos action set. Today a
    // long-press opens the photo instead — red on base.
    //
    // Feasible set (WP-M): Duplicate is NOT required — `AssetMutations`
    // exposes no duplicate operation and the server has no asset-duplicate
    // endpoint, so a Duplicate button would be dead (same precedent as
    // `SelectMoreMenu`, which omits Duplicate/Adjust-Date). Copy and Hide
    // hold the strictness instead.
    let firstCell = app.collectionViews.cells.firstMatch
    XCTAssertTrue(firstCell.waitForExistence(timeout: 30))
    firstCell.press(forDuration: 0.8)
    Parity.require("grid-context-menu", in: app, gap: "G4", owner: "WP-M")
    for action in [
      "grid-context-copy", "grid-context-hide", "grid-context-share",
      "grid-context-favorite", "grid-context-addto", "grid-context-delete",
    ] {
      Parity.require(action, in: app, gap: "G4", owner: "WP-M")
    }
    XCTAssertFalse(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 3),
      "G4: a grid long-press must present the context menu, not open the viewer")
  }

  func test_grid_longPress_showsIconHeaderRow() throws {
    // LP8/Track C: Photos' grid long-press menu carries an icon header row
    // (Copy/Hide/Share/Favorite shortcuts above the list,
    // photos/05-grid-longpress-menu.png). Duplicate stays OUT (no backend);
    // Delete stays list-only behind its confirmation, never auto-tapped.
    let app = Parity.launch()
    let firstCell = app.collectionViews.cells.firstMatch
    XCTAssertTrue(firstCell.waitForExistence(timeout: 30))
    firstCell.press(forDuration: 0.8)
    Parity.require("grid-context-menu", in: app, gap: "LP8", owner: "Track C")
    Parity.require("grid-context-header", in: app, gap: "LP8", owner: "Track C")
    for header in [
      "grid-context-header-copy", "grid-context-header-hide",
      "grid-context-header-share", "grid-context-header-favorite",
    ] {
      Parity.require(header, in: app, gap: "LP8", owner: "Track C")
    }
    XCTAssertFalse(
      app.descendants(matching: .any)["grid-context-header-duplicate"]
        .waitForExistence(timeout: 3),
      "LP8: Duplicate must stay out of the menu (no duplicate backend)")
  }

  func test_viewerLongPress_opensContextMenu() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    // V6/WP-M: long-press in the viewer is a documented no-op today.
    let pager = app.descendants(matching: .any)["viewer-pager"]
    XCTAssertTrue(pager.waitForExistence(timeout: 10))
    // Sync on the photo itself, not just the pager: pressing while the page
    // still shows its loading spinner races image decode (no image view, no
    // gesture) and proves nothing about the menu.
    let loading = app.descendants(matching: .any)["viewer-loading"]
    if loading.waitForExistence(timeout: 5) {
      let gone = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == false"), object: loading)
      _ = XCTWaiter.wait(for: [gone], timeout: 15)
    }
    pager.press(forDuration: 0.8)
    Parity.require("viewer-context-menu", in: app, gap: "V6", owner: "WP-M")
  }

  func test_selectMode_toolbarOffersAddToAndFavorite() throws {
    let app = Parity.launch()
    // C5/WP-M: select-mode toolbar offers Add To and Favorite in addition to
    // Share/Delete. (Select entry path matches the A3 smoke test.)
    let select = app.buttons["Select"]
    XCTAssertTrue(
      select.waitForExistence(timeout: 10),
      "C5: expected a Select control on the Library grid")
    select.tap()
    app.collectionViews.cells.firstMatch.tap()
    // Bulk actions live behind the top "…" menu (A3 smoke path).
    let moreMenu = app.descendants(matching: .any)["select-more-menu"]
    XCTAssertTrue(
      moreMenu.waitForExistence(timeout: 10),
      "C5: expected the select-mode \"…\" menu after selecting a cell")
    moreMenu.tap()
    Parity.require("select-action-add-to-album", in: app, gap: "C5", owner: "WP-M")
    Parity.require("select-action-favorite", in: app, gap: "C5", owner: "WP-M")
  }
}
