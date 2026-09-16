import SwiftUI

@main
struct HeirloomIOSApp: App {
  @StateObject private var session: AppSession

  init() {
    let session = AppSession()
    _session = StateObject(wrappedValue: session)
    // A5: BGProcessingTask fallback registration must happen at launch, before first
    // backgrounding (the extension target covers system photo jobs).
    BackupScheduler.register(session: session)
    BackupScheduler.scheduleNext()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(session)
    }
  }
}

struct RootView: View {
  @EnvironmentObject var session: AppSession
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      if session.signedIn {
        MainTabs()
      } else {
        // `ConnectView` writes the Keychain token itself; Continue rebuilds the session from it
        // (re-checked on every foregrounding, so background/foreground also enters).
        VStack {
          ConnectView()
          Button("Continue") {
            Task { await session.reload() }
          }
          .buttonStyle(.borderedProminent)
          .padding()
        }
      }
    }
    .task { await session.reload() }
    .onChange(of: scenePhase) { _, new in
      if new == .active {
        Task {
          await session.reload()
          session.checkPendingRoute()
        }
      }
    }
  }
}

struct MainTabs: View {
  @EnvironmentObject var session: AppSession

  var body: some View {
    // A9.6: selection binding so `OpenSearchIntent` can land on the Search tab.
    TabView(selection: $session.requestedTab) {
      LibraryView()
        .tag("library")
        .tabItem { Label("Library", systemImage: "photo").accessibilityIdentifier("tab-library") }
      CollectionsView()
        .tag("collections")
        .tabItem {
          Label("Collections", systemImage: "square.grid.2x2").accessibilityIdentifier(
            "tab-collections")
        }
      SearchView()
        .tag("search")
        .tabItem {
          Label("Search", systemImage: "magnifyingglass").accessibilityIdentifier("tab-search")
        }
      NavigationStack {
        SpacesListView()
      }
      .tag("shared")
      .tabItem { Label("Shared", systemImage: "person.2").accessibilityIdentifier("tab-shared") }
      SettingsView()
        .tag("settings")
        .tabItem { Label("Settings", systemImage: "gear").accessibilityIdentifier("tab-settings") }
    }
  }
}
