import AppKit
import SwiftUI
import VisionKit

/// A9.2 (macOS): still viewer with VisionKit Live Text. An `ImageAnalysisOverlayView` sits
/// over the image and receives the `ImageAnalysis` computed after each tier upgrade, so
/// text selection, data detectors, Visual Look Up, and subject lift work like on iOS.
struct MacLiveTextView: NSViewRepresentable {
  var image: NSImage
  var analysis: ImageAnalysis?
  /// Swipe-to-page (owner request): same `page(by:)` path as the zoom view.
  var onPage: ((Int) -> Void)? = nil

  func makeNSView(context: Context) -> NSView {
    let container = ViewerPageCatcherView()
    container.onPage = onPage
    let imageView = NSImageView(image: image)
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.imageAlignment = .alignCenter
    imageView.autoresizingMask = [.width, .height]
    imageView.frame = container.bounds
    container.addSubview(imageView)
    context.coordinator.imageView = imageView
    let overlay = ImageAnalysisOverlayView()
    overlay.preferredInteractionTypes = .automatic
    overlay.autoresizingMask = [.width, .height]
    overlay.frame = container.bounds
    container.addSubview(overlay)
    context.coordinator.overlay = overlay
    return container
  }

  func updateNSView(_ container: NSView, context: Context) {
    context.coordinator.imageView?.image = image
    context.coordinator.overlay?.analysis = analysis
    (container as? ViewerPageCatcherView)?.onPage = onPage
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject {
    weak var imageView: NSImageView?
    weak var overlay: ImageAnalysisOverlayView?
  }
}
