import AppKit
import SwiftUI

/// XCUITest launches the app from a background test-runner process.  On some macOS
/// versions the initial SwiftUI window is created minimized instead of becoming key,
/// even though the application process has started.  Make the test-only launch mode
/// perform the same unminimize + foreground sequence as a Dock click.
@MainActor
private enum MacUITestWindowPresenter {
  static var isEnabled: Bool {
    HeirloomLaunchFlag.isPresent("-ui-testing", legacy: "--ui-testing")
  }

  static func presentInitialWindow() {
    guard isEnabled else { return }

    // The SwiftUI scene creates its NSWindow just after its content appears.  Deferring
    // one turn ensures it is available before we ask AppKit to bring it forward.
    DispatchQueue.main.async {
      let windows = NSApp.windows
      guard !windows.isEmpty else { return }

      NSApp.activate(ignoringOtherApps: true)
      for window in windows {
        if window.isMiniaturized {
          window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
      }
    }
  }
}

/// WP4 quit guard (Step 2): sheets hold no unsaved data, so ⌘Q / AppleScript quit is
/// immediate — except while a move or upload is in flight, when the user confirms.
/// `pendingUploads` is a best-known cache (enqueue sites refresh it); the delegate
/// rechecks the live queue before prompting, so a stale count costs one query, never
/// a spurious prompt.
@MainActor
final class HeirloomQuitGuard {
  static let shared = HeirloomQuitGuard()
  var isMoveInProgress = false
  var pendingUploads = 0
}

/// WP4 Step 2 "Quit while a sheet is open": sheets hold no unsaved data, so every
/// quit path returns `.terminateNow` — except while a move or upload is in flight,
/// when an NSAlert confirms ("Quit anyway? N uploads in progress").
@MainActor
final class HeirloomAppDelegate: NSObject, NSApplicationDelegate {
  /// Set once per window launch (same object identity survives login/logout, which
  /// only mutate `userId`; last window wins — only used for the pending count).
  var state: MacAppState?

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let state else { return .terminateNow }
    if HeirloomQuitGuard.shared.isMoveInProgress, HeirloomQuitGuard.shared.pendingUploads <= 0 {
      return Self.confirmMove() ? .terminateNow : .terminateCancel
    }
    if HeirloomQuitGuard.shared.pendingUploads <= 0 { return .terminateNow }
    // Possible uploads: confirm against the live queue, then reply exactly once.
    Task { @MainActor in
      let live = (try? await state.store.pendingUploadCount())
        ?? HeirloomQuitGuard.shared.pendingUploads
      if live > 0 || HeirloomQuitGuard.shared.isMoveInProgress {
        sender.reply(toApplicationShouldTerminate: Self.confirmUploads(live))
      } else {
        sender.reply(toApplicationShouldTerminate: true)
      }
    }
    return .terminateLater
  }

  private static func confirmUploads(_ count: Int) -> Bool {
    let alert = NSAlert()
    alert.messageText = "Quit anyway? \(count) upload\(count == 1 ? "" : "s") in progress."
    alert.informativeText = "Quitting now may interrupt the current upload."
    alert.addButton(withTitle: "Quit Anyway")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private static func confirmMove() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Quit anyway? A move is in progress."
    alert.informativeText = "Quitting now may interrupt the current move."
    alert.addButton(withTitle: "Quit Anyway")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}

/// macOS shell entry (A4): connect screen until signed in, then the Photos-for-Mac style
/// library window. `--fixture-seed` launches the seeded in-memory world for UI smoke tests.
@main
struct HeirloomMacOSApp: App {
  @NSApplicationDelegateAdaptor(HeirloomAppDelegate.self) private var delegate
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
      .onAppear {
        MacUITestWindowPresenter.presentInitialWindow()
      }
      .task {
        state = Self.launchState()
        // The delegate only needs the store for the quit-time pending-upload recheck.
        delegate.state = state
        if HeirloomLaunchFlag.isPresent("-fixture-seed", legacy: "--fixture-seed") {
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
    if HeirloomLaunchFlag.isPresent("-fixture-seed", legacy: "--fixture-seed") {
      return try? MacAppState.seeded()
    }
    // Must read the same domain `completeLogin` writes to (SharedContainer.sharedDefaults) —
    // reading UserDefaults.standard here silently never sees a real login's saved server.
    let savedURL = SharedContainer.sharedDefaults.string(forKey: SharedContainer.serverURLKey)
      .flatMap { URL(string: $0) }
    // A placeholder with no host fails `ImmichConnection`'s server-URL validation, so
    // `MacAppState.standard` throws and `state` never leaves nil on a fresh install
    // (matches the dummy host `seeded()` uses below for the same reason).
    let defaultURL = savedURL ?? URL(string: "https://unconfigured.invalid")!
    return try? MacAppState.standard(serverURL: defaultURL)
  }
}
