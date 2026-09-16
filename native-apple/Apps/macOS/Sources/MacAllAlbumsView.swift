import CoreModel
import SwiftUI

/// The main-pane counterpart to the sidebar's All Albums row. Album navigation is intentionally
/// separated from the disclosure state, just as it is in Photos: expanding the sidebar never
/// replaces the current timeline, while selecting All Albums presents every album here.
///
/// WP6 slice C (§6): the grid reuses the Collections `MacCoverTile` (single tile shape for
/// albums everywhere), offers name/recent sorting, and creates albums through the existing
/// `MacNewAlbumSheet` (same sheet as the sidebar flow — no forked creation path).
struct MacAllAlbumsView: View {
  @Bindable var state: MacAppState
  var openAlbum: (Album) -> Void

  private enum Sort: String, CaseIterable {
    case name
    case recent
  }

  @State private var sort = Sort.name
  @State private var showingNewAlbum = false
  @State private var entries: [AllAlbumsEntry] = []

  private var sorted: [AllAlbumsEntry] {
    switch sort {
    case .name:
      entries.sorted {
        $0.album.name.localizedCaseInsensitiveCompare($1.album.name) == .orderedAscending
      }
    case .recent:
      entries.sorted { $0.album.updatedAt > $1.album.updatedAt }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Picker("Sort", selection: $sort) {
          Text("Name").tag(Sort.name)
          Text("Recent").tag(Sort.recent)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
        .accessibilityIdentifier("all-albums-sort")
        Spacer()
        Button {
          showingNewAlbum = true
        } label: {
          Label("New Album", systemImage: "plus")
        }
        .accessibilityIdentifier("all-albums-new")
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 12)
      ScrollView {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 22)],
          spacing: 22
        ) {
          ForEach(sorted) { entry in
            MacCoverTile(
              title: entry.album.name,
              subtitle: "\(entry.count) item\(entry.count == 1 ? "" : "s")",
              coverId: entry.coverId,
              pipeline: state.pipeline
            ) { openAlbum(entry.album) }
            .accessibilityIdentifier("all-albums-\(entry.album.id)")
          }
        }
        .padding(24)
      }
    }
    .overlay {
      if entries.isEmpty {
        ContentUnavailableView("No Albums", systemImage: "rectangle.stack")
      }
    }
    .navigationTitle("All Albums")
    .task { await load() }
    .onChange(of: state.albums.count) { _, _ in Task { await load() } }
    .sheet(isPresented: $showingNewAlbum) {
      MacNewAlbumSheet(state: state, seedAssetIds: []) {
        showingNewAlbum = false
        Task { await load() }
      }
    }
  }

  /// Counts and covers come from the store (same queries the Collections shelf uses);
  /// covers stream their thumbnails inside `MacCoverTile`, so this only resolves ids.
  private func load() async {
    var built: [AllAlbumsEntry] = []
    for entry in state.albums {
      let album = entry.album
      let ids = (try? await state.store.assetIds(inAlbum: album.id)) ?? []
      built.append(AllAlbumsEntry(
        album: album, count: ids.count,
        coverId: album.thumbnailAssetId ?? ids.first))
    }
    entries = built
  }
}

/// One album row for `MacAllAlbumsView`: the `Album` plus the derived count/cover the
/// shared tile needs. Kept separate from Collections' `AlbumShelfEntry` because the sort
/// needs the full `Album` (name + `updatedAt`).
private struct AllAlbumsEntry: Identifiable {
  var album: Album
  var count: Int
  var coverId: String?
  var id: String { album.id }
}

#Preview("All Albums") {
  MacPreviewFixture { state in
    MacAllAlbumsView(state: state, openAlbum: { _ in })
      .frame(width: 1100, height: 760)
  }
}
