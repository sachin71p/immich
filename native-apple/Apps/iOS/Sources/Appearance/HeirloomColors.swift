import SwiftUI
import UIKit

// MARK: - WP-L semantic appearance tokens (phase 1)
//
// Light-appearance parity (PLAN L1–L3). Every color the viewer, library title,
// info sheet, and editor read must come from here in phase 2 — no literal
// `.black` / `.white` in those views afterwards.
//
// Two token kinds:
// - *Adaptive* tokens follow the system appearance (the L1 fix: the viewer
//   renders white chrome in light, black in dark, matching pair L02-viewer).
// - *Fixed* tokens deliberately ignore appearance (the L2 scrim stays dark in
//   both appearances like Photos; the L3 editor veil stays dark pending the
//   re-verify — Photos' editor is dark in both, which may be correct).
//
// Phase 2 adopts these in: Viewer.swift, Viewer/ViewerChrome.swift,
// Viewer/ViewerInfoPanel.swift, Library/LibraryView.swift (+ header),
// EditView.swift (fixed tokens only). Grid/chrome/menu files owned by
// WP-G / WP-C / WP-M are NOT in scope until those packages merge.

enum HeirloomAppearance {
  // MARK: adaptive

  /// Viewer page + pager backdrop. Replaces `Color.black` in Viewer.swift:93,207.
  /// Light: system background (white). Dark: black.
  static let viewerBackdrop = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark ? .black : .systemBackground
    })

  /// Base color tinted into the viewer glass pills. Replaces the
  /// `.black.opacity(0.35)` tint in ViewerChrome.swift (8 sites).
  /// Light: white-based pills. Dark: black-based pills.
  static let chromeTintBase = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark ? .black : .white
    })

  /// Primary chrome glyph text. Replaces `.white.opacity(0.8)` in
  /// ViewerChrome.swift:75 and `.white.opacity(0.85)` in ViewerInfoPanel.swift.
  static let chromePrimaryText = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.85)
        : UIColor.label.withAlphaComponent(0.9)
    })

  /// Secondary chrome text. Replaces `.white.opacity(0.7)` in
  /// ViewerInfoPanel.swift (7 sites) and ViewerChrome.swift.
  static let chromeSecondaryText = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.7)
        : UIColor.secondaryLabel
    })

  /// Faint chrome text. Replaces `.white.opacity(0.5)` in
  /// ViewerInfoPanel.swift:121,174.
  static let chromeTertiaryText = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.5)
        : UIColor.tertiaryLabel
    })

  /// Subtle capsule fill behind chrome glyphs. Replaces
  /// `.white.opacity(0.15)` / `.white.opacity(0.2)` in ViewerInfoPanel.swift.
  static let chromeSubtleFill = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.18)
        : UIColor.systemFill
    })

  /// Info-sheet card background. Replaces `Color(white: 0.08)` and
  /// `Color(white: 0.14)` in ViewerInfoPanel.swift:186,210.
  static let infoCardBackground = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(white: 0.14, alpha: 1)
        : UIColor.secondarySystemGroupedBackground
    })

  /// Viewer loading indicator. Replaces `.tint(.white)` in Viewer.swift.
  static let viewerLoadingTint = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark ? .white : .label
    })

  /// UIKit mirror of `viewerBackdrop` for the `ViewerPageController` view and
  /// page hosts (`ViewerPager.swift`), which are UIKit and cannot read a
  /// SwiftUI `Color`. Same contract: black in dark, system background in light.
  static let viewerBackdropUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? .black : .systemBackground
  }

  // MARK: fixed (identical in both appearances)

  /// Library title text. INTENDED always-white — Photos keeps white-on-scrim
  /// in both appearances (pair L01-library) — but currently UNUSED: the
  /// title is the native nav-bar title, and `.toolbarColorScheme(.dark)` (the
  /// only SwiftUI route to whiten it) collapses the large title + toolbar
  /// items out of the bar on this SDK (Xcode 27 / iOS 27 simulator, verified
  /// by screenshot: bar shows subtitle only). Kept so the intent survives for
  /// a WP-X revisit on a newer SDK; the native dark title over the light
  /// scrim below meets the contrast target meanwhile.
  static let libraryTitleText = Color.white

  /// Blur scrim behind the library title. ADAPTIVE (revised from fixed-dark
  /// in phase 2 for the reason above): white-based blur in light behind the
  /// native dark title, black 0.45 in dark behind the native white title.
  /// Backs the `library-title-scrim` test surface and drives the L2
  /// ≥ 4.5:1 contrast target in both appearances.
  static let libraryTitleScrim = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor.black.withAlphaComponent(0.45)
        : UIColor.white.withAlphaComponent(0.72)
    })

  /// Editor modal veils. Fixed dark pending the L3 re-verify (Photos' editor
  /// is dark in both appearances, so this may already be correct).
  /// Replaces `Color.black.opacity(0.5)` (crop mask, EditView.swift:466) and
  /// `Color.black.opacity(0.4)` (saving veil, EditView.swift:844).
  static let editorVeil = Color.black.opacity(0.45)
}
