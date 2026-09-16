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
      rotate: { rotation += 90 },
      trash: { trash() },
      move: { showingMove = true },
      addToAlbum: { showingAddToAlbum = true },
      toggleInspector: { showingInspector.toggle() },
      openViewer: {},
      preview: {}
    )
  }

  /// Display-order paging context (WP2 Step 4: was the unfiltered full id list).
  private var siblings: [String] { state.viewerContext?.ids ?? [] }

  private var index: Int? {
    guard let context = state.viewerContext, !context.rows.isEmpty,
      let raw = context.indexById[assetId]
    else { return nil }
    return min(max(0, raw), context.rows.count - 1)
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
          MacZoomableImageView(image: image, onZoomBeyondPreview: upgradeTier)
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
    .navigationTitle(asset?.originalFileName ?? "Viewer")
    .focusedValue(\.macAssetActions, assetActions)
    .toolbar {
      if let onClose {
        ToolbarItem(placement: .navigation) {
          Button { onClose() } label: { Label("Back", systemImage: "chevron.left") }
        }
      }
      ToolbarItemGroup {
        Button { toggleFavorite() } label: {
          Label("Favorite", systemImage: (asset?.isFavorite ?? false) ? "heart.fill" : "heart")
        }
        Button { rotation += 90 } label: { Label("Rotate", systemImage: "rotate.right") }
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
          onDone: { _ in Task { await load(tier: .preview) } })
          .frame(minWidth: 900, minHeight: 640)
      }
    }
    .focusable()
    .focused($isFocused)
    .onKeyPress(.leftArrow) { page(by: -1); return .handled }
    .onKeyPress(.rightArrow) { page(by: 1); return .handled }
    .onKeyPress(.escape) {
      guard let onClose else { return .ignored }
      onClose()
      return .handled
    }
    .task(id: assetId) { await load(tier: .preview) }
    .onAppear { isFocused = true }
  }

  private func page(by delta: Int) {
    guard let index, !siblings.isEmpty else { return }
    let next = siblings[(index + delta + siblings.count) % siblings.count]
    if let onNavigate {
      onNavigate(next)
    } else {
      openWindow(value: MacWindow.viewer(next))
    }
  }

  private func load(tier: MediaTier) async {
    do {
      guard let fresh = try await state.store.asset(id: assetId) else { return }
      asset = fresh
      let loaded = try await state.pipeline.load(asset: fresh, tier: tier)
      switch loaded.content {
      case .placeholder(let image): self.image = image
      case .tier(_, let image, _): self.image = image
      }
      loadedTier = tier
      await analyzeLiveText()
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func upgradeTier() {
    guard loadedTier != .original, asset != nil else { return }
    Task { await load(tier: .original) }
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

  private func toggleFavorite() {
    guard let asset else { return }
    Task {
      do {
        try await state.assetMutations().setFavorite(ids: [assetId], isFavorite: !asset.isFavorite)
        self.asset = try await state.store.asset(id: assetId)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func trash() {
    Task {
      do {
        try await state.assetMutations().trash(ids: [assetId])
        await state.refresh()
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
        try await state.assetMutations().setLocked(ids: [asset.id], isLocked: asset.visibility != .locked)
        self.asset = try await state.store.asset(id: asset.id)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

/// NSScrollView magnifier: pinch/scroll zoom; crossing 2× fires `onZoomBeyondPreview` once so the
/// viewer upgrades to the original tier (brief task 3).
struct MacZoomableImageView: NSViewRepresentable {
  var image: NSImage
  var onZoomBeyondPreview: () -> Void

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
    context.coordinator.update(action: onZoomBeyondPreview)
    (scrollView.documentView as? NSImageView)?.image = image
  }

  func makeCoordinator() -> Coordinator { Coordinator(action: onZoomBeyondPreview) }

  /// Main-thread-confined zoom state carried across the @Sendable notification closure.
  final class ZoomState: @unchecked Sendable {
    weak var scrollView: NSScrollView?
    var onZoom: () -> Void = {}
    var fired = false
  }

  final class Coordinator: NSObject {
    private let state = ZoomState()
    private var observer: NSObjectProtocol?

    init(action: @escaping () -> Void) {
      state.onZoom = action
    }

    func update(action: @escaping () -> Void) {
      state.onZoom = action
    }

    func observe(scrollView: NSScrollView) {
      state.scrollView = scrollView
      let state = self.state
      observer = NotificationCenter.default.addObserver(
        forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main
      ) { _ in
        MainActor.assumeIsolated {
          guard !state.fired, let view = state.scrollView, view.magnification > 2 else { return }
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
