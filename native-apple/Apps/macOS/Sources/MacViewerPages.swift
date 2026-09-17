import AppKit
import AVKit
import CoreModel
import Media
import SwiftUI
import VisionKit

// MARK: - paging player view (V4)

// swiftlint:disable:next todo
/// `AVPlayerView` that never traps paging gestures (V4): dominant-x scroll is
/// forwarded up the responder chain so the `NSPageController` strip sees the
/// same 1:1 swipe as image pages, and ←/→ arrive at the viewer level even
/// while the player view holds focus.
final class PagingAVPlayerView: AVPlayerView {
  var onArrowKey: ((Int) -> Void)?

  override func scrollWheel(with event: NSEvent) {
    superview?.scrollWheel(with: event)
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 123: onArrowKey?(-1)
    case 124: onArrowKey?(1)
    default: super.keyDown(with: event)
    }
  }
}

// MARK: - image page (V1, V8)

// swiftlint:disable:next todo
/// Zoomable image page (V1 full, V8): an `NSScrollView` (`allowsMagnification`,
/// min = fit, max 8×) with a centred document view. The Live Text overlay is a
/// subview of the document view so it scales with the image (PLAN §2.2) —
///
/// there is no separate Live Text view path. Double-click smart-zooms fit ↔ 2×
/// at the pointer; a pinch continuing inward at fit starts an interactive
/// close (V7) through `onPinchClose`.
final class ImagePageController: NSViewController {
  var onMagnification: ((Double) -> Void)?
  var onPage: ((Int) -> Void)?
  var onPinchClose: ((CGFloat) -> Void)?
  var onPinchCloseEnd: ((CGFloat) -> Void)?

  private let assetID: String
  private let thumbhash: String?
  private let store: ViewerPageStore

  private let scrollView = ZoomPageScrollView()
  private let imageView = NSImageView()
  private let overlay = ImageAnalysisOverlayView()

  /// Lazily-loaded analysis (V1): runs only after the page has settled.
  private var analysisTask: Task<Void, Never>?
  private var loadTask: Task<Void, Never>?
  private var loadedFullsize = false

  init(assetID: String, thumbhash: String?, store: ViewerPageStore) {
    self.assetID = assetID
    self.thumbhash = thumbhash
    self.store = store
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func loadView() {
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 1
    scrollView.maxMagnification = CGFloat(SmartZoomMath.maxMagnification)
    scrollView.documentView = imageView
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.imageAlignment = .alignCenter
    if let thumb = store.cachedThumbnail(id: assetID) { imageView.image = thumb }
    imageView.addSubview(overlay)
    overlay.preferredInteractionTypes = .automatic
    overlay.frame = imageView.bounds
    overlay.autoresizingMask = [.width, .height]
    scrollView.onPage = onPage
    scrollView.magnificationDidChange = { [weak self] in
      guard let self else { return }
      onMagnification?(Double(scrollView.magnification))
      self.upgradeTierIfNeeded()
    }
    scrollView.onPinchClose = { [weak self] scale in self?.onPinchClose?(scale) }
    scrollView.onPinchCloseEnd = { [weak self] scale in self?.onPinchCloseEnd?(scale) }
    let click = NSClickGestureRecognizer(target: self, action: #selector(smartZoom(_:)))
    click.numberOfClicksRequired = 2
    scrollView.addGestureRecognizer(click)
    view = scrollView
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    loadTask?.cancel()
    loadTask = Task { [weak self] in await self?.load() }
    scheduleLazyAnalysis()
  }

  override func viewDidDisappear() {
    super.viewDidDisappear()
    loadTask?.cancel()
    analysisTask?.cancel()
  }

  /// Tiered loading (preview → fullsize past 1.5×): every step replaces the
  /// image and nothing ever assigns nil, so the old tier stays visible until
  /// the new one arrives — no blank flash between pages or tiers.
  private func load() async {
    let id = assetID
    do {
      for try await step in await store.previewStream(id: id, thumbhash: thumbhash) {
        try Task.checkCancellation()
        switch step.content {
        case .placeholder(let next): setImageIfNew(next)
        case .tier(_, let next, _): setImageIfNew(next)
        }
      }
      upgradeTierIfNeeded()
    } catch is CancellationError {
    } catch {
      HeirloomLog.media.error(
        "image page load failed asset=\(id, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
    }
  }

  private func setImageIfNew(_ next: NSImage) {
    if imageView.image !== next { imageView.image = next }
  }

  private func upgradeTierIfNeeded() {
    guard !loadedFullsize, Double(scrollView.magnification) > 1.5 else { return }
    loadedFullsize = true
    Task { [weak self] in
      guard let self else { return }
      do {
        for try await step in await store.fullsizeStream(id: assetID, thumbhash: thumbhash) {
          try Task.checkCancellation()
          if case .tier(_, let next, _) = step.content { setImageIfNew(next) }
        }
      } catch {}
    }
  }

  func setImage(_ image: NSImage, analysis: ImageAnalysis? = nil) {
    imageView.image = image
    overlay.analysis = analysis
    analysisTask?.cancel()
    scheduleLazyAnalysis()
  }

  /// Toolbar zoom-slider binding (V8/V9, both directions).
  func setMagnificationValue(_ value: Double) {
    let clamped = min(max(1, value), SmartZoomMath.maxMagnification)
    scrollView.setMagnification(CGFloat(clamped), centeredAt: scrollView.centerPoint)
  }

  private func scheduleLazyAnalysis() {
    guard overlay.analysis == nil else { return }
    analysisTask?.cancel()
    analysisTask = Task { [weak self] in
      // Analysis runs lazily, only after the page has settled for 0.5 s (V1).
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled, let self, let image = imageView.image else { return }
      let result = await store.analyze(image)
      guard !Task.isCancelled else { return }
      overlay.analysis = result
    }
  }

  /// Smart zoom (V8): toggle fit ↔ 2× anchored at the pointer.
  @objc private func smartZoom(_ gesture: NSClickGestureRecognizer) {
    let point = gesture.location(in: scrollView.contentView)
    let target = SmartZoomMath.toggled(current: Double(scrollView.magnification))
    scrollView.setMagnification(CGFloat(target), centeredAt: point)
  }
}

/// Scroll view for image pages: pans while zoomed (Photos behavior) and lets
/// horizontal scroll bubble to the pager strip at 1.0× for 1:1 tracking (V5).
/// A magnify event continuing inward at fit starts an interactive close (V7).
/// Clip view that keeps the image centred when it is smaller than the
/// viewport (V1 full).
final class CenteringClipView: NSClipView {
  override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
    var rect = super.constrainBoundsRect(proposed)
    guard let doc = documentView else { return rect }
    if doc.frame.width < rect.width {
      rect.origin.x = (doc.frame.width - rect.width) / 2
    }
    if doc.frame.height < rect.height {
      rect.origin.y = (doc.frame.height - rect.height) / 2
    }
    return rect
  }
}

final class ZoomPageScrollView: NSScrollView {
  var onPage: ((Int) -> Void)?
  var magnificationDidChange: (() -> Void)?
  var onPinchClose: ((CGFloat) -> Void)?
  var onPinchCloseEnd: ((CGFloat) -> Void)?

  private var pinchCloseArmed = false
  private var pinchScale: CGFloat = 1

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    contentView = CenteringClipView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    contentView = CenteringClipView()
  }

  override func scrollWheel(with event: NSEvent) {
    if magnification > 1.001 {
      // Zoomed: pan until the edge, then page (PLAN §2.1). The edge check is
      // approximate: at either content bound a dominant-x scroll pages.
      if isAtHorizontalEdge(for: event) {
        let dir = event.scrollingDeltaX < 0 ? 1 : -1
        onPage?(dir)
        return
      }
      super.scrollWheel(with: event)
      return
    }
    // At fit the strip owns the gesture: forward untouched for 1:1 tracking.
    superview?.scrollWheel(with: event)
  }

  private func isAtHorizontalEdge(for event: NSEvent) -> Bool {
    guard let doc = documentView else { return true }
    let visible = contentView.bounds
    if event.scrollingDeltaX < 0 { return visible.maxX >= doc.bounds.maxX - 1 }
    if event.scrollingDeltaX > 0 { return visible.minX <= doc.bounds.minX + 1 }
    return false
  }

  override func magnify(with event: NSEvent) {
    // Pinch continuing inward at fit (magnification < 0) arms the interactive
    // close; the viewer scales a snapshot toward the source cell (V7).
    if magnification <= 1.001, event.magnification < 0 {
      pinchCloseArmed = true
      pinchScale *= max(0.01, 1 + event.magnification)
      onPinchClose?(pinchScale)
      return
    }
    pinchCloseArmed = false
    super.magnify(with: event)
    magnificationDidChange?()
  }

  override func beginGesture(with event: NSEvent) {
    pinchScale = 1
    super.beginGesture(with: event)
  }

  override func endGesture(with event: NSEvent) {
    // Gesture end (V7): close if the accumulated scale < 0.8, else spring back.
    if pinchCloseArmed {
      pinchCloseArmed = false
      onPinchCloseEnd?(pinchScale)
      pinchScale = 1
    }
    super.endGesture(with: event)
  }

  override func smartMagnify(with event: NSEvent) {
    let point = convert(event.locationInWindow, to: contentView)
    let target = SmartZoomMath.toggled(current: Double(magnification))
    setMagnification(CGFloat(target), centeredAt: point)
    magnificationDidChange?()
  }
}

private extension NSView {
  var centerPoint: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }
}

// MARK: - video page (V3)

// swiftlint:disable:next todo
/// Video page (V3): builds its player through `VideoPlaybackLoader` (the same
/// loader path as production, auth header included) and logs
/// `AVPlayerItem.status` + error through `HeirloomLog` until `readyToPlay`.
final class VideoPageController: NSViewController {
  var onArrowKey: ((Int) -> Void)?
  var onReady: ((Bool) -> Void)?

  private let playerView = PagingAVPlayerView()
  private let spinner = NSProgressIndicator()
  private var statusObservation: NSKeyValueObservation?
  private var loaderTask: Task<Void, Never>?

  private let assetID: String
  private let loader: VideoPlaybackLoader

  init(assetID: String, loader: VideoPlaybackLoader) {
    self.assetID = assetID
    self.loader = loader
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func loadView() {
    playerView.controlsStyle = .inline
    playerView.onArrowKey = { [weak self] in self?.onArrowKey?($0) }
    view = playerView
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    loaderTask?.cancel()
    loaderTask = Task { [weak self] in await self?.start() }
  }

  override func viewDidDisappear() {
    super.viewDidDisappear()
    loaderTask?.cancel()
    playerView.player?.pause()
    playerView.player = nil
    statusObservation = nil
  }

  private func start() async {
    guard !Task.isCancelled else { return }
    let outcome = await loader.load(assetID: assetID)
    guard !Task.isCancelled else { return }
    switch outcome {
    case .ready(let player, let item):
      playerView.player = player
      observe(item: item)
      player.play()
    case .failed:
      onReady?(false)
    }
  }

  private func observe(item: AVPlayerItem) {
    if item.status == .readyToPlay { onReady?(true) }
    statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      if item.status == .readyToPlay {
        self?.onReady?(true)
      } else if item.status == .failed {
        HeirloomLog.media.error(
          "video page failed asset=\(self?.assetID ?? "?", privacy: .public) error=\(String(describing: item.error), privacy: .public)")
        self?.onReady?(false)
      }
    }
  }
}

// MARK: - live photo page

/// Live Photo page: resolves the motion id asynchronously, then embeds the
/// SwiftUI `MacLivePhotoPageView` (LIVE badge + hover hint + press-to-play).
final class LivePhotoPageController: NSViewController {
  var onArrowKey: ((Int) -> Void)?

  private let assetID: String
  private let store: ViewerPageStore
  private var loadTask: Task<Void, Never>?

  init(assetID: String, store: ViewerPageStore) {
    self.assetID = assetID
    self.store = store
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func loadView() {
    let spinner = NSProgressIndicator()
    spinner.style = .spinning
    spinner.startAnimation(nil)
    view = NSView()
    spinner.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(spinner)
    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    loadTask?.cancel()
    loadTask = Task { [weak self] in await self?.load() }
  }

  override func viewDidDisappear() {
    super.viewDidDisappear()
    loadTask?.cancel()
  }

  private func load() async {
    guard let asset = await store.fetchAsset(id: assetID),
      let motionId = asset.livePhotoVideoId
    else { return }
    guard !Task.isCancelled else { return }
    let child = NSHostingController(
      rootView: MacLivePhotoPageView(asset: asset, motionAssetId: motionId, state: store.state))
    addChild(child)
    child.view.frame = view.bounds
    child.view.autoresizingMask = [.width, .height]
    view.addSubview(child.view)
  }
}
