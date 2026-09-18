import AppKit
import CoreModel
import Editing
import LocalStore
import Media
import Rules
import Search
import SwiftUI
import VisionKit

/// Asset viewer (brief task 3): in-window and full-screen, arrow-key and horizontal-scroll
/// paging (trackpad swipe / wheel-x; chevron buttons removed per owner request), pinch zoom
/// with tier upgrade (thumbnail → preview → original through `MediaPipeline`), floating Info
/// inspector (⌘I), favorite (.), rotate (⌘R, persisted through the edit path for photos),
/// delete (⌘⌫), move to… (⌘⇧M), add to album.
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
  /// Display rotation in clockwise quarter turns (WP5 item 4): reset on every page change;
  /// the persisted rotation arrives back through the pipeline, never through this state.
  @State private var quarterTurns = 0
  @State private var rotationError: String?
  /// "San Jose, California" for the title subtitle (WP5 item 5), from the EXIF row.
  @State private var titlePlace: String?
  @State private var showingInspector = false
  @State private var showingMove = false
  @State private var showingEditMode = false
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

  /// Window title (WP5 item 5): capture date ("February 8, 2026"). The filename moved to
  /// the inspector.
  private var viewerTitle: String {
    guard let date = asset?.localDateTime else { return "Viewer" }
    return date.formatted(date: .long, time: .omitted)
  }

  /// Subtitle: time plus place when known ("1:44 AM · San Jose, California").
  private var viewerSubtitle: String {
    guard let date = asset?.localDateTime else { return "" }
    let time = date.formatted(date: .omitted, time: .shortened)
    guard let place = titlePlace, !place.isEmpty else { return time }
    return "\(time) · \(place)"
  }

  /// Display rotation in degrees from the quarter-turn count.
  private var rotationDegrees: Double { Double(((quarterTurns % 4) + 4) % 4) * 90 }

  /// Re-fit scale for 90°/270° turns (WP5 item 4): the ratio of the swapped-aspect fit to the
  /// base fit, so the rotated image stays inside the container instead of overflowing it.
  private func rotationFitScale(container: CGSize) -> CGFloat {
    guard quarterTurns % 2 != 0 else { return 1 }
    let w: CGFloat
    let h: CGFloat
    if let aw = asset?.width, let ah = asset?.height, aw > 0, ah > 0 {
      w = CGFloat(aw)
      h = CGFloat(ah)
    } else if let size = image?.size, size.width > 0, size.height > 0 {
      w = size.width
      h = size.height
    } else {
      return 1
    }
    guard container.width > 0, container.height > 0 else { return 1 }
    let fit = min(container.width / w, container.height / h)
    guard fit > 0 else { return 1 }
    return min(container.width / h, container.height / w) / fit
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

  var body: some View {
    // WP-E E1/E2: full-window edit mode replaces the viewer content (first click on
    // Edit, Return, or the `HeirloomViewer.openEdit` notification).
    if showingEditMode, let asset, let preview = editPreview {
      MacEditModeView(
        asset: asset, access: editAccess, preview: preview,
        loadOriginalData: { try await downloadOriginal(asset) },
        loadVideoFile: asset.type == .video ? { try await downloadOriginalFile(asset) } : nil,
        persistence: RESTEditPersistence(
          serverURL: state.serverURL,
          token: { [connection = state.connection] in await connection.tokenStore.get() }),
        isFavorite: asset.isFavorite,
        onFavorite: { toggleFavorite() },
        onDone: { _ in Task { await loadProgressive() } },
        onExit: { showingEditMode = false })
    } else {
      viewerBody
    }
  }

  private var viewerBody: some View {
    ZStack {
      if let asset, asset.type == .video {
        MacVideoPageView(asset: asset, state: state) {
          if canEdit(asset) { showingEditMode = true }
        }
      } else if let asset, let motionId = asset.livePhotoVideoId {
        MacLivePhotoPageView(asset: asset, motionAssetId: motionId, state: state)
      } else if let image {
        // Rotation re-fit (WP5 item 4): the representable fills the container aspect-fit, so a
        // 90°/270° turn must shrink the whole rendered view to the swapped-aspect fit size —
        // otherwise the rotated image overflows the bounds. Animated 0.2 s per the brief.
        GeometryReader { proxy in
          Group {
            if liveTextEnabled {
              MacLiveTextView(image: image, analysis: liveText, onPage: { page(by: $0) })
            } else {
              MacZoomableImageView(
                image: image, onZoomBeyondPreview: upgradeTier,
                onMagnification: { magnification = $0 },
                onPage: { page(by: $0) }
              )
            }
          }
          .rotationEffect(.degrees(rotationDegrees))
          .scaleEffect(rotationFitScale(container: proxy.size))
        }
        .animation(.easeInOut(duration: 0.2), value: quarterTurns)
      } else {
        ProgressView().controlSize(.large)
      }
      if let error {
        Text(error).foregroundStyle(.red).font(.caption).padding()
      }
      if let rotationError {
        Text(rotationError).foregroundStyle(.red).font(.caption).padding()
      }
    }
    .accessibilityIdentifier(AXIDs.viewer)
    .frame(minWidth: 640, minHeight: 480)
    .background(
      GeometryReader { proxy in
        Color.clear.preference(key: ViewerSizeKey.self, value: proxy.size)
      }
    )
    .onPreferenceChange(ViewerSizeKey.self) { viewSize = $0 }
    .navigationTitle(viewerTitle)
    .navigationSubtitle(viewerSubtitle)
    .focusedValue(\.macAssetActions, assetActions)
    .toolbar {
      if let onClose {
        ToolbarItem(placement: .navigation) {
          Button { onClose() } label: { Label("Back", systemImage: "chevron.left") }
        }
      }
      // No chevron paging buttons (owner request): horizontal scroll pages prev/next
      // and Esc/Back exits. Arrows arrive via `.onKeyPress` below.
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
          // WP-E E1: a single click opens edit mode at once (no double-click).
          Button { showingEditMode = true } label: { Label("Edit", systemImage: "slider.horizontal.3") }
            .accessibilityIdentifier(AXIDs.toolbarEdit)
        }
        Button { rotateClockwise() } label: { Label("Rotate", systemImage: "rotate.right") }
          .disabled(asset?.type == .video)
          .help(
            asset?.type == .video
              ? "Rotation is not available for videos" : "Rotate 90° clockwise (⌘R)")
        Button { showingInspector.toggle() } label: { Label("Info", systemImage: "info.circle") }
        Toggle("Live Text", isOn: $liveTextEnabled)
          .disabled(asset?.type == .video)
      }
    }
    .inspector(isPresented: $showingInspector) {
      if let asset {
        MacInspectorView(asset: asset, state: state)
      }
    }
    .sheet(isPresented: $showingMove) {
      MacMoveSheet(state: state, assetIds: [assetId]) { results in
        showingMove = false
        // Same posts as the grid's move sheet (MacMainWindow): moved rows leave every
        // context without a reload; when this asset moved out, advance past it (item 7).
        let moved = Set(results.filter { $0.status == .moved }.map(\.assetId))
        guard !moved.isEmpty else { return }
        MacAssetChangeCenter.shared.post(.removedFromCurrentContexts(ids: moved))
        if moved.contains(assetId) { advanceAfterRemoval(removedId: assetId) }
      }
    }
    .sheet(isPresented: $showingAddToAlbum) {
      MacAddToAlbumSheet(state: state, assetIds: [assetId]) {
        showingAddToAlbum = false
        MacAssetChangeCenter.shared.post(.albumsChanged)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .heirloomOpenEdit)) { note in
      // WP-E E1: open on the viewer notification (first click / Return route here).
      if let id = note.userInfo?["assetId"] as? String, id != assetId { return }
      if let asset, canEdit(asset) { showingEditMode = true }
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
    // WP-E E1: Return opens edit mode (first-click parity for keyboard).
    .onKeyPress(.return) {
      guard !showingEditMode, let asset, canEdit(asset) else { return .ignored }
      showingEditMode = true
      return .handled
    }
    // Esc closes the inline viewer; the existing `onClose` callback returns to the
    // grid with the prior selection intact (WP5 item 8). Standalone viewer windows
    // (no `onClose`) keep the window-level close behavior.
    .onKeyPress(.escape) {
      guard let onClose else { return .ignored }
      onClose()
      return .handled
    }
    .task(id: assetId) {
      // Display-only state never carries across pages (rotation re-fit is per photo; the
      // persisted rotation arrives back through the pipeline, not through this state).
      quarterTurns = 0
      rotationError = nil
      liveText = nil
      titlePlace = nil
      await ensureFallbackContext()
      await loadProgressive()
    }
    .onAppear { isFocused = true }
    .task(id: liveTextEnabled) {
      // Toggling Live Text on after load still needs an analysis (item 10); the preview
      // tier is enough — analysis runs on whatever tier is currently displayed.
      if liveTextEnabled, liveText == nil, image != nil, asset?.type != .video {
        await analyzeLiveText()
      }
    }
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
      if id == assetId {
        titlePlace = try? await state.store.exifSummary(assetId: id)?.placeString
      }
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

  /// Rotation persistence (WP5 item 4): the path WP4 decided PERSISTABLE — the same
  /// EditRecipe/PUT-edits/KV route the grid uses (`MacMainWindow.rotate(ids:)`), minus the
  /// render/upload, which pure rotation does not need (`requiresClientRender == false`).
  /// Videos are excluded per that decision (their rotation is a `VideoRecipe` client export).
  private func persistRotationIfEnabled() {
    guard let asset, asset.type != .video else { return }
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
        // 404 → fresh recipe; any other fetch failure aborts rather than clobbers.
        let stored = try await persistence.fetchRecipe(assetId: id)
        var recipe = stored?.recipe ?? EditRecipe()
        var crop = recipe.crop ?? CropRecipe()
        crop.quarterTurns = (crop.quarterTurns + 1) % 4
        recipe.crop = crop
        // Full merged split, like the grid: a 4th turn wraps to 0 upstream turns and emits
        // no items, so clear instead of hitting the empty no-op guard (stale server rotate).
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
        // Re-stream the preview so the persisted orientation shows up here too.
        await loadProgressive()
      } catch is CancellationError {
      } catch {
        rotationError = "Could not save rotation: \(error.localizedDescription)"
        HeirloomLog.ui.error("viewer rotate failed: \(String(describing: error))")
      }
    }
  }

  private func rotateClockwise() {
    quarterTurns = (quarterTurns + 1) % 4
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

/// One shared swipe-to-page interpreter for both viewer scroll containers below.
/// Dominant-x scroll (trackpad swipe or mouse-wheel-x) maps to a page delta with
/// Photos direction: swipe left (dx < 0) advances, swipe right goes back. Trackpad
/// gestures accumulate precise points and fire once per swipe; discrete wheels fire
/// one page per detent. Vertical scroll and momentum coasting return false so the
/// caller passes them through untouched.
final class PageSwipeTracker {
  private var pendingX: CGFloat = 0
  private var consumed = false
  /// Precise points of dominant-x travel that trigger a page.
  private static let travel: CGFloat = 80

  /// Page delta (-1/0/+1) for a horizontal scroll event; 0 means "not a page gesture".
  func delta(for event: NSEvent) -> Int {
    let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
    guard dx != 0, abs(dx) > abs(dy), event.momentumPhase.isEmpty else { return 0 }
    if !event.hasPreciseScrollingDeltas { return dx > 0 ? -1 : 1 }
    if event.phase.contains(.began) { pendingX = 0; consumed = false }
    defer {
      if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
        pendingX = 0; consumed = false
      }
    }
    guard !consumed else { return 0 }
    pendingX += dx
    guard abs(pendingX) >= Self.travel else { return 0 }
    consumed = true
    let dir = pendingX > 0 ? -1 : 1
    pendingX = 0
    return dir
  }
}

/// Plain-view paging catcher for the Live Text photo path (no zoom there, so no
/// magnification gate): unhandled scrolls bubble up the responder chain to this
/// container, which pages on dominant-x and forwards everything else.
final class ViewerPageCatcherView: NSView {
  var onPage: ((Int) -> Void)?
  private let tracker = PageSwipeTracker()

  override func scrollWheel(with event: NSEvent) {
    let dir = tracker.delta(for: event)
    guard dir != 0 else { super.scrollWheel(with: event); return }
    onPage?(dir)
  }
}

/// NSScrollView magnifier with swipe-to-page: pinch zoom is native
/// (`allowsMagnification`, clamped to min/max below); a dominant-x scroll at 1.0×
/// pages through `onPage` instead, reusing the viewer's `page(by:)` path. Past 1.0×
/// the scroll pans (Photos behavior), so zoom never fights paging.
final class ViewerPagingScrollView: NSScrollView {
  var onPage: ((Int) -> Void)?
  private let tracker = PageSwipeTracker()

  override func scrollWheel(with event: NSEvent) {
    // Zoomed: pan. Everything else delegates to the tracker; non-page scrolls
    // (vertical, momentum, zoomed horizontal) keep native behavior.
    if magnification > 1.001 { super.scrollWheel(with: event); return }
    let dir = tracker.delta(for: event)
    guard dir != 0 else { super.scrollWheel(with: event); return }
    onPage?(dir)
  }
}

/// NSScrollView magnifier: pinch/scroll zoom; crossing 1.5× fires `onZoomBeyondPreview`
/// once so the viewer upgrades to the fullsize tier (WP5 item 2). Every magnification
/// change is also reported through `onMagnification` so the viewer can decide the
/// window-exceeds-preview upgrade without polling.
struct MacZoomableImageView: NSViewRepresentable {
  var image: NSImage
  var onZoomBeyondPreview: () -> Void
  var onMagnification: (Double) -> Void = { _ in }
  /// Swipe-to-page (owner request): routed into the viewer's `page(by:)`, so the
  /// neighbor-preload and no-blank-flash invariants hold for gestures exactly as
  /// for buttons and arrow keys — no second paging implementation.
  var onPage: ((Int) -> Void)? = nil

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = ViewerPagingScrollView()
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 1
    scrollView.maxMagnification = 8
    scrollView.onPage = onPage
    let imageView = NSImageView(image: image)
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.imageAlignment = .alignCenter
    scrollView.documentView = imageView
    context.coordinator.observe(scrollView: scrollView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.update(
      action: onZoomBeyondPreview, magnification: onMagnification, image: image,
      onPage: onPage)
    (scrollView as? ViewerPagingScrollView)?.onPage = onPage
    (scrollView.documentView as? NSImageView)?.image = image
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      action: onZoomBeyondPreview, magnification: onMagnification, image: image,
      onPage: onPage)
  }

  /// Main-thread-confined zoom state carried across the @Sendable notification closure.
  final class ZoomState: @unchecked Sendable {
    weak var scrollView: NSScrollView?
    var onZoom: () -> Void = {}
    var onMagnification: (Double) -> Void = { _ in }
    var onPage: ((Int) -> Void)? = nil
    weak var lastImage: NSImage?
    var fired = false
  }

  final class Coordinator: NSObject {
    private let state = ZoomState()
    private var observer: NSObjectProtocol?
    private var boundsObserver: NSObjectProtocol?

    init(
      action: @escaping () -> Void, magnification: @escaping (Double) -> Void, image: NSImage,
      onPage: ((Int) -> Void)? = nil
    ) {
      state.onZoom = action
      state.onMagnification = magnification
      state.onPage = onPage
      state.lastImage = image
    }

    func update(
      action: @escaping () -> Void, magnification: @escaping (Double) -> Void, image: NSImage,
      onPage: ((Int) -> Void)? = nil
    ) {
      state.onZoom = action
      state.onMagnification = magnification
      state.onPage = onPage
      // The scroll view persists across pages (only its image swaps), so re-arm the
      // once-per-page fullsize trigger when a new page's image arrives.
      if state.lastImage !== image {
        state.lastImage = image
        state.fired = false
      }
    }

    /// Reports one magnification step: continuous zoom feedback plus the
    /// once-per-page > 1.5× fullsize trigger. Runs SwiftUI-side outside the
    /// rotation re-fit, so pinch zoom composes with rotation instead of fighting it.
    /// Static so the @Sendable notification closures never send the coordinator.
    private static func reportMagnification(_ state: ZoomState) {
      guard let view = state.scrollView else { return }
      let mag = Double(view.magnification)
      state.onMagnification(mag)
      guard !state.fired, mag > 1.5 else { return }
      state.fired = true
      state.onZoom()
    }

    func observe(scrollView: NSScrollView) {
      state.scrollView = scrollView
      if let paging = scrollView as? ViewerPagingScrollView { paging.onPage = state.onPage }
      let state = self.state
      observer = NotificationCenter.default.addObserver(
        forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main
      ) { _ in
        MainActor.assumeIsolated { Self.reportMagnification(state) }
      }
      // Continuous pinch feedback (the notification above fires only at gesture
      // end): the clip view's bounds move throughout a live magnify.
      scrollView.contentView.postsBoundsChangedNotifications = true
      boundsObserver = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification, object: scrollView.contentView,
        queue: .main
      ) { _ in
        MainActor.assumeIsolated { Self.reportMagnification(state) }
      }
    }

    deinit {
      if let observer { NotificationCenter.default.removeObserver(observer) }
      if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }
  }
}

#Preview("Viewer") {
  MacPreviewFixture { state in
    MacViewerView(state: state, assetId: "asset-personal-1")
      .frame(width: 1000, height: 700)
  }
}
