import AVFoundation
import CoreImage
import CoreModel
import Editing
import PencilKit
import Rules
import SwiftUI

/// A8 edit screen (brief UIs): tool tabs (Adjust, Filters, Crop, Portrait, Markup — plus
/// Video for videos), a horizontal dial slider, Done/Cancel.
///
/// Deliberately decoupled from Viewer/Media/SyncEngine (other phases build on those): the
/// caller supplies the preview image and async source loaders, and Done persists through
/// `EditPersistence` — upstream ops to `PUT /assets/:id/edits`, everything else to the
/// `fork.editRecipe.v1` metadata KV plus a full-res render uploaded as a NEW asset.
/// Compare = press-and-hold the preview.
public struct EditView: View {
  var asset: Asset
  var access: AccessContext
  var preview: UIImage
  var loadOriginalData: () async throws -> Data
  var loadVideoFile: (() async throws -> URL)?
  var loadMotionFile: (() async throws -> URL)?
  var persistence: RESTEditPersistence
  var onDone: (String?) -> Void

  @State private var history = EditHistory()
  @State private var tool: EditTool = .adjust
  @State private var adjustParam: AdjustParam = .exposure
  @State private var renderedPreview: UIImage
  @State private var comparing = false
  @State private var saving = false
  @State private var saveError: String?
  @State private var renderedAssetId: String?
  @State private var videoDuration: Double?
  @State private var cropDraft: NormalizedRect?
  @State private var dragAnchor: CGRect?
  @State private var canvas = PKCanvasView()
  @State private var hasLoadedRecipe = false
  @Environment(\.dismiss) private var dismiss

  private let renderer = EditRenderer()

  public init(
    asset: Asset, access: AccessContext, preview: UIImage,
    loadOriginalData: @escaping () async throws -> Data,
    loadVideoFile: (() async throws -> URL)? = nil,
    loadMotionFile: (() async throws -> URL)? = nil,
    persistence: RESTEditPersistence,
    onDone: @escaping (String?) -> Void = { _ in }
  ) {
    self.asset = asset
    self.access = access
    self.preview = preview
    self.loadOriginalData = loadOriginalData
    self.loadVideoFile = loadVideoFile
    self.loadMotionFile = loadMotionFile
    self.persistence = persistence
    self.onDone = onDone
    self._renderedPreview = State(initialValue: preview)
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        previewArea
        toolBody
        dialArea
        toolTabs
      }
      .navigationTitle("Edit")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(saving)
        }
        ToolbarItemGroup(placement: .primaryAction) {
          undoRedoButtons
          Button("Done") { save() }.bold().disabled(saving || (!history.isDirty && renderedAssetId == nil))
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
      .task { await initialLoad() }
      .onChange(of: history.current) { _, _ in rerenderPreview() }
    }
  }

  // MARK: - Preview

  private var previewArea: some View {
    GeometryReader { geo in
      let fit = AspectFit.rect(for: preview.size, in: geo.size)
      ZStack {
        Image(uiImage: comparing ? preview : renderedPreview)
          .resizable()
          .scaledToFit()
          .frame(width: fit.width, height: fit.height)
        if tool == .markup {
          PencilCanvas(canvas: $canvas)
            .frame(width: fit.width, height: fit.height)
        }
        if tool == .crop, let rect = cropDraft {
          cropOverlay(rect, display: fit.size)
            .frame(width: fit.width, height: fit.height)
        }
        if tool == .portrait, let focus = history.current.portrait?.focus {
          Circle().fill(.yellow).frame(width: 22, height: 22)
            .position(
              x: CGFloat(focus.x) * fit.width, y: CGFloat(focus.y) * fit.height)
        }
      }
      .frame(width: fit.width, height: fit.height)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .onTapGesture { loc in
        if tool == .portrait, history.current.portrait != nil {
          // Tap is in the outer space; map into the fit frame.
          let ox = (geo.size.width - fit.width) / 2
          let oy = (geo.size.height - fit.height) / 2
          let px = (loc.x - ox) / fit.width
          let py = (loc.y - oy) / fit.height
          guard (0...1).contains(px), (0...1).contains(py) else { return }
          commitPortrait(focus: NormalizedPoint(x: Double(px), y: Double(py)))
        }
      }
      // Compare (press-and-hold): show the original while held.
      .simultaneousGesture(DragGesture(minimumDistance: 0)
        .onChanged { _ in comparing = true }
        .onEnded { _ in comparing = false })
    }
    .background(.black)
  }

  // MARK: - Tool body + dial

  @ViewBuilder
  private var toolBody: some View {
    switch tool {
    case .adjust:
      adjustGrid
    case .filters:
      filtersRow
    case .crop:
      cropControls
    case .portrait:
      portraitControls
    case .markup:
      Text(hasInk ? "Draw with Apple Pencil or finger — ink flattens into the saved render."
        : "Draw with Apple Pencil or finger.")
        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
    case .video:
      videoControls
    }
  }

  @ViewBuilder
  private var dialArea: some View {
    switch tool {
    case .adjust:
      dial(value: adjustBinding, range: -100...100, format: "\(Int(adjustValue))")
    case .filters:
      dial(
        value: Binding(
          get: { Double(history.current.style?.intensity ?? 100) },
          set: { v in
            var r = history.current
            let name = r.style?.style ?? .vivid
            r.style = StyleRecipe(style: name, intensity: Int(v))
            history.commit(r)
          }), range: 0...100, format: "Intensity \(Int(history.current.style?.intensity ?? 100))")
    case .crop:
      dial(
        value: Binding(
          get: { history.current.crop?.straightenDegrees ?? 0 },
          set: { v in var r = history.current; var c = r.crop ?? CropRecipe(); c.straightenDegrees = v; r.crop = c; history.commit(r) }),
        range: -45...45, format: String(format: "Straighten %.1f°", history.current.crop?.straightenDegrees ?? 0))
    case .portrait:
      dial(
        value: Binding(
          get: { history.current.portrait?.aperture ?? 2.8 },
          set: { v in
            var r = history.current
            var p = r.portrait ?? PortraitRecipe()
            p.aperture = v
            r.portrait = p
            history.commit(r)
          }), range: 1.4...16, format: String(format: "ƒ/%.1f", history.current.portrait?.aperture ?? 2.8))
    case .markup, .video:
      EmptyView()
    }
  }

  private func dial(value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
    VStack(spacing: 2) {
      Slider(value: value, in: range)
        .padding(.horizontal)
      Text(format).font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }

  private var toolTabs: some View {
    HStack {
      ForEach(EditTool.available(for: asset), id: \.self) { t in
        Button {
          tool = t
          if t == .crop, cropDraft == nil { cropDraft = history.current.crop?.rect }
        } label: {
          VStack(spacing: 2) {
            Image(systemName: t.icon).font(.title3)
            Text(t.title).font(.caption2)
          }
          .frame(maxWidth: .infinity)
          .foregroundStyle(tool == t ? .yellow : .primary)
        }
      }
    }
    .padding(.vertical, 8)
    .background(.thinMaterial)
  }

  // MARK: - Adjust

  private var adjustGrid: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack {
        ForEach(AdjustParam.allCases, id: \.self) { p in
          Button { adjustParam = p } label: {
            VStack {
              Image(systemName: p.icon)
              Text(p.title).font(.caption2)
              Text("\(Int(value(of: p)))").font(.caption2).monospacedDigit()
                .foregroundStyle(value(of: p) == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.yellow))
            }
            .frame(width: 64)
            .foregroundStyle(adjustParam == p ? .yellow : .primary)
          }
        }
      }
      .padding(.horizontal)
    }
  }

  private var adjustValue: Double {
    value(of: adjustParam)
  }

  private var adjustBinding: Binding<Double> {
    Binding(get: { value(of: adjustParam) }, set: { setAdjust($0) })
  }

  private func value(of p: AdjustParam) -> Double {
    let a = history.current.adjust
    switch p {
    case .exposure: return Double(a.exposure)
    case .brilliance: return Double(a.brilliance)
    case .highlights: return Double(a.highlights)
    case .shadows: return Double(a.shadows)
    case .contrast: return Double(a.contrast)
    case .brightness: return Double(a.brightness)
    case .blackPoint: return Double(a.blackPoint)
    case .saturation: return Double(a.saturation)
    case .vibrance: return Double(a.vibrance)
    case .warmth: return Double(a.warmth)
    case .tint: return Double(a.tint)
    case .sharpness: return Double(a.sharpness)
    case .definition: return Double(a.definition)
    case .noiseReduction: return Double(a.noiseReduction)
    case .vignette: return Double(a.vignette)
    }
  }

  private func setAdjust(_ v: Double) {
    var r = history.current
    var a = r.adjust
    let i = Int(v.rounded())
    switch adjustParam {
    case .exposure: a.exposure = i
    case .brilliance: a.brilliance = i
    case .highlights: a.highlights = i
    case .shadows: a.shadows = i
    case .contrast: a.contrast = i
    case .brightness: a.brightness = i
    case .blackPoint: a.blackPoint = i
    case .saturation: a.saturation = i
    case .vibrance: a.vibrance = i
    case .warmth: a.warmth = i
    case .tint: a.tint = i
    case .sharpness: a.sharpness = i
    case .definition: a.definition = i
    case .noiseReduction: a.noiseReduction = i
    case .vignette: a.vignette = i
    }
    r.adjust = a
    history.commit(r)
  }

  // MARK: - Filters

  private var filtersRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(EditStyle.allCases, id: \.self) { style in
          Button {
            var r = history.current
            r.style = style == .none ? nil : StyleRecipe(style: style, intensity: r.style?.intensity ?? 100)
            history.commit(r)
          } label: {
            VStack {
              filterThumb(style)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                  RoundedRectangle(cornerRadius: 10)
                    .stroke(history.current.style?.style == style ? .yellow : .clear, lineWidth: 2))
              Text(style.displayName).font(.caption2)
            }
          }
        }
      }
      .padding(.horizontal)
    }
  }

  private func filterThumb(_ style: EditStyle) -> some View {
    Group {
      if let ui = FilterThumbCache.thumb(assetId: asset.id, style: style, source: preview, renderer: renderer) {
        Image(uiImage: ui).resizable()
      } else {
        Image(uiImage: preview).resizable()
      }
    }
  }

  // MARK: - Crop

  private var cropControls: some View {
    VStack(spacing: 6) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(CropAspect.allCases, id: \.self) { aspect in
            Button(aspect == .free ? "Free" : aspect.rawValue) { applyAspect(aspect) }
              .buttonStyle(.bordered)
              .tint(history.current.crop?.aspect == aspect ? .yellow : .gray)
          }
          Button("Reset") {
            var r = history.current
            r.crop = nil
            cropDraft = nil
            history.commit(r)
          }
          .buttonStyle(.bordered)
        }
        .padding(.horizontal)
      }
      HStack {
        Button("Rotate 90°") {
          var r = history.current
          var c = r.crop ?? CropRecipe()
          c.quarterTurns = (c.quarterTurns + 1) % 4
          r.crop = c
          history.commit(r)
        }
        Button("Flip H") {
          var r = history.current
          var c = r.crop ?? CropRecipe()
          c.flipHorizontal.toggle()
          r.crop = c
          history.commit(r)
        }
        Button("Flip V") {
          var r = history.current
          var c = r.crop ?? CropRecipe()
          c.flipVertical.toggle()
          r.crop = c
          history.commit(r)
        }
        Button("Auto") { Task { await autoStraighten() } }
      }
      .buttonStyle(.bordered)
      .font(.caption)
      HStack {
        stepper("V-Keystone", value: perspectiveBinding(vertical: true))
        stepper("H-Keystone", value: perspectiveBinding(vertical: false))
      }
      .font(.caption)
    }
    .padding(.vertical, 4)
  }

  private func stepper(_ title: String, value: Binding<Int>) -> some View {
    HStack {
      Text(title)
      Button("-") { value.wrappedValue = max(-100, value.wrappedValue - 5) }
      Text("\(value.wrappedValue)").monospacedDigit().frame(minWidth: 36)
      Button("+") { value.wrappedValue = min(100, value.wrappedValue + 5) }
    }
  }

  private func perspectiveBinding(vertical: Bool) -> Binding<Int> {
    Binding(
      get: {
        vertical
          ? (history.current.crop?.perspectiveVertical ?? 0)
          : (history.current.crop?.perspectiveHorizontal ?? 0)
      },
      set: { v in
        var r = history.current
        var c = r.crop ?? CropRecipe()
        if vertical { c.perspectiveVertical = v } else { c.perspectiveHorizontal = v }
        r.crop = c
        history.commit(r)
      })
  }

  private func applyAspect(_ aspect: CropAspect) {
    var r = history.current
    var c = r.crop ?? CropRecipe()
    c.aspect = aspect
    if let ratio = aspect.ratio {
      // Centered rect of the requested ratio at 90% of the fitting dimension.
      let w: Double
      let h: Double
      if ratio >= 1 { w = 0.9; h = 0.9 / ratio } else { h = 0.9; w = 0.9 * ratio }
      let rect = NormalizedRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
      c.rect = rect
      cropDraft = rect
    } else if aspect == .free {
      c.rect = nil
      cropDraft = nil
    }
    r.crop = c
    history.commit(r)
  }

  private func cropOverlay(_ rect: NormalizedRect, display size: CGSize) -> some View {
    let r = CGRect(
      x: CGFloat(rect.x) * size.width, y: CGFloat(rect.y) * size.height,
      width: CGFloat(rect.width) * size.width, height: CGFloat(rect.height) * size.height)
    return ZStack {
      Color.black.opacity(0.5)
        .mask(CropDimShape(outer: size, rect: r).fill(style: FillStyle(eoFill: true)))
        .allowsHitTesting(false)
      Rectangle().stroke(.white, lineWidth: 1).frame(width: r.width, height: r.height)
        .position(x: r.midX, y: r.midY)
        .allowsHitTesting(false)
      ForEach(0..<4, id: \.self) { i in
        Circle().fill(.white).frame(width: 26, height: 26)
          .position(corner(i, of: r))
          .gesture(DragGesture()
            .onChanged { g in dragCorner(i, total: g.translation, in: size) }
            .onEnded { _ in dragAnchor = nil })
      }
    }
  }

  private func corner(_ i: Int, of r: CGRect) -> CGPoint {
    switch i {
    case 0: return CGPoint(x: r.minX, y: r.minY)
    case 1: return CGPoint(x: r.maxX, y: r.minY)
    case 2: return CGPoint(x: r.minX, y: r.maxY)
    default: return CGPoint(x: r.maxX, y: r.maxY)
    }
  }

  private func dragCorner(_ i: Int, total t: CGSize, in size: CGSize) {
    guard let draft = cropDraft, size.width > 0, size.height > 0 else { return }
    // `translation` is total-from-gesture-start: always apply it to the rect captured
    // when the drag began, never incrementally to the evolving draft.
    if dragAnchor == nil {
      dragAnchor = CGRect(
        x: CGFloat(draft.x) * size.width, y: CGFloat(draft.y) * size.height,
        width: CGFloat(draft.width) * size.width, height: CGFloat(draft.height) * size.height)
    }
    guard var anchor = dragAnchor else { return }
    var rect = draft
    var r = anchor
    let dx = t.width
    let dy = t.height
    switch i {
    case 0: r.origin.x += dx; r.origin.y += dy; r.size.width -= dx; r.size.height -= dy
    case 1: r.origin.y += dy; r.size.width += dx; r.size.height -= dy
    case 2: r.origin.x += dx; r.size.width -= dx; r.size.height += dy
    default: r.size.width += dx; r.size.height += dy
    }
    r = r.intersection(CGRect(origin: .zero, size: size))
    guard r.width > 44, r.height > 44 else { return }
    if let aspect = history.current.crop?.aspect, let ratio = aspect.ratio {
      // Lock aspect around the dragged corner's opposite anchor.
      let anchor: CGPoint =
        switch i {
        case 0: CGPoint(x: r.maxX, y: r.maxY)
        case 1: CGPoint(x: r.minX, y: r.maxY)
        case 2: CGPoint(x: r.maxX, y: r.minY)
        default: CGPoint(x: r.minX, y: r.minY)
        }
      var w = r.width
      var h = w / CGFloat(ratio)
      if h > r.height { h = r.height; w = h * CGFloat(ratio) }
      r = CGRect(x: anchor.x - (i % 2 == 0 ? w : 0), y: anchor.y - (i < 2 ? h : 0), width: w, height: h)
      r = r.intersection(CGRect(origin: .zero, size: size))
    }
    anchor = r
    dragAnchor = anchor
    rect = NormalizedRect(
      x: Double(r.minX / size.width), y: Double(r.minY / size.height),
      width: Double(r.width / size.width), height: Double(r.height / size.height))
    cropDraft = rect
    var rec = history.current
    var c = rec.crop ?? CropRecipe()
    c.rect = rect
    rec.crop = c
    history.commit(rec)
  }

  private func autoStraighten() async {
    guard let cg = preview.cgImage else { return }
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

  // MARK: - Portrait

  private var portraitControls: some View {
    VStack(spacing: 6) {
      if portraitAvailableLocal {
        Toggle("Portrait depth blur", isOn: Binding(
          get: { history.current.portrait != nil },
          set: { on in
            var r = history.current
            r.portrait = on ? (r.portrait ?? PortraitRecipe()) : nil
            history.commit(r)
          }))
        .padding(.horizontal)
        Text("Tap the preview to move the focus point.")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("No depth data in this photo — Portrait is unavailable.")
          .font(.caption).foregroundStyle(.secondary).padding()
      }
    }
    .padding(.vertical, 4)
  }

  private var portraitAvailableLocal: Bool {
    guard let ci = CIImage(image: preview) else { return false }
    return EditRenderer.portraitAvailable(source: ci)
  }

  private func commitPortrait(focus: NormalizedPoint) {
    var r = history.current
    var p = r.portrait ?? PortraitRecipe()
    p.focus = focus
    r.portrait = p
    history.commit(r)
  }

  // MARK: - Video / Live Photo

  @ViewBuilder
  private var videoControls: some View {
    VStack(spacing: 8) {
      if asset.type == .video {
        if let dur = videoDuration {
          trimSlider(duration: dur, label: "Trim")
        } else {
          ProgressView().task { await loadDuration() }
        }
        Toggle("Mute", isOn: Binding(
          get: { history.current.video?.muted ?? false },
          set: { v in
            var r = history.current
            var recipe = r.video ?? VideoRecipe()
            recipe.muted = v
            r.video = recipe.isEmpty ? nil : recipe
            history.commit(r)
          }))
        .padding(.horizontal)
        Button("Rotate 90°") {
          var r = history.current
          var recipe = r.video ?? VideoRecipe()
          recipe.quarterTurns = (recipe.quarterTurns + 1) % 4
          r.video = recipe.isEmpty ? nil : recipe
          history.commit(r)
        }
        .buttonStyle(.bordered)
      } else if asset.livePhotoVideoId != nil {
        if loadMotionFile != nil {
          Toggle("Mute motion photo", isOn: Binding(
            get: { history.current.video?.muted ?? false },
            set: { v in
              var r = history.current
              var recipe = r.video ?? VideoRecipe()
              recipe.muted = v
              r.video = recipe.isEmpty ? nil : recipe
              history.commit(r)
            }))
          .padding(.horizontal)
          if let dur = videoDuration {
            keyFrameSlider(duration: dur)
          } else {
            ProgressView().task { await loadDuration(motion: true) }
          }
        } else {
          Text("Motion part unavailable offline — still-image edits only.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func trimSlider(duration: Double, label: String) -> some View {
    VStack {
      Text("\(label): \(fmtTime(history.current.video?.trimStart ?? 0)) – \(fmtTime(history.current.video?.trimEnd ?? duration))")
        .font(.caption).monospacedDigit()
      HStack {
        Slider(
          value: Binding(
            get: { history.current.video?.trimStart ?? 0 },
            set: { v in setTrim(start: min(v, (history.current.video?.trimEnd ?? duration) - 0.5), end: nil) }),
          in: 0...max(0.5, duration - 0.5))
        Slider(
          value: Binding(
            get: { history.current.video?.trimEnd ?? duration },
            set: { v in setTrim(start: nil, end: max(v, (history.current.video?.trimStart ?? 0) + 0.5)) }),
          in: 0.5...duration)
      }
      .padding(.horizontal)
    }
  }

  private func keyFrameSlider(duration: Double) -> some View {
    VStack {
      Text("Key frame: \(fmtTime(history.current.video?.livePhotoKeyFrame ?? 0))")
        .font(.caption).monospacedDigit()
      Slider(
        value: Binding(
          get: { history.current.video?.livePhotoKeyFrame ?? 0 },
          set: { v in
            var r = history.current
            var recipe = r.video ?? VideoRecipe()
            recipe.livePhotoKeyFrame = v
            r.video = recipe
            history.commit(r)
          }), in: 0...duration)
      .padding(.horizontal)
    }
  }

  private func setTrim(start: Double?, end: Double?) {
    var r = history.current
    var recipe = r.video ?? VideoRecipe()
    if let start { recipe.trimStart = start }
    if let end { recipe.trimEnd = end }
    r.video = recipe.isEmpty ? nil : recipe
    history.commit(r)
  }

  private func fmtTime(_ s: Double) -> String {
    String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
  }

  private func loadDuration(motion: Bool = false) async {
    do {
      let url: URL
      if motion {
        url = try await loadMotionFile!()
      } else {
        guard let loader = loadVideoFile else { return }
        url = try await loader()
      }
      let asset = AVURLAsset(url: url)
      let dur = try await asset.load(.duration).seconds
      videoDuration = dur.isFinite ? dur : nil
    } catch {
      videoDuration = nil
    }
  }

  // MARK: - Undo / paste / revert

  private var undoRedoButtons: some View {
    HStack {
      Button { history.undo(); cropDraft = history.current.crop?.rect } label: {
        Label("Undo", systemImage: "arrow.uturn.backward")
      }
      .disabled(!history.canUndo)
      Button { history.redo(); cropDraft = history.current.crop?.rect } label: {
        Label("Redo", systemImage: "arrow.uturn.forward")
      }
      .disabled(!history.canRedo)
      Menu {
        Button("Copy edits") { copyEdits() }
        Button("Paste edits") { pasteEdits() }
        Button("Revert to original", role: .destructive) {
          history.revertToOriginal()
          cropDraft = nil
          canvas.drawing = PKDrawing()
        }
      } label: {
        Label("More", systemImage: "ellipsis.circle")
      }
    }
  }

  private func copyEdits() {
    do {
      UIPasteboard.general.setData(try history.copiedData(), forPasteboardType: "com.heirloom.edit-recipe")
    } catch {
      saveError = "Could not copy edits: \(error)"
    }
  }

  private func pasteEdits() {
    do {
      guard let data = UIPasteboard.general.data(forPasteboardType: "com.heirloom.edit-recipe") else { return }
      history.commit(try EditHistory.pastedRecipe(from: data))
      cropDraft = history.current.crop?.rect
    } catch {
      saveError = "Could not paste edits: \(error)"
    }
  }

  // MARK: - Load + preview render

  private func initialLoad() async {
    guard !hasLoadedRecipe else { return }
    hasLoadedRecipe = true
    do {
      if let payload = try await persistence.fetchRecipe(assetId: asset.id),
        payload.format == EditRecipeKey.current
      {
        history = EditHistory(initial: payload.recipe)
        cropDraft = payload.recipe.crop?.rect
      }
    } catch {
      // Offline or never edited — start clean, not an error.
    }
    rerenderPreview()
  }

  @State private var previewTask: Task<Void, Never>?

  private func rerenderPreview() {
    previewTask?.cancel()
    let recipe = history.current
    let src = preview
    previewTask = Task { @MainActor in
      // Render off-main would need a thread-safe bridge; preview images are small
      // (Media thumbnail/preview tier), so render inline and bail if superseded.
      try? await Task.sleep(nanoseconds: 30_000_000)
      guard !Task.isCancelled else { return }
      if let ci = CIImage(image: src),
        let cg = renderer.cgImage(source: ci, recipe: recipe, previewMaxPixel: 1080)
      {
        renderedPreview = UIImage(cgImage: cg)
      } else {
        renderedPreview = src
      }
    }
  }

  private var hasInk: Bool { !canvas.drawing.strokes.isEmpty }

  /// Snapshot PencilKit ink scaled to `pixelSize` for flattening into the full-res export.
  private func inkOverlay(pixelSize: CGSize) -> CGImage? {
    guard hasInk else { return nil }
    let bounds = canvas.bounds
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let scale = max(pixelSize.width / bounds.width, pixelSize.height / bounds.height)
    let img = canvas.drawing.image(from: CGRect(origin: .zero, size: bounds.size), scale: scale)
    return img.cgImage
  }

  // MARK: - Save (persistence split)

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
          renderedId = try await saveVideo()
        } else {
          renderedId = try await savePhoto()
        }
        renderedAssetId = renderedId
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

  private func savePhoto() async throws -> String? {
    var recipe = history.current
    let inked = hasInk
    if inked, recipe.markup == nil {
      recipe.markup = MarkupRecipe(hasFlattenedInk: true)
    }
    let srcData = try await loadOriginalData()
    guard let srcCI = CIImage(data: srcData) else { throw EditRenderError.undecodableSource }
    let size = srcCI.extent.size
    let split = try EditSplitter.split(recipe, imageSize: size)
    try await persistence.applyUpstreamEdits(assetId: asset.id, items: split.upstream)
    var renderedId: String?
    if split.needsClientRender {
      let report = try renderer.export(
        sourceData: srcData, recipe: recipe, format: exportFormat(for: asset.originalFileName),
        markupOverlay: inkOverlay(pixelSize: size))
      let ext = report.data.isHEIC ? "heic" : "jpg"
      let upload = RenderedUpload(
        data: report.data,
        filename: RenderedUpload.editedFilename(for: asset.originalFileName, fileExtension: ext),
        contentType: ext == "heic" ? "image/heic" : "image/jpeg",
        fileCreatedAt: asset.fileCreatedAt ?? Date(), fileModifiedAt: asset.fileModifiedAt ?? Date(),
        spaceId: asset.spaceId)
      renderedId = try await persistence.uploadRendered(
        sourceAssetId: asset.id, upload: upload, recipe: recipe)
    }
    try await persistence.saveRecipe(EditPersistencePayload(
      sourceAssetId: asset.id, recipe: recipe, renderedAssetId: renderedId))
    return renderedId
  }

  private func exportFormat(for filename: String) -> EditRenderer.ExportFormat {
    let ext = (filename as NSString).pathExtension.lowercased()
    if ext == "heic" || ext == "heif" { return .heic(quality: 0.9) }
    return .jpeg(quality: 0.92)
  }

  private func saveVideo() async throws -> String? {
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
    let newId = try await persistence.uploadRendered(sourceAssetId: asset.id, upload: upload, recipe: full)
    try await persistence.saveRecipe(EditPersistencePayload(
      sourceAssetId: asset.id, recipe: full, renderedAssetId: newId))
    return newId
  }
}

// MARK: - Supporting types

public enum EditTool: String, CaseIterable, Hashable {
  case adjust, filters, crop, portrait, markup, video

  static func available(for asset: Asset) -> [EditTool] {
    var tools: [EditTool] = [.adjust, .filters, .crop, .portrait, .markup]
    if asset.type == .video || asset.livePhotoVideoId != nil { tools.append(.video) }
    return tools
  }

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

  var icon: String {
    switch self {
    case .adjust: return "slider.horizontal.3"
    case .filters: return "camera.filters"
    case .crop: return "crop"
    case .portrait: return "person.crop.circle"
    case .markup: return "pencil.tip.crop.circle"
    case .video: return "video"
    }
  }
}

public enum AdjustParam: String, CaseIterable, Hashable {
  case exposure, brilliance, highlights, shadows, contrast, brightness, blackPoint,
    saturation, vibrance, warmth, tint, sharpness, definition, noiseReduction, vignette

  var title: String {
    switch self {
    case .exposure: return "Exposure"
    case .brilliance: return "Brilliance"
    case .highlights: return "Highlights"
    case .shadows: return "Shadows"
    case .contrast: return "Contrast"
    case .brightness: return "Brightness"
    case .blackPoint: return "Black Pt"
    case .saturation: return "Saturation"
    case .vibrance: return "Vibrance"
    case .warmth: return "Warmth"
    case .tint: return "Tint"
    case .sharpness: return "Sharpness"
    case .definition: return "Definition"
    case .noiseReduction: return "Noise"
    case .vignette: return "Vignette"
    }
  }

  var icon: String {
    switch self {
    case .exposure: return "plusminus.circle"
    case .brilliance: return "sun.max"
    case .highlights: return "sunrise"
    case .shadows: return "sunset"
    case .contrast: return "circle.lefthalf.filled"
    case .brightness: return "sun.min"
    case .blackPoint: return "circle.fill"
    case .saturation: return "drop"
    case .vibrance: return "drop.fill"
    case .warmth: return "thermometer.sun"
    case .tint: return "eyedropper"
    case .sharpness: return "triangle"
    case .definition: return "square.dashed"
    case .noiseReduction: return "wind"
    case .vignette: return "circle.dotted"
    }
  }
}

/// Dimmed crop editor: full-frame dim with an even-odd rectangular hole.
struct CropDimShape: Shape {
  var outer: CGSize
  var rect: CGRect
  func path(in _: CGRect) -> Path {
    var p = Path()
    p.addRect(CGRect(origin: .zero, size: outer))
    p.addRect(rect)
    return p
  }
}

/// Aspect-fit rect of `image` inside `container` (same math as `scaledToFit`).
enum AspectFit {
  static func rect(for image: CGSize, in container: CGSize) -> CGRect {
    guard image.width > 0, image.height > 0, container.width > 0, container.height > 0 else {
      return CGRect(origin: .zero, size: container)
    }
    let sc = min(container.width / image.width, container.height / image.height)
    let size = CGSize(width: image.width * sc, height: image.height * sc)
    return CGRect(
      x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
      width: size.width, height: size.height)
  }
}

struct PencilCanvas: UIViewRepresentable {
  @Binding var canvas: PKCanvasView

  func makeUIView(context: Context) -> PKCanvasView {
    canvas.drawingPolicy = .anyInput
    canvas.backgroundColor = .clear
    canvas.isOpaque = false
    return canvas
  }

  func updateUIView(_ uiView: PKCanvasView, context: Context) {
    if context.coordinator.toolPicker == nil, let window = uiView.window,
      let picker = PKToolPicker.shared(for: window)
    {
      picker.setVisible(true, forFirstResponder: uiView)
      picker.addObserver(uiView)
      uiView.becomeFirstResponder()
      context.coordinator.toolPicker = picker
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator {
    var toolPicker: PKToolPicker?
  }
}

/// Lazily-rendered, cached filter thumbnails (rendered once per style per source image).
enum FilterThumbCache {
  nonisolated(unsafe) private static var cache: [String: UIImage] = [:]
  private static let lock = NSLock()

  static func thumb(assetId: String, style: EditStyle, source: UIImage, renderer: EditRenderer) -> UIImage? {
    let key = "\(assetId)/\(style.rawValue)"
    lock.lock()
    let hit = cache[key]
    lock.unlock()
    if let hit { return hit }
    guard style != .none, let ci = CIImage(image: source) else { return nil }
    let recipe = EditRecipe(style: StyleRecipe(style: style, intensity: 100))
    guard let cg = renderer.cgImage(source: ci, recipe: recipe, previewMaxPixel: 112) else { return nil }
    let ui = UIImage(cgImage: cg)
    lock.lock()
    cache[key] = ui
    lock.unlock()
    return ui
  }
}

private extension Data {
  /// Best-effort HEIC sniff (ftyp box brand) for picking the edited filename extension.
  var isHEIC: Bool {
    guard count > 12 else { return false }
    let brand = String(data: self[8..<12], encoding: .ascii) ?? ""
    return brand == "heic" || brand == "heix" || brand == "hevc" || brand == "hevx"
  }
}
