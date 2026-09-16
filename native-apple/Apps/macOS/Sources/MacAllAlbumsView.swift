import AppKit
import CoreModel
import Media
import SwiftUI

/// The main-pane counterpart to the sidebar's All Albums row. Album navigation is intentionally
/// separated from the disclosure state, just as it is in Photos: expanding the sidebar never
/// replaces the current timeline, while selecting All Albums presents every album here.
struct MacAllAlbumsView: View {
  @Bindable var state: MacAppState
  var openAlbum: (Album) -> Void

  private var albums: [Album] { state.albums.map(\.album).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }

  var body: some View {
    ScrollView {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 22)],
        spacing: 22
      ) {
        ForEach(albums) { album in
          Button { openAlbum(album) } label: {
            MacAlbumCard(album: album, state: state)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("all-albums-\(album.id)")
        }
      }
      .padding(24)
    }
    .overlay {
      if albums.isEmpty {
        ContentUnavailableView("No Albums", systemImage: "rectangle.stack")
      }
    }
    .navigationTitle("All Albums")
  }
}

private struct MacAlbumCard: View {
  var album: Album
  @Bindable var state: MacAppState
  @State private var image: NSImage?
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .quaternaryLabelColor))
        if let image {
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Image(systemName: "photo.on.rectangle.angled")
            .font(.system(size: 34))
            .foregroundStyle(.secondary)
        }
      }
      .frame(height: 150)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      Text(album.name).font(.headline).lineLimit(1)
      Text("\(count) item\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
    }
    .task(id: album.id) {
      let ids = (try? await state.store.assetIds(inAlbum: album.id)) ?? []
      count = ids.count
      guard let id = ids.first,
        let asset = try? await state.store.asset(id: id),
        let loaded = try? await state.pipeline.load(asset: asset, tier: .thumbnail)
      else { return }
      switch loaded.content {
      case .placeholder(let value): image = value
      case .tier(_, let value, _): image = value
      }
    }
  }
}

#Preview("All Albums") {
  MacPreviewFixture { state in
    MacAllAlbumsView(state: state, openAlbum: { _ in })
      .frame(width: 1100, height: 760)
  }
}
