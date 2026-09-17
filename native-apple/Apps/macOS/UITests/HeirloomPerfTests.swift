import XCTest

/// WP-T T6: performance scaffolding (TEST-PLAN T6). Each named signpost gets a
/// `measure(metrics:)` test; signposts that don't exist yet are
/// `XCTSkip("awaiting <WP>")` so the class stays green until the feature WPs
/// emit them. Runs on the owner's Mac only, via `verify.sh mac-perf`, on the
/// large fixture (`-HeirloomFixture large`, ~102k synthetic rows).
///
/// Setting baselines: run once with the scheme's `.xcbaseline` recording on
/// this Mac (Xcode → Test navigator → HeirloomPerfTests → "Set Baseline"), take
/// the median of 3 quiet-host runs, and commit the baseline with the WP report.
/// WP-X §2 fails any median regression > 10%.
final class HeirloomPerfTests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app = XCUIApplication()
    // Booleans are SINGLE-DASH (see MacSmokeTests): a `--` flag swallows the
    // next argv token and the stranded token kills the initial scene.
    app.launchArguments = [
      "-fixture-seed", "-HeirloomFixture=large",
      "-ApplePersistenceIgnoreState", "YES",
    ]
  }

  override func tearDown() {
    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }
    super.tearDown()
  }

  private func launchAndWaitForGrid(file: StaticString = #filePath, line: UInt = #line) {
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 120), file: file, line: line)
    XCTAssertTrue(
      app.descendants(matching: .any)["asset-grid"].waitForExistence(timeout: 120),
      "grid renders on the large fixture", file: file, line: line)
  }

  // MARK: - launch (no signpost needed)

  func testLaunchResponsiveness() {
    measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
      launchAndWaitForGrid()
      app.terminate()
    }
  }

  // MARK: - signpost scaffolding (skipped until the owning WP emits them)
  // Each test below measures an `XCTOSSignpostMetric(subsystem:
  // "com.immich.heirloom.macos", category: "HeirloomLog", name: <signpost>)`
  // once the owning WP emits that signpost.

  func testLaunchFirstThumbnails() throws {
    throw XCTSkip("awaiting WP-F: Launch.FirstThumbnails signpost")
  }

  func testLibraryReturn() throws {
    throw XCTSkip("awaiting WP-F: Library.Return signpost")
  }

  func testPageFirstPaint() throws {
    throw XCTSkip("awaiting WP-P: Page.FirstPaint signpost")
  }

  func testTimelineQuery() throws {
    throw XCTSkip("awaiting WP-F: Timeline.Query signpost")
  }

  func testEditOpen() throws {
    throw XCTSkip("awaiting WP-E: Edit.Open signpost")
  }

  func testViewerPage() throws {
    throw XCTSkip("awaiting WP-V: Viewer.Page signpost")
  }

  func testViewerOpenTransition() throws {
    throw XCTSkip("awaiting WP-V: Viewer.OpenTransition signpost")
  }

  func testGridPinchCommit() throws {
    throw XCTSkip("awaiting WP-G: Grid.PinchCommit signpost")
  }
}
