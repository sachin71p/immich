import Foundation

/// WP-V viewer pager model: pure logic shared by the `NSPageController` host
/// (`MacViewerPager.swift`) and the unit tests (`Tests/Viewer/`).
///
/// Dependency-free (Foundation only) so the logic-test bundle can compile it
/// without the app target. AppKit/SwiftUI integration lives in the sibling
/// `MacViewerPager.swift` / `MacViewerPages.swift` files.
enum ViewerPagerMath {
  /// Clamped paging: no wrap, so → then ← returns to the same photo (V6).
  static func clampedIndex(_ raw: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return min(max(0, raw), count - 1)
  }

  /// Neighbour preload window around the current page (V5/V6): ±2, clamped.
  static func preloadWindow(center: Int, count: Int, radius: Int = 2) -> ClosedRange<Int> {
    guard count > 0 else { return 0...0 }
    let c = clampedIndex(center, count: count)
    return max(0, c - radius)...min(count - 1, c + radius)
  }

  /// Rapid-press coalescing (V6): at most one pending animated step; when more
  /// than one press is pending the animation is skipped (returns false).
  static func shouldAnimateStep(pendingPresses: Int) -> Bool { pendingPresses <= 1 }

  /// Photos direction: swipe left (dx < 0) advances, swipe right goes back.
  static func pageDelta(dx: CGFloat) -> Int { dx < 0 ? 1 : -1 }

  /// Scroll-to-page gate (V5): paging from horizontal scroll requires the
  /// system "Swipe between pages" setting; arrows always page.
  static func pagesFromScroll(isSwipeTrackingEnabled: Bool) -> Bool {
    isSwipeTrackingEnabled
  }

  /// Rubber-band cap at the ends (V5): the offset never exceeds 1/3 of travel.
  static func rubberBandedOffset(travel: CGFloat) -> CGFloat { travel / 3 }
}

/// Smart-zoom math (V8): double-click toggles fit ↔ 2× anchored at the
/// pointer; Z toggles the same way; ⌘+/⌘− step ×1.5 clamped to 8×.
enum SmartZoomMath {
  static let fitMagnification: Double = 1
  static let smartMagnification: Double = 2
  static let maxMagnification: Double = 8
  static let stepFactor: Double = 1.5

  static func toggled(current: Double) -> Double {
    abs(current - fitMagnification) < 0.001 ? smartMagnification : fitMagnification
  }

  static func stepped(_ current: Double, times: Int) -> Double {
    min(maxMagnification, current * pow(stepFactor, Double(times)))
  }
}

/// Edge-hover chevron visibility (V11): chevrons appear within 0.15 s near an
/// edge and are hidden at the first/last index.
enum ChevronVisibility {
  enum Edge { case prev, next }

  static func isVisible(edge: Edge, index: Int, count: Int, hoverNearEdge: Bool) -> Bool {
    guard hoverNearEdge, count > 1 else { return false }
    switch edge {
    case .prev: return index > 0
    case .next: return index < count - 1
    }
  }
}

/// Pinch-to-close decision (V7): close when the end scale is below 0.8 or the
/// velocity is still heading inward; otherwise spring back. With no
/// `ViewerTransitionSource` the caller cross-fades instead of animating a cell.
enum PinchCloseDecision {
  static let closeScaleThreshold: CGFloat = 0.8

  static func shouldClose(endScale: CGFloat, velocityInward: Bool) -> Bool {
    endScale < closeScaleThreshold || velocityInward
  }
}

/// Viewer header formatter (SPEC-TOOLBAR-SETTINGS §2a, V9/V19).
///
/// Line 1: place name, falling back to the date. Line 2: "Month d, yyyy at
/// h:mm:ss a · N of M" with locale grouping separators; the counter is hidden
/// for single-item contexts.
enum ViewerHeaderFormatter {
  static func title(place: String?, date: Date, locale: Locale = .current) -> String {
    if let place, !place.isEmpty { return place }
    let f = DateFormatter()
    f.locale = locale
    f.dateStyle = .long
    f.timeStyle = .none
    return f.string(from: date)
  }

  static func subtitle(
    date: Date, timeZone: TimeZone? = nil, index: Int, total: Int,
    locale: Locale = .current
  ) -> String {
    let df = DateFormatter()
    df.locale = locale
    if let timeZone { df.timeZone = timeZone }
    df.dateFormat = DateFormatter.dateFormat(
      fromTemplate: "MMMMdYYYYhmmsa", options: 0, locale: locale)
    let datePart = df.string(from: date)
    guard total > 1 else { return datePart }
    let nf = NumberFormatter()
    nf.locale = locale
    nf.numberStyle = .decimal
    let position = nf.string(from: NSNumber(value: index + 1)) ?? "\(index + 1)"
    let count = nf.string(from: NSNumber(value: total)) ?? "\(total)"
    let separator = locale.identifier.hasPrefix("de") ? "von" : "of"
    return "\(datePart) · \(position) \(separator) \(count)"
  }
}

/// Viewer context-menu contract (V10, shared with WP-G grid context).
/// Titles are in exactly Photos' order; conditional rows are gated by scope.
enum ViewerContextMenuSpec {
  enum AssetKind { case photo, video, live }
  enum Library { case personal, shared }
  enum Scope { case library, album }
  enum Context { case viewer, grid }

  static func titles(
    kind: AssetKind, library: Library = .personal, scope: Scope = .library
  ) -> [String] {
    var items = ["Get Info", "Copy", "Share…"]
    if scope == .album { items.append("Make Album Cover") }
    items.append("Show in All Photos")
    if kind != .video { items += ["Rotate Left", "Rotate Right"] }
    items += ["Copy Edits", "Paste Edits", "Revert to Original"]
    items += ["Add to", "Add to Album", "Edit With", "Duplicate", "Hide", "Delete"]
    if scope == .album { items.append("Remove from Album") }
    if library == .shared { items.append("Move to Library") }
    return items
  }
}
