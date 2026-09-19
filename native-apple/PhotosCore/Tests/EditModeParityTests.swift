import CoreImage
import CoreModel
import Editing
import Foundation
import Testing

/// WP-E (Edit parity) red-first tests: TEST-PLAN E3–E8.
///
/// - E3/E4: new Adjust section keys render deterministically; old payloads decode
///   with neutral defaults and render identically.
/// - E5: Undertone/Mood style presets match golden renders; classic recipes stay back-compat.
/// - E6: crop-rect math (clamp, aspect, straighten scale).
/// - E7: proxy-first open; Done gated on the async original.
/// - E8: Tools tab lists only available tools; hidden when none are.
@Suite struct EditModeParityTests {
  /// Two-tone synthetic fixture (warm left, cool right): flat enough to be stable,
  /// edged enough that sharpen/grain/vignette keys visibly change pixels.
  private func fixtureImage() -> CIImage {
    let left = CIImage(color: CIColor(red: 0.75, green: 0.45, blue: 0.30))
      .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 32))
    let right = CIImage(color: CIColor(red: 0.25, green: 0.45, blue: 0.70))
      .cropped(to: CGRect(x: 16, y: 0, width: 16, height: 32))
    return left.composited(over: right)
  }

  private func hash(_ recipe: EditRecipe) -> UInt64? {
    EditRenderer().pixelHash(source: fixtureImage(), recipe: recipe)
  }

  // MARK: - E3/E4 new Adjust keys

  /// Every new Adjust key from the WP-E section map.
  private func newKeyRecipes(value: Int) -> [(String, EditRecipe)] {
    return [
      ("cast", { var a = AdjustRecipe(); a.cast = value; return EditRecipe(adjust: a) }()),
      ("bwIntensity", { var a = AdjustRecipe(); a.bwIntensity = value; return EditRecipe(adjust: a) }()),
      ("bwNeutrals", { var a = AdjustRecipe(); a.bwNeutrals = value; return EditRecipe(adjust: a) }()),
      ("bwTone", { var a = AdjustRecipe(); a.bwTone = value; return EditRecipe(adjust: a) }()),
      ("grain", { var a = AdjustRecipe(); a.grain = value; return EditRecipe(adjust: a) }()),
      ("wbTemperature", { var a = AdjustRecipe(); a.wbTemperature = value; return EditRecipe(adjust: a) }()),
      ("wbTint", { var a = AdjustRecipe(); a.wbTint = value; return EditRecipe(adjust: a) }()),
      ("sharpenEdges", { var a = AdjustRecipe(); a.sharpenEdges = value; return EditRecipe(adjust: a) }()),
      ("sharpenFalloff", { var a = AdjustRecipe(); a.sharpenFalloff = value; return EditRecipe(adjust: a) }()),
      ("vignetteStrength", { var a = AdjustRecipe(); a.vignetteStrength = value; return EditRecipe(adjust: a) }()),
      ("vignetteRadius", { var a = AdjustRecipe(); a.vignetteRadius = value; return EditRecipe(adjust: a) }()),
      ("vignetteSoftness", { var a = AdjustRecipe(); a.vignetteSoftness = value; return EditRecipe(adjust: a) }()),
    ]
  }

  @Test("E3/E4: each new Adjust key renders deterministically at 3 strengths")
  func newAdjustKeysDeterministic() {
    for strength in [30, 60, 100] {
      for (name, recipe) in newKeyRecipes(value: strength) {
        guard let first = hash(recipe), let second = hash(recipe) else { return }
        #expect(first == second, "key \(name) at \(strength) is non-deterministic")
      }
    }
  }

  @Test("E3/E4: each new Adjust key changes pixels vs neutral")
  func newAdjustKeysChangePixels() {
    guard let plain = hash(EditRecipe()) else { return }
    for (name, recipe) in newKeyRecipes(value: 60) {
      // Detail keys (falloff/radius/softness) only modulate their section's base
      // amount, so they are covered by newAdjustDetailKeysModulate below.
      guard !["sharpenFalloff", "vignetteRadius", "vignetteSoftness"].contains(name) else { continue }
      guard let edited = hash(recipe) else { return }
      #expect(edited != plain, "key \(name) has no visible effect")
    }
  }

  @Test("E3/E4: detail keys modulate their section's render")
  func newAdjustDetailKeysModulate() {
    var sharpBase = AdjustRecipe()
    sharpBase.sharpenEdges = 60
    var sharpDetail = sharpBase
    sharpDetail.sharpenFalloff = 60
    guard let a = hash(EditRecipe(adjust: sharpBase)), let b = hash(EditRecipe(adjust: sharpDetail)) else {
      return
    }
    #expect(a != b, "sharpenFalloff has no modulating effect")
    var vigBase = AdjustRecipe()
    vigBase.vignetteStrength = 60
    var vigRadius = vigBase
    vigRadius.vignetteRadius = 60
    var vigSoft = vigBase
    vigSoft.vignetteSoftness = 60
    guard let c = hash(EditRecipe(adjust: vigBase)), let d = hash(EditRecipe(adjust: vigRadius)),
      let e = hash(EditRecipe(adjust: vigSoft))
    else { return }
    #expect(c != d, "vignetteRadius has no modulating effect")
    #expect(c != e, "vignetteSoftness has no modulating effect")
  }

  @Test("E3/E4: old adjust payloads decode with neutral defaults for new keys")
  func oldAdjustPayloadBackCompat() throws {
    let old = """
      {"exposure":25,"brilliance":0,"highlights":0,"shadows":0,"contrast":0,
       "brightness":0,"blackPoint":0,"saturation":0,"vibrance":0,"warmth":-10,
       "tint":0,"sharpness":0,"definition":0,"noiseReduction":0,"vignette":40,
       "autoEnhance":false}
      """
    let decoded = try JSONDecoder().decode(AdjustRecipe.self, from: Data(old.utf8))
    #expect(decoded.exposure == 25)
    #expect(decoded.warmth == -10)
    #expect(decoded.vignette == 40)
    #expect(decoded.cast == 0)
    #expect(decoded.bwIntensity == 0)
    #expect(decoded.grain == 0)
    #expect(decoded.wbTemperature == 0)
    #expect(decoded.sharpenEdges == 0)
    #expect(decoded.vignetteStrength == 0)
    #expect(decoded == AdjustRecipe(
      exposure: 25, warmth: -10, vignette: 40))
  }

  @Test("E3/E4: old recipe fixture renders identically after the schema grows")
  func oldRecipeRendersIdentically() throws {
    let url = try #require(Bundle.module.url(
      forResource: "edit-recipe-base-v1", withExtension: "json", subdirectory: "Fixtures"))
    let oldRecipe = try JSONDecoder().decode(EditRecipe.self, from: Data(contentsOf: url))
    let rebuilt = EditRecipe(
      adjust: AdjustRecipe(exposure: 25, warmth: -10, vignette: 40),
      style: StyleRecipe(style: .vividWarm, intensity: 80),
      crop: CropRecipe(
        rect: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
        quarterTurns: 1, flipHorizontal: true, aspect: .square))
    #expect(oldRecipe == rebuilt)
    guard let a = hash(oldRecipe), let b = hash(rebuilt) else { return }
    #expect(a == b)
  }

  // MARK: - E5 styles

  @Test("E5: every Undertone and Mood preset renders deterministically")
  func stylePresetsDeterministic() {
    for style in EditStyle.allCases where style != .none {
      let recipe = EditRecipe(style: StyleRecipe(style: style, intensity: 100))
      guard let first = hash(recipe), let second = hash(recipe) else { return }
      #expect(first == second, "style \(style.displayName) is non-deterministic")
    }
  }

  @Test("E5: every Undertone and Mood preset visibly differs from neutral")
  func stylePresetsVisible() {
    guard let plain = hash(EditRecipe()) else { return }
    for style in EditStyle.undertonePresets + EditStyle.moodPresets {
      let recipe = EditRecipe(style: StyleRecipe(style: style, intensity: 100))
      guard let rendered = hash(recipe) else { return }
      #expect(rendered != plain, "style \(style.displayName) has no visible effect")
    }
  }

  @Test("E5: classic recipes decode and render identically (back-compat)")
  func classicStylesBackCompat() throws {
    let url = try #require(Bundle.module.url(
      forResource: "edit-recipe-classic-noir", withExtension: "json", subdirectory: "Fixtures"))
    let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(contentsOf: url))
    let rebuilt = EditRecipe(style: StyleRecipe(style: .noir, intensity: 100))
    #expect(decoded == rebuilt)
    guard let a = hash(decoded), let b = hash(rebuilt) else { return }
    #expect(a == b)
    #expect(EditStyle.classicStyles.contains(.noir))
    #expect(EditStyle.classicStyles.contains(.vividWarm))
  }

  @Test("E5: new Undertone fixture decodes to the documented preset")
  func undertoneFixtureDecodes() throws {
    let url = try #require(Bundle.module.url(
      forResource: "edit-recipe-undertone-amber", withExtension: "json", subdirectory: "Fixtures"))
    let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(contentsOf: url))
    #expect(decoded.style?.style == .undertoneAmber)
    #expect(EditStyle.undertonePresets.contains(.undertoneAmber))
  }

  @Test("E3/E4: filmstrip renders one thumb per strength, deterministically")
  func filmstripThumbs() {
    let strengths = [-100, -50, 0, 50, 100]
    let first = EditFilmstrip.thumbs(
      source: fixtureImage(), base: EditRecipe(), keyPath: \.exposure, strengths: strengths)
    #expect(first.count == strengths.count)
    #expect(first.allSatisfy { $0 != nil })
    let second = EditFilmstrip.thumbs(
      source: fixtureImage(), base: EditRecipe(), keyPath: \.exposure, strengths: strengths)
    for (a, b) in zip(first, second) {
      guard let a, let b else { continue }
      #expect(
        (a.dataProvider?.data as Data?) == (b.dataProvider?.data as Data?))
    }
  }

  // MARK: - E6 crop math

  @Test("E6: handle drags clamp to image bounds")
  func cropClampsToBounds() {
    let drag = NormalizedRect(x: -0.2, y: 0.9, width: 1.6, height: 0.5)
    let clamped = CropMath.clamped(drag)
    #expect(clamped.x >= 0 && clamped.y >= 0)
    #expect(clamped.x + clamped.width <= 1.0 + 1e-9)
    #expect(clamped.y + clamped.height <= 1.0 + 1e-9)
    #expect(clamped.width > 0 && clamped.height > 0)
  }

  @Test("E6: aspect presets keep their ratio, honoring orientation")
  func cropAspectRatios() {
    for aspect in CropAspect.allCases {
      for orientation in [CropOrientation.landscape, .portrait] {
        let rect = CropMath.rect(for: aspect, orientation: orientation)
        guard let ratio = aspect.ratio(orientation: orientation) else { continue }
        let actual = rect.width / rect.height
        #expect(abs(actual - ratio) / ratio < 0.02, "\(aspect) \(orientation): \(actual) != \(ratio)")
      }
    }
    // New WP-E presets exist.
    #expect(CropAspect(rawValue: "4:5") == .fourFive)
    #expect(CropAspect(rawValue: "5:7") == .fiveSeven)
    #expect(CropAspect(rawValue: "3:5") == .threeFive)
  }

  @Test("E6: straighten auto-scales to avoid empty corners")
  func cropStraightenScale() {
    #expect(CropMath.straightenScale(degrees: 0) == 1.0)
    let s10 = CropMath.straightenScale(degrees: 10)
    let s30 = CropMath.straightenScale(degrees: 30)
    #expect(s10 > 1.0 && s30 > s10)
  }

  // MARK: - E7 proxy-first open

  @Test("E7: Done stays disabled until the async original arrives")
  func editOpenGatesDone() async throws {
    let loader = EditOriginalLoader()
    #expect(loader.state == .proxyReady)
    #expect(!loader.isDoneEnabled)
    loader.beginLoading()
    #expect(loader.state == .loadingOriginal)
    #expect(!loader.isDoneEnabled)
    let task = Task { () async throws -> Data in
      try await Task.sleep(nanoseconds: 50_000_000)
      return Data([1, 2, 3])
    }
    // While the stubbed original is in flight, Done must stay disabled.
    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(loader.state == .loadingOriginal)
    #expect(!loader.isDoneEnabled)
    loader.complete(with: try await task.value)
    #expect(loader.state == .ready)
    #expect(loader.isDoneEnabled)
    #expect(loader.didRerender)
    #expect(loader.originalData == Data([1, 2, 3]))
    // Failure path: Done stays disabled.
    let failing = EditOriginalLoader()
    failing.beginLoading()
    failing.fail()
    #expect(failing.state == .failed)
    #expect(!failing.isDoneEnabled)
  }

  @Test("E7: Edit.Open signpost name is pinned")
  func editOpenSignpostPinned() {
    #expect(HeirloomSignpost.editOpen.description == "EditOpen")
  }

  // MARK: - E8 tools gating

  @Test("E8: Tools tab hides when no tool is available")
  func toolsTabHiddenWhenEmpty() {
    #expect(EditToolRegistry(tools: []).visibleTools.isEmpty)
    #expect(!EditToolRegistry(tools: []).shouldShowToolsTab)
  }

  @Test("E8: Tools tab lists only available tools")
  func toolsTabListsAvailableOnly() {
    let registry = EditToolRegistry(tools: [
      EditTool(id: "cleanup", title: "Clean Up", isAvailable: false),
      EditTool(id: "retouch", title: "Retouch", isAvailable: true),
    ])
    #expect(registry.visibleTools.map { $0.id } == ["retouch"])
    #expect(registry.shouldShowToolsTab)
  }
}
