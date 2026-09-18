import XCTest

/// WP-T shared harness for the Heirloom iOS → Photos parity matrix
/// (`.claude/plans/heirloom-ios-photos-parity/TEST-PLAN.md`).
///
/// Conventions every parity test follows:
/// - Launch with `-useFixtureStore` (read-only fixture DB: no server, nothing
///   destructive). Each test launches its own app instance; the app is left
///   wherever the assertions end — XCUITest terminates it, so tests never need
///   to tap Save/Done/Delete to "clean up".
/// - Navigate only through accessibility identifiers that exist on today's base
///   (`library-grid`, `viewer-pager`, `viewer-info-panel`, tab-bar labels…).
///   Every *new* identifier a test needs is owned by the work package named in
///   the failure message — a red test fails naming its gap, its owner, and the
///   missing identifier, never with a bare `XCTAssertTrue(false)`.
/// - §0.5 hazard rule: if a stray "Delete Photo?" alert ever appears on an
///   automated path, call `Parity.dismissStrayDeleteDialog` (taps Cancel) and
///   fail the test — destructive controls must stay away from automation.
/// - §0.3 / TEST-PLAN §3: performance assertions are Release-on-physical-device
///   only. `requirePhysicalDevice` throws `XCTSkip` on the Simulator; perf
///   tests assert budgets with `XCTAssertLessThan` on a measured value, never
///   with `measure` baselines.
enum Parity {
  /// Launch the app against the read-only fixture DB and wait for the grid.
  @discardableResult
  static func launch(
    extraArgs: [String] = [],
    file: StaticString = #filePath, line: UInt = #line
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-useFixtureStore"] + extraArgs
    app.launch()
    XCTAssertTrue(
      app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 120),
      "library grid should render from the fixture DB", file: file, line: line)
    dismissStrayDeleteDialog(app)
    return app
  }

  /// Require an element by accessibility identifier. Fails red naming the gap,
  /// the owning work package, and the missing identifier.
  @discardableResult
  static func require(
    _ id: String, in app: XCUIApplication, gap: String, owner: String,
    timeout: TimeInterval = 10,
    file: StaticString = #filePath, line: UInt = #line
  ) -> XCUIElement {
    let element = app.descendants(matching: .any)[id]
    if !element.waitForExistence(timeout: timeout) {
      dismissStrayDeleteDialog(app)
      XCTFail(
        "\(gap)/\(owner): expected accessibilityIdentifier \"\(id)\" — "
          + "adding it is in scope for \(owner), not the test",
        file: file, line: line)
    }
    return element
  }

  /// Open the viewer on the first grid cell via identifiers known on base.
  static func openViewer(
    _ app: XCUIApplication,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let firstCell = app.collectionViews.cells.firstMatch
    XCTAssertTrue(
      firstCell.waitForExistence(timeout: 30),
      "grid should paint cells", file: file, line: line)
    firstCell.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["viewer-pager"].waitForExistence(timeout: 10),
      "tapping a grid cell should open the viewer", file: file, line: line)
    dismissStrayDeleteDialog(app)
  }

  /// Page through the viewer (swipe left = next photo) until a video page
  /// appears. The fixture seeds videos, so failing to find one is a red
  /// signal, not a skip.
  static func openVideoViewer(
    _ app: XCUIApplication, maxPages: Int = 15,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    openViewer(app, file: file, line: line)
    for _ in 0..<maxPages {
      if app.descendants(matching: .any)["video-page"].exists { return }
      if app.descendants(matching: .any)["video-scrubber"].exists { return }
      app.swipeLeft()
    }
    dismissStrayDeleteDialog(app)
    XCTFail(
      "F2,E5,E6/WP-R,WP-E: no video page found after paging \(maxPages) photos — "
        + "the fixture seeds videos, so video rendering or paging is broken",
      file: file, line: line)
  }

  /// Open the photo editor from the viewer via the viewer's adjust/edit
  /// control. Never taps Save/Done/Delete — the test ends with the editor
  /// open and XCUITest terminates the app.
  static func openEditor(
    _ app: XCUIApplication,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    for label in ["Adjust", "Edit", "Tune"] {
      let button = app.buttons[label]
      if button.waitForExistence(timeout: 3), button.isHittable {
        button.tap()
        return
      }
    }
    dismissStrayDeleteDialog(app)
    XCTFail(
      "F1,F3,E1/WP-E: viewer exposes no Adjust/Edit entry control — "
        + "the editor entry point needs a stable button (and WP-E must add "
        + "accessibilityIdentifier \"editor-chrome\" to the editor itself)",
      file: file, line: line)
  }

  /// Reveal the inline info panel with a swipe up (known-good on base).
  static func openInfoPanel(
    _ app: XCUIApplication,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    openViewer(app, file: file, line: line)
    app.swipeUp()
    XCTAssertTrue(
      app.descendants(matching: .any)["viewer-info-panel"].waitForExistence(timeout: 10),
      "swiping up should open the inline info panel", file: file, line: line)
  }

  /// Perf/budget assertions run on a physical device only — the Simulator's
  /// photo pipeline does not represent the library's decode/render behaviour,
  /// so a Simulator pass would prove nothing (TEST-PLAN §3).
  static func requirePhysicalDevice(
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
      throw XCTSkip("Release-on-physical-device-only: skipped on Simulator")
    }
  }

  /// §0.5: a stray "Delete Photo?" dialog must never be confirmed by
  /// automation. Cancel it and let the caller fail for the right reason.
  static func dismissStrayDeleteDialog(_ app: XCUIApplication) {
    let alert = app.alerts["Delete Photo?"]
    if alert.waitForExistence(timeout: 2) {
      alert.buttons["Cancel"].tap()
    }
  }
}

/// Non-black-frame assertion (TEST-PLAN §2.1): the one new mechanism WP-T
/// owns. Thresholds are named constants — calibration points, not magic
/// numbers — and may need adjusting once real F1–F3 fixes land.
enum ParityCanvas {
  /// Mean luminance below this AND stddev below `blackStddevThreshold`
  /// counts as a black canvas (0–255 scale).
  static let blackMeanThreshold = 8.0
  static let blackStddevThreshold = 3.0
  /// Points per side of the sample grid (10×10 = 100 samples).
  static let sampleGridSize = 10
  /// Outer margin ignored to dodge rounded corners/letterboxing.
  static let sampleMarginFraction = 0.05

  /// True when the image is NOT a uniform black frame. A real photo or video
  /// frame — even a dark one — clears at least one of the two thresholds.
  static func isNonBlack(_ image: CGImage) -> Bool {
    let width = image.width, height = image.height
    guard width > 0, height > 0,
      let provider = image.dataProvider,
      let data = provider.data,
      let bytes = CFDataGetBytePtr(data)
    else { return false }
    let bytesPerRow = image.bytesPerRow
    let bytesPerPixel = max(1, image.bitsPerPixel / 8)
    // Channel order is irrelevant here: uniform-black reads ~0 either way,
    // and the stddev gate only needs variation, not colorimetry.
    var sum = 0.0, sumSq = 0.0, count = 0.0
    let n = sampleGridSize
    for row in 0..<n {
      for col in 0..<n {
        let fx = sampleMarginFraction
          + (Double(col) + 0.5) / Double(n) * (1 - 2 * sampleMarginFraction)
        let fy = sampleMarginFraction
          + (Double(row) + 0.5) / Double(n) * (1 - 2 * sampleMarginFraction)
        let x = min(width - 1, Int(fx * Double(width)))
        let y = min(height - 1, Int(fy * Double(height)))
        let offset = y * bytesPerRow + x * bytesPerPixel
        guard offset + 2 < CFDataGetLength(data) else { continue }
        let luminance = 0.299 * Double(bytes[offset])
          + 0.587 * Double(bytes[offset + 1]) + 0.114 * Double(bytes[offset + 2])
        sum += luminance
        sumSq += luminance * luminance
        count += 1
      }
    }
    guard count > 0 else { return false }
    let mean = sum / count
    let variance = max(0, sumSq / count - mean * mean)
    let stddev = variance.squareRoot()
    return !(mean < blackMeanThreshold && stddev < blackStddevThreshold)
  }

  /// Poll an element-scoped screenshot until the surface shows content or the
  /// budget deadline passes. Uses `element.screenshot()`, not a full-device
  /// screenshot — cropping in test code is unreliable across devices.
  /// The test must never background the app while polling: backgrounding
  /// masks the F1/F3 defect (§5b).
  static func waitForContent(
    elementId: String, in app: XCUIApplication, within budget: TimeInterval,
    gap: String, owner: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let element = app.descendants(matching: .any)[elementId]
    guard element.waitForExistence(timeout: 10) else {
      XCTFail(
        "\(gap)/\(owner): expected rendering surface \"\(elementId)\" — "
          + "adding it is in scope for \(owner), not the test",
        file: file, line: line)
      return
    }
    let deadline = Date().addingTimeInterval(budget)
    while Date() < deadline {
      if let cgImage = element.screenshot().image.cgImage, isNonBlack(cgImage) {
        return
      }
      usleep(50_000)
    }
    XCTFail(
      "\(gap): surface \"\(elementId)\" still uniformly black after \(Int(budget * 1000))ms — "
        + "content never reached the screen",
      file: file, line: line)
  }
}
