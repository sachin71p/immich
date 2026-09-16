import SwiftUI

/// Canvas cannot construct `MacAppState` directly because the production state owns a local
/// database, media pipeline, and authenticated connection. This lightweight host uses the same
/// deterministic in-memory fixture as UI smoke tests, so every preview is safe to render offline.
struct MacPreviewFixture<Content: View>: View {
  @State private var state: MacAppState?
  @ViewBuilder var content: (MacAppState) -> Content

  var body: some View {
    Group {
      if let state {
        content(state)
      } else {
        ProgressView("Loading preview…")
          .frame(minWidth: 800, minHeight: 600)
      }
    }
    .task {
      guard state == nil, let seeded = try? MacAppState.seeded() else { return }
      try? await seeded.seedForSmoke()
      state = seeded
    }
  }
}
