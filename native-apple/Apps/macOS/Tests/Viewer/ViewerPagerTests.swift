import Foundation
import XCTest

/// WP-V viewer unit tests (TEST-PLAN §2 V1–V15, V19; V12/V16–V18 live in the
/// Info-panel suite). Pure-logic rows run here via `verify.sh mac-unit`;
/// UI/snapshot rows are owned by the main session (see WP-V-REPORT).
final class ViewerPagerTests: XCTestCase {
  // MARK: - V5 pager math

  func testClampedIndexNeverWraps() {
    XCTAssertEqual(ViewerPagerMath.clampedIndex(-1, count: 5), 0)
    XCTAssertEqual(ViewerPagerMath.clampedIndex(5, count: 5), 4)
    XCTAssertEqual(ViewerPagerMath.clampedIndex(2, count: 5), 2)
  }

  func testPreloadWindowIsPlusMinusTwo() {
    XCTAssertEqual(ViewerPagerMath.preloadWindow(center: 50, count: 102_000).count, 5)
    XCTAssertEqual(ViewerPagerMath.preloadWindow(center: 0, count: 102_000), 0...2)
    XCTAssertEqual(
      ViewerPagerMath.preloadWindow(center: 101_999, count: 102_000), 101_997...101_999)
  }

  func testNaturalDirectionDxNegativeAdvances() {
    XCTAssertEqual(ViewerPagerMath.pageDelta(dx: -30), 1)
    XCTAssertEqual(ViewerPagerMath.pageDelta(dx: 30), -1)
  }

  func testScrollPagingRequiresSwipeTrackingSetting() {
    XCTAssertTrue(ViewerPagerMath.pagesFromScroll(isSwipeTrackingEnabled: true))
    XCTAssertFalse(ViewerPagerMath.pagesFromScroll(isSwipeTrackingEnabled: false))
  }

  func testRubberBandCapsAtThirdOfTravel() {
    XCTAssertEqual(ViewerPagerMath.rubberBandedOffset(travel: 90), 30, accuracy: 0.001)
  }

  // MARK: - V6 navigation coalescing

  func testRapidPressesSkipAnimationAfterFirstPending() {
    XCTAssertTrue(ViewerPagerMath.shouldAnimateStep(pendingPresses: 0))
    XCTAssertTrue(ViewerPagerMath.shouldAnimateStep(pendingPresses: 1))
    XCTAssertFalse(ViewerPagerMath.shouldAnimateStep(pendingPresses: 2))
    XCTAssertFalse(ViewerPagerMath.shouldAnimateStep(pendingPresses: 5))
  }

  // MARK: - V7 pinch-close

  func testPinchCloseBelowThresholdCloses() {
    XCTAssertTrue(PinchCloseDecision.shouldClose(endScale: 0.79, velocityInward: false))
    XCTAssertFalse(PinchCloseDecision.shouldClose(endScale: 0.8, velocityInward: false))
    XCTAssertTrue(PinchCloseDecision.shouldClose(endScale: 0.95, velocityInward: true))
  }

  // MARK: - V8 smart zoom

  func testSmartZoomTogglesFitAnd2x() {
    XCTAssertEqual(SmartZoomMath.toggled(current: 1.0), 2.0, accuracy: 0.001)
    XCTAssertEqual(SmartZoomMath.toggled(current: 2.0), 1.0, accuracy: 0.001)
  }

  func testZoomStepsClampAt8x() {
    XCTAssertEqual(SmartZoomMath.stepped(1.0, times: 3), 3.375, accuracy: 0.001)
    XCTAssertEqual(SmartZoomMath.stepped(1.0, times: 10), 8.0, accuracy: 0.001)
  }

  // MARK: - V9/V19 header formatter

  func testSubtitleFormatsCounterWithGroupingEnUS() {
    let date = Date(timeIntervalSince1970: 1_775_000_000)
    let subtitle = ViewerHeaderFormatter.subtitle(
      date: date, timeZone: TimeZone(identifier: "America/Los_Angeles"),
      index: 6387, total: 12108, locale: Locale(identifier: "en_US"))
    XCTAssertTrue(subtitle.contains("6,388 of 12,108"), subtitle)
  }

  func testSubtitleLocalizesCounterDeDE() {
    let date = Date(timeIntervalSince1970: 1_775_000_000)
    let subtitle = ViewerHeaderFormatter.subtitle(
      date: date, timeZone: TimeZone(identifier: "Europe/Berlin"),
      index: 6387, total: 12108, locale: Locale(identifier: "de_DE"))
    XCTAssertTrue(subtitle.contains("6.388 von 12.108"), subtitle)
  }

  func testSingleItemContextOmitsCounter() {
    let date = Date(timeIntervalSince1970: 1_775_000_000)
    let subtitle = ViewerHeaderFormatter.subtitle(
      date: date, index: 0, total: 1, locale: Locale(identifier: "en_US"))
    XCTAssertFalse(subtitle.contains("of"))
    XCTAssertFalse(subtitle.contains("1 of 1"))
  }

  func testTitleFallsBackToDateWithoutPlace() {
    let date = Date(timeIntervalSince1970: 1_775_000_000)
    XCTAssertEqual(
      ViewerHeaderFormatter.title(place: "Miami Beach", date: date), "Miami Beach")
    XCTAssertFalse(
      ViewerHeaderFormatter.title(place: nil, date: date, locale: Locale(identifier: "en_US"))
        .isEmpty)
  }

  // MARK: - V10 context menu order

  func testPhotoLibraryMenuOrder() {
    XCTAssertEqual(
      ViewerContextMenuSpec.titles(kind: .photo),
      ["Get Info", "Copy", "Share…", "Show in All Photos", "Rotate Left", "Rotate Right",
        "Copy Edits", "Paste Edits", "Revert to Original", "Add to", "Add to Album",
        "Edit With", "Duplicate", "Hide", "Delete"])
  }

  func testVideoOmitsRotation() {
    let titles = ViewerContextMenuSpec.titles(kind: .video)
    XCTAssertFalse(titles.contains("Rotate Left"))
    XCTAssertFalse(titles.contains("Rotate Right"))
  }

  func testAlbumScopeAddsAlbumRows() {
    let titles = ViewerContextMenuSpec.titles(kind: .photo, scope: .album)
    XCTAssertTrue(titles.contains("Make Album Cover"))
    XCTAssertTrue(titles.contains("Remove from Album"))
  }

  func testSharedLibraryAddsMoveRow() {
    let titles = ViewerContextMenuSpec.titles(kind: .photo, library: .shared)
    XCTAssertTrue(titles.contains("Move to Library"))
  }

  // MARK: - V11 chevrons

  func testChevronsHiddenAtEnds() {
    XCTAssertFalse(
      ChevronVisibility.isVisible(edge: .prev, index: 0, count: 10, hoverNearEdge: true))
    XCTAssertFalse(
      ChevronVisibility.isVisible(edge: .next, index: 9, count: 10, hoverNearEdge: true))
    XCTAssertTrue(
      ChevronVisibility.isVisible(edge: .next, index: 0, count: 10, hoverNearEdge: true))
    XCTAssertFalse(
      ChevronVisibility.isVisible(edge: .next, index: 3, count: 10, hoverNearEdge: false))
  }
}
