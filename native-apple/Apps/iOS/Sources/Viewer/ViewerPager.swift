import CoreModel
import LocalStore
import Media
import SwiftUI
import UIKit

// MARK: - UIKit pager (WP3 step 2)

/// Horizontal paging viewer driven by an id list: a `UIPageViewController` whose pages
/// are hosted `ViewerPage` views (still zoom, Live Photo, video hosts all stay SwiftUI).
/// Only the current page and its neighbours exist as view controllers, so opening is
/// O(1) in views regardless of library size; neighbours prefetch at the preview tier.
///
/// Dismiss is a UIKit vertical pan on the page controller's view (never a SwiftUI
/// `.gesture(DragGesture())` on the NavigationStack — that recognizer won the gesture
/// arena over the system-hosted bottom bar and made the "…" Menu non-hittable, V1).
/// A single tap on a page toggles the SwiftUI chrome around the pager.
struct ViewerPager: UIViewControllerRepresentable {
  var ids: [String]
  var session: AppSession
  /// SwiftUI-owned page index (two-way: pager reports swipes, filmstrip writes jumps).
  @Binding var currentIndex: Int
  /// Shared Live Photo play trigger (a reference so already-built pages see each tap).
  var livePlay: LivePlayRequest
  /// False while the info panel is open, so closing it can't dismiss the viewer.
  var dismissEnabled: Bool = true
  var onSingleTap: () -> Void
  var onDismiss: () -> Void
  var onSwipeUp: () -> Void = {}

  func makeUIViewController(context: Context) -> ViewerPageController {
    // The Binding struct itself is captured (reference semantics): page-controller
    // callbacks arrive on the main thread and write straight through, which
    // re-invokes updateUIViewController as a no-op (indices already equal).
    let indexBinding = _currentIndex
    let controller = ViewerPageController(
      ids: ids,
      startIndex: indexBinding.wrappedValue,
      session: session,
      livePlay: livePlay,
      onIndexChange: { index in indexBinding.wrappedValue = index },
      onSingleTap: onSingleTap,
      onDismiss: onDismiss,
      onSwipeUp: onSwipeUp)
    controller.dismissEnabled = dismissEnabled
    context.coordinator.controller = controller
    return controller
  }

  func updateUIViewController(_ controller: ViewerPageController, context: Context) {
    controller.ids = ids
    controller.dismissEnabled = dismissEnabled
    if controller.currentIndex != currentIndex {
      controller.jump(to: currentIndex, animated: true)
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject {
    weak var controller: ViewerPageController?
  }
}

/// Swipe-down-to-dismiss distance, matching the old SwiftUI drag threshold.
private enum ViewerDismiss {
  static let distance: CGFloat = 140
  static let velocity: CGFloat = 900
}

/// Swipe-up-to-info thresholds (mirrors the dismiss feel, upward).
private enum ViewerSwipeUp {
  static let distance: CGFloat = 120
  static let velocity: CGFloat = 900
}

final class ViewerPageController: UIPageViewController {
  var ids: [String]
  var dismissEnabled = true
  private(set) var currentIndex: Int
  private let session: AppSession
  private let livePlay: LivePlayRequest
  private let onIndexChange: (Int) -> Void
  private let onSingleTap: () -> Void
  private let onDismiss: () -> Void
  private let onSwipeUp: () -> Void
  private var prefetch: Task<Void, Never>?

  init(
    ids: [String], startIndex: Int, session: AppSession,
    livePlay: LivePlayRequest,
    onIndexChange: @escaping (Int) -> Void,
    onSingleTap: @escaping () -> Void,
    onDismiss: @escaping () -> Void,
    onSwipeUp: @escaping () -> Void
  ) {
    self.ids = ids
    self.currentIndex = min(max(startIndex, 0), max(ids.count - 1, 0))
    self.session = session
    self.livePlay = livePlay
    self.onIndexChange = onIndexChange
    self.onSingleTap = onSingleTap
    self.onDismiss = onDismiss
    self.onSwipeUp = onSwipeUp
    super.init(
      transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    dataSource = self
    delegate = self
    // WP-L L1: same contract as HeirloomAppearance.viewerBackdrop — black in
    // dark, system background in light (UIKit cannot read the SwiftUI token).
    view.backgroundColor = HeirloomAppearance.viewerBackdropUIColor
    view.accessibilityIdentifier = "viewer-pager"
    if let first = page(at: currentIndex) {
      setViewControllers([first], direction: .forward, animated: false)
    }
    let verticalPan = UIPanGestureRecognizer(target: self, action: #selector(handleVertical(_:)))
    verticalPan.delegate = self
    view.addGestureRecognizer(verticalPan)
    prefetchAround(currentIndex)
  }

  /// Filmstrip jump (or any programmatic navigation): no-op when already there, so the
  /// SwiftUI two-way index binding can't loop.
  func jump(to index: Int, animated: Bool) {
    guard index != currentIndex, ids.indices.contains(index),
      let target = page(at: index)
    else { return }
    let direction: NavigationDirection = index > currentIndex ? .forward : .reverse
    currentIndex = index
    setViewControllers([target], direction: direction, animated: animated) { [weak self] done in
      guard let self, done else { return }
      self.onIndexChange(index)
      self.prefetchAround(index)
    }
  }

  private func page(at index: Int) -> ViewerPageHost? {
    guard ids.indices.contains(index) else { return nil }
    let page = ViewerPage(assetId: ids[index], onSingleTap: onSingleTap, livePlay: livePlay)
    let host = ViewerPageHost(pageIndex: index, rootView: AnyView(page.environmentObject(session)))
    host.view.backgroundColor = HeirloomAppearance.viewerBackdropUIColor
    return host
  }

  /// Preview-tier prefetch for ±2 pages (the current page loads itself at full tiers
  /// through `ViewerPage`; neighbours only warm the pipeline cache).
  private func prefetchAround(_ index: Int) {
    prefetch?.cancel()
    guard let store = session.store, let pipeline = session.pipeline else { return }
    let window = (-2...2).map { index + $0 }.filter { $0 != index && ids.indices.contains($0) }
    prefetch = Task {
      for neighbour in window {
        guard !Task.isCancelled else { return }
        let id = ids[neighbour]
        guard let asset = try? await store.asset(id: id) else { continue }
        _ = try? await pipeline.load(asset: asset, tier: .preview)
      }
    }
  }

  /// Vertical pan: downward drags dismiss (with finger-follow), upward drags reveal
  /// the info panel. Mostly-vertical only, so paging never competes.
  @objc private func handleVertical(_ pan: UIPanGestureRecognizer) {
    switch pan.state {
    case .changed:
      let translation = pan.translation(in: view)
      view.transform = CGAffineTransform(translationX: 0, y: max(0, translation.y))
    case .ended, .cancelled:
      let translation = pan.translation(in: view)
      let velocity = pan.velocity(in: view)
      if translation.y > ViewerDismiss.distance || velocity.y > ViewerDismiss.velocity {
        onDismiss()
      } else if translation.y < -ViewerSwipeUp.distance
        || velocity.y < -ViewerSwipeUp.velocity
      {
        UIView.animate(withDuration: 0.25) { self.view.transform = .identity }
        onSwipeUp()
      } else {
        UIView.animate(withDuration: 0.25) { self.view.transform = .identity }
      }
    default:
      break
    }
  }
}

extension ViewerPageController: UIPageViewControllerDataSource {
  func pageViewController(
    _ pageViewController: UIPageViewController,
    viewControllerBefore viewController: UIViewController
  ) -> UIViewController? {
    guard let host = viewController as? ViewerPageHost else { return nil }
    return page(at: host.pageIndex - 1)
  }

  func pageViewController(
    _ pageViewController: UIPageViewController,
    viewControllerAfter viewController: UIViewController
  ) -> UIViewController? {
    guard let host = viewController as? ViewerPageHost else { return nil }
    return page(at: host.pageIndex + 1)
  }
}

extension ViewerPageController: UIPageViewControllerDelegate {
  func pageViewController(
    _ pageViewController: UIPageViewController,
    didFinishAnimating finished: Bool,
    previousViewControllers: [UIViewController],
    transitionCompleted completed: Bool
  ) {
    guard finished, completed,
      let host = pageViewController.viewControllers?.first as? ViewerPageHost
    else { return }
    currentIndex = host.pageIndex
    onIndexChange(host.pageIndex)
    prefetchAround(host.pageIndex)
  }
}

extension ViewerPageController: UIGestureRecognizerDelegate {
  /// Only downward, mostly-vertical drags dismiss; horizontal paging (and the per-page
  /// zoom scroll views) keep their touches. Simultaneous recognition with the page
  /// controller's internal scroll pan is harmless — the content fits, so it never
  /// consumes a vertical drag.
  func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
    guard let pan = gesture as? UIPanGestureRecognizer, let view else { return false }
    let velocity = pan.velocity(in: view)
    guard abs(velocity.y) > 2 * abs(velocity.x) else { return false }
    // Upward drags always reveal info; downward drags dismiss unless the info
    // panel is open (its own close drag owns those).
    return velocity.y < 0 || dismissEnabled
  }

  func gestureRecognizer(
    _ gesture: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool {
    true
  }
}

/// `UIHostingController` carrying its page index for the data source.
final class ViewerPageHost: UIHostingController<AnyView> {
  let pageIndex: Int

  init(pageIndex: Int, rootView: AnyView) {
    self.pageIndex = pageIndex
    super.init(rootView: rootView)
  }

  required init?(coder aDecoder: NSCoder) {
    pageIndex = 0
    super.init(coder: aDecoder)
  }
}
