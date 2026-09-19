import AppKit
import AVFoundation
import CoreImage
import CoreModel
import Editing
import Rules
import SwiftUI

/// A8 macOS edit mode (brief UIs): preview canvas plus a right-hand tool panel (Adjust
/// sections with disclosure + sliders, Filters, Crop, Portrait, Markup, Video).
/// Keyboard: Undo ⌘Z, Redo ⇧⌘Z, Done ⌘S, Cancel Esc, tool tabs ⌘1…⌘6.
///
/// Same decoupling as iOS `EditView`: the caller supplies the preview image and the source
/// loader; Done persists through `EditPersistence` (upstream `/edits` + recipe KV +
/// full-res render PUT as the asset's rendition). Markup here is our own vector model (`MacMarkupCanvas`
/// + `MacMarkupElement`), so it round-trips through the recipe — unlike iOS PencilKit ink,
/// which only flattens into the render.
public struct MacEditView: View {
  var asset: Asset
  var access: AccessContext
  var preview: NSImage
  var loadOriginalData: () async throws -> Data
  var loadVideoFile: (() async throws -> URL)?
  var persistence: RESTEditPersistence
  var onDone: (String?) -> Void

  @State private var history = EditHistory()
  @State private var tool: MacEditTool = .adjust
  @State private var renderedPreview: NSImage
  @State private var comparing = false
  @State private var saving = false
  @State private var saveError: String?
  @State private var videoDuration: Double?
  @State private var markupTool: MacMarkupTool = .pen
  @State private var markupColorHex = "#FFCC00"
  @State private var markupWidth: Double = 4
  @State private var markupText = "Caption"
  @State private var elements: [MacMarkupElement] = []
  @State private var hasLoadedRecipe = false
  @State private var showDiscardConfirm = false
  @Environment(\.dismiss) private var dismiss

  private let renderer = EditRenderer()

  public init(
    asset: Asset, access: AccessContext, preview: NSImage,
    loadOriginalData: @escaping () async throws -> Data,
    loadVideoFile: (() async throws -> URL)? = nil,
    persistence: RESTEditPersistence,
    onDone: @escaping (String?) -> Void = { _ in }
  ) {
    self.asset = asset
    self.access = access
    self.preview = preview
    self.loadOriginalData = loadOriginalData
    self.loadVideoFile = loadVideoFile
    self.persistence = persistence
    self.onDone = onDone
    self._renderedPreview = State(initialValue: preview)
  }

  public var body: some View {
    HSplitView {
      canvasArea
        .frame(minWidth: 480, minHeight: 400)
      toolPanel
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
    }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        // WP-E E1: Escape = Cancel, with a discard confirm when dirty.
        Button("Cancel") { history.isDirty ? showDiscardConfirm = true : dismiss() }
          .disabled(saving).keyboardShortcut(.cancelAction)
      }
      ToolbarItemGroup {
        Button { history.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
          .disabled(!history.canUndo).keyboardShortcut("z", modifiers: .command)
        Button { history.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
          .disabled(!history.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
        Menu {
          Button("Copy edits") { copyEdits() }
          Button("Paste edits") { pasteEdits() }
          Button("Revert to original", role: .destructive) { revertAll() }
        } label: { Label("More", systemImage: "ellipsis.circle") }
      }
      ToolbarItem(placement: .primaryAction) {
        Button("Done") { save() }.bold()
          .disabled(saving || !history.isDirty)
          .keyboardShortcut("s", modifiers: .command)
      }
    }
    .overlay { if saving { savingOverlay } }
    .alert("Save failed", isPresented: Binding(
      get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    ) {
      Button("OK") { saveError = nil }
    } message: {
      Text(saveError ?? "")
    }
    .alert("Discard changes?", isPresented: $showDiscardConfirm) {
      Button("Discard", role: .destructive) { dismiss() }
      Button("Keep editing", role: .cancel) {}
    } message: {
      Text("Your edits have not been saved.")
    }
    .task { await initialLoad() }
    .onChange(of: history.current) { _, _ in rerenderPreview() }
    .onChange(of: elements) { _, _ in syncMarkupRecipe() }
  }

  // MARK: - Canvas

  private var canvasArea: some View {
    GeometryReader { geo in
      let fit = macFit(image: preview.size, in: geo.size)
      ZStack {
        Color.black
        Image(nsImage: comparing ? preview : renderedPreview)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: fit.width, height: fit.height)
        if tool == .markup {
          MacMarkupCanvas(
            elements: $elements, markupTool: markupTool, colorHex: markupColorHex,
            width: markupWidth, text: markupText)
          .frame(width: fit.width, height: fit.height)
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .contentShape(Rectangle())
      .simultaneousGesture(DragGesture(minimumDistance: 0)
        .onChanged { _ in if tool != .markup { comparing = true } }
        .onEnded { g in
          comparing = false
          if tool == .portrait, history.current.portrait != nil {
            // Drag end location is in the outer space; map into the fit frame.
            let ox = (geo.size.width - fit.width) / 2
            let oy = (geo.size.height - fit.height) / 2
            let px = (g.location.x - ox) / fit.width
            let py = (g.location.y - oy) / fit.height
            guard (0...1).contains(px), (0...1).contains(py) else { return }
            var r = history.current
            var po = r.portrait ?? PortraitRecipe()
            po.focus = NormalizedPoint(x: Double(px), y: Double(py))
            r.portrait = po
            history.commit(r)
          }
        })
    }
  }

  // MARK: - Tool panel

  private var toolPanel: some View {
    VStack(spacing: 0) {
      Picker("Tool", selection: $tool) {
        ForEach(MacEditTool.available(for: asset), id: \.self) { t in
          Text(t.title).tag(t)
        }
      }
      .pickerStyle(.segmented)
      .padding(8)
      ScrollView {
        switch tool {
        case .adjust: adjustPanel
        case .filters: filtersPanel
        case .crop: cropPanel
        case .portrait: portraitPanel
        case .markup: markupPanel
        case .video: videoPanel
        }
      }
    }
  }

  // MARK: Adjust

  private var adjustPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle("Auto enhance", isOn: Binding(
        get: { history.current.adjust.autoEnhance },
        set: { v in var r = history.current; r.adjust.autoEnhance = v; history.commit(r) }))
      DisclosureGroup("Light") {
        adjustSlider(.exposure, "Exposure")
        adjustSlider(.brilliance, "Brilliance")
        adjustSlider(.highlights, "Highlights")
        adjustSlider(.shadows, "Shadows")
        adjustSlider(.contrast, "Contrast")
        adjustSlider(.brightness, "Brightness")
        adjustSlider(.blackPoint, "Black point")
      }
      DisclosureGroup("Color") {
        adjustSlider(.saturation, "Saturation")
        adjustSlider(.vibrance, "Vibrance")
        adjustSlider(.warmth, "Warmth")
        adjustSlider(.tint, "Tint")
      }
      DisclosureGroup("Detail") {
        adjustSlider(.sharpness, "Sharpness")
        adjustSlider(.definition, "Definition")
        adjustSlider(.noiseReduction, "Noise reduction")
        adjustSlider(.vignette, "Vignette")
      }
    }
    .padding(8)
  }

  private func adjustSlider(_ param: MacAdjustParam, _ title: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title).font(.caption)
        Spacer()
        Text("\(macAdjustValue(param))").font(.caption).monospacedDigit()
      }
      Slider(
        value: Binding(
          get: { Double(macAdjustValue(param)) },
          set: { v in macSetAdjust(param, Int(v.rounded())) }),
        in: -100...100)
    }
  }

  private func macAdjustValue(_ p: MacAdjustParam) -> Int {
    let a = history.current.adjust
    switch p {
    case .exposure: return a.exposure
    case .brilliance: return a.brilliance
    case .highlights: return a.highlights
    case .shadows: return a.shadows
    case .contrast: return a.contrast
    case .brightness: return a.brightness
    case .blackPoint: return a.blackPoint
    case .saturation: return a.saturation
    case .vibrance: return a.vibrance
    case .warmth: return a.warmth
    case .tint: return a.tint
    case .sharpness: return a.sharpness
    case .definition: return a.definition
    case .noiseReduction: return a.noiseReduction
    case .vignette: return a.vignette
    }
  }

  private func macSetAdjust(_ p: MacAdjustParam, _ v: Int) {
    var r = history.current
    var a = r.adjust
    switch p {
    case .exposure: a.exposure = v
    case .brilliance: a.brilliance = v
    case .highlights: a.highlights = v
    case .shadows: a.shadows = v
    case .contrast: a.contrast = v
    case .brightness: a.brightness = v
    case .blackPoint: a.blackPoint = v
    case .saturation: a.saturation = v
    case .vibrance: a.vibrance = v
    case .warmth: a.warmth = v
    case .tint: a.tint = v
    case .sharpness: a.sharpness = v
    case .definition: a.definition = v
    case .noiseReduction: a.noiseReduction = v
    case .vignette: a.vignette = v
    }
    r.adjust = a
    history.commit(r)
  }

  // MARK: Filters

  private var filtersPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))]) {
        ForEach(EditStyle.allCases, id: \.self) { style in
          Button {
            var r = history.current
            r.style = style == .none ? nil : StyleRecipe(style: style, intensity: r.style?.intensity ?? 100)
            history.commit(r)
          } label: {
            VStack {
              macFilterThumb(style)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                  RoundedRectangle(cornerRadius: 8)
                    .stroke(history.current.style?.style == style ? .yellow : .clear, lineWidth: 2))
              Text(style.displayName).font(.caption2)
            }
          }
          .buttonStyle(.plain)
        }
      }
      HStack {
        Text("Intensity").font(.caption)
        Slider(
          value: Binding(
            get: { Double(history.current.style?.intensity ?? 100) },
            set: { v in
              var r = history.current
              let name = r.style?.style ?? .vivid
              r.style = StyleRecipe(style: name, intensity: Int(v))
              history.commit(r)
            }), in: 0...100)
      }
    }
    .padding(8)
  }

  private func macFilterThumb(_ style: EditStyle) -> some View {
    Group {
      if style == .none {
        Image(nsImage: preview).resizable()
      } else if let cg = macThumbCG(style) {
        Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: 64, height: 64))).resizable()
      } else {
        Image(nsImage: preview).resizable()
      }
    }
  }

  private func macThumbCG(_ style: EditStyle) -> CGImage? {
    guard let tiff = preview.tiffRepresentation, let ci = CIImage(data: tiff) else { return nil }
    let recipe = EditRecipe(style: StyleRecipe(style: style, intensity: 100))
    return renderer.cgImage(source: ci, recipe: recipe, previewMaxPixel: 128)
  }

  // MARK: Crop

  private var cropPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Aspect").font(.caption).foregroundStyle(.secondary)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))]) {
        ForEach(CropAspect.allCases, id: \.self) { aspect in
          Button(aspect == .free ? "Free" : aspect.rawValue) { macApplyAspect(aspect) }
            .buttonStyle(.bordered)
            .tint(history.current.crop?.aspect == aspect ? .yellow : .gray)
        }
      }
      HStack {
        Text("Straighten").font(.caption)
        Slider(
          value: Binding(
            get: { history.current.crop?.straightenDegrees ?? 0 },
            set: { v in
              var r = history.current
              var c = r.crop ?? CropRecipe()
              c.straightenDegrees = v
              r.crop = c
              history.commit(r)
            }), in: -45...45)
      }
      HStack {
        Button("Rotate 90°") { macBumpTurns() }
        Button("Flip H") { macToggleFlip(horizontal: true) }
        Button("Flip V") { macToggleFlip(horizontal: false) }
      }
      .buttonStyle(.bordered)
      HStack {
        Button("Auto-straighten") { Task { await macAutoStraighten() } }
        Button("Reset crop", role: .destructive) {
          var r = history.current
          r.crop = nil
          history.commit(r)
        }
      }
      .buttonStyle(.bordered)
      HStack {
        Text("V-keystone").font(.caption)
        Stepper(
          "\(history.current.crop?.perspectiveVertical ?? 0)",
          value: Binding(
            get: { history.current.crop?.perspectiveVertical ?? 0 },
            set: { v in macSetKeystone(vertical: true, value: v) }),
          in: -100...100)
      }
      HStack {
        Text("H-keystone").font(.caption)
        Stepper(
          "\(history.current.crop?.perspectiveHorizontal ?? 0)",
          value: Binding(
            get: { history.current.crop?.perspectiveHorizontal ?? 0 },
            set: { v in macSetKeystone(vertical: false, value: v) }),
          in: -100...100)
      }
    }
    .padding(8)
  }

  private func macApplyAspect(_ aspect: CropAspect) {
    var r = history.current
    var c = r.crop ?? CropRecipe()
    c.aspect = aspect
    if let ratio = aspect.ratio {
      let w: Double
      let h: Double
      if ratio >= 1 { w = 0.9; h = 0.9 / ratio } else { h = 0.9; w = 0.9 * ratio }
      c.rect = NormalizedRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    } else if aspect == .free {
      c.rect = nil
    }
    r.crop = c
    history.commit(r)
  }

  private func macBumpTurns() {
    var r = history.current
    var c = r.crop ?? CropRecipe()
    c.quarterTurns = (c.quarterTurns + 1) % 4
    r.crop = c
    history.commit(r)
  }

  private func macToggleFlip(horizontal: Bool) {
    var r = history.current
    var c = r.crop ?? CropRecipe()
    if horizontal { c.flipHorizontal.toggle() } else { c.flipVertical.toggle() }
    r.crop = c
    history.commit(r)
  }

  private func macSetKeystone(vertical: Bool, value: Int) {
    var r = history.current
    var c = r.crop ?? CropRecipe()
    if vertical { c.perspectiveVertical = value } else { c.perspectiveHorizontal = value }
    r.crop = c
    history.commit(r)
  }

  private func macAutoStraighten() async {
    guard let tiff = preview.tiffRepresentation,
      let cg = CIImage(data: tiff).flatMap({ renderer.cgImage(source: $0, recipe: EditRecipe()) })
    else { return }
    do {
      let angle = try await renderer.suggestedStraightenAngle(for: cg)
      var r = history.current
      var c = r.crop ?? CropRecipe()
      c.straightenDegrees = min(45, max(-45, angle))
      r.crop = c
      history.commit(r)
    } catch {
      saveError = "No horizon found — straighten manually."
    }
  }

  // MARK: Portrait

  private var portraitPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      if macPortraitAvailable {
        Toggle("Portrait depth blur", isOn: Binding(
          get: { history.current.portrait != nil },
          set: { on in
            var r = history.current
            r.portrait = on ? (r.portrait ?? PortraitRecipe()) : nil
            history.commit(r)
          }))
        HStack {
          Text("Aperture").font(.caption)
          Slider(
            value: Binding(
              get: { history.current.portrait?.aperture ?? 2.8 },
              set: { v in
                var r = history.current
                var po = r.portrait ?? PortraitRecipe()
                po.aperture = v
                r.portrait = po
                history.commit(r)
              }), in: 1.4...16)
          Text(String(format: "ƒ/%.1f", history.current.portrait?.aperture ?? 2.8))
            .font(.caption).monospacedDigit()
        }
        Text("Click the preview to move the focus point.")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("No depth data in this photo — Portrait is unavailable.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(8)
  }

  private var macPortraitAvailable: Bool {
    guard let tiff = preview.tiffRepresentation, let ci = CIImage(data: tiff) else { return false }
    return EditRenderer.portraitAvailable(source: ci)
  }

  // MARK: Markup

  private var markupPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Tool").font(.caption).foregroundStyle(.secondary)
      Picker("Markup tool", selection: $markupTool) {
        ForEach(MacMarkupTool.allCases, id: \.self) { t in Text(t.title).tag(t) }
      }
      .pickerStyle(.segmented)
      // WP-E E1 clip fix: keep intrinsic sizes in the 280–340 pt panel at 1280×800.
      .fixedSize(horizontal: false, vertical: true)
      .frame(minWidth: 260)
      HStack {
        Text("Color").font(.caption)
        ForEach(["#FFCC00", "#FF3B30", "#0A84FF", "#30D158", "#FFFFFF", "#000000"], id: \.self) { hex in
          Button {
            markupColorHex = hex
          } label: {
            Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
              .overlay(Circle().stroke(markupColorHex == hex ? .yellow : .gray))
          }
          .buttonStyle(.plain)
        }
      }
      .frame(minWidth: 260)
      HStack {
        Text("Width").font(.caption)
        Slider(value: $markupWidth, in: 1...20)
        Text("\(Int(markupWidth))").font(.caption).monospacedDigit()
      }
      .frame(minWidth: 260)
      if markupTool == .text {
        TextField("Caption", text: $markupText)
          .textFieldStyle(.roundedBorder)
      }
      Text("Click-drag on the preview to draw. Vector markup is stored in the recipe.")
        .font(.caption).foregroundStyle(.secondary)
      Button("Clear markup", role: .destructive) { elements.removeAll() }
        .buttonStyle(.bordered)
    }
    .padding(8)
  }

  private func syncMarkupRecipe() {
    var r = history.current
    if elements.isEmpty {
      if r.markup != nil {
        r.markup = nil
        history.commit(r)
      }
    } else {
      r.markup = MarkupRecipe(elements: elements)
      // Commit without flooding undo: replace current only if markup differs.
      if r != history.current { history.commit(r) }
    }
  }

  // MARK: Video

  @ViewBuilder
  private var videoPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      if asset.type == .video {
        if let dur = videoDuration {
          Text("Trim: \(macFmt(history.current.video?.trimStart ?? 0)) – \(macFmt(history.current.video?.trimEnd ?? dur))")
            .font(.caption).monospacedDigit()
          Slider(
            value: Binding(
              get: { history.current.video?.trimStart ?? 0 },
              set: { v in macSetTrim(start: min(v, (history.current.video?.trimEnd ?? dur) - 0.5), end: nil) }),
            in: 0...max(0.5, dur - 0.5))
          Slider(
            value: Binding(
              get: { history.current.video?.trimEnd ?? dur },
              set: { v in macSetTrim(start: nil, end: max(v, (history.current.video?.trimStart ?? 0) + 0.5)) }),
            in: 0.5...dur)
        } else {
          ProgressView().task { await macLoadDuration() }
        }
        Toggle("Mute", isOn: Binding(
          get: { history.current.video?.muted ?? false },
          set: { v in macSetVideo { $0.muted = v } }))
        Button("Rotate 90°") { macSetVideo { $0.quarterTurns = ($0.quarterTurns + 1) % 4 } }
          .buttonStyle(.bordered)
      } else {
        Text("Still-image edits only for this asset.").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(8)
  }

  private func macSetVideo(_ mutate: (inout VideoRecipe) -> Void) {
    var r = history.current
    var recipe = r.video ?? VideoRecipe()
    mutate(&recipe)
    r.video = recipe.isEmpty ? nil : recipe
    history.commit(r)
  }

  private func macSetTrim(start: Double?, end: Double?) {
    macSetVideo {
      if let start { $0.trimStart = start }
      if let end { $0.trimEnd = end }
    }
  }

  private func macFmt(_ s: Double) -> String {
    String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
  }

  private func macLoadDuration() async {
    guard let loader = loadVideoFile else { return }
    do {
      let asset = AVURLAsset(url: try await loader())
      let dur = try await asset.load(.duration).seconds
      videoDuration = dur.isFinite ? dur : nil
    } catch {
      videoDuration = nil
    }
  }

  // MARK: - Copy / paste / revert / load / render

  private func copyEdits() {
    let pb = NSPasteboard.general
    pb.clearContents()
    do {
      pb.setData(try history.copiedData(), forType: NSPasteboard.PasteboardType("com.heirloom.edit-recipe"))
    } catch {
      saveError = "Could not copy edits: \(error)"
    }
  }

  private func pasteEdits() {
    do {
      guard
        let data = NSPasteboard.general.data(
          forType: NSPasteboard.PasteboardType("com.heirloom.edit-recipe"))
      else { return }
      history.commit(try EditHistory.pastedRecipe(from: data))
      elements = history.current.markup?.elements ?? []
    } catch {
      saveError = "Could not paste edits: \(error)"
    }
  }

  private func revertAll() {
    history.revertToOriginal()
    elements.removeAll()
  }

  private func initialLoad() async {
    guard !hasLoadedRecipe else { return }
    hasLoadedRecipe = true
    do {
      if let payload = try await persistence.fetchRecipe(assetId: asset.id),
        payload.format == EditRecipeKey.current
      {
        history = EditHistory(initial: payload.recipe)
        elements = payload.recipe.markup?.elements ?? []
      }
    } catch {
      // Offline or never edited — start clean, not an error.
    }
    rerenderPreview()
  }

  @State private var macPreviewTask: Task<Void, Never>?

  private func rerenderPreview() {
    macPreviewTask?.cancel()
    let recipe = history.current
    let src = preview
    macPreviewTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 30_000_000)
      guard !Task.isCancelled else { return }
      if let tiff = src.tiffRepresentation, let ci = CIImage(data: tiff),
        let cg = renderer.cgImage(source: ci, recipe: recipe, previewMaxPixel: 1080)
      {
        renderedPreview = NSImage(cgImage: cg, size: src.size)
      } else {
        renderedPreview = src
      }
    }
  }

  private var savingOverlay: some View {
    ZStack {
      Color.black.opacity(0.4).ignoresSafeArea()
      VStack(spacing: 12) {
        ProgressView()
        Text("Rendering full resolution…").font(.caption).foregroundStyle(.white)
      }
      .padding(24)
      .background(.ultraThinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 14))
    }
  }

  private func save() {
    saving = true
    saveError = nil
    Task {
      do {
        try EditAccess.requireEdit(asset, in: access)
        let renderedId: String?
        if asset.type == .video {
          renderedId = try await macSaveVideo()
        } else {
          renderedId = try await macSavePhoto()
        }
        await MainActor.run {
          saving = false
          onDone(renderedId)
          dismiss()
        }
      } catch {
        await MainActor.run {
          saving = false
          saveError = String(describing: error)
        }
      }
    }
  }

  private func macSavePhoto() async throws -> String? {
    var recipe = history.current
    if !elements.isEmpty { recipe.markup = MarkupRecipe(elements: elements) }
    let srcData = try await loadOriginalData()
    guard let srcCI = CIImage(data: srcData) else { throw EditRenderError.undecodableSource }
    let size = srcCI.extent.size
    let split = try EditSplitter.split(recipe, imageSize: size)
    try await persistence.applyUpstreamEdits(assetId: asset.id, items: split.upstream)
    if split.needsClientRender {
      let overlay = renderMarkupOverlay(elements, pixelSize: size)
      let report = try renderer.export(
        sourceData: srcData, recipe: recipe, format: macExportFormat(for: asset.originalFileName),
        markupOverlay: overlay)
      let isHeic = macIsHEIC(report.data)
      let ext = isHeic ? "heic" : "jpg"
      let upload = RenderedUpload(
        data: report.data,
        filename: RenderedUpload.editedFilename(for: asset.originalFileName, fileExtension: ext),
        contentType: isHeic ? "image/heic" : "image/jpeg",
        fileCreatedAt: asset.fileCreatedAt ?? Date(), fileModifiedAt: asset.fileModifiedAt ?? Date(),
        spaceId: asset.spaceId)
      // E1: the render lands as the asset's rendition (same asset, one timeline item).
      try await persistence.uploadRendition(assetId: asset.id, upload: upload)
    }
    // E1: no separate rendered asset exists, so renderedAssetId stays nil.
    try await persistence.saveRecipe(EditPersistencePayload(
      sourceAssetId: asset.id, recipe: recipe, renderedAssetId: nil))
    return nil
  }

  private func macExportFormat(for filename: String) -> EditRenderer.ExportFormat {
    let ext = (filename as NSString).pathExtension.lowercased()
    if ext == "heic" || ext == "heif" { return .heic(quality: 0.9) }
    return .jpeg(quality: 0.92)
  }

  private func macSaveVideo() async throws -> String? {
    guard let loader = loadVideoFile else { return nil }
    let url = try await loader()
    let recipe = history.current.video ?? VideoRecipe()
    let result = try await VideoEdit.export(sourceURL: url, recipe: recipe)
    let data = try Data(contentsOf: result.fileURL)
    try? FileManager.default.removeItem(at: result.fileURL)
    var full = history.current
    full.video = recipe
    let upload = RenderedUpload(
      data: data,
      filename: RenderedUpload.editedFilename(for: asset.originalFileName, fileExtension: "mp4"),
      contentType: "video/mp4",
      fileCreatedAt: asset.fileCreatedAt ?? Date(), fileModifiedAt: asset.fileModifiedAt ?? Date(),
      spaceId: asset.spaceId, durationMs: Int(result.durationSeconds * 1000))
    // E1: the export lands as the asset's rendition (same asset, one timeline item).
    try await persistence.uploadRendition(assetId: asset.id, upload: upload)
    // E1: no separate rendered asset exists, so renderedAssetId stays nil.
    try await persistence.saveRecipe(EditPersistencePayload(
      sourceAssetId: asset.id, recipe: full, renderedAssetId: nil))
    return nil
  }
}

// MARK: - Supporting types

public enum MacEditTool: String, CaseIterable, Hashable {
  case adjust, filters, crop, portrait, markup, video

  static func available(for asset: Asset) -> [MacEditTool] { [.adjust, .filters, .crop, .portrait, .markup] + ((asset.type == .video || asset.livePhotoVideoId != nil) ? [.video] : []) }

  var title: String {
    switch self {
    case .adjust: return "Adjust"
    case .filters: return "Filters"
    case .crop: return "Crop"
    case .portrait: return "Portrait"
    case .markup: return "Markup"
    case .video: return "Video"
    }
  }
}

public enum MacAdjustParam: String, CaseIterable, Hashable {
  case exposure, brilliance, highlights, shadows, contrast, brightness, blackPoint,
    saturation, vibrance, warmth, tint, sharpness, definition, noiseReduction, vignette
}

public enum MacMarkupTool: String, CaseIterable, Hashable {
  case pen, line, arrow, rectangle, ellipse, text

  var title: String {
    switch self {
    case .pen: return "Pen"
    case .line: return "Line"
    case .arrow: return "Arrow"
    case .rectangle: return "Rect"
    case .ellipse: return "Oval"
    case .text: return "Text"
    }
  }
}

func macFit(image: CGSize, in container: CGSize) -> CGSize {
  guard image.width > 0, image.height > 0, container.width > 0, container.height > 0 else {
    return container
  }
  let s = min(container.width / image.width, container.height / image.height)
  return CGSize(width: image.width * s, height: image.height * s)
}

private func macIsHEIC(_ data: Data) -> Bool {
  guard data.count > 12 else { return false }
  let brand = String(data: data[8..<12], encoding: .ascii) ?? ""
  return brand == "heic" || brand == "heix" || brand == "hevc" || brand == "hevx"
}

extension Color {
  init(hex: String) {
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h.removeFirst() }
    var value: UInt64 = 0
    Scanner(string: h).scanHexInt64(&value)
    let r: Double
    let g: Double
    let b: Double
    if h.count == 8 {
      r = Double((value >> 24) & 0xff) / 255
      g = Double((value >> 16) & 0xff) / 255
      b = Double((value >> 8) & 0xff) / 255
    } else {
      r = Double((value >> 16) & 0xff) / 255
      g = Double((value >> 8) & 0xff) / 255
      b = Double(value & 0xff) / 255
    }
    self.init(red: r, green: g, blue: b)
  }
}

// MARK: - Vector markup canvas (AppKit)

struct MacMarkupCanvas: NSViewRepresentable {
  @Binding var elements: [MacMarkupElement]
  var markupTool: MacMarkupTool
  var colorHex: String
  var width: Double
  var text: String

  func makeNSView(context: Context) -> MarkupDrawView {
    let v = MarkupDrawView()
    v.coordinator = context.coordinator
    return v
  }

  func updateNSView(_ view: MarkupDrawView, context: Context) {
    context.coordinator.parent = self
    view.elements = elements
    view.needsDisplay = true
  }

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  final class Coordinator {
    var parent: MacMarkupCanvas
    var currentPen: [NormalizedPoint] = []
    var dragStart: NSPoint?
    var dragCurrent: NSPoint?
    init(parent: MacMarkupCanvas) { self.parent = parent }
  }
}

final class MarkupDrawView: NSView {
  var elements: [MacMarkupElement] = []
  var coordinator: MacMarkupCanvas.Coordinator?

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  private func normalized(_ p: NSPoint) -> NormalizedPoint {
    NormalizedPoint(
      x: bounds.width > 0 ? Double(p.x / bounds.width) : 0,
      y: bounds.height > 0 ? Double(p.y / bounds.height) : 0)
  }

  private func point(_ p: NormalizedPoint) -> NSPoint {
    NSPoint(x: CGFloat(p.x) * bounds.width, y: CGFloat(p.y) * bounds.height)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    guard let c = coordinator else { return }
    let p = convert(event.locationInWindow, from: nil)
    c.dragStart = p
    c.dragCurrent = p
    if c.parent.markupTool == .pen { c.currentPen = [normalized(p)] }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let c = coordinator else { return }
    let p = convert(event.locationInWindow, from: nil)
    c.dragCurrent = p
    if c.parent.markupTool == .pen { c.currentPen.append(normalized(p)) }
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    guard let c = coordinator else { return }
    let p = convert(event.locationInWindow, from: nil)
    let tool = c.parent.markupTool
    let hex = c.parent.colorHex
    let w = c.parent.width
    let start = c.dragStart ?? p
    switch tool {
    case .pen:
      c.currentPen.append(normalized(p))
      if c.currentPen.count > 1 {
        c.parent.elements.append(.pen(points: c.currentPen, width: w, colorHex: hex))
      }
      c.currentPen = []
    case .line:
      c.parent.elements.append(.line(
        from: normalized(start), to: normalized(p), width: w, colorHex: hex))
    case .arrow:
      c.parent.elements.append(.arrow(
        from: normalized(start), to: normalized(p), width: w, colorHex: hex))
    case .rectangle:
      let o = normalized(NSPoint(x: min(start.x, p.x), y: min(start.y, p.y)))
      c.parent.elements.append(.rectangle(
        origin: o,
        size: NormalizedSize(
          width: Double(abs(p.x - start.x) / max(1, bounds.width)),
          height: Double(abs(p.y - start.y) / max(1, bounds.height))),
        width: w, colorHex: hex))
    case .ellipse:
      let o = normalized(NSPoint(x: min(start.x, p.x), y: min(start.y, p.y)))
      c.parent.elements.append(.ellipse(
        origin: o,
        size: NormalizedSize(
          width: Double(abs(p.x - start.x) / max(1, bounds.width)),
          height: Double(abs(p.y - start.y) / max(1, bounds.height))),
        width: w, colorHex: hex))
    case .text:
      c.parent.elements.append(.text(
        at: normalized(p), string: c.parent.text, fontSize: 32, colorHex: hex))
    }
    c.dragStart = nil
    c.dragCurrent = nil
    elements = c.parent.elements
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for el in elements { stroke(el, in: ctx) }
    // Live rubber-band for the in-progress gesture.
    if let c = coordinator, let s = c.dragStart, let e = c.dragCurrent, s != e {
      switch c.parent.markupTool {
      case .pen:
        stroke(.pen(points: c.currentPen, width: c.parent.width, colorHex: c.parent.colorHex), in: ctx)
      case .line:
        stroke(.line(from: normalized(s), to: normalized(e), width: c.parent.width, colorHex: c.parent.colorHex), in: ctx)
      case .arrow:
        stroke(.arrow(from: normalized(s), to: normalized(e), width: c.parent.width, colorHex: c.parent.colorHex), in: ctx)
      case .rectangle:
        let o = NSPoint(x: min(s.x, e.x), y: min(s.y, e.y))
        stroke(
          .rectangle(
            origin: normalized(o),
            size: NormalizedSize(
              width: Double(abs(e.x - s.x) / max(1, bounds.width)),
              height: Double(abs(e.y - s.y) / max(1, bounds.height))),
            width: c.parent.width, colorHex: c.parent.colorHex), in: ctx)
      case .ellipse:
        let o = NSPoint(x: min(s.x, e.x), y: min(s.y, e.y))
        stroke(
          .ellipse(
            origin: normalized(o),
            size: NormalizedSize(
              width: Double(abs(e.x - s.x) / max(1, bounds.width)),
              height: Double(abs(e.y - s.y) / max(1, bounds.height))),
            width: c.parent.width, colorHex: c.parent.colorHex), in: ctx)
      case .text:
        break
      }
    }
  }

  private func stroke(_ el: MacMarkupElement, in ctx: CGContext) {
    switch el {
    case .pen(let points, let w, let hex):
      ctx.setStrokeColor(MarkupColor.cgColor(hex))
      ctx.setLineWidth(CGFloat(w))
      let pts = points.map { point($0) }
      guard let first = pts.first else { return }
      ctx.move(to: first)
      for p in pts.dropFirst() { ctx.addLine(to: p) }
      ctx.strokePath()
    case .line(let from, let to, let w, let hex):
      ctx.setStrokeColor(MarkupColor.cgColor(hex))
      ctx.setLineWidth(CGFloat(w))
      ctx.move(to: point(from))
      ctx.addLine(to: point(to))
      ctx.strokePath()
    case .arrow(let from, let to, let w, let hex):
      let a = point(from)
      let b = point(to)
      ctx.setStrokeColor(MarkupColor.cgColor(hex))
      ctx.setFillColor(MarkupColor.cgColor(hex))
      ctx.setLineWidth(CGFloat(w))
      ctx.move(to: a)
      ctx.addLine(to: b)
      ctx.strokePath()
      let angle = atan2(b.y - a.y, b.x - a.x)
      let head = CGFloat(w) * 4 + 8
      ctx.move(to: b)
      ctx.addLine(to: CGPoint(x: b.x - head * cos(angle - 0.45), y: b.y - head * sin(angle - 0.45)))
      ctx.addLine(to: CGPoint(x: b.x - head * cos(angle + 0.45), y: b.y - head * sin(angle + 0.45)))
      ctx.closePath()
      ctx.fillPath()
    case .rectangle(let origin, let size, let w, let hex):
      ctx.setStrokeColor(MarkupColor.cgColor(hex))
      ctx.setLineWidth(CGFloat(w))
      let o = point(origin)
      ctx.stroke(CGRect(
        x: o.x, y: o.y, width: CGFloat(size.width) * bounds.width,
        height: CGFloat(size.height) * bounds.height))
    case .ellipse(let origin, let size, let w, let hex):
      ctx.setStrokeColor(MarkupColor.cgColor(hex))
      ctx.setLineWidth(CGFloat(w))
      let o = point(origin)
      ctx.strokeEllipse(in: CGRect(
        x: o.x, y: o.y, width: CGFloat(size.width) * bounds.width,
        height: CGFloat(size.height) * bounds.height))
    case .text(let at, let string, let fontSize, let hex):
      let p = point(at)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: CGFloat(fontSize)),
        .foregroundColor: NSColor(cgColor: MarkupColor.cgColor(hex)) ?? .yellow,
      ]
      (string as NSString).draw(at: p, withAttributes: attrs)
    }
  }
}
