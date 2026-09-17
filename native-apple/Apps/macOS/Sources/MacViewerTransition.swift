import AppKit

/// Viewer ↔ grid transition contract (PLAN §2.3, WP-V step 5, joint with WP-G).
///
/// The grid implements this; the viewer animates a snapshot layer between the
/// cell rect and the fit rect (0.3 s spring). Pinch-close is interactive: the
/// layer follows the gesture's scale.
protocol ViewerTransitionSource: AnyObject {
  /// Cell frame in window coordinates for the open/close snapshot animation.
  func frameInWindow(for assetId: String) -> CGRect?
  /// Cell image for the snapshot layer (nil → cross-fade fallback).
  func image(for assetId: String) -> NSImage?
  /// Hide the source cell while the snapshot layer stands in for it.
  func setHidden(_ hidden: Bool, assetId: String)
  /// Ensure the target cell exists before a close starts.
  func scrollToVisible(assetId: String)
}

/// No-op default so standalone windows, search results and deep links (no grid
/// source) cross-fade instead of animating from a cell rect.
final class NullTransitionSource: ViewerTransitionSource {
  func frameInWindow(for assetId: String) -> CGRect? { nil }
  func image(for assetId: String) -> NSImage? { nil }
  func setHidden(_ hidden: Bool, assetId: String) {}
  func scrollToVisible(assetId: String) {}
}
