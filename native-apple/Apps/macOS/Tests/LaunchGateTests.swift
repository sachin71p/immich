import XCTest

/// WP-F F3 unit coverage: the synchronous sign-in gate and the never-"0 Photos"
/// footer rule. The UI half (connect.form never exists on signed-in launch) is
/// `MacFunctionalTests.testSignedInLaunchNeverShowsConnect` (mac-ui, main session).
final class LaunchGateTests: XCTestCase {
  func testSignedInRequiresURLTokenAndUserID() {
    XCTAssertTrue(
      LaunchGate.isSignedIn(
        serverURLString: "https://photos.example.com", tokenPresent: true, userID: "u1"))
    XCTAssertFalse(
      LaunchGate.isSignedIn(serverURLString: nil, tokenPresent: true, userID: "u1"))
    XCTAssertFalse(
      LaunchGate.isSignedIn(serverURLString: "", tokenPresent: true, userID: "u1"))
    XCTAssertFalse(
      LaunchGate.isSignedIn(
        serverURLString: "https://photos.example.com", tokenPresent: false, userID: "u1"))
    XCTAssertFalse(
      LaunchGate.isSignedIn(
        serverURLString: "https://photos.example.com", tokenPresent: true, userID: nil))
    XCTAssertFalse(
      LaunchGate.isSignedIn(
        serverURLString: "https://photos.example.com", tokenPresent: true, userID: ""))
  }

  func testPlaceholderAndMalformedURLsAreSignedOut() {
    XCTAssertFalse(
      LaunchGate.isSignedIn(
        serverURLString: "https://unconfigured.invalid", tokenPresent: false, userID: nil))
    XCTAssertFalse(
      LaunchGate.isSignedIn(serverURLString: "not a url", tokenPresent: true, userID: "u1"))
  }

  func testFooterShowsSpinnerWhileLoadingWithNoRows() {
    XCTAssertNil(
      LaunchGate.footerCountsText(photos: 0, videos: 0, phaseIsLoading: true, hasRows: false))
  }

  func testFooterShowsCountsOtherwise() {
    XCTAssertEqual(
      LaunchGate.footerCountsText(photos: 0, videos: 0, phaseIsLoading: false, hasRows: false),
      "0 Photos, 0 Videos")
    XCTAssertEqual(
      LaunchGate.footerCountsText(photos: 12, videos: 3, phaseIsLoading: true, hasRows: true),
      "12 Photos, 3 Videos")
    XCTAssertEqual(
      LaunchGate.footerCountsText(photos: 1, videos: 1, phaseIsLoading: false, hasRows: true),
      "1 Photo, 1 Video")
  }

  func testConnectFormIdentifierContract() {
    XCTAssertEqual(AXIDs.connectForm, "connect.form")
  }
}
