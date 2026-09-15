import AppKit
import SwiftUI

/// `WindowGroup(for:)` scenes don't auto-open a window on a state-restoration-free launch
/// (fresh install, or `-ApplePersistenceIgnoreState YES` under XCTest); open the library
/// window explicitly once AppKit finishes launching.
private final class AppDelegate: NSObject, NSApplicationDelegate {
  var onLaunch: (() -> Void)?
  func applicationDidFinishLaunching(_ notification: Notification) {
    onLaunch?()
  }
}

/// macOS shell entry (A4): connect screen until signed in, then the Photos-for-Mac style
/// library window. `--fixture-seed` launches the seeded in-memory world for UI smoke tests.
@main
struct PhotosForkMacOSApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow
  @State private var state: MacAppState?

  var body: some Scene {
    let _ = appDelegate.onLaunch = { openWindow(value: MacWindow.library) }
    WindowGroup(id: "main", for: MacWindow.self) { $value in
      Group {
        if let state {
          if state.isConnected {
            MacMainView(state: state, window: value ?? .library)
          } else {
            MacConnectView(state: state)
          }
        } else {
          ProgressView()
        }
      }
      // Attached to the stable `Group`, not `ProgressView()`: once `state` becomes non-nil
      // this branch swaps to MacMainView/MacConnectView, which would tear down and cancel
      // a `.task` scoped to `ProgressView()` mid-await (CancellationError from `seedForSmoke`).
      .task {
        state = Self.launchState()
        if CommandLine.arguments.contains("--fixture-seed") {
          try? await state?.seedForSmoke()
        } else {
          await state?.adoptKeychainSession()
        }
      }
    }
    .defaultLaunchBehavior(.presented)
    // Without an explicit default size, the library window can open narrow enough that
    // AppKit collapses toolbar items (e.g. the zoom slider) into the "more items" overflow.
    .defaultSize(width: 1400, height: 900)
    .commands {
      MacCommands()
    }

    Settings {
      if let state {
        MacSettingsView(state: state)
      }
    }
  }

  private static func launchState() -> MacAppState? {
    if CommandLine.arguments.contains("--fixture-seed") {
      return try? MacAppState.seeded()
    }
    let savedURL = UserDefaults.standard.string(forKey: "PhotosFork.serverURL")
      .flatMap { URL(string: $0) }
    let defaultURL = savedURL ?? URL(string: "https://")!
    return try? MacAppState.standard(serverURL: defaultURL)
  }
}
