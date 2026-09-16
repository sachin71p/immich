import AppKit
import CoreModel
import Editing
import LocalStore
import Media
import Rules
import Search
import SwiftUI
import VisionKit

/// Asset viewer (brief task 3): in-window and full-screen, arrow-key paging, pinch/scroll zoom
/// with tier upgrade (thumbnail → preview → original through `MediaPipeline`), floating Info
/// inspector (⌘I), favorite (.), rotate (⌘R, display-only until A8 persists edits), delete (⌘⌫),
/// move to… (⌘⇧M), add to album.
struct MacViewerView: View {
  @Bindable var state: MacAppState
  var assetId: String
  /// Non-nil when hosted inline in `MacLibraryBrowser`: arrow-key paging updates `assetId` in
  /// place instead of opening another window. Nil in the standalone `MacWindow.viewer` scene
  /// (`File > New Viewer Window`), where paging still opens a new window as before.
  var onNavigate: ((String) -> Void)? = nil
  /// Non-nil when hosted inline: shows a back button/Escape to return to the library instead of
  /// relying on the window's own close button.
  var onClose: (() -> Void)? = nil
  @State private var asset: Asset?
  @State private var image: NSImage?
  @State private var loadedTier: MediaTier?
  /// Live viewer extent (points) for the window-exceeds-preview fullsize check.
  @State private var viewSize: CGSize = .zero
  /// Live magnification from the zoom view for the > 1.5× fullsize check.
  @State private var magnification: Double = 1
  @State private var rotation: Double = 0
  @State private var showingInspector = false
  @State private var showingMove = false
  @State private var showingEdit = false
  @State private var showingAddToAlbum = false
  @State private var error: String?
  @State private var liveTextEnabled = true
  @State private var liveText: ImageAnalysis?
  @Environment(\.openWindow) private var openWindow
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
      // Space while the viewer is focused toggles Quick Look off (WP5 item 8). The
      // grid's Space opens the panel; the menus own the shortcut in both cases, so
      // this closure is the viewer's only Space path — no double-fire.
      preview: { MacPreviewPanel.dismiss() }
    )
  }

  /// Display-order paging context (WP2 Step 4: was the unfiltered full id list).
  /// Falls back to a one-element snapshot when `viewerContext` is nil (a window
  /// opened from Search, Map or a deep link — WP5 item 1). The fallback stays local
  /// so a standalone viewer window never clobbers the library's shared context.
  private var effectiveContext: TimelineGridSnapshot? { state.viewerContext ?? fallbackContext }
  @State private var fallbackContext: TimelineGridSnapshot?

  private var index: Int? {
    guard let context = effectiveContext, !context.rows.isEmpty,
      let raw = context.indexById[assetId]
    else { return nil }
    return min(max(0, raw), context.rows.count - 1)
  }

  private var canGoPrevious: Bool { (index ?? 0) > 0 }
  private var canGoNext: Bool {
    guard let index, let context = effectiveContext else { return false }
    return index < context.rows.count - 1
  }

  /// Immich doesn't sync Apple's Portrait-mode depth EXIF, so unlike native Photos this can only
  /// badge what `Asset` itself already knows, without a separate `AssetExif` fetch: Live Photo.
  private var mediaTypeBadge: (title: String, systemImage: String)? {
    guard let asset, asset.livePhotoVideoId != nil else { return nil }
    return ("Live", "livephoto")
  }

  var body: some View {
    ZStack {
      if let asset, asset.type == .video {
        MacVideoPageView(asset: asset, state: state) {
          if canEdit(asset) { showingEdit = true }
        }
      } else if let asset, let motionId = asset.livePhotoVideoId {
        MacLivePhotoPageView(asset: asset, motionAssetId: motionId, state: state)
      } else if let image {
        if liveTextEnabled {
          MacLiveTextView(image: image, analysis: liveText)
            .rotationEffect(.degrees(rotation))
        } else {
          MacZoomableImageView(
            image: image, onZoomBeyondPreview: upgradeTier,
            onMagnification: { magnification = $0 }
          )
          .rotationEffect(.degrees(rotation))
        }
      } else {
        ProgressView().controlSize(.large)
      }
      if let error {
        Text(error).foregroundStyle(.red).font(.caption).padding()
      }
    }
    .overlay(alignment: .topLeading) {
      if let badge = mediaTypeBadge {
        Label(badge.title, systemImage: badge.systemImage)
          .font(.caption.weight(.semibold))
          .labelStyle(.titleAndIcon)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(.thinMaterial, in: Capsule())
          .padding(12)
      }
    }
    .frame(minWidth: 640, minHeight: 480)
    .background(
      GeometryReader { proxy in
        Color.clear.preference(key: ViewerSizeKey.self, value: proxy.size)
      }
    )
    .onPreferenceChange(ViewerSizeKey.self) { viewSize = $0 }
    .navigationTitle(asset?.originalFileName ?? "Viewer")
    .focusedValue(\.macAssetActions, assetActions)
    .toolbar {
      if let onClose {
        ToolbarItem(placement: .navigation) {
          Button { onClose() } label: { Label("Back", systemImage: "chevron.left") }
        }
      }
      // Paging affordances (WP5 item 1): clamped, disabled at the ends. No keyboard
      // shortcuts here — arrows arrive via `.onKeyPress` below, and giving the
      // buttons arrow shortcuts too would page twice per keystroke.
      ToolbarItemGroup(placement: .navigation) {
        Button { page(by: -1) } label: { Label("Previous", systemImage: "chevron.left") }
          .disabled(!canGoPrevious)
        Button { page(by: 1) } label: { Label("Next", systemImage: "chevron.right") }
          .disabled(!canGoNext)
      }
      ToolbarItemGroup {
        Button { toggleFavorite() } label: {
          Label("Favorite", systemImage: (asset?.isFavorite ?? false) ? "heart.fill" : "heart")
        }
        Button { trash() } label: { Label("Delete", systemImage: "trash") }
        Button { showingMove = true } label: { Label("Move to…", systemImage: "folder") }
        Button { showingAddToAlbum = true } label: { Label("Add to Album", systemImage: "rectangle.stack.badge.plus") }
        if let asset, canLock(asset) {
          Button { toggleLocked(asset) } label: {
            Label(asset.visibility == .locked ? "Unlock" : "Lock", systemImage: asset.visibility == .locked ? "lock.open" : "lock")
          }
        }
        if let asset, canEdit(asset) {
          Button { showingEdit = true } label: { Label("Edit", systemImage: "slider.horizontal.3") }
        }
        Button { rotateClockwise() } label: { Label("Rotate", systemImage: "rotate.right") }
        Button { showingInspector.toggle() } label: { Label("Info", systemImage: "info.circle") }
        Toggle("Live Text", isOn: $liveTextEnabled)
      }
    }
    .inspector(isPresented: $showingInspector) {
      if let asset {
        MacInfoPanel(asset: asset, state: state)
      }
    }
    .sheet(isPresented: $showingMove) {
      MacMoveSheet(state: state, assetIds: [assetId]) { _ in showingMove = false }
    }
    .sheet(isPresented: $showingAddToAlbum) {
      MacAddToAlbumSheet(state: state, assetIds: [assetId]) { showingAddToAlbum = false }
    }
    .sheet(isPresented: $showingEdit) {
      if let asset, let preview = editPreview {
        MacEditView(
          asset: asset, access: editAccess, preview: preview,
          loadOriginalData: { try await downloadOriginal(asset) },
          loadVideoFile: asset.type == .video ? { try await downloadOriginalFile(asset) } : nil,
          persistence: RESTEditPersistence(
            serverURL: state.serverURL,
            token: { [connection = state.connection] in await connection.tokenStore.get() }),
          onDone: { _ in Task { await loadProgressive() } })
          .frame(minWidth: 900, minHeight: 640)
      }
    }
    .focusable()
    .focused($isFocused)
    // Arrow keys arrive exactly once (WP5 item 1): while this inline viewer is
    // visible the grid's NSCollectionView is out of the hierarchy (MacMainWindow
    // shows either the viewer or the grid, never both), and the focus claim above
    // keeps AppKit from routing the keystroke anywhere else. Verified by focus,
    // not by suppression — there is no grid handler left to suppress.
    .onKeyPress(.leftArrow) { page(by: -1); return .handled }
    .onKeyPress(.rightArrow) { page(by: 1); return .handled }
    // Esc closes the inline viewer; the existing `onClose` callback returns to the
    // grid with the prior selection intact (WP5 item 8). Standalone viewer windows
    // (no `onClose`) keep the window-level close behavior.
    .onKeyPress(.escape) {
      guard let onClose else { return .ignored }
      onClose()
      return .handled
    }
    .task(id: assetId) {
      await ensureFallbackContext()
      await loadProgressive()
    }
    .onAppear { isFocused = true }
  }

  /// Clamped paging through `viewerContext` display order (WP5 item 1): no wrap,
  /// so → then ← returns to the same photo.
  private func page(by delta: Int) {
    guard let context = effectiveContext, let index, !context.rows.isEmpty else { return }
    let next = min(max(0, index + delta), context.rows.count - 1)
    guard next != index else { return }
    let id = context.rows[next].id
    if let onNavigate {
      onNavigate(id)
    } else {
      openWindow(value: MacWindow.viewer(id))
    }
  }

  /// Builds the one-element context when `viewerContext` is nil (WP5 item 1).
  private func ensureFallbackContext() async {
    guard state.viewerContext == nil, fallbackContext?.indexById[assetId] == nil else { return }
    guard let asset = try? await state.store.asset(id: assetId) else { return }
    fallbackContext = TimelineGridSnapshot.build(
      sections: [TimelineSourceSection(kind: .none, rows: [TimelineRow(asset: asset)])],
      order: .newestFirst,
      include: { _ in true },
      generation: 0)
  }

  /// Instant open (WP5 item 2): synchronous memory-cache thumbnail scaled up, then
  /// the `.preview` stream step by step, then `.fullsize` when zoomed past 1.5× or
  /// the window backing pixels exceed the preview size. Every step replaces the
  /// image; nothing ever assigns nil, so the old page stays visible until the new
  /// tier arrives — no blank flash between pages.
  private func loadProgressive() async {
    let id = assetId
    if let cg = state.pipeline.cachedImage(id: id, tier: .thumbnail) {
      image = NSImage(cgImage: cg, size: NSZeroSize)
      loadedTier = .thumbnail
    } else {
      loadedTier = nil
    }
    do {
      guard let fresh = try await state.store.asset(id: id) else { return }
      try Task.checkCancellation()
      asset = fresh
      for try await step in await state.pipeline.stream(asset: fresh, tier: .preview) {
        try Task.checkCancellation()
        switch step.content {
        case .placeholder(let next): image = next
        case .tier(let tier, let next, _):
          image = next
          loadedTier = tier
        }
      }
      await analyzeLiveText()
      if id == assetId, shouldUpgradeToFullsize() {
        await loadFullsize(asset: fresh, id: id)
      }
      await settleAndPreload()
    } catch is CancellationError {
      // Page changed mid-load; the new page's task owns the view now.
    } catch {
      self.error = error.localizedDescription
    }
  }

  /// Fullsize upgrade: magnification > 1.5 or the window backing pixels exceed the
  /// preview pixel size (WP5 item 2).
  private func shouldUpgradeToFullsize() -> Bool {
    if magnification > 1.5 { return true }
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    let pixels = max(viewSize.width, viewSize.height) * scale
    return pixels > CGFloat(MediaTier.preview.defaultPixelSize ?? 2048)
  }

  private func loadFullsize(asset: Asset, id: String) async {
    do {
      for try await step in await state.pipeline.stream(asset: asset, tier: .fullsize) {
        try Task.checkCancellation()
        guard id == assetId, case .tier(let tier, let next, _) = step.content else { continue }
        image = next
        loadedTier = tier
      }
    } catch is CancellationError {
    } catch {
      self.error = error.localizedDescription
    }
  }

  /// Zoom-past-preview upgrade (WP5 item 2): fires once per page at > 1.5×.
  private func upgradeTier() {
    guard let asset, loadedTier != .fullsize, loadedTier != .original else { return }
    loadedTier = .fullsize
    let id = assetId
    Task { await loadFullsize(asset: asset, id: id) }
  }

  private var editPreview: NSImage? {
    if let image { return image }
    return nil
  }

  private var editAccess: AccessContext {
    // Built on demand (membership-lazy): personal + owned assets are decided by user id
    // alone; space/library rows resolve when the sheet opens via `canEdit`.
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
    // Space/library memberships load once per viewer (guarded: no refresh loop).
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

  /// A9.2: analyze the loaded still for Live Text. Failures leave `liveText` nil and the
  /// viewer keeps working — Live Text is an enhancement, never a gate.
  private func analyzeLiveText() async {
    guard liveTextEnabled, let image,
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
      if !liveTextEnabled { liveText = nil }
      return
    }
    do {
      liveText = try await ImageAnalyzer().analyze(
        cgImage, orientation: .up,
        configuration: ImageAnalyzer.Configuration([.text, .machineReadableCode, .visualLookUp]))
    } catch {
      liveText = nil
    }
  }

  private func downloadOriginal(_ asset: Asset) async throws -> Data {
    var request = URLRequest(
      url: MediaEndpoint(serverURL: state.serverURL, assetID: asset.id).originalURL())
    if let token = await state.connection.tokenStore.get() {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let (data, _) = try await URLSession.shared.data(for: request)
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

  /// Rotation hook (WP5 item 4): WP4's persistence decision, written at the top of
  /// `reports/WP4-REPORT.md`, fills this single function in. Until then rotation is
  /// display-only and nothing here touches persistence.
  private func persistRotationIfEnabled() { }

  private func rotateClockwise() {
    rotation += 90
    persistRotationIfEnabled()
  }

  /// Neighbor preload (WP5 item 3): 100 ms after the page settles, warm ±2 at the
  /// preview tier and drop prefetch work outside that window.
  private func settleAndPreload() async {
    try? await Task.sleep(for: .milliseconds(100))
    guard !Task.isCancelled else { return }
    guard let context = effectiveContext, let center = index else { return }
    let lo = max(0, center - 2)
    let hi = min(context.rows.count - 1, center + 2)
    let items = context.rows[lo...hi].map { (id: $0.id, thumbhash: $0.thumbhash) }
    await state.pipeline.cancelPrefetch(keeping: Set(items.map(\.id)))
    guard !Task.isCancelled else { return }
    await state.pipeline.prefetch(items, tier: .preview)
  }

  /// After delete or lock, advance to the next item (previous at the end), or close
  /// the viewer when the context becomes empty (WP5 item 7).
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
    let next = remaining[min(at, remaining.count - 1)].id
    if let onNavigate {
      onNavigate(next)
    } else {
      openWindow(value: MacWindow.viewer(next))
    }
  }

  private func toggleFavorite() {
    guard let asset else { return }
    Task {
      do {
        let make = !asset.isFavorite
        try await state.assetMutations().setFavorite(ids: [assetId], isFavorite: make)
        // Grid patches in place via the change center — no reload (WP5 item 7). The
        // local refetch below only refreshes this view's own heart state.
        MacAssetChangeCenter.shared.post(.favorite(ids: [assetId], isFavorite: make))
        self.asset = try await state.store.asset(id: assetId)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func trash() {
    Task {
      do {
        // The server has trash, so no confirmation — same as the grid's delete
        // (MacMainWindow.trash). Post instead of reloading; the loader applies the
        // removal and this viewer advances past the deleted row (WP5 item 7).
        try await state.assetMutations().trash(ids: [assetId])
        MacAssetChangeCenter.shared.post(.removedFromCurrentContexts(ids: [assetId]))
        advanceAfterRemoval(removedId: assetId)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func canLock(_ asset: Asset) -> Bool {
    asset.ownerId == state.userId && asset.spaceId == nil && asset.libraryId == nil
  }

  private func toggleLocked(_ asset: Asset) {
    Task { @MainActor in
      guard await LockedMediaAuthentication.authenticate(
        reason: asset.visibility == .locked ? "Unlock your personal photo" : "Lock this personal photo")
      else { return }
      do {
        let locking = asset.visibility != .locked
        try await state.assetMutations().setLocked(ids: [asset.id], isLocked: locking)
        if locking {
          // A locked row leaves every context: post so the grid drops it without a
          // reload, and advance past it like a delete (WP5 item 7).
          MacAssetChangeCenter.shared.post(.removedFromCurrentContexts(ids: [asset.id]))
          advanceAfterRemoval(removedId: asset.id)
        } else {
          self.asset = try await state.store.asset(id: asset.id)
        }
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

/// Carries the viewer extent from the background `GeometryReader` to `viewSize`.
private struct ViewerSizeKey: PreferenceKey {
  // SwiftUI reads/writes preferences on the main thread only; the value is a
  // trivial `CGSize`, so unchecked shared access here is main-thread-confined.
  nonisolated(unsafe) static var defaultValue: CGSize = .zero
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// NSScrollView magnifier: pinch/scroll zoom; crossing 1.5× fires `onZoomBeyondPreview`
/// once so the viewer upgrades to the fullsize tier (WP5 item 2). Every magnification
/// change is also reported through `onMagnification` so the viewer can decide the
/// window-exceeds-preview upgrade without polling.
struct MacZoomableImageView: NSViewRepresentable {
  var image: NSImage
  var onZoomBeyondPreview: () -> Void
  var onMagnification: (Double) -> Void = { _ in }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 1
    scrollView.maxMagnification = 8
    let imageView = NSImageView(image: image)
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.imageAlignment = .alignCenter
    scrollView.documentView = imageView
    context.coordinator.observe(scrollView: scrollView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.update(
      action: onZoomBeyondPreview, magnification: onMagnification, image: image)
    (scrollView.documentView as? NSImageView)?.image = image
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(action: onZoomBeyondPreview, magnification: onMagnification, image: image)
  }

  /// Main-thread-confined zoom state carried across the @Sendable notification closure.
  final class ZoomState: @unchecked Sendable {
    weak var scrollView: NSScrollView?
    var onZoom: () -> Void = {}
    var onMagnification: (Double) -> Void = { _ in }
    weak var lastImage: NSImage?
    var fired = false
  }

  final class Coordinator: NSObject {
    private let state = ZoomState()
    private var observer: NSObjectProtocol?

    init(
      action: @escaping () -> Void, magnification: @escaping (Double) -> Void, image: NSImage
    ) {
      state.onZoom = action
      state.onMagnification = magnification
      state.lastImage = image
    }

    func update(
      action: @escaping () -> Void, magnification: @escaping (Double) -> Void, image: NSImage
    ) {
      state.onZoom = action
      state.onMagnification = magnification
      // The scroll view persists across pages (only its image swaps), so re-arm the
      // once-per-page fullsize trigger when a new page's image arrives.
      if state.lastImage !== image {
        state.lastImage = image
        state.fired = false
      }
    }

    func observe(scrollView: NSScrollView) {
      state.scrollView = scrollView
      let state = self.state
      observer = NotificationCenter.default.addObserver(
        forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main
      ) { _ in
        MainActor.assumeIsolated {
          guard let view = state.scrollView else { return }
          state.onMagnification(Double(view.magnification))
          guard !state.fired, view.magnification > 1.5 else { return }
          state.fired = true
          state.onZoom()
        }
      }
    }

    deinit {
      if let observer { NotificationCenter.default.removeObserver(observer) }
    }
  }
}

/// Floating Info panel content (⌘I): everything the local mirror knows about the asset.
struct MacInfoPanel: View {
  var asset: Asset
  var state: MacAppState
  @State private var ownerName: String?

  var body: some View {
    Form {
      Section("Info") {
        LabeledContent("Name", value: asset.originalFileName)
        if let date = asset.localDateTime {
          LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .shortened))
        }
        LabeledContent("Container", value: containerName)
        LabeledContent("Owner", value: ownerName ?? asset.ownerId)
          .task(id: asset.ownerId) {
            ownerName = try? await state.store.user(id: asset.ownerId)?.name
          }
        if let w = asset.width, let h = asset.height {
          LabeledContent("Dimensions", value: "\(w) × \(h)")
        }
        LabeledContent("Favorite", value: asset.isFavorite ? "Yes" : "No")
      }
      MacFullExifBrowser(assetId: asset.id, state: state)
    }
    .formStyle(.grouped)
    .frame(minWidth: 260)
  }

  private var containerName: String {
    switch asset.container {
    case .personal: return "Personal Library"
    case .space(let id):
      return state.spaces.first(where: { $0.space.id == id })?.space.name ?? "Shared Library"
    case .library(let id):
      return state.libraries.first(where: { $0.library.id == id })?.library.name ?? "External Library"
    }
  }
}

#Preview("Viewer") {
  MacPreviewFixture { state in
    MacViewerView(state: state, assetId: "asset-personal-1")
      .frame(width: 1000, height: 700)
  }
}
