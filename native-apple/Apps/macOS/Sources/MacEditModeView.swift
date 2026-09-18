import AppKit
import AVFoundation
import CoreImage
import CoreModel
import Editing
import ImageIO
import Rules
import SwiftUI

// MARK: - WP-V / WP-E contract

extension Notification.Name {
  /// Posted to open edit mode (WP-E E1; observed by `MacViewerView`). `userInfo`
  /// may carry `"assetId"`; a viewer opens when it matches (or when absent).
  /// Defined here because WP-V has not published it yet.
  static let heirloomOpenEdit = Notification.Name("HeirloomViewer.openEdit")
  /// Posted by `MacEditModeView` on appear/disappear with `userInfo["active"]`.
  /// `MacMainWindow` collapses/restores the sidebar around full-window edit mode.
  static let heirloomEditModeActive = Notification.Name("HeirloomViewer.editModeActive")
}

/// Isolation-crossing box for filmstrip sources. `CIImage` is immutable and safe to
/// render from any thread (the same basis as `EditRenderer`'s `@unchecked
/// Sendable`); this only carries the image into a detached render task.
private struct UncheckedCIImage: @unchecked Sendable {
  let image: CIImage
  init(_ image: CIImage) { self.image = image }
}

/// Renders one filmstrip row fully off-main (detached task); the caller assigns
/// the result back on the main actor. All inputs are `Sendable` (per-strength
/// recipes are precomputed by the caller because key paths are not `Sendable`).
private func editFilmstripThumbs(source: UncheckedCIImage, recipes: [EditRecipe]) async -> [CGImage?] {
  await Task.detached(priority: .utility) {
    EditFilmstrip.thumbs(source: source.image, recipes: recipes)
  }.value
}

/// Full-window edit mode shell (WP-E E2): replaces the viewer content, sets the dark
/// appearance, and drives proxy-first rendering (proxy at once, original async with a
/// spinner; Done gated until the original arrives). Never presses Done on a real asset
/// in tests — fixture only (`-HeirloomFixture`), Cancel otherwise.
struct MacEditModeView: View {
  var asset: Asset
  var access: AccessContext
  var preview: NSImage
  var loadOriginalData: () async throws -> Data
  var loadVideoFile: (() async throws -> URL)?
  var persistence: RESTEditPersistence
  var isFavorite: Bool
  var onFavorite: () -> Void
  var onDone: (String?) -> Void
  var onExit: () -> Void

  @State private var history = EditHistory()
  @State private var versionStore = EditVersionStore()
  @State private var historyExpanded = false
  @State private var tab: EditModeTab = .adjust
  @State private var renderedPreview: NSImage
  @State private var canvasSource: NSImage
  @State private var comparing = false
  @State private var saving = false
  @State private var saveError: String?
  @State private var showDiscard = false
  @State private var zoomPercent: Double = 100
  @State private var cropOrientation: CropOrientation = .landscape
  @State private var cropDragging = false
  @State private var videoDuration: Double?
  @State private var markupTool: MacMarkupTool = .pen
  @State private var markupColorHex = "#FFCC00"
  @State private var markupWidth: Double = 4
  @State private var markupText = "Caption"
  @State private var elements: [MacMarkupElement] = []
  @State private var hasLoadedRecipe = false
  @State private var toolsRegistry = EditToolRegistry()
  @State private var eyedropperArmed = false
  @State private var renderTask: Task<Void, Never>?
  @State private var originalPhase = EditOriginalLoader.State.proxyReady

  private let loader = EditOriginalLoader()
  private let renderer = EditRenderer()

  init(
    asset: Asset, access: AccessContext, preview: NSImage,
    loadOriginalData: @escaping () async throws -> Data,
    loadVideoFile: (() async throws -> URL)? = nil,
    persistence: RESTEditPersistence,
    isFavorite: Bool = false,
    onFavorite: @escaping () -> Void = {},
    onDone: @escaping (String?) -> Void = { _ in },
    onExit: @escaping () -> Void = {}
  ) {
    self.asset = asset
    self.access = access
    self.preview = preview
    self.loadOriginalData = loadOriginalData
    self.loadVideoFile = loadVideoFile
    self.persistence = persistence
    self.isFavorite = isFavorite
    self.onFavorite = onFavorite
    self.onDone = onDone
    self.onExit = onExit
    self._renderedPreview = State(initialValue: preview)
    self._canvasSource = State(initialValue: preview)
  }

  // MARK: - Shell

  var body: some View {
    VStack(spacing: 0) {
      topBar
      Divider()
      HSplitView {
        canvasArea
          .frame(minWidth: 480, minHeight: 400)
        ScrollView {
          toolPanel
            .frame(minWidth: 280)
            .fixedSize(horizontal: false, vertical: false)
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
      }
      if asset.type == .video {
        videoTrimBar
      }
    }
    .preferredColorScheme(.dark)
    .background(Color(nsColor: .windowBackgroundColor))
    .toolbar(.hidden, for: .windowToolbar)
    .overlay { if saving { editSavingOverlay } }
    .alert("Save failed", isPresented: Binding(
      get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    ) {
      Button("OK") { saveError = nil }
    } message: {
      Text(saveError ?? "")
    }
    .alert("Discard changes?", isPresented: $showDiscard) {
      Button("Discard", role: .destructive) { exit() }
      Button("Keep editing", role: .cancel) {}
    } message: {
      Text("Your edits have not been saved.")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AXIDs.editMode)
    .task { await openSession() }
    .onDisappear {
      NotificationCenter.default.post(
        name: .heirloomEditModeActive, object: nil, userInfo: ["active": false])
    }
    .onChange(of: history.current) { _, _ in rerenderPreview() }
    .onChange(of: elements) { _, _ in syncMarkupRecipe() }
    .onKeyPress(.escape) {
      if history.isDirty { showDiscard = true } else { exit() }
      return .handled
    }
    .onKeyPress(keys: ["a", "s", "c", "t"]) { press in
      // Tab keys when no text field has focus (spec E9).
      if NSApp.keyWindow?.firstResponder is NSTextView { return .ignored }
      switch press.characters {
      case "a": tab = .adjust
      case "s": tab = .styles
      case "c": tab = .crop
      case "t": if toolsRegistry.shouldShowToolsTab { tab = .tools }
      default: return .ignored
      }
      return .handled
    }
    .onKeyPress(keys: ["m"], phases: [.down, .up]) { press in
      comparing = press.phase != .up
      return .handled
    }
  }

  private func exit() { onExit() }

  // NOTE (known issue, owner-visible): a focused NSSlider eats Escape as
  // cancelOperation, so Escape right after a slider drag needs focus elsewhere
  // first (the tests click the canvas). A local key-down monitor was tried and
  // never installed (makeNSView never ran — cause unknown); keyboard Tab-into-
  // slider + Escape likely shares the trap natively with AppKit.

  // MARK: - Top bar (spec E2)

  private var topBar: some View {
    HStack(spacing: 12) {
      Slider(value: $zoomPercent, in: 10...400)
        .frame(width: 120)
        .accessibilityIdentifier(AXIDs.editZoom)
        .help("Zoom (\(Int(zoomPercent))%)")
      Button("Revert to Original", role: .destructive) { revertAll() }
        .disabled(!history.isDirty)
        .accessibilityIdentifier(AXIDs.editRevert)
      // Tap toggles; press-and-hold on the photo peeks the original. A continuous
      // gesture on this button starves repeat taps after the first toggle, so the
      // hold lives on the canvas image (which carries no tap action to conflict).
      Button(comparing ? "After" : "Before") { comparing.toggle() }
        .accessibilityIdentifier(AXIDs.editCompare)
        // E9: while comparing, the before (original) image is on screen.
        .accessibilityValue(comparing ? "Original" : "Edited")
        .help("Click to toggle, press-and-hold the photo (or hold M) to compare with the original")
      Spacer()
      Picker("Tool", selection: $tab) {
        Text("Adjust").tag(EditModeTab.adjust)
        Text("Styles").tag(EditModeTab.styles)
        Text("Crop").tag(EditModeTab.crop)
        if toolsRegistry.shouldShowToolsTab { Text("Tools").tag(EditModeTab.tools) }
        if asset.type == .video { Text("Video").tag(EditModeTab.video) }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 420)
      Spacer()
      Menu {
        Button("Markup") { tab = .markup }
        Button("Edit With External Editor…") { Task { await editExternally() } }
        Divider()
        Button("Copy edits") { copyEdits() }
          .keyboardShortcut("C", modifiers: [.command, .shift])
        Button("Paste edits") { pasteEdits() }
          .keyboardShortcut("V", modifiers: [.command, .shift])
      } label: { Label("More", systemImage: "ellipsis.circle") }
      .accessibilityIdentifier(AXIDs.editMore)
      Button { onFavorite() } label: {
        Label("Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
      }
      Button { bumpTurns() } label: { Label("Rotate", systemImage: "rotate.right") }
        .disabled(asset.type == .video)
      Toggle("Auto Enhance", isOn: Binding(
        get: { history.current.adjust.autoEnhance },
        set: { v in var r = history.current; r.adjust.autoEnhance = v; history.commit(r) }))
        .toggleStyle(.checkbox)
      Button("Cancel") { history.isDirty ? showDiscard = true : exit() }
        .accessibilityIdentifier(AXIDs.editCancel)
        .keyboardShortcut(.cancelAction)
        .disabled(saving)
      Button("Done") { save() }
        .bold()
        .tint(.yellow)
        .accessibilityIdentifier(AXIDs.editDone)
        .disabled(saving || !history.isDirty || !loader.isDoneEnabled)
        .help(originalPhase == .ready ? "Save edits" : "Loading original…")
        .keyboardShortcut("s", modifiers: .command)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  // MARK: - Canvas

  private var canvasArea: some View {
    GeometryReader { geo in
      let fit = macFit(image: canvasSource.size, in: geo.size)
      let scale = zoomPercent / 100
      ZStack {
        Color.black
        Image(nsImage: comparing ? preview : renderedPreview)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: fit.width * scale, height: fit.height * scale)
          .clipped()
          .onLongPressGesture(minimumDuration: 0.2, pressing: { comparing = $0 }) {}
        if tab == .crop { cropOverlay(fit: fit) }
        if tab == .markup {
          MacMarkupCanvas(
            elements: $elements, markupTool: markupTool, colorHex: markupColorHex,
            width: markupWidth, text: markupText)
          .frame(width: fit.width, height: fit.height)
        }
        if originalPhase == .loadingOriginal {
          VStack {
            Spacer()
            HStack {
              Spacer()
              ProgressView()
                .controlSize(.small)
                .help("Loading original…")
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }
          }
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .contentShape(Rectangle())
      .onTapGesture(count: 1) { location in
        // First click anywhere meaningful opens edit — this view IS edit mode;
        // the tap serves the eyedropper when armed (White Balance section).
        if eyedropperArmed { sampleWhiteBalance(at: location, geo: geo, fit: fit) }
      }
    }
  }

  // MARK: - Crop overlay (handles, thirds grid, pan)

  private func cropOverlay(fit: CGSize) -> some View {
    GeometryReader { geo in
      let origin = CGPoint(x: (geo.size.width - fit.width) / 2, y: (geo.size.height - fit.height) / 2)
      let rect = history.current.crop?.rect
        ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)
      let view = CGRect(
        x: origin.x + CGFloat(rect.x) * fit.width,
        y: origin.y + CGFloat(rect.y) * fit.height,
        width: CGFloat(rect.width) * fit.width,
        height: CGFloat(rect.height) * fit.height)
      ZStack {
        Color.black.opacity(0.45)
          .frame(width: geo.size.width, height: geo.size.height)
          .mask {
            Rectangle()
              .frame(width: geo.size.width, height: geo.size.height)
              .overlay {
                Rectangle()
                  .frame(width: view.width, height: view.height)
                  .position(x: view.midX, y: view.midY)
                  .blendMode(.destinationOut)
              }
          }
          .allowsHitTesting(false)
        Rectangle()
          .stroke(.white, lineWidth: 1)
          .frame(width: view.width, height: view.height)
          .position(x: view.midX, y: view.midY)
          .gesture(DragGesture()
            .onChanged { g in
              cropDragging = true
              moveCrop(by: g.translation, fit: fit)
            }
            .onEnded { _ in cropDragging = false })
        if cropDragging {
          ThirdsGrid()
            .frame(width: view.width, height: view.height)
            .position(x: view.midX, y: view.midY)
            .allowsHitTesting(false)
        }
        ForEach(0..<4, id: \.self) { i in
          Circle()
            .fill(.white)
            .frame(width: 14, height: 14)
            .position(cropHandlePoint(i, in: view))
            .gesture(DragGesture()
              .onChanged { g in
                cropDragging = true
                dragCropHandle(i, by: g.translation, fit: fit, origin: origin)
              }
              .onEnded { _ in cropDragging = false })
        }
      }
    }
  }

  private func cropHandlePoint(_ i: Int, in view: CGRect) -> CGPoint {
    switch i {
    case 0: return CGPoint(x: view.minX, y: view.minY)
    case 1: return CGPoint(x: view.maxX, y: view.minY)
    case 2: return CGPoint(x: view.minX, y: view.maxY)
    default: return CGPoint(x: view.maxX, y: view.maxY)
    }
  }

  private func currentCropRect() -> NormalizedRect {
    history.current.crop?.rect ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)
  }

  private func setCropRect(_ rect: NormalizedRect) {
    var r = history.current
    var c = r.crop ?? CropRecipe()
    c.rect = rect
    r.crop = c
    history.commit(r)
  }

  private func moveCrop(by translation: CGSize, fit: CGSize) {
    guard fit.width > 0, fit.height > 0 else { return }
    let cur = currentCropRect()
    let dx = Double(translation.width / fit.width)
    let dy = Double(translation.height / fit.height)
    setCropRect(CropMath.clamped(NormalizedRect(
      x: cur.x + dx, y: cur.y + dy, width: cur.width, height: cur.height)))
  }

  private func dragCropHandle(_ i: Int, by translation: CGSize, fit: CGSize, origin: CGPoint) {
    guard fit.width > 0, fit.height > 0 else { return }
    // Translation accumulates from gesture start; recompute from the committed rect.
    let dx = Double(translation.width / fit.width)
    let dy = Double(translation.height / fit.height)
    let cur = currentCropRect()
    var x0 = cur.x
    var y0 = cur.y
    var x1 = cur.x + cur.width
    var y1 = cur.y + cur.height
    // Corner order: 0 TL, 1 TR, 2 BL, 3 BR (origin upper-left).
    if i == 0 || i == 2 { x0 += dx } else { x1 += dx }
    if i == 0 || i == 1 { y0 += dy } else { y1 += dy }
    setCropRect(CropMath.clamped(NormalizedRect(
      x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))))
  }
}

private struct ThirdsGrid: View {
  var body: some View {
    GeometryReader { geo in
      Path { p in
        for k in 1..<3 {
          let x = geo.size.width * CGFloat(k) / 3
          p.move(to: CGPoint(x: x, y: 0))
          p.addLine(to: CGPoint(x: x, y: geo.size.height))
          let y = geo.size.height * CGFloat(k) / 3
          p.move(to: CGPoint(x: 0, y: y))
          p.addLine(to: CGPoint(x: geo.size.width, y: y))
        }
      }
      .stroke(.white.opacity(0.8), lineWidth: 0.75)
    }
  }
}

/// Edit-mode tabs. Adjust|Styles|Crop|Tools are the spec segmented control;
/// markup lives under "…" and video appears for video assets (spec E2/E6/E8).
enum EditModeTab: String, Hashable {
  case adjust, styles, crop, tools, markup, video
}

// MARK: - Tool panels

extension MacEditModeView {
  @ViewBuilder
  private var toolPanel: some View {
    VStack(spacing: 0) {
      switch tab {
      case .adjust: adjustPanel
      case .styles: stylesPanel
      case .crop: cropPanel
      case .tools: toolsPanel
      case .markup: markupPanel
      case .video: videoPanel
      }
      Spacer(minLength: 0)
      historySection
      Button("Reset Adjustments", role: .destructive) {
        var r = history.current
        r.adjust = AdjustRecipe()
        history.commit(r)
      }
      .buttonStyle(.bordered)
      .padding(8)
    }
    .padding(8)
  }

  // MARK: - History (D6a version stack)

  /// Timestamp list of persisted Done versions. Tap-to-restore appends the
  /// restored recipe as a NEW version (never overwrites); Cancel still
  /// discards the in-progress edit without touching the stack. A plain
  /// button, not a DisclosureGroup: a collapsed DisclosureGroup is
  /// AX-invisible, so UI tests could never expand it (same reason as the
  /// section Options buttons).
  private var historySection: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button(historyExpanded ? "History ⌄" : "History ›") { historyExpanded.toggle() }
        .accessibilityIdentifier(AXIDs.editHistory)
        .font(.caption)
        .buttonStyle(.plain)
      if historyExpanded {
        if versionStore.isEmpty {
          Text("No saved versions yet.")
            .font(.caption).foregroundStyle(.secondary)
        } else {
          ForEach(versionStore.versions.indices, id: \.self) { i in
            HStack {
              Text(versionStore.versions[i].savedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
              Spacer()
              Button("Restore") { restoreVersion(at: i) }
                .accessibilityIdentifier(AXIDs.editHistoryRestore(i))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AXIDs.editHistoryRow(i))
          }
        }
      }
    }
  }

  private var isFixtureSeeded: Bool {
    HeirloomLaunchFlag.isPresent("-fixture-seed", legacy: "--fixture-seed")
  }

  /// Fixture-only seed (no server under `-fixture-seed`): two deterministic
  /// versions so UI tests can list History and exercise tap-to-restore
  /// without pressing Done on a real asset. Production never calls this.
  private func seedFixtureVersions() {
    guard versionStore.isEmpty else { return }
    versionStore = EditVersionStore(versions: [
      EditRecipeVersion(
        id: "fixture-v1", savedAt: Date(timeIntervalSince1970: 1_700_000_000),
        recipe: EditRecipe(adjust: AdjustRecipe(exposure: -40))),
      EditRecipeVersion(
        id: "fixture-v2", savedAt: Date(timeIntervalSince1970: 1_700_003_600),
        recipe: EditRecipe(adjust: AdjustRecipe(exposure: 50))),
    ])
  }

  private func restoreVersion(at index: Int) {
    guard let recipe = versionStore.restore(at: index) else { return }
    history.commit(recipe)
    elements = recipe.markup?.elements ?? []
    persistVersions()
  }

  /// Persists the stack beside the single-slot recipe. Fixture launches have
  /// no server: the stack stays in memory (fixture flag only).
  private func persistVersions() {
    guard !isFixtureSeeded else { return }
    let payload = EditVersionPayload(sourceAssetId: asset.id, versions: versionStore.versions)
    Task {
      do {
        try await persistence.saveVersions(payload)
      } catch {
        await MainActor.run { saveError = "Could not save version history: \(error)" }
      }
    }
  }

  // MARK: Adjust (spec E4)

  private var adjustPanel: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(EditAdjustSection.allCases, id: \.self) { section in
        if section == .depth {
          DepthSectionView(history: $history, source: previewCI)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AXIDs.editTab(section.rawValue))
        } else {
          EditAdjustSectionView(
            section: section,
            recipe: Binding(
              get: { history.current.adjust },
              set: { v in var r = history.current; r.adjust = v; history.commit(r) }),
            source: previewCI,
            eyedropperArmed: $eyedropperArmed)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AXIDs.editTab(section.rawValue))
        }
      }
    }
  }

  private var previewCI: CIImage? {
    guard let tiff = preview.tiffRepresentation else { return nil }
    return CIImage(data: tiff)
  }

  // MARK: Styles (spec E5)

  private var stylesPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Undertone").font(.caption).foregroundStyle(.secondary)
      styleGrid(EditStyle.undertonePresets)
      Text("Mood").font(.caption).foregroundStyle(.secondary)
      styleGrid(EditStyle.moodPresets)
      if usesClassicStyle {
        Text("Classic").font(.caption).foregroundStyle(.secondary)
        styleGrid(EditStyle.classicStyles)
      }
      HStack {
        Text("Intensity").font(.caption)
        Slider(
          value: Binding(
            get: { Double(history.current.style?.intensity ?? 100) },
            set: { v in
              var r = history.current
              let name = r.style?.style ?? .undertoneStandard
              r.style = StyleRecipe(style: name, intensity: Int(v))
              history.commit(r)
            }), in: 0...100)
      }
      Text("Existing filter recipes (Vivid …, Noir) keep rendering and appear above only in Classic.")
        .font(.caption2).foregroundStyle(.secondary)
    }
  }

  private var usesClassicStyle: Bool {
    guard let s = history.current.style?.style else { return false }
    return EditStyle.classicStyles.contains(s)
  }

  private func styleGrid(_ styles: [EditStyle]) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))]) {
      ForEach(styles, id: \.self) { style in
        Button {
          var r = history.current
          r.style = StyleRecipe(style: style, intensity: r.style?.intensity ?? 100)
          history.commit(r)
        } label: {
          VStack {
            styleThumb(style)
              .frame(width: 60, height: 60)
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
  }

  private func styleThumb(_ style: EditStyle) -> some View {
    Group {
      if let ci = previewCI,
        let cg = renderer.cgImage(
          source: ci, recipe: EditRecipe(style: StyleRecipe(style: style, intensity: 100)),
          previewMaxPixel: 128)
      {
        Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: 60, height: 60))).resizable()
      } else {
        Image(nsImage: preview).resizable()
      }
    }
  }

  // MARK: Crop (spec E6)

  private var cropPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Aspect").font(.caption).foregroundStyle(.secondary)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))]) {
        ForEach(CropAspect.allCases, id: \.self) { aspect in
          Button(aspect.displayName) { applyAspect(aspect) }
            .buttonStyle(.bordered)
            .tint(history.current.crop?.aspect == aspect ? .yellow : .gray)
        }
      }
      Picker("Orientation", selection: $cropOrientation) {
        Text("Landscape").tag(CropOrientation.landscape)
        Text("Portrait").tag(CropOrientation.portrait)
      }
      .pickerStyle(.segmented)
      .onChange(of: cropOrientation) { _, _ in
        if let aspect = history.current.crop?.aspect { applyAspect(aspect) }
      }
      cropDial(
        "Straighten", value: Binding(
          get: { history.current.crop?.straightenDegrees ?? 0 },
          set: { v in setCrop { $0.straightenDegrees = max(-45, min(45, v)) } }),
        range: -45...45)
      cropDial(
        "Vertical", value: Binding(
          get: { Double(history.current.crop?.perspectiveVertical ?? 0) },
          set: { v in setCrop { $0.perspectiveVertical = Int(v) } }),
        range: -45...45)
      cropDial(
        "Horizontal", value: Binding(
          get: { Double(history.current.crop?.perspectiveHorizontal ?? 0) },
          set: { v in setCrop { $0.perspectiveHorizontal = Int(v) } }),
        range: -45...45)
      HStack {
        Button("Flip H") { setCrop { $0.flipHorizontal.toggle() } }
        Button("Flip V") { setCrop { $0.flipVertical.toggle() } }
        Button("Rotate 90°") { bumpTurns() }
      }
      .buttonStyle(.bordered)
      HStack {
        Button("Auto") { Task { await autoStraighten() } }
        Button("Reset", role: .destructive) {
          var r = history.current
          r.crop = nil
          history.commit(r)
        }
      }
      .buttonStyle(.bordered)
      Text("Drag the photo to move the crop; drag corners to resize.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func cropDial(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
    HStack {
      Text(title).font(.caption).frame(width: 76, alignment: .leading)
      Slider(value: value, in: range, step: 1)
      Text(String(format: "%.0f°", value.wrappedValue))
        .font(.caption).monospacedDigit().frame(width: 40)
    }
  }

  private func applyAspect(_ aspect: CropAspect) {
    var r = history.current
    var c = r.crop ?? CropRecipe()
    c.aspect = aspect
    c.rect = CropMath.rect(for: aspect, orientation: cropOrientation)
    if CropMath.rect(for: aspect, orientation: cropOrientation) == NormalizedRect(x: 0, y: 0, width: 1, height: 1),
      aspect == .free
    {
      c.rect = nil
    }
    r.crop = c
    history.commit(r)
  }

  private func setCrop(_ mutate: (inout CropRecipe) -> Void) {
    var r = history.current
    var c = r.crop ?? CropRecipe()
    mutate(&c)
    r.crop = c
    history.commit(r)
  }

  private func bumpTurns() {
    var r = history.current
    var c = r.crop ?? CropRecipe()
    c.quarterTurns = (c.quarterTurns + 1) % 4
    r.crop = c
    history.commit(r)
  }

  private func autoStraighten() async {
    guard let tiff = preview.tiffRepresentation,
      let cg = CIImage(data: tiff).flatMap({ renderer.cgImage(source: $0, recipe: EditRecipe()) })
    else { return }
    do {
      let angle = try await renderer.suggestedStraightenAngle(for: cg)
      setCrop { $0.straightenDegrees = min(45, max(-45, angle)) }
    } catch {
      saveError = "No horizon found — straighten manually."
    }
  }

  // MARK: Tools (spec E8)

  @ViewBuilder
  private var toolsPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      if toolsRegistry.visibleTools.isEmpty {
        Text("No retouch tools are available on-device yet.")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        ForEach(toolsRegistry.visibleTools, id: \.id) { tool in
          Text(tool.title)
        }
      }
    }
  }

  // MARK: Markup (spec E6/E1 clip fix)

  private var markupPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Tool").font(.caption).foregroundStyle(.secondary)
      Picker("Markup tool", selection: $markupTool) {
        ForEach(MacMarkupTool.allCases, id: \.self) { t in Text(t.title).tag(t) }
      }
      .pickerStyle(.segmented)
      // Clip fix (E1): the segmented control + swatches keep their intrinsic size
      // inside the 280–380 pt panel instead of compressing to zero at 1280×800.
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
  }

  // MARK: Video (spec: trim tab + trim bar under the canvas)

  @ViewBuilder
  private var videoPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      if asset.type == .video {
        if let dur = videoDuration {
          Text("Trim: \(fmtTime(currentVideo.trimStart ?? 0)) – \(fmtTime(currentVideo.trimEnd ?? dur))")
            .font(.caption).monospacedDigit()
          Slider(
            value: Binding(
              get: { currentVideo.trimStart ?? 0 },
              set: { v in setVideo { $0.trimStart = min(v, (currentVideo.trimEnd ?? dur) - 0.5) } }),
            in: 0...max(0.5, dur - 0.5))
          Slider(
            value: Binding(
              get: { currentVideo.trimEnd ?? dur },
              set: { v in setVideo { $0.trimEnd = max(v, (currentVideo.trimStart ?? 0) + 0.5) } }),
            in: 0.5...dur)
        } else {
          ProgressView().task { await loadVideoDuration() }
        }
        Toggle("Mute", isOn: Binding(
          get: { currentVideo.muted },
          set: { v in setVideo { $0.muted = v } }))
      } else {
        Text("Still-image edits only for this asset.").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var videoTrimBar: some View {
    HStack(spacing: 12) {
      Text("Trim").font(.caption).foregroundStyle(.secondary)
      if let dur = videoDuration {
        Slider(
          value: Binding(
            get: { currentVideo.trimStart ?? 0 },
            set: { v in setVideo { $0.trimStart = min(v, (currentVideo.trimEnd ?? dur) - 0.5) } }),
          in: 0...max(0.5, dur - 0.5))
          .frame(maxWidth: 300)
        Text("\(fmtTime(currentVideo.trimStart ?? 0)) – \(fmtTime(currentVideo.trimEnd ?? dur)) / \(fmtTime(dur))")
          .font(.caption).monospacedDigit()
      } else {
        ProgressView().controlSize(.small).task { await loadVideoDuration() }
      }
      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }

  private var currentVideo: VideoRecipe { history.current.video ?? VideoRecipe() }

  private func setVideo(_ mutate: (inout VideoRecipe) -> Void) {
    var r = history.current
    var recipe = r.video ?? VideoRecipe()
    mutate(&recipe)
    r.video = recipe.isEmpty ? nil : recipe
    history.commit(r)
  }

  private func fmtTime(_ s: Double) -> String {
    String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
  }

  private func loadVideoDuration() async {
    guard let loader = loadVideoFile else { return }
    do {
      let av = AVURLAsset(url: try await loader())
      let dur = try await av.load(.duration).seconds
      videoDuration = dur.isFinite ? dur : nil
    } catch {
      videoDuration = nil
    }
  }
}

// MARK: - Adjust sections (spec E4)

/// One Adjust section: header row (title, AUTO, reset, enable toggle), a smart
/// filmstrip slider for the headline param, and an Options disclosure with fine
/// sliders. Sections with dedicated UI (D3 levels handles, D1 selective-color
/// swatches, D2 curve editor, D4 red-eye tools) render it instead of fine
/// sliders — see `deferredNote` for the rest.
enum EditAdjustSection: String, CaseIterable {
  case light, color, blackWhite, whiteBalance, curves, levels, definition
  case selectiveColor, noiseReduction, sharpen, vignette, depth, redEye

  var title: String {
    switch self {
    case .light: return "Light"
    case .color: return "Color"
    case .blackWhite: return "Black & White"
    case .whiteBalance: return "White Balance"
    case .curves: return "Curves"
    case .levels: return "Levels"
    case .definition: return "Definition"
    case .selectiveColor: return "Selective Color"
    case .noiseReduction: return "Noise Reduction"
    case .sharpen: return "Sharpen"
    case .vignette: return "Vignette"
    case .depth: return "Depth"
    case .redEye: return "Red-Eye"
    }
  }

  var icon: String {
    switch self {
    case .light: return "sun.max"
    case .color: return "paintpalette"
    case .blackWhite: return "circle.lefthalf.filled"
    case .whiteBalance: return "thermometer"
    case .curves: return "point.3.connected.trianglepath.dotted"
    case .levels: return "slider.horizontal.3"
    case .definition: return "circle.dotted"
    case .selectiveColor: return "eyedropper.halffull"
    case .noiseReduction: return "wind"
    case .sharpen: return "triangle"
    case .vignette: return "circle.dashed"
    case .depth: return "person.crop.circle"
    case .redEye: return "eye"
    }
  }

  /// Recipe keys owned by the section (enable toggle zeroes these; reset zeroes these).
  var keys: [WritableKeyPath<AdjustRecipe, Int>] {
    switch self {
    case .light: return [\.exposure, \.brilliance, \.highlights, \.shadows, \.brightness, \.contrast, \.blackPoint]
    case .color: return [\.saturation, \.vibrance, \.cast]
    case .blackWhite: return [\.bwIntensity, \.bwNeutrals, \.bwTone, \.grain]
    case .whiteBalance: return [\.wbTemperature, \.wbTint, \.warmth, \.tint]
    case .curves: return []
    case .levels: return [\.levelsInBlack, \.levelsInWhite, \.levelsOutBlack, \.levelsOutWhite]
    case .definition: return [\.definition]
    case .selectiveColor:
      return [
        \.selRedHue, \.selRedSat, \.selRedLum, \.selRedRange,
        \.selOrangeHue, \.selOrangeSat, \.selOrangeLum, \.selOrangeRange,
        \.selYellowHue, \.selYellowSat, \.selYellowLum, \.selYellowRange,
        \.selGreenHue, \.selGreenSat, \.selGreenLum, \.selGreenRange,
        \.selBlueHue, \.selBlueSat, \.selBlueLum, \.selBlueRange,
        \.selMagentaHue, \.selMagentaSat, \.selMagentaLum, \.selMagentaRange,
      ]
    case .noiseReduction: return [\.noiseReduction]
    case .sharpen: return [\.sharpness, \.sharpenEdges, \.sharpenFalloff]
    case .vignette: return [\.vignette, \.vignetteStrength, \.vignetteRadius, \.vignetteSoftness]
    case .redEye: return [\.redEyeStrength]
    case .depth: return []
    }
  }

  /// Point-array recipe keys owned by the section (D2 Curves: master RGB plus
  /// per-channel state). The header reset/enable toggle owns these alongside
  /// `keys` above.
  var curveKeys: [WritableKeyPath<AdjustRecipe, [CurvePoint]>] {
    switch self {
    case .curves: return [\.curvesMaster, \.curvesRed, \.curvesGreen, \.curvesBlue]
    default: return []
    }
  }

  /// Fine sliders in Options: (label, key path).
  var fineSliders: [(String, WritableKeyPath<AdjustRecipe, Int>)] {
    switch self {
    case .light:
      return [("Brilliance", \.brilliance), ("Exposure", \.exposure), ("Highlights", \.highlights),
        ("Shadows", \.shadows), ("Brightness", \.brightness), ("Contrast", \.contrast),
        ("Black Point", \.blackPoint)]
    case .color: return [("Saturation", \.saturation), ("Vibrance", \.vibrance), ("Cast", \.cast)]
    case .blackWhite:
      return [("Intensity", \.bwIntensity), ("Neutrals", \.bwNeutrals), ("Tone", \.bwTone), ("Grain", \.grain)]
    case .whiteBalance:
      return [("Temperature", \.wbTemperature), ("Tint", \.wbTint), ("Warmth", \.warmth), ("Cast Tint", \.tint)]
    case .curves: return []
    case .levels: return []
    case .definition: return [("Definition", \.definition)]
    case .selectiveColor: return []
    case .noiseReduction: return [("Noise Reduction", \.noiseReduction)]
    case .sharpen:
      return [("Intensity", \.sharpness), ("Edges", \.sharpenEdges), ("Falloff", \.sharpenFalloff)]
    case .vignette:
      return [("Strength", \.vignetteStrength), ("Radius", \.vignetteRadius),
        ("Softness", \.vignetteSoftness), ("Classic", \.vignette)]
    case .depth, .redEye: return []
    }
  }

  /// Headline param for the smart filmstrip slider (nil = no filmstrip).
  var filmstripKey: (String, WritableKeyPath<AdjustRecipe, Int>)? {
    switch self {
    case .light: return ("Exposure", \.exposure)
    case .color: return ("Saturation", \.saturation)
    case .blackWhite: return ("Intensity", \.bwIntensity)
    case .whiteBalance: return ("Temperature", \.wbTemperature)
    case .definition: return ("Definition", \.definition)
    case .noiseReduction: return ("Noise Reduction", \.noiseReduction)
    case .sharpen: return ("Edges", \.sharpenEdges)
    case .vignette: return ("Strength", \.vignetteStrength)
    default: return nil
    }
  }

  /// Honest capability note for sections without dedicated recipe keys.
  var deferredNote: String? {
    switch self {
    case .curves:
      return nil
    case .levels:
      return nil
    case .selectiveColor:
      return nil
    case .redEye:
      return nil
    default: return nil
    }
  }
}

private struct EditAdjustSectionView: View {
  var section: EditAdjustSection
  @Binding var recipe: AdjustRecipe
  var source: CIImage?
  @Binding var eyedropperArmed: Bool
  @State private var thumbs: [CGImage?] = []
  @State private var thumbsTask: Task<Void, Never>?
  @State private var sectionActive = true
  @State private var sectionExpanded = true
  @State private var optionsExpanded = false
  @State private var selectiveHue = 0
  @State private var redEyeThumb: CGImage?
  @State private var curveChannel: CurveChannel = .master
  @State private var armedPicker: CurvePicker? = nil

  var body: some View {
    // Sections default expanded: the filmstrip headline and Options rows are the
    // panel's working surface (and a collapsed group hides its content from AX,
    // leaving UI tests nothing to drive).
    DisclosureGroup(isExpanded: $sectionExpanded) {
      VStack(alignment: .leading, spacing: 6) {
        if let (label, key) = section.filmstripKey {
          filmstrip(label: label, key: key)
        }
        // A plain button, not a DisclosureGroup: a collapsed DisclosureGroup is
        // AX-invisible (no triangle, no label), so UI tests could never expand it.
        Button(optionsExpanded ? "Options ⌄" : "Options ›") { optionsExpanded.toggle() }
          .accessibilityIdentifier(AXIDs.editSectionOptions(section.rawValue))
          .font(.caption)
          .buttonStyle(.plain)
        if optionsExpanded {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(section.fineSliders, id: \.0) { label, key in
              fineSlider(label: label, key: key)
            }
            if section == .whiteBalance {
              whiteBalanceExtras
            }
            if section == .curves {
              curveEditor
            }
            if section == .levels {
              levelsHandles
            }
            if section == .selectiveColor {
              selectiveColorSection
            }
            if section == .redEye {
              redEyeTools
            }
            if let note = section.deferredNote {
              Text(note).font(.caption2).foregroundStyle(.secondary)
            }
          }
        }
      }
      .padding(.leading, 4)
    } label: {
      sectionHeader
    }
  }

  private var sectionHeader: some View {
    HStack(spacing: 6) {
      Image(systemName: section.icon).foregroundStyle(.secondary)
      Text(section.title)
      Spacer()
      if section == .light || section == .whiteBalance {
        Button("AUTO") { autoSection() }
          .buttonStyle(.bordered)
          .controlSize(.mini)
      }
      Button {
        for key in section.keys { recipe[keyPath: key] = 0 }
        // Region taps are not Int keys, so the generic reset cannot reach them.
        if section == .redEye { recipe.redEyeRegions = [] }
        for key in section.curveKeys { recipe[keyPath: key] = [] }
      } label: { Image(systemName: "arrow.counterclockwise") }
        .buttonStyle(.plain)
        .help("Reset \(section.title)")
      if !section.keys.isEmpty || !section.curveKeys.isEmpty {
        Toggle("", isOn: Binding(
          get: { sectionActive },
          set: { v in
            sectionActive = v
            if !v {
              for key in section.keys { recipe[keyPath: key] = 0 }
              if section == .redEye { recipe.redEyeRegions = [] }
              for key in section.curveKeys { recipe[keyPath: key] = [] }
            }
          }))
          .toggleStyle(.switch)
          .controlSize(.mini)
      }
    }
    .font(.callout)
  }

  private func autoSection() {
    switch section {
    case .light:
      recipe.autoEnhance = true
    case .whiteBalance:
      recipe.wbTemperature = 0
      recipe.wbTint = 0
      recipe.warmth = 0
      recipe.tint = 0
    default: break
    }
  }

  private func fineSlider(
    label: String, key: WritableKeyPath<AdjustRecipe, Int>, axKey: String? = nil
  ) -> some View {
    HStack {
      Text(label).font(.caption).frame(width: 88, alignment: .leading)
      Slider(value: Binding(
        get: { Double(recipe[keyPath: key]) },
        set: { recipe[keyPath: key] = Int($0.rounded()) }), in: -100...100)
        .accessibilityIdentifier(AXIDs.editSlider(axKey ?? label))
      Text("\(recipe[keyPath: key])").font(.caption).monospacedDigit().frame(width: 36)
    }
  }

  private func filmstrip(label: String, key: WritableKeyPath<AdjustRecipe, Int>) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      HStack(spacing: 4) {
        ForEach([-100, -50, 0, 50, 100], id: \.self) { strength in
          Button {
            recipe[keyPath: key] = strength
          } label: {
            if let cg = thumbImage(for: strength) {
              Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: 48, height: 48)))
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                  RoundedRectangle(cornerRadius: 6)
                    .stroke(recipe[keyPath: key] == strength ? .yellow : .clear, lineWidth: 2))
            } else {
              RoundedRectangle(cornerRadius: 6)
                .fill(.gray.opacity(0.3))
                .frame(width: 48, height: 48)
            }
          }
          .buttonStyle(.plain)
        }
      }
    }
    .task {
      // Thumbnails render once per section from the section-open recipe, off-main.
      // `CIImage` is immutable and render-safe across threads (same basis as
      // `EditRenderer`'s `@unchecked Sendable`); the unchecked box only crosses
      // the isolation boundary, and results publish back on the main actor.
      guard let source else { return }
      let base = EditRecipe(adjust: recipe)
      let boxed = UncheckedCIImage(source)
      let recipes = [-100, -50, 0, 50, 100].map { strength -> EditRecipe in
        var r = base
        r.adjust[keyPath: key] = strength
        return r
      }
      thumbsTask?.cancel()
      thumbsTask = Task { @MainActor in
        thumbs = await editFilmstripThumbs(source: boxed, recipes: recipes)
      }
    }
  }

  private func thumbImage(for strength: Int) -> CGImage? {
    let idx: Int
    switch strength {
    case -100: idx = 0
    case -50: idx = 1
    case 0: idx = 2
    case 50: idx = 3
    default: idx = 4
    }
    guard thumbs.indices.contains(idx) else { return nil }
    return thumbs[idx]
  }

  private var whiteBalanceExtras: some View {
    HStack {
      Text("Neutral Gray / Skin Tone").font(.caption)
      Spacer()
      Button(eyedropperArmed ? "Cancel eyedropper" : "Eyedropper") {
        eyedropperArmed.toggle()
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
  }

  /// True input/output handles (D3): two dual-thumb sliders over the dedicated
  /// levels keys. Crossing is clamped — low never passes high and vice versa.
  private var levelsHandles: some View {
    VStack(alignment: .leading, spacing: 4) {
      DualThumbSlider(
        title: "Input", low: $recipe.levelsInBlack, high: $recipe.levelsInWhite,
        axLow: AXIDs.editSlider("levels-input-black"),
        axHigh: AXIDs.editSlider("levels-input-white"),
        axReadout: AXIDs.editSlider("levels-input-readout"))
      DualThumbSlider(
        title: "Output", low: $recipe.levelsOutBlack, high: $recipe.levelsOutWhite,
        axLow: AXIDs.editSlider("levels-output-black"),
        axHigh: AXIDs.editSlider("levels-output-white"),
        axReadout: AXIDs.editSlider("levels-output-readout"))
    }
  }

  /// Swatch picker + per-hue sliders (D1): six hue swatches, each with
  /// Hue/Saturation/Luminance/Range sliders over the dedicated recipe keys.
  /// Every control carries an `AXIDs.editSlider`-style contract ID
  /// (`sel-swatch-<id>`, `sel-<id>-hue|saturation|luminance|range`).
  private var selectiveColorSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        ForEach(SelectiveHue.allCases) { hue in
          Button {
            selectiveHue = hue.rawValue
          } label: {
            Circle()
              .fill(hue.color)
              .frame(width: 22, height: 22)
              .overlay(
                Circle()
                  .stroke(selectiveHue == hue.rawValue ? .yellow : .clear, lineWidth: 2))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier(AXIDs.editSlider("sel-swatch-\(hue.axID)"))
          .accessibilityLabel("\(hue.title) swatch")
        }
      }
      let hue = SelectiveHue(rawValue: selectiveHue) ?? .reds
      fineSlider(label: "Hue", key: hue.hueKey, axKey: "sel-\(hue.axID)-hue")
      fineSlider(label: "Saturation", key: hue.satKey, axKey: "sel-\(hue.axID)-saturation")
      fineSlider(label: "Luminance", key: hue.lumKey, axKey: "sel-\(hue.axID)-luminance")
      fineSlider(label: "Range", key: hue.rangeKey, axKey: "sel-\(hue.axID)-range")
    }
  }

  /// Tap-to-select eye regions + strength (D4). Taps on the canvas land as
  /// normalized regions (capped at 10); Detect Faces seeds them from Vision
  /// eye landmarks instead. The first tap arms the section (strength 0 → 100)
  /// so a placed correction renders immediately.
  private var redEyeTools: some View {
    VStack(alignment: .leading, spacing: 4) {
      redEyeCanvas
      HStack {
        Text(verbatim: redEyeCountText)
          .font(.caption).foregroundStyle(.secondary)
          .accessibilityIdentifier(AXIDs.editSlider("redeye-count"))
        Spacer()
        Button("Detect Faces") { detectFaces() }
          .buttonStyle(.plain).font(.caption)
          .disabled(source == nil)
        Button("Clear") { recipe.redEyeRegions = [] }
          .buttonStyle(.plain).font(.caption)
          .disabled(recipe.redEyeRegions.isEmpty)
      }
      fineSlider(label: "Strength", key: \.redEyeStrength, axKey: "redeye-strength")
    }
  }

  private var redEyeCountText: String {
    switch recipe.redEyeRegions.count {
    case 0: return "No corrections"
    case 1: return "1 correction"
    default: return "\(recipe.redEyeRegions.count) corrections"
    }
  }

  /// Placement canvas: a stretched source thumbnail (stretch keeps the tap →
  /// normalized mapping exact) with a marker per region. A zero-distance drag
  /// is a click, so UI-test clicks land here as placements.
  private var redEyeCanvas: some View {
    GeometryReader { geo in
      ZStack {
        if let redEyeThumb {
          Image(nsImage: NSImage(cgImage: redEyeThumb, size: NSSize(width: 320, height: 200)))
            .resizable()
        } else {
          RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.3))
        }
        ForEach(recipe.redEyeRegions.indices, id: \.self) { i in
          let r = recipe.redEyeRegions[i]
          Circle()
            .stroke(.yellow, lineWidth: 2)
            .frame(width: 14, height: 14)
            .position(x: CGFloat(r.x) * geo.size.width, y: CGFloat(r.y) * geo.size.height)
        }
      }
      .gesture(DragGesture(minimumDistance: 0).onEnded { d in
        placeRedEye(at: d.location, in: geo.size)
      })
      .accessibilityElement(children: .ignore)
      .accessibilityIdentifier(AXIDs.editSlider("redeye-canvas"))
      .accessibilityLabel("Red-eye tap canvas")
      .accessibilityValue(redEyeCountText)
    }
    .frame(height: 120)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .task {
      guard let source else { return }
      let thumbs = await editFilmstripThumbs(
        source: UncheckedCIImage(source), recipes: [EditRecipe()])
      redEyeThumb = thumbs.first ?? nil
    }
  }

  private func placeRedEye(at location: CGPoint, in size: CGSize) {
    guard size.width > 0, size.height > 0, recipe.redEyeRegions.count < 10 else { return }
    recipe.redEyeRegions.append(RedEyeRegion(
      x: min(1, max(0, location.x / size.width)),
      y: min(1, max(0, location.y / size.height))))
    if recipe.redEyeStrength == 0 { recipe.redEyeStrength = 100 }
  }

  /// Seeds regions from on-device Vision eye landmarks (Tier A: Vision + Core
  /// Image only). No faces (or no landmarks) leaves the recipe untouched.
  private func detectFaces() {
    guard let source else { return }
    let boxed = UncheckedCIImage(source)
    Task { @MainActor in
      let thumbs = await editFilmstripThumbs(source: boxed, recipes: [EditRecipe()])
      guard let cg = thumbs.first ?? nil else { return }
      let found = (try? await EditRenderer().suggestedRedEyeRegions(for: cg)) ?? []
      guard !found.isEmpty else { return }
      recipe.redEyeRegions = Array((recipe.redEyeRegions + found).prefix(10))
      if recipe.redEyeStrength == 0 { recipe.redEyeStrength = 100 }
    }
  }

  /// Points binding for the selected curve channel (D2 per-channel state).
  private var curvePoints: Binding<[CurvePoint]> {
    Binding(
      get: { curveChannel.points(recipe) },
      set: { curveChannel.set(&recipe, $0) })
  }

  /// Full RGB + per-channel curve editor (D2): channel selector, custom curve
  /// canvas with point add/drag, and black/grey/white pickers.
  private var curveEditor: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        ForEach(CurveChannel.allCases) { ch in
          Button(ch.title) { curveChannel = ch }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fontWeight(ch == curveChannel ? .bold : .regular)
            .accessibilityIdentifier(ch.axID)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(AXIDs.editSlider("curves-channel"))
      CurveCanvas(
        points: curvePoints, picker: $armedPicker,
        axCanvas: AXIDs.editSlider("curves-canvas"),
        axReadout: AXIDs.editSlider("curves-readout"),
        axPoint: AXIDs.editSlider("curves-point"))
      HStack(spacing: 4) {
        ForEach(CurvePicker.allCases) { p in
          Button(armedPicker == p ? "\(p.title)…" : p.title) {
            armedPicker = (armedPicker == p) ? nil : p
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityIdentifier(p.axID)
        }
        Spacer()
        Button("Clear") { curvePoints.wrappedValue = [] }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityIdentifier(AXIDs.editSlider("curves-clear"))
      }
    }
  }
}

/// Curve channel (D2): master RGB composite plus isolated per-channel state.
private enum CurveChannel: String, CaseIterable, Identifiable {
  case master, red, green, blue

  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var axID: String { AXIDs.editSlider("curves-channel-" + rawValue) }

  func points(_ recipe: AdjustRecipe) -> [CurvePoint] {
    switch self {
    case .master: return recipe.curvesMaster
    case .red: return recipe.curvesRed
    case .green: return recipe.curvesGreen
    case .blue: return recipe.curvesBlue
    }
  }

  func set(_ recipe: inout AdjustRecipe, _ pts: [CurvePoint]) {
    switch self {
    case .master: recipe.curvesMaster = pts
    case .red: recipe.curvesRed = pts
    case .green: recipe.curvesGreen = pts
    case .blue: recipe.curvesBlue = pts
    }
  }
}

/// Black/grey/white pickers (D2): arming one makes the next canvas click pin
/// the black rail (`x = 0`), the white rail (`x = 1`), or a midtone anchor.
private enum CurvePicker: String, CaseIterable, Identifiable {
  case black, grey, white

  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var axID: String { AXIDs.editSlider("curves-picker-" + rawValue) }
}

/// Custom curve canvas (D2): click/drag adds a point or moves the nearest one
/// (25pt grab radius), an armed picker pins rails instead, and arrow keys nudge
/// the last-touched point ±0.01 (keyboard-accessible editing, and UI-test
/// drivable like the D3 handles).
private struct CurveCanvas: View {
  private static let height: Double = 160
  private static let grabRadius: Double = 25
  private static let keyStep = 0.01
  private static let railSnap = 0.02

  @Binding var points: [CurvePoint]
  @Binding var picker: CurvePicker?
  let axCanvas: String
  let axReadout: String
  let axPoint: String
  @State private var dragIndex: Int? = nil
  @State private var lastIndex: Int? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: "points: \(points.count)")
        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        .accessibilityIdentifier(axReadout)
      Text(verbatim: lastText)
        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        .accessibilityIdentifier(axPoint)
      GeometryReader { geo in
        let size = CGSize(width: geo.size.width, height: Self.height)
        ZStack {
          Rectangle().fill(.gray.opacity(0.15))
          grid(in: size)
          curveLine(in: size)
          ForEach(points.indices, id: \.self) { i in
            Circle()
              .fill(.white)
              .frame(width: 12, height: 12)
              .overlay(Circle().stroke(Color.accentColor, lineWidth: i == lastIndex ? 3 : 1))
              .position(position(of: points[i], in: size))
          }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { d in apply(at: d.location, in: size) }
            .onEnded { _ in dragIndex = nil })
      }
      .frame(height: Self.height)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(axCanvas)
    .focusable()
    .onKeyPress(.upArrow) { nudge(dx: 0, dy: Self.keyStep); return .handled }
    .onKeyPress(.downArrow) { nudge(dx: 0, dy: -Self.keyStep); return .handled }
    .onKeyPress(.leftArrow) { nudge(dx: -Self.keyStep, dy: 0); return .handled }
    .onKeyPress(.rightArrow) { nudge(dx: Self.keyStep, dy: 0); return .handled }
  }

  private var lastText: String {
    let idx = (lastIndex.flatMap { points.indices.contains($0) ? $0 : nil }) ?? points.indices.last
    guard let i = idx else { return "last: —" }
    return String(format: "last: (%.2f, %.2f)", points[i].x, points[i].y)
  }

  private func position(of p: CurvePoint, in size: CGSize) -> CGPoint {
    CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
  }

  private func distance(of p: CurvePoint, from origin: CGPoint, in size: CGSize) -> Double {
    let q = position(of: p, in: size)
    return hypot(q.x - origin.x, q.y - origin.y)
  }

  private func unit(at loc: CGPoint, in size: CGSize) -> CurvePoint {
    CurvePoint(x: loc.x / size.width, y: 1 - loc.y / size.height)
  }

  private func upsert(_ pt: CurvePoint) {
    if let i = points.firstIndex(where: { abs($0.x - pt.x) < Self.railSnap }) {
      points[i] = pt
      lastIndex = i
    } else {
      points.append(pt)
      lastIndex = points.indices.last
    }
  }

  private func apply(at loc: CGPoint, in size: CGSize) {
    guard size.width > 1, size.height > 1 else { return }
    let pt = unit(at: loc, in: size)
    if picker == .black {
      upsert(CurvePoint(x: 0, y: pt.y))
      picker = nil
      return
    }
    if picker == .white {
      upsert(CurvePoint(x: 1, y: pt.y))
      picker = nil
      return
    }
    picker = nil
    if dragIndex == nil {
      let origin = position(of: pt, in: size)
      var near: Int? = nil
      var best = Self.grabRadius
      for i in points.indices {
        let d = distance(of: points[i], from: origin, in: size)
        if d <= best {
          best = d
          near = i
        }
      }
      if let near {
        dragIndex = near
      } else {
        points.append(pt)
        dragIndex = points.indices.last
      }
    }
    if let i = dragIndex, points.indices.contains(i) {
      points[i] = pt
      lastIndex = i
    }
  }

  private func nudge(dx: Double, dy: Double) {
    let idx = (lastIndex.flatMap { points.indices.contains($0) ? $0 : nil }) ?? points.indices.last
    guard let i = idx else { return }
    points[i] = CurvePoint(x: points[i].x + dx, y: points[i].y + dy)
    lastIndex = i
  }

  private func grid(in size: CGSize) -> some View {
    Path { path in
      for f in [1.0 / 3, 2.0 / 3] {
        path.move(to: CGPoint(x: size.width * f, y: 0))
        path.addLine(to: CGPoint(x: size.width * f, y: size.height))
        path.move(to: CGPoint(x: 0, y: size.height * f))
        path.addLine(to: CGPoint(x: size.width, y: size.height * f))
      }
      path.move(to: CGPoint(x: 0, y: size.height))
      path.addLine(to: CGPoint(x: size.width, y: 0))
    }
    .stroke(.gray.opacity(0.4), lineWidth: 1)
  }

  private func curveLine(in size: CGSize) -> some View {
    Path { path in
      let n = 64
      for k in 0...n {
        let x = Double(k) / Double(n)
        let p = CGPoint(x: x * size.width, y: (1 - CurvePoint.evaluate(points, at: x)) * size.height)
        if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
      }
    }
    .stroke(Color.accentColor, lineWidth: 2)
  }
}

/// Dual-handle 0...100 range slider (D3 Levels input/output). Each handle drags
/// continuously and is also an adjustable AX element (swipe steps ±5) so UI
/// tests can drive it. Crossing is clamped: low never passes high and vice versa.
private struct DualThumbSlider: View {
  private static let diameter: Double = 14
  private static let step = 5

  let title: String
  @Binding var low: Int
  @Binding var high: Int
  let axLow: String
  let axHigh: String
  let axReadout: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title).font(.caption)
        Spacer()
        Text(verbatim: "\(low) - \(high)")
          .font(.caption).monospacedDigit().foregroundStyle(.secondary)
          .accessibilityIdentifier(axReadout)
      }
      GeometryReader { geo in
        let span = max(1, geo.size.width - Self.diameter)
        ZStack(alignment: .leading) {
          Capsule().fill(.gray.opacity(0.3)).frame(height: 4)
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.accentColor)
            .frame(width: span * CGFloat(high - low) / 100, height: 4)
            .offset(x: span * CGFloat(low) / 100 + Self.diameter / 2)
          handle(
            value: low, span: span, ax: axLow, label: "\(title) low handle",
            set: { low = min($0, high) })
          handle(
            value: high, span: span, ax: axHigh, label: "\(title) high handle",
            set: { high = max($0, low) })
        }
        .frame(height: 22)
      }
      .frame(height: 22)
    }
  }

  private func handle(
    value: Int, span: Double, ax: String, label: String, set: @escaping (Int) -> Void
  ) -> some View {
    Circle()
      .fill(.white)
      .shadow(radius: 1)
      .frame(width: Self.diameter, height: Self.diameter)
      .offset(x: span * CGFloat(value) / 100)
      .gesture(DragGesture(minimumDistance: 1).onChanged { d in
        let v = Int(((d.location.x - Self.diameter / 2) / span * 100).rounded())
        set(min(100, max(0, v)))
      })
      .focusable()
      .onKeyPress(.upArrow) { set(min(100, value + 1)); return .handled }
      .onKeyPress(.downArrow) { set(max(0, value - 1)); return .handled }
      .accessibilityElement(children: .ignore)
      .accessibilityAdjustableAction { dir in
        switch dir {
        case .increment: set(min(100, value + Self.step))
        case .decrement: set(max(0, value - Self.step))
        @unknown default: break
        }
      }
      .accessibilityIdentifier(ax)
      .accessibilityLabel(label)
      .accessibilityValue("\(value)")
  }
}

/// The six Selective Color swatches (D1), in hue order. Each maps to its four
/// recipe keys; `color` is the picker dot only (never sampled by the renderer,
/// which computes hue from the pixel itself).
private enum SelectiveHue: Int, CaseIterable, Identifiable {
  case reds, oranges, yellows, greens, blues, magentas

  var id: Int { rawValue }

  var axID: String {
    switch self {
    case .reds: return "reds"
    case .oranges: return "oranges"
    case .yellows: return "yellows"
    case .greens: return "greens"
    case .blues: return "blues"
    case .magentas: return "magentas"
    }
  }

  var title: String { axID.capitalized }

  var color: Color {
    switch self {
    case .reds: return .red
    case .oranges: return .orange
    case .yellows: return .yellow
    case .greens: return .green
    case .blues: return .blue
    case .magentas: return .purple
    }
  }

  var hueKey: WritableKeyPath<AdjustRecipe, Int> {
    switch self {
    case .reds: return \.selRedHue
    case .oranges: return \.selOrangeHue
    case .yellows: return \.selYellowHue
    case .greens: return \.selGreenHue
    case .blues: return \.selBlueHue
    case .magentas: return \.selMagentaHue
    }
  }

  var satKey: WritableKeyPath<AdjustRecipe, Int> {
    switch self {
    case .reds: return \.selRedSat
    case .oranges: return \.selOrangeSat
    case .yellows: return \.selYellowSat
    case .greens: return \.selGreenSat
    case .blues: return \.selBlueSat
    case .magentas: return \.selMagentaSat
    }
  }

  var lumKey: WritableKeyPath<AdjustRecipe, Int> {
    switch self {
    case .reds: return \.selRedLum
    case .oranges: return \.selOrangeLum
    case .yellows: return \.selYellowLum
    case .greens: return \.selGreenLum
    case .blues: return \.selBlueLum
    case .magentas: return \.selMagentaLum
    }
  }

  var rangeKey: WritableKeyPath<AdjustRecipe, Int> {
    switch self {
    case .reds: return \.selRedRange
    case .oranges: return \.selOrangeRange
    case .yellows: return \.selYellowRange
    case .greens: return \.selGreenRange
    case .blues: return \.selBlueRange
    case .magentas: return \.selMagentaRange
    }
  }
}

/// Depth section: migrates the old Portrait tab (spec E4). Requires depth data in
/// the source file; otherwise the section explains unavailability.
private struct DepthSectionView: View {
  @Binding var history: EditHistory
  var source: CIImage?

  var body: some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 6) {
        if isAvailable {
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
          Text("No depth data in this photo — Depth is unavailable.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(.leading, 4)
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
        Text("Depth")
        Spacer()
      }
      .font(.callout)
    }
  }

  private var isAvailable: Bool {
    guard let source else { return false }
    return EditRenderer.portraitAvailable(source: source)
  }
}

// MARK: - Open / render / save

extension MacEditModeView {
  private func openSession() async {
    // Edit.Open signpost (E2/E7): chrome + proxy must be on screen ≤ 300 ms.
    // The proxy is the initial state, so this brackets the open path.
    await HeirloomSignpost.interval(HeirloomSignpost.editOpen) {}
    NotificationCenter.default.post(
      name: .heirloomEditModeActive, object: nil, userInfo: ["active": true])
    guard !hasLoadedRecipe else { return }
    hasLoadedRecipe = true
    do {
      if let payload = try await persistence.fetchRecipe(assetId: asset.id),
        payload.format == EditRecipeKey.current
      {
        history = EditHistory(initial: payload.recipe)
        elements = payload.recipe.markup?.elements ?? []
      }
      // D6a: the version stack lives beside the single-slot recipe.
      if isFixtureSeeded {
        seedFixtureVersions()
      } else if let stack = try await persistence.fetchVersions(assetId: asset.id),
        stack.format == EditVersionKey.current
      {
        versionStore = EditVersionStore(versions: stack.versions)
      }
    } catch {
      // Offline or never edited — start clean, not an error.
      if isFixtureSeeded { seedFixtureVersions() }
    }
    rerenderPreview()
    loader.beginLoading()
    originalPhase = .loadingOriginal
    do {
      let data = try await loadOriginalData()
      loader.complete(with: data)
      originalPhase = loader.state
      promoteOriginal()
    } catch {
      loader.fail()
      originalPhase = loader.state
      saveError = "Could not load the original: \(error). Editing the preview; Done is disabled."
    }
  }

  private func promoteOriginal() {
    // Once the original arrives, re-render the canvas from it (spec E2).
    guard loader.state == .ready, let data = loader.originalData,
      let image = NSImage(data: data)
    else { return }
    canvasSource = image
    rerenderPreview()
  }

  private func rerenderPreview() {
    renderTask?.cancel()
    let recipe = history.current
    let src = canvasSource
    renderTask = Task { @MainActor in
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

  private func syncMarkupRecipe() {
    var r = history.current
    if elements.isEmpty {
      if r.markup != nil {
        r.markup = nil
        history.commit(r)
      }
    } else {
      r.markup = MarkupRecipe(elements: elements)
      if r != history.current { history.commit(r) }
    }
  }

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

  /// White-balance eyedropper (spec E4): samples the tapped preview pixel and
  /// neutralizes it via the Temperature-Tint keys.
  private func sampleWhiteBalance(at location: CGPoint, geo: GeometryProxy, fit: CGSize) {
    eyedropperArmed = false
    guard let tiff = preview.tiffRepresentation,
      let cg = CGImageSourceCreateWithData(tiff as CFData, nil).flatMap({
        CGImageSourceCreateImageAtIndex($0, 0, nil)
      })
    else { return }
    let ox = (geo.size.width - fit.width) / 2
    let oy = (geo.size.height - fit.height) / 2
    let px = (location.x - ox) / fit.width
    let py = (location.y - oy) / fit.height
    guard (0...1).contains(px), (0...1).contains(py) else { return }
    let sx = min(cg.width - 1, max(0, Int(px * Double(cg.width))))
    let sy = min(cg.height - 1, max(0, Int(py * Double(cg.height))))
    guard let data = cg.dataProvider?.data as Data?, cg.bitsPerPixel >= 24 else { return }
    let bpp = cg.bitsPerPixel / 8
    let off = sy * cg.bytesPerRow + sx * bpp
    guard off + 2 < data.count else { return }
    let r = Double(data[off]) / 255
    let g = Double(data[off + 1]) / 255
    let b = Double(data[off + 2]) / 255
    let avg = (r + g + b) / 3 + 1e-6
    var adjust = history.current.adjust
    adjust.wbTemperature = AdjustRecipe.clamp(Int(((b - r) / avg) * 120))
    adjust.wbTint = AdjustRecipe.clamp(Int(((g - avg) / avg) * 160))
    var full = history.current
    full.adjust = adjust
    history.commit(full)
  }

  private func editExternally() async {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("heirloom-edit-\(asset.id).jpg")
    guard let tiff = renderedPreview.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let jpg = rep.representation(using: .jpeg, properties: [:])
    else {
      saveError = "Could not stage the preview for external editing."
      return
    }
    do {
      try jpg.write(to: tmp)
      NSWorkspace.shared.open(tmp)
    } catch {
      saveError = "Could not stage the preview: \(error)"
    }
  }

  private var editSavingOverlay: some View {
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
        await MainActor.run {
          saving = false
          onDone(renderedId)
          onExit()
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
    if !elements.isEmpty { recipe.markup = MarkupRecipe(elements: elements) }
    // Export uses the original only (spec E2); Done is gated until it loads.
    let originalData: Data
    if let cached = loader.originalData {
      originalData = cached
    } else if let fresh = try? await loadOriginalData() {
      originalData = fresh
    } else {
      throw EditRenderError.undecodableSource
    }
    guard let srcCI = CIImage(data: originalData) else { throw EditRenderError.undecodableSource }
    let size = srcCI.extent.size
    let split = try EditSplitter.split(recipe, imageSize: size)
    try await persistence.applyUpstreamEdits(assetId: asset.id, items: split.upstream)
    if split.needsClientRender {
      let overlay = renderMarkupOverlay(elements, pixelSize: size)
      let report = try renderer.export(
        sourceData: originalData, recipe: recipe,
        format: exportFormat(for: asset.originalFileName),
        markupOverlay: overlay)
      let isHeic = editIsHEIC(report.data)
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
    // D6a: each Done appends a new version, never overwrites.
    await MainActor.run { versionStore.append(recipe, renderedAssetId: nil) }
    persistVersions()
    return nil
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
    // E1: the export lands as the asset's rendition (same asset, one timeline item).
    try await persistence.uploadRendition(assetId: asset.id, upload: upload)
    // E1: no separate rendered asset exists, so renderedAssetId stays nil.
    try await persistence.saveRecipe(EditPersistencePayload(
      sourceAssetId: asset.id, recipe: full, renderedAssetId: nil))
    // D6a: each Done appends a new version, never overwrites.
    let doneRecipe = full
    await MainActor.run { versionStore.append(doneRecipe, renderedAssetId: nil) }
    persistVersions()
    return nil
  }
}

private func editIsHEIC(_ data: Data) -> Bool {
  guard data.count > 12 else { return false }
  let brand = String(data: data[8..<12], encoding: .ascii) ?? ""
  return brand == "heic" || brand == "heix" || brand == "hevc" || brand == "hevx"
}
