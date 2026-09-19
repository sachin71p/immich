import AppKit
import CoreModel
import Editing
import LocalStore
import Media
import Rules
import Search
import SwiftUI

/// Asset viewer (WP-V): `NSPageController` pager (1:1 swipe, arrows), zoomable
/// image pages with a Live Text overlay, video/live pages, pinch-to-close and
/// open/close transitions, Photos-order toolbar/title/badges/chevrons/keys,
/// context menu and the in-window Info inspector.
struct MacViewerView: View {
  @Bindable var state: MacAppState
  var assetId: String
  /// Non-nil when hosted inline in `MacLibraryBrowser`: arrow-key paging updates `assetId` in
  /// place instead of opening another window. Nil in the standalone `MacWindow.viewer` scene
  /// (`File > New Viewer Window`).
  var onNavigate: ((String) -> Void)? = nil
  /// Non-nil when hosted inline: shows a back button/Escape to return to the library instead of
  /// relying on the window's own close button.
  var onClose: (() -> Void)? = nil

  init(
    state: MacAppState, assetId: String, onNavigate: ((String) -> Void)? = nil,
    onClose: (() -> Void)? = nil
  ) {
    self.state = state
    self.assetId = assetId
    self.onNavigate = onNavigate
    self.onClose = onClose
    _selectedID = State(initialValue: assetId)
  }

  /// Pager selection (V5/V6): pages in place in both inline and standalone
  /// windows; `onNavigate` additionally mirrors the id to the inline parent.
  @State private var selectedID: String
  @State private var chromeAsset: Asset?
  @State private var pageStore: ViewerPageStore?
  @State private var pagerHost: ViewerPagerViewController?
  /// Display rotation in clockwise quarter turns: reset on every page change;
  /// the persisted rotation arrives back through the pipeline, never through this state.
  @State private var quarterTurns = 0
  @State private var rotationError: String?
  /// "San Jose, California" for the title subtitle, from the EXIF row.
  @State private var titlePlace: String?
  /// Toolbar zoom slider ↔ page magnification binding (V8/V9, both directions).
  @State private var sliderValue = 1.0
  @State private var hoverEdge: ChevronVisibility.Edge?
  /// Interactive pinch-close snapshot overlay scale (V7), nil at rest.
  @State private var pinchScale: CGFloat?
  @State private var showingInspector = false
  @State private var showingMove = false
  /// WP-E E1/E2: full-window edit mode replaces the viewer content (first click
  /// on Edit, Return, or the `HeirloomViewer.openEdit` notification).
  @State private var showingEditMode = false
  /// Pixel preview for the edit shell: the placeholder tier is enough to open
  /// (mirrors WP-E's progressive `image`); cleared on page change.
  @State private var editPreviewImage: NSImage?
  @State private var editPreviewTask: Task<Void, Never>?
  @State private var showingAddToAlbum = false
  @State private var error: String?
  // Hosted inline, this view replaces an NSCollectionView (the grid) that held first responder —
  // SwiftUI doesn't hand keyboard focus to the new content automatically, so arrow-key paging
  // silently did nothing until something explicitly claims focus.
  @FocusState private var isFocused: Bool

  private var assetActions: MacAssetActions {
    MacAssetActions(
      favorite: { toggleFavorite() },
      rotate: { rotateClockwise() },
      trash: { trash() },
      move: { showingMove = true },
      addToAlbum: { showingAddToAlbum = true },
      toggleInspector: { showingInspector.toggle() },
      openViewer: {},
      // Space on an image page closes the viewer (V13); on a video page the
      // focused player consumes Space itself (play/pause, V3), so this closure
      // is the image-page and unfocused path — no double-fire.
      preview: { closeOrDismissPreview() }
    )
  }

  /// Window title (V9, SPEC-TOOLBAR-SETTINGS §2a): place name, falling back to
  /// the capture date.
  private var viewerTitle: String {
    guard let date = chromeAsset?.localDateTime else { return "Viewer" }
    return ViewerHeaderFormatter.title(place: titlePlace, date: date)
  }

  /// Subtitle (V9/V19): "Month d, yyyy at h:mm:ss a · N of M"; the counter is
  /// hidden for single-item contexts.
  private var viewerSubtitle: String {
    guard let date = chromeAsset?.localDateTime else { return "" }
    guard let context = effectiveContext, !context.rows.isEmpty, let at = index else {
      return ViewerHeaderFormatter.subtitle(
        date: date, index: 0, total: 1)
    }
    return ViewerHeaderFormatter.subtitle(
      date: date, index: at, total: context.rows.count)
  }

  /// Display rotation in degrees from the quarter-turn count.
  private var rotationDegrees: Double { Double(((quarterTurns % 4) + 4) % 4) * 90 }

  private func rotationFitScale(container: CGSize) -> CGFloat {
    guard quarterTurns % 2 != 0 else { return 1 }
    let w: CGFloat
    let h: CGFloat
    if let aw = chromeAsset?.width, let ah = chromeAsset?.height, aw > 0, ah > 0 {
      w = CGFloat(aw)
      h = CGFloat(ah)
    } else {
      return 1
    }
    guard container.width > 0, container.height > 0 else { return 1 }
    let fit = min(container.width / w, container.height / h)
    guard fit > 0 else { return 1 }
    return min(container.width / h, container.height / w) / fit
  }

  /// Display-order paging context: falls back to a one-element snapshot when
  /// `viewerContext` is nil (a window opened from Search, Map or a deep link).
  /// The fallback stays local so a standalone viewer window never clobbers the
  /// library's shared context.
  private var effectiveContext: TimelineGridSnapshot? { state.viewerContext ?? fallbackContext }
  @State private var fallbackContext: TimelineGridSnapshot?

  private var contextIDs: [String] {
    effectiveContext?.rows.map(\.id) ?? [selectedID]
  }

  private var kindById: [String: TimelineMediaKind] {
    guard let rows = effectiveContext?.rows else { return [:] }
    return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.mediaKind) })
  }

  private var thumbhashById: [String: String?] {
    guard let rows = effectiveContext?.rows else { return [:] }
    return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.thumbhash) })
  }

  private var index: Int? {
    guard let context = effectiveContext, !context.rows.isEmpty,
      let raw = context.indexById[selectedID]
    else { return nil }
    return min(max(0, raw), context.rows.count - 1)
  }

  private var selectedKind: TimelineMediaKind? { kindById[selectedID] }
  private var selectedIsVideo: Bool {
    selectedKind == .video || chromeAsset?.type == .video
  }

  @State private var exifProfile: String?

  private var isHDR: Bool {
    guard let asset = chromeAsset else { return false }
    return MediaFormatInfo.classify(
      fileName: asset.originalFileName, profileDescription: exifProfile
    ).dynamicRange == .hdr
  }

  private var isLive: Bool { chromeAsset?.livePhotoVideoId != nil }

  var body: some View {
    // WP-E E1/E2: full-window edit mode replaces the viewer content once the
    // chrome asset and a pixel preview are present; otherwise the viewer.
    if showingEditMode, let asset = chromeAsset, let preview = editPreviewImage {
      MacEditModeView(
        asset: asset, access: editAccess, preview: preview,
        loadOriginalData: { [self] in try await self.downloadOriginal(asset) },
        loadVideoFile: asset.type == .video
          ? { [self] in try await self.downloadOriginalFile(asset) } : nil,
        persistence: editPersistence,
        isFavorite: asset.isFavorite,
        onFavorite: { toggleFavorite() },
        onDone: { _ in Task { await loadChrome() } },
        onExit: { showingEditMode = false })
    } else {
      viewerBody
    }
  }

  private var viewerBody: some View {
    // AnyView boundary: keeps each half of the modifier chain small enough
    // for the type-checker (the full chain times out as one expression).
    AnyView(chrome)
    // Arrow keys page through the strip animated (V4/V6, including video
    // pages: the player view forwards arrows here, and this focus claim keeps
    // AppKit from routing the keystroke anywhere else).
    .onKeyPress(.leftArrow) { stepOrPage(by: -1); return .handled }
    .onKeyPress(.rightArrow) { stepOrPage(by: 1); return .handled }
    // Space closes on image pages (V13); on video pages the focused player
    // consumes Space itself (play/pause, V3).
    .onKeyPress(.space) {
      guard !selectedIsVideo else { return .ignored }
      closeOrDismissPreview()
      return .handled
    }
    // WP-E E1: Return opens edit mode (first-click parity for keyboard).
    .onKeyPress(.return) {
      guard !showingEditMode, let asset = chromeAsset, canEdit(asset) else { return .ignored }
      enterEditMode()
      return .handled
    }
    // Character keys (V8/V13): Z toggles zoom; ⌘+/⌘− step ×1.5; ⌥⌘R rotates
    // counter-clockwise (⌘R clockwise lives in the menus). Modifiers are
    // matched inside — `onKeyPress` offers no modifiers filter.
    .onKeyPress(phases: .down) { press in
      if press.modifiers.isEmpty, press.key == "z" {
        toggleZoomKey()
        return .handled
      }
      if press.modifiers == .command,
        press.key == KeyEquivalent("+") || press.key == KeyEquivalent("=")
      {
        stepZoomKey(times: 1)
        return .handled
      }
      if press.modifiers == .command, press.key == KeyEquivalent("-") {
        stepZoomKey(times: -1)
        return .handled
      }
      if press.modifiers == [.command, .option], press.key == KeyEquivalent("r") {
        rotate(by: -1)
        return .handled
      }
      return .ignored
    }
    // Esc closes the inline viewer; standalone windows keep window-level close.
    .onKeyPress(.escape) {
      guard let onClose else { return .ignored }
      onClose()
      return .handled
    }
    .task {
      pageStore = ViewerPageStore(state: state)
    }
    .task(id: selectedID) {
      quarterTurns = 0
      rotationError = nil
      sliderValue = 1
      pinchScale = nil
      editPreviewTask?.cancel()
      editPreviewTask = nil
      editPreviewImage = nil
      await ensureFallbackContext()
      await loadChrome()
    }
    .onChange(of: assetId) { _, new in selectedID = new }
    .onAppear { isFocused = true }
    .onReceive(NotificationCenter.default.publisher(for: .heirloomOpenEdit)) { note in
      // WP-E E1: open on the viewer notification (menus and external hosts;
      // the toolbar and key map call `enterEditMode()` directly).
      if let id = note.userInfo?["assetId"] as? String, id != selectedID { return }
      guard !showingEditMode, let asset = chromeAsset, canEdit(asset) else { return }
      enterEditMode()
    }
  }

  /// Content + chrome (title, toolbar, inspector, sheets, menu, focus). The
  /// key map and page tasks attach in `body` past the `AnyView` boundary.
  private var chrome: some View {
    viewerContent
      .frame(minWidth: 640, minHeight: 480)
      .navigationTitle(viewerTitle)
      .navigationSubtitle(viewerSubtitle)
      .focusedValue(\.macAssetActions, assetActions)
      .toolbar {
        viewerToolbar
      }
      .inspector(isPresented: $showingInspector) {
        if let chromeAsset {
          MacInspectorView(asset: chromeAsset, state: state)
        }
      }
      .sheet(isPresented: $showingMove) {
        MacMoveSheet(state: state, assetIds: [selectedID]) { handleMoveResults($0) }
      }
      .sheet(isPresented: $showingAddToAlbum) {
        MacAddToAlbumSheet(state: state, assetIds: [selectedID]) {
          showingAddToAlbum = false
          MacAssetChangeCenter.shared.post(.albumsChanged)
        }
      }
      .contextMenu { viewerContextMenu }
      .focusable()
      .focused($isFocused)
  }

  private var viewerContent: some View {
    GeometryReader { proxy in
      ZStack {
        pagerSection(container: proxy.size)
        chevronOverlay
        badgesOverlay
        errorOverlay
      }
      // Explicit group: the pager's AppKit-hosted subtree leaves SwiftUI with
      // no AX element of its own here, which drops a bare identifier.
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(AXIDs.viewer)
    }
  }

  private var errorOverlay: some View {
    ZStack {
      if pinchScale != nil {
        Color.black.opacity(0.2)
          .allowsHitTesting(false)
      }
      if let error {
        Text(error).foregroundStyle(.red).font(.caption).padding()
      }
      if let rotationError {
        Text(rotationError).foregroundStyle(.red).font(.caption).padding()
      }
    }
  }

  // MARK: - toolbar (SPEC-TOOLBAR-SETTINGS §2a, TV-3)

  /// Photos set and order: Back + zoom slider capsules leading; Info · Share ·
  /// Favorite · Rotate · Auto-Enhance, then a separate Edit capsule. Trash /
  /// Move / Add-to-Album live in menus and the context menu.
  @ToolbarContentBuilder
  private var viewerToolbar: some ToolbarContent {
    if let onClose {
      ToolbarItem(placement: .navigation) {
        Button { onClose() } label: { Label("Back", systemImage: "chevron.left") }
      }
    }
    ToolbarItem(placement: .navigation) { zoomSlider }
    ToolbarItemGroup {
      Button { showingInspector.toggle() } label: {
        Label("Info", systemImage: "info.circle")
      }
      .accessibilityIdentifier(AXIDs.toolbarInfo)
      Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
        .accessibilityIdentifier(AXIDs.toolbarShare)
      Button { toggleFavorite() } label: { favoriteLabel }
        .accessibilityIdentifier(AXIDs.toolbarFavorite)
        .accessibilityValue(isFavorited ? "favorited" : "not favorited")
      Button { rotateClockwise() } label: {
        Label("Rotate", systemImage: "rotate.left")
      }
      .disabled(selectedIsVideo)
      .accessibilityIdentifier(AXIDs.toolbarRotate)
      Button { toggleAutoEnhance() } label: { enhanceLabel }
        .accessibilityIdentifier("toolbar.autoEnhance")
    }
    // WP-E E1: a single click opens edit mode at once (no double-click).
    // Render-gated on the permission verdict so the button only exists when
    // actionable: personal assets pass on user id alone; space/library rows
    // resolve when memberships land and re-render.
    if let asset = chromeAsset, canEdit(asset) {
      ToolbarItem {
        Button { enterEditMode() } label: { Text("Edit") }
          .accessibilityIdentifier(AXIDs.toolbarEdit)
      }
    }
  }

  private var isFavorited: Bool { chromeAsset?.isFavorite ?? false }

  private var favoriteLabel: some View {
    Label("Favorite", systemImage: isFavorited ? "heart.fill" : "heart")
  }

  private var enhanceLabel: some View {
    Label(
      "Auto Enhance",
      systemImage: autoEnhanceApplied ? "wand.and.stars.inverse" : "wand.and.stars")
  }

  /// Zoom slider capsule (V8/V9): bound live to the page magnification.
  private var zoomSlider: some View {
    HStack(spacing: 4) {
      Image(systemName: "minus.magnifyingglass")
      Slider(value: $sliderValue, in: 1...SmartZoomMath.maxMagnification) {
        Text("Zoom")
      }
      .frame(width: 100)
      .accessibilityIdentifier(AXIDs.viewerZoomSlider)
      .accessibilityValue(zoomPercentText)
      .onChange(of: sliderValue) { _, new in
        pagerHost?.setSelectedPageMagnification(new)
      }
      Image(systemName: "plus.magnifyingglass")
    }
  }

  private var zoomPercentText: String { "\(Int(sliderValue * 100)) percent" }

  /// WP-E E1 entry: full-window edit replaces viewer content as soon as the
  /// chrome asset and a pixel preview are both present (`body` flips when
  /// they land; no intent queue — the toolbar only renders when actionable
  /// and the shell appears the moment its inputs exist).
  private func enterEditMode() {
    showingEditMode = true
    loadEditPreviewIfNeeded()
  }

  /// Pixel preview for the edit shell: the placeholder tier is enough to open
  /// (mirrors WP-E's progressive `image`, which also starts life as a
  /// placeholder in fixture mode); later tiers upgrade it in place.
  private func loadEditPreviewIfNeeded() {
    guard editPreviewImage == nil, editPreviewTask == nil else { return }
    guard let asset = chromeAsset else { return }
    let id = asset.id
    editPreviewTask = Task {
      defer { editPreviewTask = nil }
      guard
        let stream = await pageStore?.previewStream(id: id, thumbhash: asset.thumbhash)
      else { return }
      do {
        for try await step in stream {
          try Task.checkCancellation()
          switch step.content {
          case .placeholder(let next): editPreviewImage = next
          case .tier(_, let next, _): editPreviewImage = next
          }
        }
      } catch {}
    }
  }

  private var editPersistence: RESTEditPersistence {
    RESTEditPersistence(
      serverURL: state.serverURL,
      token: { [connection = state.connection] in await connection.tokenStore.get() })
  }

  // MARK: - page chrome sections (split for type-check performance)

  @ViewBuilder
  private func pagerSection(container: CGSize) -> some View {
    if let pageStore {
      MacViewerPager(
        ids: contextIDs, selectedID: selectedID,
        onSelect: { select(id: $0) },
        pageController: { makePage(id: $0, store: pageStore) },
        onPreload: { preload(ids: $0) },
        onHost: { pagerHost = $0 },
        onMagnification: { id, mag in
          if id == selectedID { sliderValue = mag }
        },
        onPinchClose: { id, scale in
          if id == selectedID { pinchScale = scale }
        },
        onPinchCloseEnd: { id, scale in
          if id == selectedID { resolvePinchClose(scale: scale) }
        }
      )
      .rotationEffect(.degrees(selectedIsVideo ? 0 : rotationDegrees))
      .scaleEffect(rotationFitScale(container: container))
      .animation(.easeInOut(duration: 0.2), value: quarterTurns)
    } else {
      ProgressView().controlSize(.large)
    }
  }

  /// Edge-hover chevrons (V11): hover-gated — absent from the hierarchy at
  /// rest — fading 0.15 s, hidden at the first/last index.
  private var chevronOverlay: some View {
    HStack(spacing: 0) {
      edgeZone(edge: .prev)
      Spacer(minLength: 0)
      edgeZone(edge: .next)
    }
  }

  /// Image overlay badges (SPEC-TOOLBAR-SETTINGS §2a): LIVE + HDR at the
  /// top-left, 8 pt inside, following the fitted image.
  private var badgesOverlay: some View {
    VStack {
      HStack(spacing: 6) {
        if isLive {
          Label("LIVE", systemImage: "livephoto")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .accessibilityIdentifier("viewer.badge.live")
        }
        if isHDR {
          Text("HDR")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .accessibilityIdentifier("viewer.badge.hdr")
        }
        Spacer()
      }
      .padding(8)
      Spacer()
    }
    .allowsHitTesting(false)
  }

  // MARK: - pager wiring (V5/V6)

  private func makePage(id: String, store: ViewerPageStore) -> NSViewController {
    switch kindById[id] {
    case .video:
      return VideoPageController(assetID: id, loader: store.videoLoader())
    case .livePhoto:
      return LivePhotoPageController(assetID: id, store: store)
    default:
      return ImagePageController(assetID: id, thumbhash: thumbhashById[id] ?? nil, store: store)
    }
  }

  private func select(id: String) {
    selectedID = id
    onNavigate?(id)
  }

  private func stepOrPage(by delta: Int) {
    guard let pagerHost else {
      page(by: delta)
      return
    }
    pagerHost.step(delta)
  }

  /// Clamped paging fallback (no wrap, so → then ← returns to the same photo).
  private func page(by delta: Int) {
    guard let context = effectiveContext, let index, !context.rows.isEmpty else { return }
    let next = ViewerPagerMath.clampedIndex(index + delta, count: context.rows.count)
    guard next != index else { return }
    select(id: context.rows[next].id)
  }

  private func preload(ids: [String]) {
    let hashes = thumbhashById
    Task {
      await pageStore?.prefetch(ids: ids, thumbhashes: hashes)
    }
  }

  /// Builds the one-element context when `viewerContext` is nil.
  private func ensureFallbackContext() async {
    guard state.viewerContext == nil, fallbackContext?.indexById[selectedID] == nil else { return }
    guard let asset = try? await state.store.asset(id: selectedID) else { return }
    fallbackContext = TimelineGridSnapshot.build(
      sections: [TimelineSourceSection(kind: .none, rows: [TimelineRow(asset: asset)])],
      order: .newestFirst,
      include: { _ in true },
      generation: 0)
  }

  /// Chrome state for the selected page: the asset, its place subtitle and a
  /// display-rotation reset. Page pixels load inside the page controllers.
  private func loadChrome() async {
    let id = selectedID
    guard let fresh = try? await state.store.asset(id: id) else { return }
    guard id == selectedID else { return }
    chromeAsset = fresh
    let summary = try? await state.store.exifSummary(assetId: id)
    titlePlace = summary?.placeString
    exifProfile = summary?.profileDescription
  }

  // MARK: - zoom keys (V8)

  private func toggleZoomKey() {
    sliderValue = SmartZoomMath.toggled(current: sliderValue)
    pagerHost?.setSelectedPageMagnification(sliderValue)
  }

  private func stepZoomKey(times: Int) {
    if times > 0 {
      sliderValue = SmartZoomMath.stepped(sliderValue, times: times)
    } else {
      sliderValue = max(1, sliderValue / pow(SmartZoomMath.stepFactor, Double(-times)))
    }
    pagerHost?.setSelectedPageMagnification(sliderValue)
  }

  // MARK: - pinch-close (V7)

  private func resolvePinchClose(scale: CGFloat) {
    defer { pinchScale = nil }
    guard PinchCloseDecision.shouldClose(endScale: scale, velocityInward: false) else { return }
    guard let onClose else { return }
    // No grid source yet (WP-G implements `ViewerTransitionSource`): the
    // animator cross-fades on its 0.3 s gate, then dismisses.
    ViewerTransitionAnimator.animateClose(
      snapshot: NSImage(), from: .zero, source: nil, assetId: selectedID
    ) {
      onClose()
    }
  }

  // MARK: - chrome actions (V9/V13)

  private func closeOrDismissPreview() {
    if let onClose {
      onClose()
    } else {
      MacPreviewPanel.dismiss()
    }
  }

  @State private var autoEnhanceApplied = false

  private func toggleAutoEnhance() {
    autoEnhanceApplied.toggle()
    // Enhancement rendering lands with WP-E; the toggle state is chrome-owned.
  }

  /// Share toolbar button (TV-3): `NSSharingServicePicker` with the current
  /// original, staged through a temp dir via `MacExporter` (same path as the
  /// grid's `shareSelected`).
  private func share() {
    guard let asset = chromeAsset else { return }
    Task { @MainActor in
      do {
        let exporter = MacExporter(
          serverURL: state.serverURL,
          tokenProvider: { [connection = state.connection] in await connection.tokenStore.get() })
        let dir = FileManager.default.temporaryDirectory
          .appendingPathComponent("HeirloomShare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try await exporter.downloadOriginal(asset: asset)
        let url = dir.appendingPathComponent(asset.originalFileName)
        try data.write(to: url)
        guard let view = NSApp.keyWindow?.contentView else { return }
        NSSharingServicePicker(items: [url]).show(
          relativeTo: view.bounds, of: view, preferredEdge: .minY)
      } catch is CancellationError {
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  // MARK: - context menu (V10)

  @ViewBuilder
  private var viewerContextMenu: some View {
    let kind: ViewerContextMenuSpec.AssetKind =
      selectedIsVideo ? .video : (isLive ? .live : .photo)
    let wanted = ViewerContextMenuSpec.titles(kind: kind)
    ForEach(wanted, id: \.self) { title in
      switch title {
      case "Get Info": Button("Get Info") { showingInspector.toggle() }
      case "Rotate Left": Button("Rotate Left") { rotate(by: -1) }
      case "Rotate Right": Button("Rotate Right") { rotateClockwise() }
      case "Add to Album": Button("Add to Album") { showingAddToAlbum = true }
      case "Delete": Button("Delete") { trash() }
      default: EmptyView()
      }
    }
  }

  // MARK: - edge chevrons (V11)

  @ViewBuilder
  private func edgeZone(edge: ChevronVisibility.Edge) -> some View {
    let count = effectiveContext?.rows.count ?? 1
    let at = index ?? 0
    let visible =
      hoverEdge == edge
      && ChevronVisibility.isVisible(edge: edge, index: at, count: count, hoverNearEdge: true)
    HStack {
      if edge == .next { Spacer(minLength: 0) }
      if visible {
        Button {
          stepOrPage(by: edge == .next ? 1 : -1)
        } label: {
          Label(
            edge == .next ? "Next" : "Previous",
            systemImage: edge == .next ? "chevron.right" : "chevron.left")
        }
        .accessibilityIdentifier(
          edge == .next ? AXIDs.viewerChevronNext : AXIDs.viewerChevronPrev)
        .padding(12)
        .transition(.opacity)
      }
      if edge == .prev { Spacer(minLength: 0) }
    }
    .frame(width: 96)
    .contentShape(Rectangle())
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.15)) {
        hoverEdge = hovering ? edge : (hoverEdge == edge ? nil : hoverEdge)
      }
    }
  }

  private var editAccess: AccessContext {
    AccessContext(
      currentUserId: state.userId ?? "", memberSpaceIds: editSpaceIds,
      accessibleLibraryIds: editLibraryIds)
  }

  @State private var editSpaceIds: Set<String> = []
  @State private var editLibraryIds: Set<String> = []
  @State private var editMembershipsLoaded = false

  private func canEdit(_ asset: Asset) -> Bool {
    let ctx = AccessContext(currentUserId: state.userId ?? "")
    if Permissions.canEdit(asset, in: ctx) { return true }
    if !editMembershipsLoaded {
      editMembershipsLoaded = true
      Task { await refreshEditMemberships() }
    }
    return Permissions.canEdit(asset, in: editAccess)
  }

  private func refreshEditMemberships() async {
    let uid = state.userId ?? ""
    guard !uid.isEmpty else { return }
    let spaces = (try? await state.store.spacesForUser(uid)) ?? []
    let libs = (try? await state.store.librariesForUser(uid)) ?? []
    editSpaceIds = Set(spaces.map { $0.id })
    editLibraryIds = Set(libs.map { $0.id })
  }

  /// Original-download failure with the HTTP status and body size attached, so
  /// edit mode can report *why* the canvas never sharpened instead of falling
  /// back to the proxy blur in silence.
  enum EditDownloadError: Error, LocalizedError {
    case http(status: Int, bytes: Int)

    var errorDescription: String? {
      switch self {
      case .http(let status, let bytes):
        return "original download failed (HTTP \(status), \(bytes) bytes)"
      }
    }
  }

  private func downloadOriginal(_ asset: Asset) async throws -> Data {
    var request = URLRequest(
      url: MediaEndpoint(serverURL: state.serverURL, assetID: asset.id).originalURL())
    if let token = await state.connection.tokenStore.get() {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    // A non-2xx body (JSON error, login page) is not image data: surfacing it
    // here beats a silent blur later (NSImage decodes it to nil and the canvas
    // falls back to the proxy with no alert).
    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
    print("[heirloom-edit] TEMP-DEBUG original GET \(request.url?.absoluteString ?? "<nil>") -> HTTP \(status), \(data.count) bytes")
    guard (200..<300).contains(status) else {
      throw EditDownloadError.http(status: status, bytes: data.count)
    }
    return data
  }

  private func downloadOriginalFile(_ asset: Asset) async throws -> URL {
    let data = try await downloadOriginal(asset)
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension((asset.originalFileName as NSString).pathExtension)
    try data.write(to: tmp)
    return tmp
  }

  /// Rotation persistence: the PERSISTABLE path — the same EditRecipe/PUT-edits/KV
  /// route the grid uses (`MacMainWindow.rotate(ids:)`), minus the render/upload,
  /// which pure rotation does not need (`requiresClientRender == false`).
  /// Videos are excluded (their rotation is a `VideoRecipe` client export).
  private func persistRotationIfEnabled(quarterTurns delta: Int) {
    guard let asset = chromeAsset, asset.type != .video else { return }
    let id = asset.id
    let width = asset.width ?? 0
    let height = asset.height ?? 0
    guard width > 0, height > 0 else {
      rotationError = "Could not save rotation: unknown image size."
      return
    }
    Task {
      do {
        let persistence = RESTEditPersistence(
          serverURL: state.serverURL,
          token: { [connection = state.connection] in await connection.tokenStore.get() })
        let stored = try await persistence.fetchRecipe(assetId: id)
        var recipe = stored?.recipe ?? EditRecipe()
        var crop = recipe.crop ?? CropRecipe()
        crop.quarterTurns = (crop.quarterTurns + delta) % 4
        recipe.crop = crop
        let split = try EditSplitter.split(
          recipe, imageSize: CGSize(width: width, height: height))
        if split.upstream.isEmpty {
          try await persistence.clearUpstreamEdits(assetId: id)
        } else {
          try await persistence.applyUpstreamEdits(assetId: id, items: split.upstream)
        }
        try await persistence.saveRecipe(EditPersistencePayload(
          sourceAssetId: id, recipe: recipe, renderedAssetId: stored?.renderedAssetId))
        MacAssetChangeCenter.shared.post(.edited(ids: [id]))
        rotationError = nil
      } catch is CancellationError {
      } catch {
        rotationError = "Could not save rotation: \(error.localizedDescription)"
        HeirloomLog.ui.error("viewer rotate failed: \(String(describing: error))")
      }
    }
  }

  private func rotate(by delta: Int) {
    quarterTurns = (quarterTurns + delta) % 4
    persistRotationIfEnabled(quarterTurns: delta)
  }

  private func rotateClockwise() { rotate(by: 1) }

  private func handleMoveResults(_ results: [MoveResult]) {
    showingMove = false
    let movedIDs = results.filter { $0.status == .moved }.map(\.assetId)
    let moved = Set(movedIDs)
    guard !moved.isEmpty else { return }
    MacAssetChangeCenter.shared.post(.removedFromCurrentContexts(ids: moved))
    if moved.contains(selectedID) { advanceAfterRemoval(removedId: selectedID) }
  }

  /// After delete or lock, advance to the next item (previous at the end), or close
  /// the viewer when the context becomes empty.
  private func advanceAfterRemoval(removedId: String) {
    guard let context = effectiveContext, let at = context.indexById[removedId] else {
      if let onClose { onClose() }
      return
    }
    let remaining = context.rows.filter { $0.id != removedId }
    guard !remaining.isEmpty else {
      if let onClose {
        onClose()
      } else {
        error = "This was the last photo in the viewer."
      }
      return
    }
    select(id: remaining[min(at, remaining.count - 1)].id)
  }

  private func toggleFavorite() {
    guard let asset = chromeAsset else { return }
    Task {
      do {
        let make = !asset.isFavorite
        try await state.assetMutations().setFavorite(ids: [selectedID], isFavorite: make)
        MacAssetChangeCenter.shared.post(.favorite(ids: [selectedID], isFavorite: make))
        chromeAsset = try await state.store.asset(id: selectedID)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func trash() {
    Task {
      do {
        try await state.assetMutations().trash(ids: [selectedID])
        MacAssetChangeCenter.shared.post(.removedFromCurrentContexts(ids: [selectedID]))
        advanceAfterRemoval(removedId: selectedID)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

}

#Preview("Viewer") {
  MacPreviewFixture { state in
    MacViewerView(state: state, assetId: "asset-personal-1")
      .frame(width: 1000, height: 700)
  }
}
