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
    let firstCell = app.collectionViews.cells.firstMatch
    XCTAssertTrue(firstCell.waitForExistence(timeout: 30))
    firstCell.press(forDuration: 0.8)
    Parity.require("grid-context-menu", in: app, gap: "G4", owner: "WP-M")
    for action in [
      "grid-context-duplicate", "grid-context-share", "grid-context-favorite",
      "grid-context-addto", "grid-context-delete",
    ] {
      Parity.require(action, in: app, gap: "G4", owner: "WP-M")
    }
    XCTAssertFalse(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 3),
      "G4: a grid long-press must present the context menu, not open the viewer")
  }

  func test_viewerLongPress_opensContextMenu() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    // V6/WP-M: long-press in the viewer is a documented no-op today.
    let pager = app.descendants(matching: .any)["viewer-pager"]
    XCTAssertTrue(pager.waitForExistence(timeout: 10))
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
