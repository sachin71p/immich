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
    // A9.6: selection binding so `OpenSearchIntent` can land on the Search tab —
    // the "search" value plus the `Heirloom.pendingRoute` key are the Shortcuts
    // deep-link contract; both are preserved here.
    // WP5 (T1): Library, Collections, search-role tab. Shared lives in
    // Collections + the Library filter menu (WP2/WP4); Settings moved behind
    // the account avatar (`AccountButton`, presented from Search until WP4
    // wires the Collections toolbar).
    TabView(selection: $session.requestedTab) {
      Tab("Library", systemImage: "photo", value: "library") {
        LibraryView()
      }
      Tab("Collections", systemImage: "square.grid.2x2", value: "collections") {
        CollectionsView()
      }
      Tab(value: "search", role: .search) {
        SearchView()
      }
    }
    // Same value WP2 applies on LibraryView; a duplicate minimize behavior does
    // not conflict, it converges.
    .tabBarMinimizeBehavior(.onScrollDown)
  }
}
