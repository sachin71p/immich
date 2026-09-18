import AVFoundation
import AVKit
import CoreModel
import Editing
import LocalStore
import MapKit
import Media
import Rules
import Search
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

// MARK: - zoomable image (brief task 4: pinch / double-tap zoom, progressive tier upgrade)

/// Zoomable still image with VisionKit Live Text (A9.2): the interaction is attached once
/// and the SwiftUI side feeds it the `ImageAnalysis` computed after each tier upgrade, so
/// text selection, data detectors, Visual Look Up, and subject lift (long-press to copy)
/// work on the viewer image.
struct ZoomableImageView: UIViewRepresentable {
  var image: UIImage?
  var analysis: ImageAnalysis?
  var onSingleTap: (() -> Void)? = nil
  /// WP-M (V6): page-local long-press. A SwiftUI `.onLongPressGesture` on the
  /// UIKit-hosted pager never sees the touch, so the recognizer sits here, on
  /// the image view itself, next to the existing tap recognizers.
  var onLongPress: (() -> Void)? = nil

  func makeUIView(context: Context) -> UIScrollView {
    let scroll = UIScrollView()
    scroll.minimumZoomScale = 1
    scroll.maximumZoomScale = 6
    scroll.delegate = context.coordinator
    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.isUserInteractionEnabled = true
    scroll.addSubview(imageView)
    context.coordinator.imageView = imageView
    context.coordinator.interaction.preferredInteractionTypes = .automatic
    imageView.addInteraction(context.coordinator.interaction)
    let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.zoomToggle(_:)))
    doubleTap.numberOfTapsRequired = 2
    imageView.addGestureRecognizer(doubleTap)
    let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
    singleTap.require(toFail: doubleTap)
    imageView.addGestureRecognizer(singleTap)
    // 0.35 s, not the usual 0.5 s: this view also hosts VisionKit's
    // subject-lift long-press (see the interaction above), and two
    // long-presses on one touch race — the shorter one recognizes first and
    // fails the other (no simultaneous recognition by default). The menu must
    // win that race deterministically; when VisionKit has nothing liftable
    // under the touch its recognizer stays out of the way on its own.
    let longPress = UILongPressGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
    longPress.minimumPressDuration = 0.35
    imageView.addGestureRecognizer(longPress)
    return scroll
  }

  func updateUIView(_ scroll: UIScrollView, context: Context) {
    context.coordinator.imageView?.image = image
    context.coordinator.onSingleTap = onSingleTap
    context.coordinator.onLongPress = onLongPress
    if context.coordinator.appliedAnalysis !== analysis {
      context.coordinator.appliedAnalysis = analysis
      context.coordinator.interaction.analysis = analysis
    }
    if let imageView = context.coordinator.imageView {
      imageView.frame = scroll.bounds
      imageView.contentMode = .scaleAspectFit
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject, UIScrollViewDelegate {
    var imageView: UIImageView?
    var onSingleTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    let interaction = ImageAnalysisInteraction()
    var appliedAnalysis: ImageAnalysis?

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc func zoomToggle(_ gesture: UITapGestureRecognizer) {
      guard let scroll = gesture.view?.superview as? UIScrollView else { return }
      scroll.setZoomScale(scroll.zoomScale > 1.5 ? 1 : 3, animated: true)
    }

    @objc func tapped() { onSingleTap?() }

    @objc func longPressed(_ gesture: UILongPressGestureRecognizer) {
      guard gesture.state == .began else { return }
      onLongPress?()
    }
  }
}

// MARK: - single asset page

struct ViewerPage: View {
  @EnvironmentObject var session: AppSession
  var assetId: String
  var onSingleTap: (() -> Void)? = nil
  var livePlay: LivePlayRequest

  @State private var asset: Asset?
  @State private var image: UIImage?
  @State private var liveText: ImageAnalysis?
  /// WP-M (V6): page-local long-press menu (stills only — video/live pages
  /// live in `LiveVideo.swift`, outside WP-M's allowance; see the report).
  @State private var showLongPressMenu = false
  @State private var showAlbumPicker = false
  @State private var actionError: String?

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if let asset, asset.type == .video {
        VideoPage(asset: asset)
      } else if let asset, let motionId = asset.livePhotoVideoId {
        LivePhotoPageView(
          asset: asset, motionAssetId: motionId,
          onSingleTap: onSingleTap, playRequest: livePlay)
      } else if let image {
        ZoomableImageView(
          image: image, analysis: liveText, onSingleTap: onSingleTap,
          onLongPress: { showLongPressMenu = true })
      } else {
        ProgressView()
          .tint(.white)
          .accessibilityIdentifier("viewer-loading")
      }
    }
    .task(id: assetId) {
      await load()
    }
    // Page-local menu sheet: Delete confirms inside the menu and only then
    // trashes, so automation asserts presence without tapping through (§0.5).
    .sheet(isPresented: $showLongPressMenu) {
      if let asset {
        ViewerLongPressMenu(
          asset: asset, access: session.access,
          preview: image,
          onShare: { share(asset) },
          onFavorite: { toggleFavorite(asset) },
          onCopy: { copyAsset(asset) },
          onAddToAlbum: { showAlbumPicker = true },
          onHide: { setHidden(asset) },
          onTrash: { trash(asset) })
      }
    }
    .sheet(isPresented: $showAlbumPicker) {
      AlbumPickerSheet(assetIds: [assetId])
        .environmentObject(session)
    }
    .alert("Action failed", isPresented: Binding(
      get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    ) {
      Button("OK") { actionError = nil }
    } message: {
      Text(actionError ?? "")
    }
  }

  private func load() async {
    guard let store = session.store else { return }
    asset = try? await store.asset(id: assetId)
    guard let asset, let pipeline = session.pipeline else { return }
    // Progressive tier upgrade (brief task 4): thumbnail first for instant paint, then preview,
    // then the full tier — each step replaces the previous image.
    for tier: MediaTier in [.thumbnail, .preview, .fullsize] {
      do {
        let loaded = try await pipeline.load(asset: asset, tier: tier)
        let next: UIImage? = switch loaded.content {
        case .placeholder(let img): img
        case .tier(_, let img, _): img
        }
        if let next {
          image = next
          // Live Text runs once, on the full tier only (P6: per-tier analysis on the
          // main actor stalled the viewer under load).
          if tier == .fullsize { await analyzeLiveText(next) }
        }
        if tier == .fullsize { break }
      } catch {
        break
      }
    }
  }

  /// WP-M (V6): page-local menu actions. Session-direct (the page owns no
  /// chrome helpers): same mutation-then-refresh pattern as the grid menu, and
  /// the same guarded share/copy paths as `ViewerView`. Failures surface in
  /// the page alert; cancellations never do.
  private func toggleFavorite(_ asset: Asset) {
    mutate {
      guard let mutations = session.assetMutations else { return }
      try await mutations.setFavorite(ids: [asset.id], isFavorite: !asset.isFavorite)
    }
  }

  private func setHidden(_ asset: Asset) {
    mutate {
      guard let mutations = session.assetMutations else { return }
      try await mutations.setHidden(ids: [asset.id], isHidden: asset.visibility != .hidden)
    }
  }

  private func trash(_ asset: Asset) {
    mutate {
      guard let mutations = session.assetMutations else { return }
      try await mutations.trash(ids: [asset.id])
    }
  }

  private func share(_ asset: Asset) {
    Task {
      guard let base = session.apiBaseURL,
        let token = await session.bearerToken(),
        let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene }).first?.windows.first
      else { return }
      do {
        var request = URLRequest(
          url: MediaEndpoint(serverURL: base, assetID: asset.id).originalURL())
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(asset.originalFileName)
        try data.write(to: tmp)
        let activity = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
          popover.sourceView = window
        }
        window.rootViewController?.present(activity, animated: true)
      } catch {
        if !error.isCancellation { actionError = error.localizedDescription }
      }
    }
  }

  private func copyAsset(_ asset: Asset) {
    Task {
      guard let pipeline = session.pipeline,
        let result = try? await pipeline.load(asset: asset, tier: .preview)
      else { return }
      switch result.content {
      case .placeholder(let img), .tier(_, let img, _):
        UIPasteboard.general.images = [img]
      }
    }
  }

  private func mutate(_ work: @escaping () async throws -> Void) {
    Task {
      do {
        try await work()
        try await session.refresh()
        await load()
      } catch {
        if !error.isCancellation { actionError = error.localizedDescription }
      }
    }
  }

  /// A9.2: analyze the latest still for Live Text. Vision runs detached (P6: it must
  /// never execute on the main actor); failures leave `liveText` nil and the viewer
  /// keeps working — Live Text is an enhancement, never a gate.
  private func analyzeLiveText(_ uiImage: UIImage) async {
    guard let cgImage = uiImage.cgImage else { return }
    // VisionKit's `ImageAnalysis` isn't Sendable; the completed result is handed
    // once from the detached task to the main actor and never shared afterwards.
    struct CompletedAnalysis: @unchecked Sendable {
      let analysis: ImageAnalysis?
    }
    let completed = await Task.detached(priority: .utility) {
      let analyzer = ImageAnalyzer()
      return CompletedAnalysis(
        analysis: try? await analyzer.analyze(
          cgImage, orientation: .up,
          configuration: ImageAnalyzer.Configuration([.text, .machineReadableCode, .visualLookUp])))
    }.value
    liveText = completed.analysis
  }
}

// MARK: - viewer (brief task 4)

/// Full-screen viewer: UIKit paging over a `ViewerRoute` (O(1) open), progressive tiers,
/// swipe-down dismiss with the grid behind it, swipe-up info panel, and native-style
/// glass chrome (top pill, badges, filmstrip, bottom bar) with permission gating.
struct ViewerView: View {
  @EnvironmentObject var session: AppSession
  private let route: ViewerRoute?

  @State private var ids: [String]
  @State private var currentIndex: Int
  @State private var currentId: String?
  @State private var asset: Asset?
  @State private var showChrome = true
  @State private var showInfo = false
  @State private var showMoveSheet = false
  @State private var showAlbumPicker = false
  @State private var editRequest: EditSession?
  @State private var actionError: String?
  @State private var openMs: Double?
  @State private var exif: AssetExif?
  @State private var ownerName: String?
  @State private var showTrashConfirm = false
  @StateObject private var livePlay = LivePlayRequest()
  @Environment(\.dismiss) private var dismiss
  private let openStart = Date()

  /// Legacy entry: fixed id list (Library/Search/Collections/Spaces/Albums call sites).
  init(ids: [String], initialId: String?) {
    self.route = nil
    _ids = State(initialValue: ids)
    let start = initialId ?? ids.first
    _currentId = State(initialValue: start)
    _currentIndex = State(initialValue: ids.firstIndex(of: start ?? "") ?? 0)
  }

  /// WP1 contract entry: index provider plus start id — resolved once on open, never an
  /// array copy per tap or per SwiftUI update.
  init(route: ViewerRoute) {
    self.route = route
    _ids = State(initialValue: [])
    _currentId = State(initialValue: route.startId)
    _currentIndex = State(initialValue: 0)
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if ids.isEmpty {
        ProgressView()
          .tint(.white)
          .accessibilityIdentifier("viewer-loading")
      } else {
        ViewerPager(
          ids: ids, session: session, currentIndex: $currentIndex,
          livePlay: livePlay,
          dismissEnabled: !showInfo,
          onSingleTap: { showChrome.toggle() },
          onDismiss: { dismiss() },
          onSwipeUp: { showInfo = true })
      }
      if showInfo, let asset {
        ViewerInfoPanel(
          asset: asset, exif: exif, containerName: containerName(for: asset),
          onClose: { showInfo = false }
        )
        .environmentObject(session)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 4)
        .padding(.bottom, showChrome ? ViewerLayout.bottomReserve : 12)
      }
      // UI-test hooks (hidden): page position and open latency.
      Text("\(min(currentIndex + 1, max(ids.count, 1))) of \(ids.count)")
        .accessibilityIdentifier("viewer-page-index")
        .opacity(0)
        .allowsHitTesting(false)
      if let openMs {
        Text("openMs=\(String(format: "%.0f", openMs))")
          .accessibilityIdentifier("viewer-open-summary")
          .opacity(0)
          .allowsHitTesting(false)
      }
    }
    .safeAreaInset(edge: .top) {
      if showChrome, asset != nil {
        VStack(spacing: 8) {
          ViewerTopBar(
            line1: pillLines.0, line2: pillLines.1,
            menu: AnyView(moreMenu),
            onBack: { dismiss() })
          ViewerBadgeRow(
            isLive: asset?.livePhotoVideoId != nil,
            ownerName: ownerName,
            onPlayLive: { livePlay.token += 1 })
        }
        .padding(.horizontal, 12)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if showChrome, let asset {
        VStack(spacing: 10) {
          ViewerFilmstrip(
            ids: ids, currentIndex: currentIndex, session: session,
            onJump: { currentIndex = $0 })
          ViewerGlassBar(
            asset: asset, access: session.access,
            isFavorite: asset.isFavorite,
            onShare: { share(asset) },
            onFavorite: { toggleFavorite(asset) },
            onInfo: { showInfo.toggle() },
            onAdjust: { openEdit(asset) },
            onTrash: { showTrashConfirm = true })
        }
        .frame(maxWidth: .infinity)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: showChrome)
    // Delete confirmation as an alert (the Spaces/Albums convention): a
    // confirmationDialog drops its cancel-role button from the AX hierarchy.
    .alert("Delete Photo?", isPresented: $showTrashConfirm) {
      Button("Delete", role: .destructive) {
        if let asset {
          mutate {
            try await session.assetMutations?.trash(ids: [asset.id])
            dismiss()
          }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This photo moves to Recently Deleted.")
    }
      .sheet(isPresented: $showMoveSheet) {
        if let currentId {
          MoveSheet(selectedIds: [currentId]) {
            Task { await reloadAsset() }
          }
          .environmentObject(session)
        }
      }
      .sheet(isPresented: $showAlbumPicker) {
        if let currentId {
          AlbumPickerSheet(assetIds: [currentId])
            .environmentObject(session)
        }
      }
      // (WP-M V6 lives page-locally in `ViewerPage` below — a SwiftUI
      // `.onLongPressGesture` on the UIKit-hosted pager never sees the touch,
      // so the recognizer sits on the page's own image view.)
      // WP-R (F3b): item-based cover. The previous `isPresented` + captured-
      // `self` content could present a stale snapshot (empty canvas, chrome
      // only after a scene-phase re-sync). The item carries fresh values as
      // parameters, so the content can never go stale.
      .fullScreenCover(item: $editRequest) { request in
        if let base = session.apiBaseURL {
          EditView(
            asset: request.asset, access: session.access, preview: request.preview,
            loadOriginalData: { [asset = request.asset] in try await downloadOriginal(asset) },
            loadVideoFile: request.asset.type == .video
              ? { [asset = request.asset] in try await downloadOriginalFile(asset) } : nil,
            loadDisplayImage: { [asset = request.asset] in try await fullDisplayImage(for: asset) },
            persistence: RESTEditPersistence(
              serverURL: base, token: { await session.bearerToken() }),
            onDone: { _ in Task { await reloadAsset() } })
        }
      }
      .alert("Action failed", isPresented: Binding(
        get: { actionError != nil }, set: { if !$0 { actionError = nil } })
      ) {
        Button("OK") { actionError = nil }
      } message: {
        Text(actionError ?? "")
      }
      .task(id: currentId) { await reloadAsset() }
      // Route entry resolves its ids once, inside the ViewerOpen signpost (the route
      // is Sendable; the asset load below stays on the main actor). The legacy entry
      // already has its list.
      .task {
        if let route, ids.isEmpty {
          let pending = route
          let resolved = HeirloomSignpost.interval(HeirloomSignpost.viewerOpen) {
            pending.resolveIds()
          }
          ids = resolved
          currentIndex = resolved.firstIndex(of: pending.startId) ?? 0
        }
        await reloadAsset()
        if openMs == nil {
          openMs = Date().timeIntervalSince(openStart) * 1000
        }
      }
      // The pager owns the index: swipes report back through the binding, and the
      // chrome asset follows.
      .onChange(of: currentIndex) { _, index in
        if ids.indices.contains(index) {
          currentId = ids[index]
        }
      }
  }

  /// Centre-pill lines for the current asset (location over date · time).
  private var pillLines: (String, String) {
    ViewerDateText.pillLines(date: asset?.localDateTime, city: exif?.city ?? exif?.state)
  }

  /// The top-bar "…" menu (same actions the old bottom-bar menu held; permission
  /// gating and lock semantics unchanged).
  @ViewBuilder
  private var moreMenu: some View {
    if let asset {
      ViewerMoreMenu(
        asset: asset, access: session.access,
        isOwnerPersonal: canLock(asset),
        onCopy: { copyAsset(asset) },
        onAddToAlbum: { showAlbumPicker = true },
        onMoveTo: { showMoveSheet = true },
        onArchive: {
          mutate {
            guard let mutations = session.assetMutations else { return }
            try await mutations.setArchived(
              ids: [asset.id], isArchived: asset.visibility != .archive)
          }
        },
        onHide: {
          mutate {
            guard let mutations = session.assetMutations else { return }
            try await mutations.setHidden(ids: [asset.id], isHidden: asset.visibility != .hidden)
          }
        },
        onLock: {
          Task {
            guard await LockedMediaAuthentication.authenticate(
              reason: asset.visibility == .locked ? "Unlock your personal photo" : "Lock this personal photo")
            else { return }
            mutate {
              guard let mutations = session.assetMutations else { return }
              try await mutations.setLocked(ids: [asset.id], isLocked: asset.visibility != .locked)
            }
          }
        })
    }
  }

  /// WP-R (F3b): the editor's present payload. Carried by value through
  /// `.fullScreenCover(item:)` so the presented content is always fresh —
  /// unlike `isPresented` + captured-`self` content, which can present stale.
  private struct EditSession: Identifiable {
    let id = UUID()
    var asset: Asset
    var preview: UIImage
  }

  private func containerName(for asset: Asset) -> String {
    switch asset.container {
    case .personal(let ownerId):
      return ownerId == session.userId ? "Personal Library" : "Personal Library (shared)"
    case .space(let id): return session.spaces.first { $0.id == id }?.name ?? "Shared Library"
    case .library(let id): return session.libraries.first { $0.id == id }?.name ?? "External Library"
    }
  }

  private func toggleFavorite(_ asset: Asset) {
    mutate {
      guard let mutations = session.assetMutations else { return }
      try await mutations.setFavorite(ids: [asset.id], isFavorite: !asset.isFavorite)
    }
  }

  private func mutate(_ work: @escaping () async throws -> Void) {
    Task {
      do {
        try await work()
        try await session.refresh()
        await reloadAsset()
      } catch {
        // L2: cancellation is never a user-facing error.
        if !error.isCancellation { actionError = error.localizedDescription }
      }
    }
  }

  private func canLock(_ asset: Asset) -> Bool {
    asset.ownerId == session.userId && asset.spaceId == nil && asset.libraryId == nil
  }

  private func share(_ asset: Asset) {
    Task {
      guard let base = session.apiBaseURL,
        let token = await session.bearerToken(),
        let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene }).first?.windows.first
      else { return }
      do {
        var request = URLRequest(
          url: MediaEndpoint(serverURL: base, assetID: asset.id).originalURL())
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(asset.originalFileName)
        try data.write(to: tmp)
        let activity = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
          popover.sourceView = window
        }
        window.rootViewController?.present(activity, animated: true)
      } catch {
        // L2: cancellation is never a user-facing error.
        if !error.isCancellation { actionError = error.localizedDescription }
      }
    }
  }

  private func copyAsset(_ asset: Asset) {
    Task {
      guard let base = session.apiBaseURL,
        let token = await session.bearerToken()
      else { return }
      do {
        var request = URLRequest(
          url: MediaEndpoint(serverURL: base, assetID: asset.id).originalURL())
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        if asset.type == .video {
          UIPasteboard.general.setData(data, forPasteboardType: UTType.movie.identifier)
        } else if let image = UIImage(data: data) {
          UIPasteboard.general.image = image
        } else {
          UIPasteboard.general.string = asset.id
        }
      } catch {
        // L2: cancellation is never a user-facing error.
        if !error.isCancellation { actionError = error.localizedDescription }
      }
    }
  }

  /// WP-R (F1/F3/F3b): present-first editing. The old path awaited the full-res
  /// original with no deadline *before* presenting, so a stalled fetch gated the
  /// editor chrome itself (F3b) and its failure modes ended on an empty canvas
  /// (F1/F3). Now the cover presents over the viewer's already-decoded image
  /// (same tiers `ViewerPage` paints); the full-res upgrade arrives in the
  /// background and can only replace the seed on a successful decode — never
  /// with an empty image. Save re-fetches the original itself, so the upgrade
  /// is display-only.
  private func openEdit(_ asset: Asset) {
    // Synchronous memory-cache probe: the viewer just painted these tiers.
    if let seed = cachedEditSeed(for: asset) {
      editRequest = EditSession(asset: asset, preview: seed)
      return
    }
    Task {
      do {
        // Nothing cached: bound the preview-tier fetch (the viewer stays visible
        // underneath, so this never shows black) and only then present.
        let preview = try await withMainActorTimeout(seconds: EditorLoadBudget.cachedPreviewFetch) {
          try await previewTierImage(for: asset)
        }
        editRequest = EditSession(asset: asset, preview: preview)
      } catch {
        // L2: cancellation is never a user-facing error.
        if !error.isCancellation { actionError = error.localizedDescription }
      }
    }
  }

  /// Best already-decoded image for `asset.id`: fullsize → preview → thumbnail →
  /// thumbhash placeholder. `nil` means "fetch"; never synthesizes an empty image.
  private func cachedEditSeed(for asset: Asset) -> UIImage? {
    if let pipeline = session.pipeline {
      for tier: MediaTier in [.fullsize, .preview, .thumbnail] {
        if let cg = pipeline.cachedImage(id: asset.id, tier: tier) {
          return UIImage(cgImage: cg)
        }
      }
    }
    if let hash = asset.thumbhash,
      let decoded = try? ThumbHash.decode(base64: hash),
      let cg = decoded.makeCGImage()
    {
      return UIImage(cgImage: cg)
    }
    return nil
  }

  /// First image yielded by the working viewer pipeline at preview tier.
  private func previewTierImage(for asset: Asset) async throws -> UIImage {
    guard let pipeline = session.pipeline else { throw EditAccessError.notPermitted }
    for try await loaded in await pipeline.stream(asset: asset, tier: .preview) {
      switch loaded.content {
      case .placeholder(let img), .tier(_, let img, _):
        return img
      }
    }
    throw EditAccessError.notPermitted
  }

  /// WP-R (F1/F3): full-res canvas upgrade. Returns a *decoded* image — throws
  /// on undecodable data so the caller keeps the preview seed. Never returns an
  /// empty `UIImage()` (the old video path did, painting a permanent black
  /// canvas behind interactive chrome).
  private func fullDisplayImage(for asset: Asset) async throws -> UIImage {
    let data = try await downloadOriginal(asset)
    if let image = UIImage(data: data) { return image }
    guard asset.type == .video else { throw EditRenderError.undecodableSource }
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    try data.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    guard let frame = await firstFrame(of: tmp) else {
      throw EditRenderError.undecodableSource
    }
    return frame
  }

  private func downloadOriginal(_ asset: Asset) async throws -> Data {
    guard let base = session.apiBaseURL, let token = await session.bearerToken() else {
      throw EditAccessError.notPermitted
    }
    var request = URLRequest(
      url: MediaEndpoint(serverURL: base, assetID: asset.id).originalURL())
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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

  private func firstFrame(of url: URL) async -> UIImage? {
    // Synchronous thumbnail extraction on a background task (classic API — no
    // async-API availability questions on any deployment target).
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    do {
      let cg = try generator.copyCGImage(at: .zero, actualTime: nil)
      return UIImage(cgImage: cg)
    } catch {
      return nil
    }
  }

  private func reloadAsset() async {
    guard let currentId, let store = session.store else { return }
    asset = try? await store.asset(id: currentId)
    // Chrome context loads with the asset: exif for the title pill, owner name for
    // the "From" badge. Both are single-row lookups; failures hide their UI.
    guard let asset else {
      exif = nil
      ownerName = nil
      return
    }
    exif = try? await store.exif(for: asset.id)
    ownerName = nil
    if asset.spaceId != nil, asset.ownerId != session.userId,
      let user = try? await store.user(id: asset.ownerId), !user.name.isEmpty
    {
      ownerName = user.name
    }
  }
}

