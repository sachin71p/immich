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
}
