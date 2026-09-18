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

  @Test("Recipe KV key and payload format tag are pinned")
  func recipeKeyPinned() throws {
    #expect(EditRecipeKey.current == "fork.editRecipe.v1")
    let payload = EditPersistencePayload(sourceAssetId: "asset-1", recipe: sampleRecipe())
    let data = try JSONEncoder().encode(payload)
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(obj?["format"] as? String == "fork.editRecipe.v1")
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
    #expect(EditVersionKey.current == "fork.editVersions.v1")
    #expect(EditVersionKey.current != EditRecipeKey.current)
    let data = try JSONEncoder().encode(payload)
    let back = try JSONDecoder().decode(EditVersionPayload.self, from: data)
    #expect(back == payload)
    // Pre-D6a payload without the versions key: empty stack, not an error.
    let bare = #"{"format":"fork.editVersions.v1","sourceAssetId":"asset-1"}"#
      .data(using: .utf8)!
    let empty = try JSONDecoder().decode(EditVersionPayload.self, from: bare)
    #expect(empty.versions.isEmpty)
    let bareStore = try JSONDecoder().decode(EditVersionStore.self, from: "{}".data(using: .utf8)!)
    #expect(bareStore.isEmpty)
  }
}
