import SwiftUI

/// macOS shell entry (A4): connect screen until signed in, then the Photos-for-Mac style
/// library window. `--fixture-seed` launches the seeded in-memory world for UI smoke tests.
@main
struct PhotosForkMacOSApp: App {
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
            .task {
              state = Self.launchState()
              if CommandLine.arguments.contains("--fixture-seed") {
                try? await state?.seedForSmoke()
              } else {
                await state?.adoptKeychainSession()
              }
            }
        }
      }
    }
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
