import XCTest

/// WP-T red-first tests for F1, F3, F3b (P0 correctness) and E1–E7 (editor
/// surface). Every test is RED on today's base: the canvas surfaces and tab
/// identifiers below do not exist yet and are owned by WP-E (canvas delivery)
/// and WP-R (asset-load correctness).
///
/// §0.5: editors are exercised with Cancel/abandon, never Done/Save — each
/// test ends with the editor open and XCUITest terminates the app. No test
/// backgrounds the app: backgrounding masks the F1/F3 defect (§5b).
final class EditorUITests: XCTestCase {
  func test_photoEditor_canvasReceivesImage_withoutAppSwitch() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    Parity.openEditor(app)
    // F1/WP-R+WP-E: canvas clears the §2.1 threshold within 400 ms of the
    // editor opening. Today the canvas is black at 45 s+ — red on base.
    ParityCanvas.waitForContent(
      elementId: "editor-canvas", in: app, within: 0.4,
      gap: "F1", owner: "WP-R/WP-E")
  }

  func test_videoEditor_canvasReceivesImage() throws {
    let app = Parity.launch()
    Parity.openVideoViewer(app)
    Parity.openEditor(app)
    // F3/WP-R+WP-E: same non-black gate for video.
    ParityCanvas.waitForContent(
      elementId: "editor-canvas", in: app, within: 2.0,
      gap: "F3", owner: "WP-R/WP-E")
  }

  func test_editorChrome_appearsWithoutSceneChange() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    let start = Date()
    Parity.openEditor(app)
    // F3b/WP-R: separate root cause from the black canvas — the chrome itself
    // must appear with no background/foreground cycle. The 5 s bound below is
    // a smoke bound for the Simulator; the §5 budget (< 300 ms, unconditional)
    // is asserted Release-on-device by WP-X once WP-R lands.
    let chrome = Parity.require(
      "editor-chrome", in: app, gap: "F3b", owner: "WP-R")
    XCTAssertLessThan(
      Date().timeIntervalSince(start), 5.0,
      "F3b: editor chrome took too long to appear without a scene change")
    XCTAssertTrue(chrome.isHittable, "F3b: editor chrome should be interactive")
  }

  func test_editor_tabTaxonomy_matchesTargetSet() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    Parity.openEditor(app)
    // E1/WP-E: assert the taxonomy WP-E's plan lands on. TEST-PLAN notes the
    // plan does not mandate Photos' exact set — update these identifiers to
    // the agreed final set before WP-E closes E1.
    for tab in ["editor-tab-styles", "editor-tab-adjust", "editor-tab-crop", "editor-tab-tools"] {
      Parity.require(tab, in: app, gap: "E1", owner: "WP-E")
    }
  }

  func test_editorStyles_showLiveThumbnailPreviews() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    Parity.openEditor(app)
    // E2/WP-E: style cells render live thumbnails of the photo, not text
    // labels; a CUSTOMIZE control exists.
    Parity.require("editor-style-cell-0", in: app, gap: "E2", owner: "WP-E")
    Parity.require("editor-styles-customize", in: app, gap: "E2", owner: "WP-E")
  }

  func test_editorValueControl_isTickRulerDial() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    Parity.openEditor(app)
    // E3/WP-E: tick-ruler dial with centre marker, not a plain slider.
    Parity.require("editor-value-dial", in: app, gap: "E3", owner: "WP-E")
    Parity.require("editor-value-dial-centre", in: app, gap: "E3", owner: "WP-E")
  }

  func test_editor_offersCleanUpExtendReframe() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    Parity.openEditor(app)
    // E4/WP-E.
    for tool in ["editor-tool-cleanup", "editor-tool-extend", "editor-tool-reframe"] {
      Parity.require(tool, in: app, gap: "E4", owner: "WP-E")
    }
  }

  func test_videoEditor_hasTrimFilmstripWithHandles() throws {
    let app = Parity.launch()
    Parity.openVideoViewer(app)
    Parity.openEditor(app)
    // E5/WP-E: frame-thumbnail filmstrip, yellow trim handles, play button —
    // not Mute + speed only.
    Parity.require("editor-trim-filmstrip", in: app, gap: "E5", owner: "WP-E")
    Parity.require("editor-trim-handle-start", in: app, gap: "E5", owner: "WP-E")
    Parity.require("editor-trim-handle-end", in: app, gap: "E5", owner: "WP-E")
    Parity.require("editor-trim-play", in: app, gap: "E5", owner: "WP-E")
  }

  func test_videoEditor_hasAudioMixTab() throws {
    let app = Parity.launch()
    Parity.openVideoViewer(app)
    Parity.openEditor(app)
    // E6/WP-E.
    Parity.require("editor-tab-audiomix", in: app, gap: "E6", owner: "WP-E")
  }

  func test_editorPortraitTab_hiddenWhenNoDepthData() throws {
    let app = Parity.launch()
    Parity.openViewer(app)
    Parity.openEditor(app)
    // E7/WP-E: for an asset with no depth data the Portrait tab is absent (or
    // non-empty) — not a permanent dead stub. The fixture's first asset has
    // no depth data.
    let portraitTab = app.descendants(matching: .any)["editor-tab-portrait"]
    if portraitTab.waitForExistence(timeout: 5) {
      XCTFail(
        "E7/WP-E: Portrait tab is present for an asset with no depth data — "
          + "surface it only when applicable")
    }
  }
}
