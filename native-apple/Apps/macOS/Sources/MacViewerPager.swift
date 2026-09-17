import AppKit
import CoreModel
import Media
import SwiftUI
import VisionKit

// MARK: - page store

/// Async loading behind the page controllers (V5/V6): row-based tier streams
/// (no full `Asset` needed), memory-cache thumbnails, lazy Live Text analysis
/// and ±2 neighbour prefetch. One store per viewer.
@MainActor
final class ViewerPageStore {
  let state: MacAppState

  init(state: MacAppState) { self.state = state }

  func cachedThumbnail(id: String) -> NSImage? {
    guard let cg = state.pipeline.cachedImage(id: id, tier: .thumbnail) else { return nil }
    return NSImage(cgImage: cg, size: NSZeroSize)
  }

  func previewStream(id: String, thumbhash: String?) async
    -> AsyncThrowingStream<MediaLoadedImage, any Error>
  {
    await state.pipeline.stream(id: id, thumbhash: thumbhash, tier: .preview)
  }

  func fullsizeStream(id: String, thumbhash: String?) async
    -> AsyncThrowingStream<MediaLoadedImage, any Error>
  {
    await state.pipeline.stream(id: id, thumbhash: thumbhash, tier: .fullsize)
  }

  func fetchAsset(id: String) async -> Asset? {
    try? await state.store.asset(id: id)
  }

  /// Live Text analysis (V1): failures leave the result nil — Live Text is an
  /// enhancement, never a gate.
  func analyze(_ image: NSImage) async -> ImageAnalysis? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return nil }
    do {
      return try await ImageAnalyzer().analyze(
        cgImage, orientation: .up,
        configuration: ImageAnalyzer.Configuration([.text, .machineReadableCode, .visualLookUp]))
    } catch {
      return nil
    }
  }

  /// Neighbour preload (V5/V6): warm ±2 at the preview tier, drop prefetch
  /// work outside the window.
  func prefetch(ids: [String], thumbhashes: [String: String?]) async {
    await state.pipeline.cancelPrefetch(keeping: Set(ids))
    await state.pipeline.prefetch(
      ids.map { (id: $0, thumbhash: thumbhashes[$0] ?? nil) }, tier: .preview)
  }

  func videoLoader() -> VideoPlaybackLoader {
    VideoPlaybackLoader(
      serverURL: state.serverURL,
      token: { [connection = state.connection] in await connection.tokenStore.get() })
  }
}

// MARK: - pager host (V5, V6)

/// `NSPageController` host (PLAN §2.1, WP-V step 3): `.horizontalStrip` gives
/// Photos' exact interactive swipe (1:1, spring, rubber-band, honours "Swipe
/// between pages") and animated `navigateForward/Back` for ←/→.
///
/// Pages are `NSViewController`s (`ImagePageController`, `VideoPageController`
/// in `MacViewerPages.swift`). The arranged objects are asset ids only — the
/// delegate creates page controllers lazily, so 102k ids never become 102k
/// controllers. Neighbour preload is ±2 (V5/V6) through `onPreload`.
final class ViewerPagerViewController: NSViewController, NSPageControllerDelegate {
  var onSelect: ((String) -> Void)?
  var pageController: ((String) -> NSViewController)?
  var onPreload: (([String]) -> Void)?
  var onPageMagnification: ((String, Double) -> Void)?
  var onPinchClose: ((String, CGFloat) -> Void)?
  var onPinchCloseEnd: ((String, CGFloat) -> Void)?

  private let pager = NSPageController()
  private var ids: [String] = []
  private var isTransitioning = false
  /// Rapid-press coalescing (V6): at most one pending step; a pending jump
  /// lands without animation.
  private var pendingSteps = 0
  /// Created page controllers by id (V5: only demanded pages exist).
  private var pageCache: [String: NSViewController] = [:]

  init(ids: [String], selectedID: String?) {
    self.ids = ids
    self.pendingSelection = selectedID
    super.init(nibName: nil, bundle: nil)
  }

  private var pendingSelection: String?

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func loadView() {
    view = NSView()
    pager.delegate = self
    pager.transitionStyle = .horizontalStrip
    addChild(pager)
    pager.view.frame = view.bounds
    pager.view.autoresizingMask = [.width, .height]
    view.addSubview(pager.view)
    reloadArrangedObjects()
  }

  func update(ids: [String], selectedID: String) {
    // Never reset arranged objects mid-gesture: SwiftUI re-renders on every
    // slider tick, so only reload when the context itself changed.
    if ids != self.ids {
      self.ids = ids
      reloadArrangedObjects(preserving: selectedID)
    }
    guard selectedID != currentID, let index = ids.firstIndex(of: selectedID),
      index != pager.selectedIndex
    else { return }
    pager.selectedIndex = index
  }

  private var currentID: String? {
    guard !ids.isEmpty, pager.selectedIndex < ids.count else { return nil }
    return ids[pager.selectedIndex]
  }

  private func reloadArrangedObjects(preserving selectedID: String? = nil) {
    pager.arrangedObjects = ids
    let target = selectedID ?? pendingSelection
    pendingSelection = nil
    if let target, let index = ids.firstIndex(of: target) {
      pager.selectedIndex = index
    }
  }

  // MARK: arrow-key paging (V6)

  func step(_ delta: Int) {
    guard !ids.isEmpty else { return }
    if isTransitioning {
      // Queue at most one pending step; extra presses collapse into it and
      // land without animation (V6).
      pendingSteps = delta
      return
    }
    if reduceMotion { jump(delta); return }
    if delta > 0 { pager.navigateForward(self) } else { pager.navigateBack(self) }
  }

  private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  /// Unanimated jump for coalesced presses and Reduce Motion (cross-fade
  /// equivalent: no slide; the new page is already loaded, so no blank frame).
  private func jump(_ delta: Int) {
    let next = ViewerPagerMath.clampedIndex(pager.selectedIndex + delta, count: ids.count)
    pager.selectedIndex = next
    didLand(at: next)
  }

  private func didLand(at index: Int) {
    guard ids.indices.contains(index) else { return }
    onSelect?(ids[index])
    let window = ViewerPagerMath.preloadWindow(center: index, count: ids.count)
    onPreload?(window.map { ids[$0] })
    // V5 memory bound: drop page controllers outside the ±2 window (plus the
    // selected page), so paging through 102k ids stays flat.
    let keep = Set(window.map { ids[$0] })
    pageCache = pageCache.filter { keep.contains($0.key) }
  }

  // MARK: NSPageControllerDelegate

  func pageController(
    _ pageController: NSPageController, identifierFor object: Any
  ) -> String {
    object as? String ?? ""
  }

  func pageController(
    _ pageController: NSPageController, viewControllerForIdentifier identifier: String
  ) -> NSViewController {
    if let cached = pageCache[identifier] { return cached }
    let vc = self.pageController?(identifier) ?? NSViewController()
    // TEST-PLAN V4 UI: every page exposes viewer.page.<id>.
    vc.view.setAccessibilityIdentifier(AXIDs.viewerPage(identifier))
    if let image = vc as? ImagePageController {
      image.onPage = { [weak self] in self?.step($0) }
      image.onMagnification = { [weak self] mag in
        self?.onPageMagnification?(identifier, mag)
      }
      image.onPinchClose = { [weak self] scale in self?.onPinchClose?(identifier, scale) }
      image.onPinchCloseEnd = { [weak self] scale in
        self?.onPinchCloseEnd?(identifier, scale)
      }
    }
    if let video = vc as? VideoPageController {
      video.onArrowKey = { [weak self] in self?.step($0) }
    }
    pageCache[identifier] = vc
    return vc
  }

  /// Toolbar zoom-slider drive (V8/V9): set the selected image page's
  /// magnification directly.
  func setSelectedPageMagnification(_ value: Double) {
    guard let id = currentID, let page = pageCache[id] as? ImagePageController else { return }
    page.setMagnificationValue(value)
  }

  func pageControllerWillStartLiveTransition(_ pageController: NSPageController) {
    isTransitioning = true
  }

  func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
    isTransitioning = false
    didLand(at: pageController.selectedIndex)
    if pendingSteps != 0 {
      let step = pendingSteps
      pendingSteps = 0
      jump(step)
    }
  }

  func pageController(
    _ pageController: NSPageController, didTransitionTo object: Any
  ) {
    didLand(at: pageController.selectedIndex)
  }
}

/// SwiftUI host for the pager. Selection is the asset id; the factory builds
/// the image/video page controllers.
struct MacViewerPager: NSViewControllerRepresentable {
  var ids: [String]
  var selectedID: String
  var onSelect: (String) -> Void
  var pageController: (String) -> NSViewController
  var onPreload: ([String]) -> Void = { _ in }
  var onHost: (ViewerPagerViewController) -> Void = { _ in }
  var onMagnification: (String, Double) -> Void = { _, _ in }
  var onPinchClose: (String, CGFloat) -> Void = { _, _ in }
  var onPinchCloseEnd: (String, CGFloat) -> Void = { _, _ in }

  func makeNSViewController(context: Context) -> ViewerPagerViewController {
    let host = ViewerPagerViewController(ids: ids, selectedID: selectedID)
    sync(host: host, context: context)
    context.coordinator.host = host
    onHost(host)
    return host
  }

  func updateNSViewController(_ host: ViewerPagerViewController, context: Context) {
    context.coordinator.onSelect = onSelect
    context.coordinator.factory = pageController
    context.coordinator.preload = onPreload
    context.coordinator.magnification = onMagnification
    context.coordinator.pinchClose = onPinchClose
    context.coordinator.pinchCloseEnd = onPinchCloseEnd
    sync(host: host, context: context)
    host.update(ids: ids, selectedID: selectedID)
  }

  private func sync(host: ViewerPagerViewController, context: Context) {
    host.onSelect = { context.coordinator.onSelect($0) }
    host.pageController = { context.coordinator.factory($0) }
    host.onPreload = { context.coordinator.preload($0) }
    host.onPageMagnification = { context.coordinator.magnification($0, $1) }
    host.onPinchClose = { context.coordinator.pinchClose($0, $1) }
    host.onPinchCloseEnd = { context.coordinator.pinchCloseEnd($0, $1) }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  @MainActor
  final class Coordinator: NSObject {
    weak var host: ViewerPagerViewController?
    var onSelect: (String) -> Void = { _ in }
    var factory: (String) -> NSViewController = { _ in NSViewController() }
    var preload: ([String]) -> Void = { _ in }
    var magnification: (String, Double) -> Void = { _, _ in }
    var pinchClose: (String, CGFloat) -> Void = { _, _ in }
    var pinchCloseEnd: (String, CGFloat) -> Void = { _, _ in }
    func step(_ delta: Int) { host?.step(delta) }
  }
}

// MARK: - open/close transitions (V7)

/// Snapshot-flight animator between the grid cell and the viewer fit rect
/// (V7): 0.3 s ease, hiding the source cell mid-flight. With no source
/// (standalone window, search) it cross-fades. `scrollToVisible` is always
/// called on the source before a close starts so the target cell exists.
enum ViewerTransitionAnimator {
  static let duration: TimeInterval = 0.3

  static func animateClose(
    snapshot: NSImage, from viewerRect: CGRect, source: ViewerTransitionSource?,
    assetId: String, onDone: @escaping @Sendable () -> Void
  ) {
    source?.scrollToVisible(assetId: assetId)
    guard let source, let target = source.frameInWindow(for: assetId) else {
      crossFade(snapshot: snapshot, onDone: onDone)
      return
    }
    fly(snapshot: snapshot, from: viewerRect, to: target) {
      source.setHidden(false, assetId: assetId)
      onDone()
    }
    source.setHidden(true, assetId: assetId)
  }

  static func animateOpen(
    snapshot: NSImage, from source: ViewerTransitionSource?, assetId: String,
    to viewerRect: CGRect, onDone: @escaping @Sendable () -> Void
  ) {
    guard let source, let origin = source.frameInWindow(for: assetId) else {
      crossFade(snapshot: snapshot, onDone: onDone)
      return
    }
    fly(snapshot: snapshot, from: origin, to: viewerRect, onDone: onDone)
  }

  private static func fly(
    snapshot: NSImage, from: CGRect, to: CGRect, onDone: @escaping () -> Void
  ) {
    let window = NSWindow(
      contentRect: from, styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.ignoresMouseEvents = true
    let imageView = NSImageView(frame: NSRect(origin: .zero, size: from.size))
    imageView.image = snapshot
    imageView.imageScaling = .scaleProportionallyUpOrDown
    window.contentView = imageView
    window.orderFront(nil)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      window.animator().setFrame(to, display: true)
    } completionHandler: {
      window.orderOut(nil)
      onDone()
    }
  }

  private static func crossFade(snapshot _: NSImage, onDone: @escaping @Sendable () -> Void) {
    // No source rect: the viewer already swaps pages without blank flashes
    // (tier hold), so the fade is a 0.3 s no-op gate for dismissal timing.
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { onDone() }
  }
}
