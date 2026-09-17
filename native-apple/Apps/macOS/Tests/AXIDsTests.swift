import XCTest

/// WP-T T3: the identifier contract is well-formed — every parameterized
/// builder prefixes correctly and a spot-check of constants is unique.
final class AXIDsTests: XCTestCase {
  func testBuildersPrefixCorrectly() {
    XCTAssertEqual(AXIDs.gridCell("abc"), "grid.cell.abc")
    XCTAssertEqual(AXIDs.gridYearCard(2024), "grid.yearCard.2024")
    XCTAssertEqual(AXIDs.gridMonthCard(year: 2024, month: 6), "grid.monthCard.2024-06")
    XCTAssertEqual(AXIDs.viewerPage("abc"), "viewer.page.abc")
    XCTAssertEqual(AXIDs.editTab("Adjust"), "edit.tab.Adjust")
    XCTAssertEqual(AXIDs.collectionsShelf("Albums"), "collections.shelf.Albums")
    XCTAssertEqual(AXIDs.sidebarSpace("space-family"), "sidebar.space.space-family")
  }

  func testCoreConstantsAreUnique() {
    let ids = [
      AXIDs.sidebar, AXIDs.sidebarLibrary, AXIDs.sidebarCollections, AXIDs.sidebarSearch,
      AXIDs.toolbarSidebarToggle, AXIDs.toolbarScope, AXIDs.toolbarZoom, AXIDs.toolbarEdit,
      AXIDs.grid, AXIDs.viewer, AXIDs.viewerZoomSlider, AXIDs.viewerTitle,
      AXIDs.viewerSubtitle, AXIDs.viewerChevronPrev, AXIDs.viewerChevronNext,
      AXIDs.viewerVideoTime, AXIDs.inspector, AXIDs.editMode, AXIDs.editDone,
      AXIDs.editCancel, AXIDs.searchField, AXIDs.searchResults,
    ]
    XCTAssertEqual(Set(ids).count, ids.count, "no duplicate identifiers")
  }
}
