import AppKit
import SwiftUI

/// macOS shell entry (A4): connect screen until signed in, then the Photos-for-Mac style
/// library window. `--fixture-seed` launches the seeded in-memory world for UI smoke tests.
@main
struct HeirloomMacOSApp: App {
  @State private var state: MacAppState?

  var body: some Scene {
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
    let savedURL = UserDefaults.standard.string(forKey: "Heirloom.serverURL")
      .flatMap { URL(string: $0) }
    // A placeholder with no host fails `ImmichConnection`'s server-URL validation, so
    // `MacAppState.standard` throws and `state` never leaves nil on a fresh install
    // (matches the dummy host `seeded()` uses below for the same reason).
    let defaultURL = savedURL ?? URL(string: "https://unconfigured.invalid")!
    return try? MacAppState.standard(serverURL: defaultURL)
  }
}
