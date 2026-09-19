import XCTest

/// WP-T red-first tests for V4 (P0 info panel) and V5 (swipe-to-dismiss).
/// The full §2 panel order/grouping is asserted top to bottom; identifiers
/// are owned by WP-I.
final class InfoPanelUITests: XCTestCase {
  func test_infoPanel_allSectionsPresent() throws {
    let app = Parity.launch()
    Parity.openInfoPanel(app)
    // V4/WP-I: PLAN §2 order — caption, date/adjust card, device card,
    // capture/EXIF card, map card, keywords, provenance. Today the sheet
    // shows only date + raw filename.
    for id in [
      "info-caption-field",
      "info-date-card",
      "info-date-adjust",
      "info-device-card",
      "info-capture-card",
      "info-exif-strip",
      "info-map-card",
      "info-map-adjust",
      "info-keywords-field",
      "info-provenance-row",
    ] {
      Parity.require(id, in: app, gap: "V4", owner: "WP-I")
    }
    // The viewer's bottom toolbar stays visible over the sheet (§2 item 10).
    Parity.require("viewer-toolbar-share", in: app, gap: "V4", owner: "WP-I")
  }

  /// LP4/Track-B (pair 05): with camera EXIF synced, the strip shows real
  /// exposure cells in Photos order (ISO · focal · aperture · shutter)
  /// instead of "No exposure details".
  func test_infoPanel_exifStripShowsRealExposureData() throws {
    let app = Parity.launch()
    Parity.openInfoPanel(app)
    let strip = Parity.require("info-exif-strip", in: app, gap: "LP4", owner: "Track-B")
    for cell in ["ISO 80", "24 mm", "ƒ1.78", "1/95 s"] {
      XCTAssertTrue(
        strip.staticTexts[cell].waitForExistence(timeout: 10),
        "LP4: EXIF strip should show real cell \(cell)")
    }
    XCTAssertFalse(
      app.staticTexts["No exposure details"].exists,
      "LP4: real EXIF must replace the \"No exposure details\" fallback")
  }

  func test_infoPanel_dismissesBySwipeDown() throws {
    let app = Parity.launch()
    Parity.openInfoPanel(app)
    // V5/WP-V: a downward drag from the sheet's grabber dismisses without the
    // toolbar button. (Grabber-drag technique matches the known-good helper
    // in ViewerUITests; the grabber id itself is owned by WP-I.)
    let grabber = Parity.require(
      "info-sheet-grabber", in: app, gap: "V5", owner: "WP-I")
    sleep(1) // let the slide-in transition finish: mid-animation gestures drop
    let start = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
    XCTAssertFalse(
      app.descendants(matching: .any)["viewer-info-panel"].waitForExistence(timeout: 5),
      "V5: grabber swipe-down should dismiss the info sheet")
    XCTAssertTrue(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10),
      "V5: dismissing the sheet should stay in the viewer")
  }
}
