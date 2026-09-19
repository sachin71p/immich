import XCTest

/// WP-T red-first tests for F2 (P0) and V1–V3, V7, V8, plus the §4 gesture
/// regressions that already work today (swipe left/right paging, swipe up →
/// info, swipe down → exit). New files only: the pre-existing
/// `ViewerUITests.swift` is untouched, so these live here. Surface
/// identifiers are owned by WP-V (WP-R for F2's first frame).
final class ParityViewerUITests: XCTestCase {
  func test_videoViewer_firstFrameNotBlack() throws {
    let app = Parity.launch()
    Parity.openVideoViewer(app)
    // F2/WP-R: player canvas clears the §2.1 threshold within 500 ms of play.
    // Today playback renders black with a frozen scrubber — red on base.
    ParityCanvas.waitForContent(
      elementId: "video-player-canvas", in: app, within: 0.5,
      gap: "F2", owner: "WP-R")
  }

  func test_viewerTitle_showsPlaceWeekdayAndPeopleBadge() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    // V1/WP-V: place name + weekday + time title; people badge when faces
    // are present. Today the title is date + time only.
    Parity.require("viewer-title-place", in: app, gap: "V1", owner: "WP-V")
    Parity.require("viewer-title-weekday", in: app, gap: "V1", owner: "WP-V")
  }

  func test_viewer_showsLiveBadgeAndEnhanceAffordance() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    // V2/WP-V: enhance control in the top bar (first fixture asset is a still).
    Parity.require("viewer-enhance", in: app, gap: "V2", owner: "WP-V")
    // V2/WP-V: LIVE pill is live-asset-only (Photos parity — a badge on every
    // still would be noise), so page to the seeded live photo to assert it.
    var foundLive = false
    for _ in 0..<15 {
      if app.descendants(matching: .any)["livephoto-page"].waitForExistence(timeout: 2) {
        foundLive = true
        break
      }
      app.swipeLeft()
    }
    XCTAssertTrue(
      foundLive,
      "V2/WP-V: the fixture seeds a live photo — paging should reach it")
    Parity.require("viewer-live-badge", in: app, gap: "V2", owner: "WP-V")
  }

  func test_viewerToolbar_threeGroups() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    // V3/WP-V: three distinct groups — [share] · [heart/info/settings] ·
    // [delete] — not one 5-icon pill.
    Parity.require("viewer-toolbar-share", in: app, gap: "V3", owner: "WP-V")
    Parity.require("viewer-toolbar-actions", in: app, gap: "V3", owner: "WP-V")
    Parity.require("viewer-toolbar-delete", in: app, gap: "V3", owner: "WP-V")
  }

  func test_videoScrubber_isFilmstripWithCCAndMute() throws {
    let app = Parity.launch()
    Parity.openVideoViewer(app)
    // V7/WP-V: frame-thumbnail scrubber plus CC and mute — not a plain bar.
    Parity.require("video-scrubber-filmstrip", in: app, gap: "V7", owner: "WP-V")
    Parity.require("video-scrubber-cc", in: app, gap: "V7", owner: "WP-V")
    Parity.require("video-scrubber-mute", in: app, gap: "V7", owner: "WP-V")
  }

  func test_viewerPinchIn_dismissesToGrid() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    // V8/WP-V: native pinch API (TEST-PLAN §4 — the Device Hub mirror cannot
    // synthesise pinches). A pinch-in must dismiss back to the grid, not
    // leave a floating shrunk rect.
    let pager = app.descendants(matching: .any)["viewer-pager"]
    XCTAssertTrue(pager.waitForExistence(timeout: 10))
    pager.pinch(withScale: 0.5, velocity: -1)
    // The grid stays mounted behind the viewer, so its presence alone proves
    // nothing — the pager itself must be gone (same absence pattern as the
    // swipe-down regression in ViewerUITests).
    XCTAssertFalse(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 3),
      "V8/WP-V: pinch-in on an open photo should dismiss the viewer, not shrink it")
    XCTAssertTrue(
      app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 10),
      "V8/WP-V: pinch-in on an open photo should dismiss back to the grid")
  }

  // MARK: - Gesture regressions (work today — must survive WP-V)

  func test_viewerSwipeLeftRight_pagesPhotos() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    let index = app.descendants(matching: .any)["viewer-page-index"]
    XCTAssertTrue(index.waitForExistence(timeout: 10))
    let before = index.label
    app.swipeLeft()
    XCTAssertTrue(index.waitForExistence(timeout: 10))
    XCTAssertNotEqual(
      index.label, before,
      "regression: swipe left in the viewer must page to the next photo")
  }

  func test_viewerSwipeUp_opensInfoSheet() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    app.swipeUp()
    XCTAssertTrue(
      app.descendants(matching: .any)["viewer-info-panel"].waitForExistence(timeout: 10),
      "regression: swipe up in the viewer must open the info sheet")
  }

  func test_viewerSwipeDown_exitsViewer() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    app.swipeDown()
    XCTAssertTrue(
      app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 10),
      "regression: swipe down on the photo must exit the viewer")
  }
}
