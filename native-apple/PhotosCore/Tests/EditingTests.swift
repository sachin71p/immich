import CoreGraphics
import CoreImage
import CoreModel
import Editing
import Foundation
import Rules
import Testing

/// A8 editor tests: recipe serialization stability, render determinism ([AP-05] on
/// synthetic fixtures; the `@personal portrait.heic` depth half needs personal
/// fixtures, absent — see e2e/fork-assets/personal/README.md), undo/redo +
/// copy/paste, permission gating via Rules, and the upstream/recipe persistence split.
@Suite struct EditingTests {
  // MARK: - Serialization stability

  private func sampleRecipe() -> EditRecipe {
    EditRecipe(
      adjust: AdjustRecipe(exposure: 25, warmth: -10, vignette: 40),
      style: StyleRecipe(style: .dramaticWarm, intensity: 80),
      crop: CropRecipe(
        rect: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
        quarterTurns: 1, flipHorizontal: true, aspect: .square),
      portrait: PortraitRecipe(aperture: 2.0, focus: NormalizedPoint(x: 0.4, y: 0.6)),
      markup: MarkupRecipe(
        elements: [.line(
          from: NormalizedPoint(x: 0, y: 0), to: NormalizedPoint(x: 1, y: 1),
          width: 3, colorHex: "#FF0000")]),
      video: VideoRecipe(trimStart: 1.5, trimEnd: 4.0, muted: true))
  }

  @Test("Recipe round-trips through JSON with all sections intact")
  func recipeRoundTrip() throws {
    let recipe = sampleRecipe()
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let data = try enc.encode(recipe)
    let decoded = try JSONDecoder().decode(EditRecipe.self, from: data)
    #expect(decoded == recipe)
    // Deterministic encoding: same value -> byte-identical JSON (paste + KV stability).
    #expect(try enc.encode(recipe) == data)
  }

  @Test("Recipe schema keeps its field names (cross-client stability)")
  func recipeSchemaKeys() throws {
    let data = try JSONEncoder().encode(sampleRecipe())
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(obj != nil)
    #expect(Set(obj!.keys) == ["adjust", "style", "crop", "portrait", "markup", "video"])
    let adjust = obj!["adjust"] as? [String: Any]
    #expect(adjust?["exposure"] as? Int == 25)
    #expect(adjust?["autoEnhance"] as? Bool == false)
    let style = obj!["style"] as? [String: Any]
    #expect(style?["style"] as? String == "Dramatic Warm")
    #expect(style?["intensity"] as? Int == 80)
    let crop = obj!["crop"] as? [String: Any]
    #expect(crop?["quarterTurns"] as? Int == 1)
    #expect(crop?["aspect"] as? String == "1:1")
  }

  // MARK: - Levels (D3)

  @Test("[D3] Levels keys default to identity; versions default to 1; clamping holds")
  func levelsDefaults() {
    let a = AdjustRecipe()
    #expect(a.levelsInBlack == 0 && a.levelsInWhite == 100)
    #expect(a.levelsOutBlack == 0 && a.levelsOutWhite == 100)
    #expect(a.recipeVersion == 1 && a.rendererVersion == 1)
    #expect(AdjustRecipe(levelsInWhite: 500).levelsInWhite == 100)
    #expect(AdjustRecipe(levelsInBlack: -500).levelsInBlack == -100)
  }

  @Test("[D3] Levels keys round-trip; legacy payloads decode to identity + version 0")
  func levelsCodable() throws {
    var a = AdjustRecipe()
    a.levelsInBlack = 10
    a.levelsInWhite = 90
    a.levelsOutBlack = 5
    a.levelsOutWhite = 95
    let data = try JSONEncoder().encode(EditRecipe(adjust: a))
    let back = try JSONDecoder().decode(EditRecipe.self, from: data).adjust
    #expect(back.levelsInBlack == 10 && back.levelsInWhite == 90)
    #expect(back.levelsOutBlack == 5 && back.levelsOutWhite == 95)
    // Legacy payload without the new keys: identity levels, version 0.
    let legacy = #"{"exposure":25}"#.data(using: .utf8)!
    let old = try JSONDecoder().decode(AdjustRecipe.self, from: legacy)
    #expect(old.exposure == 25)
    #expect(old.levelsInBlack == 0 && old.levelsInWhite == 100)
    #expect(old.levelsOutBlack == 0 && old.levelsOutWhite == 100)
    #expect(old.recipeVersion == 0 && old.rendererVersion == 0)
  }

  @Test("[D3] Identity levels render pixel-identical (levels path is a no-op at defaults)")
  func levelsIdentityNoOp() {
    let renderer = EditRenderer()
    let src = fixtureImage()
    guard let plain = renderer.pixelHash(source: src, recipe: EditRecipe()),
      let identity = renderer.pixelHash(source: src, recipe: EditRecipe(adjust: AdjustRecipe()))
    else { return }
    #expect(identity == plain)
  }

  @Test("[D3] Non-default levels change pixels")
  func levelsChangePixels() {
    let renderer = EditRenderer()
    let src = fixtureImage()
    guard let plain = renderer.pixelHash(source: src, recipe: EditRecipe()),
      let leveled = renderer.pixelHash(
        source: src, recipe: EditRecipe(adjust: AdjustRecipe(levelsInBlack: 30, levelsOutWhite: 80)))
    else { return }
    #expect(leveled != plain)
  }

  // MARK: - Selective Color (D1)

  @Test("[D1] Selective keys default to neutral; clamping holds")
  func selectiveDefaults() {
    let a = AdjustRecipe()
    #expect(
      a.selRedHue == 0 && a.selRedSat == 0 && a.selRedLum == 0 && a.selRedRange == 0)
    #expect(
      a.selBlueHue == 0 && a.selBlueSat == 0 && a.selBlueLum == 0 && a.selBlueRange == 0)
    #expect(!a.isSelectiveActive)
    #expect(AdjustRecipe(selRedSat: 500).selRedSat == 100)
    #expect(AdjustRecipe(selGreenLum: -500).selGreenLum == -100)
    #expect(AdjustRecipe(selBlueRange: 500).selBlueRange == 100)
    #expect(AdjustRecipe(selBlueRange: -50).selBlueRange == 0)
  }

  @Test("[D1] Selective keys round-trip; missing keys decode to neutral identity")
  func selectiveCodable() throws {
    var a = AdjustRecipe()
    a.selRedSat = 40
    a.selRedRange = 60
    a.selBlueHue = -30
    let data = try JSONEncoder().encode(EditRecipe(adjust: a))
    let back = try JSONDecoder().decode(EditRecipe.self, from: data).adjust
    #expect(back.selRedSat == 40 && back.selRedRange == 60)
    #expect(back.selBlueHue == -30)
    #expect(back.selGreenSat == 0 && back.selGreenRange == 0)
    // Legacy payload without the new keys: neutral selective, still inactive.
    let legacy = #"{"exposure":25}"#.data(using: .utf8)!
    let old = try JSONDecoder().decode(AdjustRecipe.self, from: legacy)
    #expect(old.exposure == 25)
    #expect(old.selRedSat == 0 && old.selBlueHue == 0 && old.selMagentaRange == 0)
    #expect(!old.isSelectiveActive)
    // Range-only payloads stay inactive (range shapes a shift, never applies one).
    var rangeOnly = AdjustRecipe()
    rangeOnly.selRedRange = 100
    #expect(!rangeOnly.isSelectiveActive)
  }

  @Test("[D1] Identity selective renders pixel-identical (kernel path is a no-op at defaults)")
  func selectiveIdentityNoOp() {
    let renderer = EditRenderer()
    let src = fixtureImage()
    guard let plain = renderer.pixelHash(source: src, recipe: EditRecipe()),
      let identity = renderer.pixelHash(source: src, recipe: EditRecipe(adjust: AdjustRecipe()))
    else { return }
    #expect(identity == plain)
  }

  // MARK: - Curves (D2)

  @Test("[D2] Curve keys default to identity; points clamp to unit space and cap length")
  func curvesDefaults() {
    let a = AdjustRecipe()
    #expect(a.curvesMaster.isEmpty && a.curvesRed.isEmpty)
    #expect(a.curvesGreen.isEmpty && a.curvesBlue.isEmpty)
    #expect(a.isEmpty)
    let p = CurvePoint(x: -0.5, y: 1.5)
    #expect(p.x == 0 && p.y == 1)
    #expect(
      AdjustRecipe(curvesMaster: [CurvePoint(x: 2, y: 2)]).curvesMaster == [CurvePoint(x: 1, y: 1)])
    let many = Array(repeating: CurvePoint(x: 0.5, y: 0.5), count: 500)
    #expect(AdjustRecipe(curvesBlue: many).curvesBlue.count == AdjustRecipe.maxCurvePoints)
  }

  @Test("[D2] Curve evaluation interpolates with implicit (0,0)/(1,1); clamps out-of-range")
  func curvesEvaluate() {
    #expect(CurvePoint.evaluate([], at: 0.3) == 0.3)
    let pts = [CurvePoint(x: 0.5, y: 0.75)]
    #expect(CurvePoint.evaluate(pts, at: 0.5) == 0.75)
    #expect(abs(CurvePoint.evaluate(pts, at: 0.25) - 0.375) < 1e-9)
    #expect(CurvePoint.evaluate(pts, at: 0) == 0)
    #expect(CurvePoint.evaluate(pts, at: 1) == 1)
    #expect(CurvePoint.evaluate(pts, at: -2) == 0)
    #expect(CurvePoint.evaluate(pts, at: 2) == 1)
    // Endpoint overrides (black/white pickers move the rails).
    #expect(CurvePoint.evaluate([CurvePoint(x: 0, y: 0.2)], at: 0) == 0.2)
    #expect(CurvePoint.evaluate([CurvePoint(x: 1, y: 0.8)], at: 1) == 0.8)
  }

  @Test("[D2] Monotonic point sets evaluate monotonically regardless of storage order")
  func curvesMonotonic() {
    let pts = [CurvePoint(x: 0.75, y: 0.9), CurvePoint(x: 0.25, y: 0.4)]
    var prev = 0.0
    for i in 0...20 {
      let y = CurvePoint.evaluate(pts, at: Double(i) / 20)
      #expect(y >= prev - 1e-9)
      prev = y
    }
  }

  @Test("[D2] Curve keys round-trip; legacy payloads decode to identity; decode clamps")
  func curvesCodable() throws {
    var a = AdjustRecipe()
    a.curvesMaster = [CurvePoint(x: 0.25, y: 0.3), CurvePoint(x: 0.75, y: 0.8)]
    a.curvesRed = [CurvePoint(x: 0, y: 0.1)]
    let data = try JSONEncoder().encode(EditRecipe(adjust: a))
    let back = try JSONDecoder().decode(EditRecipe.self, from: data).adjust
    #expect(back.curvesMaster == a.curvesMaster)
    #expect(back.curvesRed == a.curvesRed)
    #expect(back.curvesGreen.isEmpty && back.curvesBlue.isEmpty)
    // Legacy payload without the new keys: identity curves.
    let legacy = #"{"exposure":25}"#.data(using: .utf8)!
    let old = try JSONDecoder().decode(AdjustRecipe.self, from: legacy)
    #expect(old.exposure == 25)
    #expect(old.curvesMaster.isEmpty && old.curvesRed.isEmpty)
    #expect(old.curvesGreen.isEmpty && old.curvesBlue.isEmpty)
    // Out-of-range stored points clamp on decode.
    let wild = #"{"curvesMaster":[{"x":2,"y":-1}]}"#.data(using: .utf8)!
    #expect(
      try JSONDecoder().decode(AdjustRecipe.self, from: wild).curvesMaster
        == [CurvePoint(x: 1, y: 0)])
  }

  @Test("[D2] Identity curves render pixel-identical (curves path is a no-op at defaults)")
  func curvesIdentityNoOp() {
    let renderer = EditRenderer()
    let src = fixtureImage()
    guard let plain = renderer.pixelHash(source: src, recipe: EditRecipe()),
      let identity = renderer.pixelHash(source: src, recipe: EditRecipe(adjust: AdjustRecipe()))
    else { return }
    #expect(identity == plain)
  }

  @Test("[D1] Non-default selective shift changes pixels")
  func selectiveChangePixels() {
    let renderer = EditRenderer()
    let red = CIImage(color: CIColor(red: 0.8, green: 0.1, blue: 0.1))
      .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
    guard let plain = renderer.pixelHash(source: red, recipe: EditRecipe()),
      let shifted = renderer.pixelHash(
        source: red,
        recipe: EditRecipe(adjust: AdjustRecipe(selRedSat: 100, selRedRange: 100)))
    else { return }
    #expect(shifted != plain)
  }

  @Test("[D1] Per-hue isolation: a red shift touches red pixels, spares blue ones")
  func selectivePerHueIsolation() {
    let renderer = EditRenderer()
    let red = CIImage(color: CIColor(red: 0.8, green: 0.1, blue: 0.1))
      .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
    let blue = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.8))
      .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
    let recipe = EditRecipe(adjust: AdjustRecipe(selRedLum: 100, selRedRange: 100))
    guard let redPlain = renderer.pixelHash(source: red, recipe: EditRecipe()),
      let redShifted = renderer.pixelHash(source: red, recipe: recipe),
      let bluePlain = renderer.pixelHash(source: blue, recipe: EditRecipe()),
      let blueShifted = renderer.pixelHash(source: blue, recipe: recipe)
    else { return }
    #expect(redShifted != redPlain)
    #expect(blueShifted == bluePlain)
  }

  // MARK: - Red-Eye (D4)

  @Test("[D4] Red-eye keys default to empty/off; clamping holds")
  func redEyeDefaults() {
    let a = AdjustRecipe()
    #expect(a.redEyeRegions.isEmpty && a.redEyeStrength == 0)
    #expect(AdjustRecipe(redEyeStrength: 500).redEyeStrength == 100)
    #expect(AdjustRecipe(redEyeStrength: -500).redEyeStrength == -100)
    let c = RedEyeRegion(x: 2, y: -1, radius: 9).clamped()
    #expect(c.x == 1 && c.y == 0 && c.radius == 0.25)
    let lo = RedEyeRegion(x: 0.5, y: 0.5, radius: 0).clamped()
    #expect(lo.radius == 0.01)
  }

  @Test("[D4] Red-eye keys round-trip; legacy payloads decode to empty/off")
  func redEyeCodable() throws {
    var a = AdjustRecipe()
    a.redEyeRegions = [
      RedEyeRegion(x: 0.3, y: 0.4), RedEyeRegion(x: 0.7, y: 0.35, radius: 0.06)
    ]
    a.redEyeStrength = 80
    let data = try JSONEncoder().encode(EditRecipe(adjust: a))
    let back = try JSONDecoder().decode(EditRecipe.self, from: data).adjust
    #expect(back.redEyeRegions == a.redEyeRegions)
    #expect(back.redEyeStrength == 80)
    // Legacy payload without the new keys: empty regions, strength off.
    let legacy = #"{"exposure":25}"#.data(using: .utf8)!
    let old = try JSONDecoder().decode(AdjustRecipe.self, from: legacy)
    #expect(old.exposure == 25)
    #expect(old.redEyeRegions.isEmpty && old.redEyeStrength == 0)
  }

  @Test("[D4] No regions renders pixel-identical (red-eye path is a no-op without taps)")
  func redEyeIdentityNoOp() {
    let renderer = EditRenderer()
    let src = fixtureImage()
    guard let plain = renderer.pixelHash(source: src, recipe: EditRecipe()),
      let armed = renderer.pixelHash(
        source: src, recipe: EditRecipe(adjust: AdjustRecipe(redEyeStrength: 100))),
      let tapped = renderer.pixelHash(
        source: src,
        recipe: EditRecipe(adjust: AdjustRecipe(
          redEyeRegions: [RedEyeRegion(x: 0.5, y: 0.5)], redEyeStrength: 0)))
    else { return }
    // Strength with no regions, and regions with strength off, both identity.
    #expect(armed == plain)
    #expect(tapped == plain)
  }

  @Test("[D4] Red-eye renders deterministically with regions placed")
  func redEyeDeterministic() {
    let renderer = EditRenderer()
    let src = fixtureImage()
    let recipe = EditRecipe(adjust: AdjustRecipe(
      redEyeRegions: [RedEyeRegion(x: 0.3, y: 0.4), RedEyeRegion(x: 0.7, y: 0.35)],
      redEyeStrength: 100))
    guard let first = renderer.pixelHash(source: src, recipe: recipe),
      let second = renderer.pixelHash(source: src, recipe: recipe)
    else { return }
    #expect(first == second)
  }

  @Test("[D4] Red-eye crop rects stay inside the frame")
  func redEyeCropMath() {
    let extent = CGRect(x: 0, y: 0, width: 100, height: 100)
    let center = EditRenderer.redEyeCropRect(extent, RedEyeRegion(x: 0.5, y: 0.5))
    #expect(extent.contains(center) && !center.isEmpty)
    // Corner taps clip against the frame instead of escaping it.
    let corner = EditRenderer.redEyeCropRect(extent, RedEyeRegion(x: 0, y: 0))
    #expect(!corner.isNull && !corner.isEmpty)
    #expect(extent.intersection(corner) == corner)
    // y flips: recipe origin is upper-left, CI extents lower-left.
    let top = EditRenderer.redEyeCropRect(extent, RedEyeRegion(x: 0.5, y: 0))
    let bottom = EditRenderer.redEyeCropRect(extent, RedEyeRegion(x: 0.5, y: 1))
    #expect(top.minY > bottom.minY)
  }

  @Test("[D4] Eye centroid maps face-relative landmarks to recipe space")
  func redEyeEyeMapping() {
    // Face box covering the middle of the frame; centroid at the face-box
    // center lands at the frame center; y flips (landmarks lower-left,
    // recipe upper-left).
    let face = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    let mid = EditRenderer.eyeRegion(centroidFaceX: 0.5, centroidFaceY: 0.5, faceBox: face)
    #expect(abs(mid.x - 0.5) < 1e-9 && abs(mid.y - 0.5) < 1e-9)
    let lowerLeft = EditRenderer.eyeRegion(centroidFaceX: 0, centroidFaceY: 0, faceBox: face)
    #expect(abs(lowerLeft.x - 0.25) < 1e-9 && abs(lowerLeft.y - 0.75) < 1e-9)
  }

  @Test("[D4] Faceless image suggests no regions (Vision negative path)")
  func redEyeNoFaces() async {
    let renderer = EditRenderer()
    let src = fixtureImage()
    guard let cg = renderer.cgImage(source: src, recipe: EditRecipe()) else { return }
    do {
      _ = try await renderer.suggestedRedEyeRegions(for: cg)
    } catch {
      #expect(error as? EditRenderError == .noFacesFound)
    }
  }

  @Test("[D2] Non-default master and per-channel curves change pixels")
  func curvesChangePixels() {
    let renderer = EditRenderer()
    let src = fixtureImage()
    guard let plain = renderer.pixelHash(source: src, recipe: EditRecipe()),
      let lifted = renderer.pixelHash(
        source: src,
        recipe: EditRecipe(adjust: AdjustRecipe(curvesMaster: [CurvePoint(x: 0.5, y: 0.9)]))),
      let redOnly = renderer.pixelHash(
        source: src,
        recipe: EditRecipe(adjust: AdjustRecipe(curvesRed: [CurvePoint(x: 0, y: 0.2)])))
    else { return }
    #expect(lifted != plain)
    #expect(redOnly != plain)
    #expect(redOnly != lifted)
  }

  // MARK: - E3 bronze exact-match (D1–D3, fixture-only, no GPU goldens)

  @Test("[E3] Degenerate levels range renders pixel-identical (inBlack == inWhite is identity)")
  func levelsDegenerateIdentity() {
    let renderer = EditRenderer()
    let src = fixtureImage()
    var degenerate = AdjustRecipe()
    degenerate.levelsInBlack = 50
    degenerate.levelsInWhite = 50
    guard let plain = renderer.pixelHash(source: src, recipe: EditRecipe()),
      let deg = renderer.pixelHash(source: src, recipe: EditRecipe(adjust: degenerate))
    else { return }
    #expect(deg == plain)
  }

  @Test("[E3] Empty curves + range-only selective + identity levels render pixel-identical")
  func emptyAdjustCombinedIdentity() {
    let renderer = EditRenderer()
    let src = fixtureImage()
    var a = AdjustRecipe()
    a.curvesMaster = []
    a.curvesRed = []
    a.curvesGreen = []
    a.curvesBlue = []
    // Range shapes a shift but never applies one: kernel stays gated off.
    a.selRedRange = 100
    a.selBlueRange = 100
    a.levelsInBlack = 0
    a.levelsInWhite = 100
    a.levelsOutBlack = 0
    a.levelsOutWhite = 100
    #expect(!a.isSelectiveActive)
    guard let plain = renderer.pixelHash(source: src, recipe: EditRecipe()),
      let combined = renderer.pixelHash(source: src, recipe: EditRecipe(adjust: a))
    else { return }
    #expect(combined == plain)
  }

  @Test("[E3] toneCurve resampling: point sets agreeing at the 5 CIToneCurve stops render identically")
  func toneCurveStopsExactMatch() {
    // Set A: one mid control point. Set B spells out the interpolated
    // quarter stops explicitly, so both configure the filter's 5 fixed
    // points (x = 0 / .25 / .5 / .75 / 1) identically. All values are
    // exactly representable in binary, so the two configurations agree
    // bit-for-bit (no 1-ulp wobble at the stops).
    let a = [CurvePoint(x: 0.5, y: 0.75)]
    let e25 = CurvePoint.evaluate(a, at: 0.25)
    let e75 = CurvePoint.evaluate(a, at: 0.75)
    #expect(abs(e25 - 0.375) < 1e-9)
    #expect(abs(e75 - 0.875) < 1e-9)
    let b = [
      CurvePoint(x: 0.25, y: e25), CurvePoint(x: 0.5, y: 0.75), CurvePoint(x: 0.75, y: e75)
    ]
    for x in [0.0, 0.25, 0.5, 0.75, 1.0] {
      #expect(abs(CurvePoint.evaluate(b, at: x) - CurvePoint.evaluate(a, at: x)) < 1e-9)
    }
    // Same 5-stop configuration -> bit-identical render, on both the master
    // path and the masked per-channel path.
    let renderer = EditRenderer()
    let src = fixtureImage()
    guard let plain = renderer.pixelHash(source: src, recipe: EditRecipe()),
      let masterA = renderer.pixelHash(
        source: src, recipe: EditRecipe(adjust: AdjustRecipe(curvesMaster: a))),
      let masterB = renderer.pixelHash(
        source: src, recipe: EditRecipe(adjust: AdjustRecipe(curvesMaster: b))),
      let redA = renderer.pixelHash(
        source: src, recipe: EditRecipe(adjust: AdjustRecipe(curvesRed: a))),
      let redB = renderer.pixelHash(
        source: src, recipe: EditRecipe(adjust: AdjustRecipe(curvesRed: b)))
    else { return }
    #expect(masterA == masterB)
    #expect(redA == redB)
    #expect(masterA != plain)
    #expect(redA != plain)
  }

  @Test("[E3] Selective kernel leaves black/white bit-identical at full shifts")
  func selectiveAchromaticEndpoints() {
    let renderer = EditRenderer()
    var a = AdjustRecipe()
    a.selRedHue = 100
    a.selRedSat = 100
    a.selRedLum = 100
    a.selRedRange = 100
    a.selGreenHue = -100
    a.selGreenSat = 100
    a.selGreenLum = -100
    a.selGreenRange = 100
    a.selBlueSat = 100
    a.selBlueLum = 100
    a.selBlueRange = 100
    #expect(a.isSelectiveActive)
    // 0 and 1 are fixed points of every colorspace round-trip, so the
    // achromatic guard holds bit-exactly here.
    for v in [0.0, 1.0] {
      let img = CIImage(color: CIColor(red: v, green: v, blue: v))
        .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
      guard let plain = renderer.pixelHash(source: img, recipe: EditRecipe()),
        let shifted = renderer.pixelHash(source: img, recipe: EditRecipe(adjust: a))
      else { return }
      #expect(shifted == plain)
    }
  }

  @Test("[E3] Selective kernel adds no chroma to mid-gray at full shifts")
  func selectiveAchromaticNoChroma() {
    let renderer = EditRenderer()
    let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
      .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
    var a = AdjustRecipe()
    a.selRedHue = 100
    a.selRedSat = 100
    a.selRedLum = 100
    a.selRedRange = 100
    a.selGreenHue = -100
    a.selGreenSat = 100
    a.selGreenLum = -100
    a.selGreenRange = 100
    a.selBlueHue = 50
    a.selBlueSat = 100
    a.selBlueLum = -100
    a.selBlueRange = 100
    #expect(a.isSelectiveActive)
    // Every output pixel must stay achromatic (R == G == B): selective
    // shifts may wobble luma by rounding, but must never tint gray.
    guard let cg = renderer.cgImage(source: gray, recipe: EditRecipe(adjust: a)),
      let data = cg.dataProvider?.data as Data?
    else { return }
    #expect(data.count % 4 == 0 && !data.isEmpty)
    for i in stride(from: 0, to: data.count, by: 4) {
      #expect(data[i] == data[i + 1] && data[i + 1] == data[i + 2])
    }
  }

  @Test("[E3] Selective single-hue isolation, second pair: yellow shift touches yellow, spares green")
  func selectiveYellowGreenIsolation() {
    let renderer = EditRenderer()
    let yellow = CIImage(color: CIColor(red: 0.8, green: 0.8, blue: 0.1))
      .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
    let green = CIImage(color: CIColor(red: 0.1, green: 0.8, blue: 0.1))
      .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
    let recipe = EditRecipe(adjust: AdjustRecipe(selYellowLum: 100, selYellowRange: 100))
    guard let yellowPlain = renderer.pixelHash(source: yellow, recipe: EditRecipe()),
      let yellowShifted = renderer.pixelHash(source: yellow, recipe: recipe),
      let greenPlain = renderer.pixelHash(source: green, recipe: EditRecipe()),
      let greenShifted = renderer.pixelHash(source: green, recipe: recipe)
    else { return }
    #expect(yellowShifted != yellowPlain)
    #expect(greenShifted == greenPlain)
  }

  @Test("Recipe KV key and payload format tag are pinned to v2 (legacy v1 retained)")
  func recipeKeyPinned() throws {
    #expect(EditRecipeKey.current == "fork.editRecipe.v2")
    #expect(EditRecipeKey.legacy == "fork.editRecipe.v1")
    let payload = EditPersistencePayload(sourceAssetId: "asset-1", recipe: sampleRecipe())
    let data = try JSONEncoder().encode(payload)
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(obj?["format"] as? String == "fork.editRecipe.v2")
    #expect(obj?["sourceAssetId"] as? String == "asset-1")
    #expect((obj?["recipe"] as? [String: Any]) != nil)
  }

  @Test("Empty recipe needs neither upstream edits nor a render")
  func emptyRecipeNeedsNothing() throws {
    let split = try EditSplitter.split(EditRecipe(), imageSize: CGSize(width: 4000, height: 3000))
    #expect(split.upstream.isEmpty)
    #expect(!split.needsClientRender)
    #expect(EditRecipe().isEmpty)
  }

  // MARK: - Upstream split

  @Test("Crop rect + quarter turn + flips map to upstream items with pixel params")
  func upstreamMapping() throws {
    let recipe = EditRecipe(crop: CropRecipe(
      rect: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
      quarterTurns: 3, flipHorizontal: true, flipVertical: true))
    let split = try EditSplitter.split(recipe, imageSize: CGSize(width: 4000, height: 3000))
    #expect(split.upstream.count == 4)
    #expect(!split.needsClientRender)
    let body = try EditSplitter.editsBody(split.upstream)
    let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let edits = obj?["edits"] as? [[String: Any]]
    #expect(edits?.count == 4)
    let crop = edits?.first { $0["action"] as? String == "crop" }
    let params = crop?["parameters"] as? [String: Any]
    #expect(params?["x"] as? Int == 1000)
    #expect(params?["y"] as? Int == 750)
    #expect(params?["width"] as? Int == 2000)
    #expect(params?["height"] as? Int == 1500)
    let rotate = edits?.first { $0["action"] as? String == "rotate" }
    #expect((rotate?["parameters"] as? [String: Any])?["angle"] as? Int == 270)
    let mirrors = edits?.filter { $0["action"] as? String == "mirror" }
    #expect(mirrors?.count == 2)
  }

  @Test("Straighten, perspective, adjust, style, portrait, markup, video force client render")
  func clientRenderTriggers() throws {
    let size = CGSize(width: 100, height: 100)
    #expect(try EditSplitter.split(
      EditRecipe(adjust: AdjustRecipe(exposure: 1)), imageSize: size).needsClientRender)
    #expect(try EditSplitter.split(
      EditRecipe(style: StyleRecipe(style: .mono)), imageSize: size).needsClientRender)
    #expect(try EditSplitter.split(
      EditRecipe(crop: CropRecipe(straightenDegrees: 2)), imageSize: size).needsClientRender)
    #expect(try EditSplitter.split(
      EditRecipe(crop: CropRecipe(perspectiveVertical: 10)), imageSize: size).needsClientRender)
    #expect(try EditSplitter.split(
      EditRecipe(portrait: PortraitRecipe()), imageSize: size).needsClientRender)
    #expect(try EditSplitter.split(
      EditRecipe(markup: MarkupRecipe(hasFlattenedInk: true)), imageSize: size).needsClientRender)
    #expect(try EditSplitter.split(
      EditRecipe(video: VideoRecipe(muted: true)), imageSize: size).needsClientRender)
    // Neutral style at 0 intensity does not force a render.
    #expect(!(try EditSplitter.split(
      EditRecipe(style: StyleRecipe(style: .vivid, intensity: 0)),
      imageSize: size).needsClientRender))
  }

  @Test("Degenerate crop rect throws instead of sending a server-rejected edit")
  func degenerateCrop() {
    let recipe = EditRecipe(crop: CropRecipe(rect: NormalizedRect(x: 0.5, y: 0.5, width: 0, height: 0)))
    #expect(throws: EditSplitError.degenerateCrop) {
      try EditSplitter.split(recipe, imageSize: CGSize(width: 100, height: 100))
    }
  }

  // MARK: - Render determinism

  private func fixtureImage() -> CIImage {
    CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.6))
      .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
  }

  @Test("[AP-05] Same recipe + same pixels render to the same hash (determinism)")
  func renderDeterministic() {
    let renderer = EditRenderer()
    let src = fixtureImage()
    let recipe = EditRecipe(
      adjust: AdjustRecipe(exposure: 30, contrast: 20, warmth: 15),
      style: StyleRecipe(style: .vivid, intensity: 60))
    // Nil = this machine cannot render (sandboxed builder without GPU); skip rather
    // than false-fail — the host verify tier runs these for real.
    guard let first = renderer.pixelHash(source: src, recipe: recipe),
      let second = renderer.pixelHash(source: src, recipe: recipe)
    else { return }
    #expect(first == second)
  }

  @Test("[AP-05] Empty recipe renders pixel-identical to the source; edits change pixels")
  func renderChangesPixels() {
    let renderer = EditRenderer()
    let src = fixtureImage()
    guard let plain = renderer.pixelHash(source: src, recipe: EditRecipe()),
      let edited = renderer.pixelHash(source: src, recipe: EditRecipe(adjust: AdjustRecipe(exposure: 100)))
    else { return }
    #expect(plain == renderer.pixelHash(source: src, recipe: EditRecipe()))
    #expect(edited != plain)
  }

  // MARK: - Undo/redo + copy/paste + revert

  @Test("Undo/redo walks the commit stack; equal commits are ignored")
  func undoRedo() {
    var h = EditHistory()
    #expect(!h.canUndo && !h.canRedo && !h.isDirty)
    h.commit(EditRecipe(adjust: AdjustRecipe(exposure: 10)))
    h.commit(EditRecipe(adjust: AdjustRecipe(exposure: 10))) // ignored
    #expect(!h.canRedo)
    h.commit(EditRecipe(adjust: AdjustRecipe(exposure: 20)))
    #expect(h.isDirty)
    h.undo()
    #expect(h.current.adjust.exposure == 10)
    #expect(h.canRedo)
    h.undo()
    #expect(h.current == EditRecipe())
    h.redo()
    #expect(h.current.adjust.exposure == 10)
    h.commit(EditRecipe(adjust: AdjustRecipe(exposure: 30))) // clears redo
    #expect(!h.canRedo)
  }

  @Test("Revert returns to the original empty recipe")
  func revert() {
    var h = EditHistory(initial: sampleRecipe())
    h.commit(EditRecipe(adjust: AdjustRecipe(exposure: 5)))
    h.revertToOriginal()
    #expect(h.current == EditRecipe())
  }

  @Test("Copy/paste round-trips between sessions; foreign payloads rejected")
  func copyPaste() throws {
    let h = EditHistory(initial: sampleRecipe())
    let data = try h.copiedData()
    var other = EditHistory()
    other.commit(try EditHistory.pastedRecipe(from: data))
    #expect(other.current == sampleRecipe())
    #expect(throws: EditHistoryError.incompatiblePaste) {
      try EditHistory.pastedRecipe(from: Data("{\"format\":\"other\",\"recipe\":{}}".utf8))
    }
  }

  // MARK: - Permission gating via Rules

  private func imageAsset(ownerId: String = "owner-1", spaceId: String? = "space-1") -> Asset {
    Asset(
      id: "asset-1", ownerId: ownerId, originalFileName: "a.heic", checksum: "c",
      type: .image, spaceId: spaceId)
  }

  @Test("Space member may edit; outsider may not; album membership never grants edit")
  func editGating() {
    let asset = imageAsset()
    let member = AccessContext(currentUserId: "editor-1", memberSpaceIds: ["space-1"])
    #expect(EditAccess.canEdit(asset, in: member))
    let outsider = AccessContext(currentUserId: "outsider")
    #expect(!EditAccess.canEdit(asset, in: outsider))
    #expect(throws: EditAccessError.notPermitted) {
      try EditAccess.requireEdit(asset, in: outsider)
    }
    let albumOnly = AccessContext(
      currentUserId: "album-member", memberAlbumIdsByAsset: [asset.id: ["album-1"]])
    #expect(!EditAccess.canEdit(asset, in: albumOnly))
  }

  // MARK: - Upload body

  @Test("Multipart body carries fork field names and the assetData file part")
  func multipartBody() {
    let (body, boundary) = RESTEditPersistence.multipartBody(
      fields: [("deviceAssetId", "x"), ("filename", "a-edited.jpg")],
      fileField: "assetData", filename: "a-edited.jpg", contentType: "image/jpeg",
      fileData: Data([1, 2, 3]), boundary: "test-boundary")
    let text = String(data: body, encoding: .utf8) ?? ""
    #expect(text.contains("name=\"deviceAssetId\""))
    #expect(text.contains("name=\"assetData\"; filename=\"a-edited.jpg\""))
    #expect(text.contains("Content-Type: image/jpeg"))
    #expect(text.hasSuffix("--test-boundary--\r\n"))
  }

  @Test("Edited filename keeps the base and appends -edited")
  func editedFilename() {
    #expect(RenderedUpload.editedFilename(for: "IMG_1234.heic", fileExtension: "jpg") == "IMG_1234-edited.jpg")
    #expect(RenderedUpload.editedFilename(for: "", fileExtension: "jpg") == "edited-edited.jpg")
  }

  // MARK: - Version store (D6a)

  @Test("[D6a] Done appends; beyond cap 10 the oldest are pruned in order")
  func versionCapPruneOrder() {
    var store = EditVersionStore()
    for i in 0..<12 {
      store.append(EditRecipe(adjust: AdjustRecipe(exposure: i)))
    }
    #expect(store.count == EditVersionStore.maxVersions)
    #expect(EditVersionStore.maxVersions == 10)
    // Oldest-first: exposures 0 and 1 pruned, 2...11 retained in order.
    #expect(store.versions.map(\.recipe.adjust.exposure) == Array(2..<12))
    #expect(store.latest?.recipe.adjust.exposure == 11)
  }

  @Test("[D6a] Tap-to-restore appends a new version, never overwrites")
  func versionRestoreAppends() {
    var store = EditVersionStore()
    store.append(EditRecipe(adjust: AdjustRecipe(exposure: 10)), id: "v1")
    store.append(EditRecipe(adjust: AdjustRecipe(exposure: 20)), id: "v2")
    let restored = store.restore(at: 0)
    #expect(restored == EditRecipe(adjust: AdjustRecipe(exposure: 10)))
    #expect(store.count == 3)
    // Prior versions untouched (same ids, same recipes, same order).
    #expect(store.versions[0].id == "v1")
    #expect(store.versions[1].id == "v2")
    #expect(store.versions[0].recipe.adjust.exposure == 10)
    #expect(store.versions[1].recipe.adjust.exposure == 20)
    // The restore is a NEW version carrying the old recipe.
    #expect(store.versions[2].recipe == EditRecipe(adjust: AdjustRecipe(exposure: 10)))
    #expect(store.versions[2].id != "v1")
    // Out-of-range restore leaves the stack untouched.
    #expect(store.restore(at: 99) == nil)
    #expect(store.count == 3)
    // Unknown id likewise.
    #expect(store.restore(id: "nope") == nil)
    #expect(store.count == 3)
  }

  @Test("[D6a] Old versions lacking newer keys decode with identity defaults")
  func versionBackCompatDecode() throws {
    // A v1-era persisted version: bare recipe with only `exposure`, no
    // levels keys, no recipeVersion/rendererVersion, no renderedAssetId.
    // Sibling D1–D4 keys land the same way (absent = neutral default).
    let legacy = #"{"id":"v1","savedAt":1234567890,"recipe":{"adjust":{"exposure":25}}}"#
      .data(using: .utf8)!
    let version = try JSONDecoder().decode(EditRecipeVersion.self, from: legacy)
    #expect(version.id == "v1")
    #expect(version.recipe.adjust.exposure == 25)
    #expect(version.renderedAssetId == nil)
    let adjust = version.recipe.adjust
    #expect(adjust.levelsInBlack == 0 && adjust.levelsInWhite == 100)
    #expect(adjust.levelsOutBlack == 0 && adjust.levelsOutWhite == 100)
    #expect(adjust.recipeVersion == 0 && adjust.rendererVersion == 0)
    #expect(adjust.cast == 0 && adjust.grain == 0 && adjust.wbTemperature == 0)
    // ... and renders identically to a fresh recipe with the same value.
    let renderer = EditRenderer()
    let src = fixtureImage()
    guard let old = renderer.pixelHash(source: src, recipe: version.recipe),
      let fresh = renderer.pixelHash(
        source: src, recipe: EditRecipe(adjust: AdjustRecipe(exposure: 25)))
    else { return }
    #expect(old == fresh)
  }

  @Test("[D6a] Version stack round-trips; payload missing versions decodes empty")
  func versionStoreCodable() throws {
    var store = EditVersionStore()
    store.append(EditRecipe(adjust: AdjustRecipe(exposure: 7)), id: "a")
    let payload = EditVersionPayload(sourceAssetId: "asset-1", versions: store.versions)
    #expect(payload.format == EditVersionKey.current)
    #expect(EditVersionKey.current == "fork.editVersions.v2")
    #expect(EditVersionKey.legacy == "fork.editVersions.v1")
    #expect(EditVersionKey.current != EditRecipeKey.current)
    let data = try JSONEncoder().encode(payload)
    let back = try JSONDecoder().decode(EditVersionPayload.self, from: data)
    #expect(back == payload)
    // Pre-D6a payload without the versions key: empty stack, not an error.
    let bare = #"{"format":"fork.editVersions.v2","sourceAssetId":"asset-1"}"#
      .data(using: .utf8)!
    let empty = try JSONDecoder().decode(EditVersionPayload.self, from: bare)
    #expect(empty.versions.isEmpty)
    let bareStore = try JSONDecoder().decode(EditVersionStore.self, from: "{}".data(using: .utf8)!)
    #expect(bareStore.isEmpty)
  }

  // MARK: - E1 recipe v2 + rendition (stubbed server)

  private func e1Persistence(host: String) -> RESTEditPersistence {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [E1StubURLProtocol.self]
    return RESTEditPersistence(
      serverURL: URL(string: "https://\(host)/api")!,
      token: { "stub-token" },
      session: URLSession(configuration: config))
  }

  private func e1MetadataURL(host: String, assetId: String, key: String) -> String {
    let base = URL(string: "https://\(host)/api")!
    let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
    return base.appendingPathComponent("assets/\(assetId)/metadata/\(encoded)").absoluteString
  }

  private func e1EntryResponse(payloadJSON: String) -> Data {
    Data(#"{"value":\#(payloadJSON)}"#.utf8)
  }

  private func e1Fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(
      forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try #require(String(data: Data(contentsOf: url), encoding: .utf8))
  }

  private func e1GoldenBaseRecipe() throws -> EditRecipe {
    let url = try #require(Bundle.module.url(
      forResource: "edit-recipe-base-v1", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(EditRecipe.self, from: Data(contentsOf: url))
  }

  @Test("E1: fetchRecipe prefers v2 and never touches the v1 key")
  func recipeDualReadPrefersV2() async throws {
    let host = "e1prefer.e1stub.invalid"
    let persistence = e1Persistence(host: host)
    let v2 = e1MetadataURL(host: host, assetId: "a1", key: EditRecipeKey.current)
    E1StubURLProtocol.route(
      method: "GET", url: v2, status: 200,
      body: e1EntryResponse(payloadJSON: """
        {"format":"fork.editRecipe.v2","sourceAssetId":"a1","savedAt":1700000000,\
        "recipe":{"adjust":{"exposure":50}}}
        """))
    let fetched = try await persistence.fetchRecipe(assetId: "a1")
    #expect(fetched?.recipe.adjust.exposure == 50)
    #expect(fetched?.format == EditRecipeKey.current)
    let seen = E1StubURLProtocol.requests(host: host)
    #expect(seen.map { $0.request.url?.absoluteString } == [v2])
  }

  @Test("E1: fetchRecipe falls back to v1 with identity defaults, normalized to v2")
  func recipeDualReadFallsBackToV1() async throws {
    let host = "e1fallback.e1stub.invalid"
    let persistence = e1Persistence(host: host)
    let v2 = e1MetadataURL(host: host, assetId: "asset-1", key: EditRecipeKey.current)
    let v1 = e1MetadataURL(host: host, assetId: "asset-1", key: EditRecipeKey.legacy)
    // No v2 route: the v2 GET 404s and the reader falls back to the v1 envelope fixture.
    E1StubURLProtocol.route(
      method: "GET", url: v1, status: 200,
      body: e1EntryResponse(payloadJSON: try e1Fixture("edit-recipe-kv-v1")))
    let fetched = try await persistence.fetchRecipe(assetId: "asset-1")
    // Normalized to the v2 tag in memory; the recipe decodes identically to the golden base.
    #expect(fetched?.format == EditRecipeKey.current)
    #expect(fetched?.recipe == (try e1GoldenBaseRecipe()))
    #expect(fetched?.recipe.adjust.exposure == 25)
    #expect(fetched?.recipe.style?.style == .vividWarm)
    let seen = E1StubURLProtocol.requests(host: host)
    #expect(seen.map { $0.request.url?.absoluteString } == [v2, v1])
  }

  @Test("E1: fetchRecipe returns nil when both keys are absent")
  func recipeDualReadBothAbsent() async throws {
    let host = "e1absent.e1stub.invalid"
    let persistence = e1Persistence(host: host)
    #expect(try await persistence.fetchRecipe(assetId: "a1") == nil)
    #expect(E1StubURLProtocol.requests(host: host).count == 2)
  }

  @Test("E1: saveRecipe writes v2 only and deletes v1")
  func recipeSaveWritesV2DeletesV1() async throws {
    let host = "e1save.e1stub.invalid"
    let persistence = e1Persistence(host: host)
    let base = URL(string: "https://\(host)/api")!
    E1StubURLProtocol.route(
      method: "PUT",
      url: base.appendingPathComponent("assets/a1/metadata").absoluteString,
      status: 200, body: Data("{}".utf8))
    E1StubURLProtocol.route(
      method: "DELETE",
      url: e1MetadataURL(host: host, assetId: "a1", key: EditRecipeKey.legacy),
      status: 200, body: Data("{}".utf8))
    try await persistence.saveRecipe(EditPersistencePayload(
      sourceAssetId: "a1", recipe: sampleRecipe()))
    let seen = E1StubURLProtocol.requests(host: host)
    #expect(seen.count == 2)
    let put = try #require(seen.first { $0.request.httpMethod == "PUT" })
    let putObj = try JSONSerialization.jsonObject(with: put.body) as? [String: Any]
    let items = putObj?["items"] as? [[String: Any]]
    #expect(items?.count == 1)
    #expect(items?.first?["key"] as? String == "fork.editRecipe.v2")
    #expect((items?.first?["value"] as? [String: Any])?["format"] as? String == "fork.editRecipe.v2")
    let delete = try #require(seen.first { $0.request.httpMethod == "DELETE" })
    #expect(delete.request.url?.absoluteString.contains("fork.editRecipe.v1") == true)
  }

  @Test("E1: saveRecipe still succeeds when the v1 cleanup delete fails")
  func recipeSaveToleratesV1DeleteFailure() async throws {
    let host = "e1savetolerant.e1stub.invalid"
    let persistence = e1Persistence(host: host)
    let base = URL(string: "https://\(host)/api")!
    E1StubURLProtocol.route(
      method: "PUT",
      url: base.appendingPathComponent("assets/a1/metadata").absoluteString,
      status: 200, body: Data("{}".utf8))
    // No DELETE route: the cleanup delete 404s, which the save tolerates.
    try await persistence.saveRecipe(EditPersistencePayload(
      sourceAssetId: "a1", recipe: sampleRecipe()))
  }

  @Test("E1: fetchVersions falls back to v1, normalized to v2")
  func versionsDualReadFallsBackToV1() async throws {
    let host = "e1versions.e1stub.invalid"
    let persistence = e1Persistence(host: host)
    let v2 = e1MetadataURL(host: host, assetId: "asset-1", key: EditVersionKey.current)
    let v1 = e1MetadataURL(host: host, assetId: "asset-1", key: EditVersionKey.legacy)
    E1StubURLProtocol.route(
      method: "GET", url: v1, status: 200,
      body: e1EntryResponse(payloadJSON: try e1Fixture("edit-versions-kv-v1")))
    let fetched = try await persistence.fetchVersions(assetId: "asset-1")
    #expect(fetched?.format == EditVersionKey.current)
    #expect(fetched?.versions.count == 1)
    #expect(fetched?.versions.first?.id == "v1")
    #expect(fetched?.versions.first?.recipe == (try e1GoldenBaseRecipe()))
    let seen = E1StubURLProtocol.requests(host: host)
    #expect(seen.map { $0.request.url?.absoluteString } == [v2, v1])
  }

  @Test("E1: saveVersions writes v2 only and deletes v1")
  func versionsSaveWritesV2DeletesV1() async throws {
    let host = "e1vsave.e1stub.invalid"
    let persistence = e1Persistence(host: host)
    let base = URL(string: "https://\(host)/api")!
    E1StubURLProtocol.route(
      method: "PUT",
      url: base.appendingPathComponent("assets/a1/metadata").absoluteString,
      status: 200, body: Data("{}".utf8))
    E1StubURLProtocol.route(
      method: "DELETE",
      url: e1MetadataURL(host: host, assetId: "a1", key: EditVersionKey.legacy),
      status: 200, body: Data("{}".utf8))
    var store = EditVersionStore()
    store.append(EditRecipe(adjust: AdjustRecipe(exposure: 7)), id: "a")
    try await persistence.saveVersions(EditVersionPayload(
      sourceAssetId: "a1", versions: store.versions))
    let seen = E1StubURLProtocol.requests(host: host)
    let put = try #require(seen.first { $0.request.httpMethod == "PUT" })
    let putObj = try JSONSerialization.jsonObject(with: put.body) as? [String: Any]
    let items = putObj?["items"] as? [[String: Any]]
    #expect(items?.first?["key"] as? String == "fork.editVersions.v2")
    #expect((items?.first?["value"] as? [String: Any])?["format"] as? String == "fork.editVersions.v2")
    let delete = try #require(seen.first { $0.request.httpMethod == "DELETE" })
    #expect(delete.request.url?.absoluteString.contains("fork.editVersions.v1") == true)
  }

  @Test("E1: copy/paste tag moves to v2; v1 and foreign payloads are rejected")
  func copyPasteTagMovesToV2() throws {
    let h = EditHistory(initial: sampleRecipe())
    let data = try h.copiedData()
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(obj?["format"] as? String == "fork.editRecipe.v2")
    var other = EditHistory()
    other.commit(try EditHistory.pastedRecipe(from: data))
    #expect(other.current == sampleRecipe())
    #expect(throws: EditHistoryError.incompatiblePaste) {
      try EditHistory.pastedRecipe(from: Data(
        #"{"format":"fork.editRecipe.v1","recipe":{"adjust":{"exposure":1}}}"#.utf8))
    }
    #expect(throws: EditHistoryError.incompatiblePaste) {
      try EditHistory.pastedRecipe(from: Data("{\"format\":\"other\",\"recipe\":{}}".utf8))
    }
  }

  @Test("E1: v1 KV envelopes decode identically under the v2 reader")
  func v1EnvelopesBackCompat() throws {
    let recipePayload = try JSONDecoder().decode(
      EditPersistencePayload.self, from: Data((try e1Fixture("edit-recipe-kv-v1")).utf8))
    #expect(recipePayload.recipe == (try e1GoldenBaseRecipe()))
    let versionsPayload = try JSONDecoder().decode(
      EditVersionPayload.self, from: Data((try e1Fixture("edit-versions-kv-v1")).utf8))
    #expect(versionsPayload.versions.count == 1)
    #expect(versionsPayload.versions.first?.recipe == (try e1GoldenBaseRecipe()))
  }

  @Test("E1: rendition body carries the assetData file part like the asset upload path")
  func renditionMultipartBody() {
    let upload = RenderedUpload(
      data: Data([1, 2, 3]), filename: "a-edited.jpg", contentType: "image/jpeg",
      fileCreatedAt: Date(), fileModifiedAt: Date())
    let (body, boundary) = RESTEditPersistence.renditionBody(upload: upload, boundary: "test-boundary")
    let text = String(data: body, encoding: .utf8) ?? ""
    #expect(text.contains("name=\"filename\""))
    #expect(text.contains("name=\"assetData\"; filename=\"a-edited.jpg\""))
    #expect(text.contains("Content-Type: image/jpeg"))
    #expect(text.hasSuffix("--test-boundary--\r\n"))
    #expect(boundary == "test-boundary")
  }

  @Test("E1: uploadRendition PUTs multipart to assets/:id/rendition")
  func renditionPutContract() async throws {
    let host = "e1rendition.e1stub.invalid"
    let persistence = e1Persistence(host: host)
    let base = URL(string: "https://\(host)/api")!
    let renditionURL = base.appendingPathComponent("assets/a1/rendition").absoluteString
    // The server answers the asset DTO; the client only needs a 2xx.
    E1StubURLProtocol.route(
      method: "PUT", url: renditionURL, status: 200,
      body: Data(#"{"id":"a1"}"#.utf8))
    try await persistence.uploadRendition(
      assetId: "a1",
      upload: RenderedUpload(
        data: Data([1, 2, 3]), filename: "a-edited.jpg", contentType: "image/jpeg",
        fileCreatedAt: Date(), fileModifiedAt: Date()))
    let seen = E1StubURLProtocol.requests(host: host)
    #expect(seen.count == 1)
    #expect(seen[0].request.httpMethod == "PUT")
    #expect(seen[0].request.url?.absoluteString == renditionURL)
    #expect(seen[0].request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
    let text = String(data: seen[0].body, encoding: .utf8) ?? ""
    #expect(text.contains("name=\"assetData\"; filename=\"a-edited.jpg\""))
  }
}

/// Stubbed metadata/rendition server for the E1 tests: routes are keyed by
/// "METHOD absolute-URL" and every request is recorded with its drained body.
/// Each test mints its own host, so parallel tests never share routes and no
/// reset is needed (filter recordings by host).
private final class E1StubURLProtocol: URLProtocol {
  struct Recorded {
    var request: URLRequest
    var body: Data
  }

  private static let lock = NSLock()
  private nonisolated(unsafe) static var routes: [String: (status: Int, body: Data)] = [:]
  private nonisolated(unsafe) static var seen: [Recorded] = []

  static func route(method: String, url: String, status: Int, body: Data = Data()) {
    lock.withLock { routes["\(method) \(url)"] = (status, body) }
  }

  static func requests(host: String) -> [Recorded] {
    lock.withLock { seen.filter { $0.request.url?.host == host } }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host?.hasSuffix(".e1stub.invalid") == true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let body = Self.drain(request)
    let key = "\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")"
    let route = Self.lock.withLock { Self.routes[key] }
    Self.lock.withLock { Self.seen.append(Recorded(request: request, body: body)) }
    let (status, payload) = route ?? (404, Data())
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Length": "\(payload.count)"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: payload)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  /// `URLSession.upload(for:from:)` hands the body over as a stream, so drain it here.
  private static func drain(_ request: URLRequest) -> Data {
    if let direct = request.httpBody, !direct.isEmpty { return direct }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var out = Data()
    let capacity = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let count = stream.read(buffer, maxLength: capacity)
      if count <= 0 { break }
      out.append(buffer, count: count)
    }
    return out
  }
}
