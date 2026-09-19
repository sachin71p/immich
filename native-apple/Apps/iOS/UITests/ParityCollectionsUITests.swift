import XCTest

/// WP-T red-first test for P7 (Collections additions). Identifiers owned by
/// WP-P. Heirloom's extra sections (Places, People, Shared Albums, Shared
/// Libraries, Recent Days) are deliberate extras — asserted present so WP-P
/// cannot drop them while adding Trips and Wallpaper Suggestions.
final class ParityCollectionsUITests: XCTestCase {
  func test_collections_hasTripsAndWallpaperSuggestions() throws {
    let app = Parity.launch()
    app.tabBars.buttons["Collections"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["collections"].waitForExistence(timeout: 30),
      "collections should render from the fixture DB")
    // P7/WP-P: new chips alongside the existing sections.
    Parity.require("collections-trips", in: app, gap: "P7", owner: "WP-P")
    Parity.require("collections-wallpaper-suggestions", in: app, gap: "P7", owner: "WP-P")
    // Deliberate extras that must be kept (PLAN §1 "Collections is already
    // close" + §6).
    for section in [
      "collections-section-places",
      "collections-section-people",
      "collections-section-sharedAlbums",
      "collections-section-spaces",
      "collections-section-recentDays",
    ] {
      Parity.require(section, in: app, gap: "P7", owner: "WP-P")
    }
  }
}
