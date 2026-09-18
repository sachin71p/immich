import XCTest

/// WP-T red-first tests for F6 (build guard) and L1–L3 (light appearance).
/// Appearance identifiers are owned by WP-L.
///
/// F6 note: a UITest cannot inspect the app binary for `*.debug.dylib`, so
/// the implementable form of TEST-PLAN's build guard is an app-exposed
/// `build-config` element (owned by WP-B alongside `install-ios-release`):
/// the test refuses to bless any perf number until the app reports "Release".
/// Until WP-B lands that, this test is red — which is exactly the point, since
/// `make install-ios` installs Debug today.
final class AppearanceUITests: XCTestCase {
  func test_deviceBuild_isReleaseConfiguration() throws {
    try Parity.requirePhysicalDevice()
    let app = Parity.launch()
    // F6/WP-B: the app must report its build configuration to UI tests.
    let flag = app.descendants(matching: .any)["build-config"]
    guard flag.waitForExistence(timeout: 10) else {
      XCTFail(
        "F6/WP-B: expected accessibilityIdentifier \"build-config\" reporting "
          + "\"Release\" — every perf number before WP-B's install-ios-release "
          + "target is measured against a Debug baseline and is invalid")
      return
    }
    XCTAssertEqual(
      flag.label, "Release",
      "F6: performance tests must run against a Release build, found \"\(flag.label)\"")
  }

  /// Launch with a light-appearance override. Owning WP-L calibrates this
  /// against the paired light captures once L1 lands.
  private func launchLight() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-useFixtureStore", "-AppleInterfaceStyle", "Light"]
    app.launch()
    XCTAssertTrue(
      app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 120),
      "library grid should render from the fixture DB")
    return app
  }

  func test_viewer_followsLightAppearance() throws {
    let app = launchLight()
    Parity.openViewer(app)
    // L1/WP-L: with a light trait the viewer chrome samples light, not
    // hard-coded dark. The chrome surface id is WP-L's to add.
    let chrome = Parity.require(
      "viewer-chrome-surface", in: app, gap: "L1", owner: "WP-L")
    guard let cgImage = chrome.screenshot().image.cgImage else {
      XCTFail("L1/WP-L: could not screenshot the viewer chrome surface")
      return
    }
    XCTAssertTrue(
      ParityCanvas.isNonBlack(cgImage),
      "L1/WP-L: viewer chrome surface rendered unreadable in light appearance")
  }

  func test_libraryTitle_legibleOverGridInLight() throws {
    let app = launchLight()
    // L2/WP-L: white title text over a blur scrim in both appearances —
    // contrast ratio ≥ 4.5:1 over a light photo. The title/scrim ids are
    // WP-L's to add; the content gate pins "renders something legible".
    let title = Parity.require(
      "library-title-scrim", in: app, gap: "L2", owner: "WP-L")
    guard let cgImage = title.screenshot().image.cgImage else {
      XCTFail("L2/WP-L: could not screenshot the library title scrim")
      return
    }
    XCTAssertTrue(
      ParityCanvas.isNonBlack(cgImage),
      "L2/WP-L: library title region is empty in light appearance")
  }

  func test_infoAndEditor_appearanceParity() throws {
    let app = launchLight()
    // L3/WP-L: placeholder for the manual + pixel sign-off once L1 lands.
    // Tracks the WP-L identifiers so the checklist cannot be forgotten;
    // the eyeball diff against assets/pairs stays a WP-X manual item.
    Parity.openInfoPanel(app)
    Parity.require("info-sheet-surface", in: app, gap: "L3", owner: "WP-L")
  }
}
