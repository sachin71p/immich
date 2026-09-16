import CoreModel
import LocalStore
import Rules
import SwiftUI

/// Photos-for-Mac style sidebar (brief task 1): Library, Pinned, Media Types, Shared Libraries
/// (+ "New…"), Shared External Libraries, Albums, Utilities. Drop targets: assets on an album
/// add them; assets on a library move them (with a confirm dialog).
struct MacSidebarView: View {
  @Bindable var state: MacAppState
  @Binding var selection: SidebarDestination?
  var onDropAssets: (_ ids: [String], _ destination: SidebarDestination) -> Void
  var onNewSpace: () -> Void
  var onNewAlbum: () -> Void

  var body: some View {
    List(selection: $selection) {
      Section("Library") {
        row(.library)
        row(.collections)
        row(.search)
      }
      Section("Pinned") {
        row(.favorites)
        row(.recentlySaved)
        row(.map)
        row(.people)
        row(.memories)
      }
      Section("Media Types") {
        row(.mediaPhotos)
        ForEach(NativeMediaCollection.allCases, id: \.self) { collection in
          row(.media(collection))
        }
      }
      Section("Shared Libraries") {
        collapsible(state.spaces, id: \.space.id, title: "Shared Libraries", storageKey: "spaces") { entry in
          row(.space(entry.space.id), title: entry.space.name)
        }
        Button {
          onNewSpace()
        } label: {
          Label("New…", systemImage: "plus")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar-new-space")
      }
      Section("Shared Albums") {
        collapsible(state.albums.filter(\.isShared), id: \.album.id, title: "Shared Albums", storageKey: "shared-albums") { entry in
          row(.album(entry.album.id), title: entry.album.name)
        }
      }
      Section("External Libraries") {
        collapsible(state.libraries, id: \.library.id, title: "External Libraries", storageKey: "extlibs") { entry in
          row(.externalLibrary(entry.library.id), title: entry.library.name)
        }
      }
      Section {
        DisclosureGroup("Albums", isExpanded: disclosureBinding("albums")) {
          // All Albums is a real destination, not a disclosure affordance. It opens the album
          // overview in the main pane while the disclosure keeps the sidebar compact.
          row(.allAlbums)
          ForEach(state.albums.filter { !$0.isShared }, id: \.album.id) { entry in
            row(.album(entry.album.id), title: entry.album.name)
          }
        }
        Button {
          onNewAlbum()
        } label: {
          Label("New Album…", systemImage: "plus")
        }
        .buttonStyle(.plain)
      }
      Section("Utilities") {
        row(.imports)
        row(.recentlyDeleted)
        row(.duplicates)
        row(.capturedByMe)
        row(.hidden)
        row(.archive)
        row(.locked)
      }
      if !state.cameras.isEmpty {
        Section {
          DisclosureGroup("Captured With", isExpanded: disclosureBinding("captured-with")) {
            ForEach(state.cameraCategories) { category in
              row(.camera(category.name), title: "\(category.name) (\(category.count))")
            }
          }
        }
      }
    }
    .listStyle(.sidebar)
    .accessibilityIdentifier("sidebar")
  }

  private func row(_ destination: SidebarDestination, title: String? = nil) -> some View {
    Label(title ?? destination.title, systemImage: destination.systemImage)
      .tag(destination)
      .accessibilityIdentifier("sidebar-\(accessibilityKey(destination))")
      .onDrop(of: [.plainText], isTargeted: nil) { providers in
        handleAssetDrop(providers: providers, destination: destination)
      }
  }

  /// Expand/collapse persists per section in UserDefaults (brief: Albums must persist);
  /// sections start expanded, matching `DisclosureGroup`'s default.
  private func disclosureBinding(_ key: String) -> Binding<Bool> {
    Binding(
      get: { UserDefaults.standard.object(forKey: "Heirloom.sidebar.\(key).expanded") as? Bool ?? true },
      set: { UserDefaults.standard.set($0, forKey: "Heirloom.sidebar.\(key).expanded") }
    )
  }

  /// Photos keeps long sidebar collections compact: more than 3 entries collapse behind a
  /// persisted disclosure instead of forcing the sidebar to show every source on launch.
  @ViewBuilder
  private func collapsible<Entry, ID: Hashable, Row: View>(
    _ entries: [Entry], id: KeyPath<Entry, ID>, title: String, storageKey: String,
    @ViewBuilder rowContent: @escaping (Entry) -> Row
  ) -> some View {
    if entries.count > 3 {
      DisclosureGroup(title, isExpanded: disclosureBinding(storageKey)) {
        ForEach(entries, id: id) { entry in rowContent(entry) }
      }
    } else {
      ForEach(entries, id: id) { entry in rowContent(entry) }
    }
  }

  private func accessibilityKey(_ destination: SidebarDestination) -> String {
    switch destination {
    case .library: return "library"
    case .space(let id): return "space-\(id)"
    case .externalLibrary(let id): return "extlib-\(id)"
    case .album(let id): return "album-\(id)"
    default: return destination.title.lowercased().replacingOccurrences(of: " ", with: "-")
    }
  }

  private func handleAssetDrop(providers: [NSItemProvider], destination: SidebarDestination) -> Bool {
    guard destination.dropAction != .none else { return false }
    Task { @MainActor in
      var ids: [String] = []
      for provider in providers {
        if let text = try? await provider.loadText() {
          ids += Self.assetIds(from: text)
        }
      }
      if !ids.isEmpty { onDropAssets(ids, destination) }
    }
    return true
  }

  /// Grid drags write one id per provider (plain text); Finder file drops never reach this path
  /// (they use `.fileURL` on the detail side) so anything arriving here is an asset move/add.
  static func assetIds(from text: String) -> [String] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("[") {
      return (try? JSONDecoder().decode([String].self, from: Data(trimmed.utf8))) ?? []
    }
    return trimmed.isEmpty ? [] : [trimmed]
  }
}

extension NSItemProvider {
  @MainActor
  func loadText() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      _ = loadObject(ofClass: NSString.self) { object, error in
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: (object as? NSString ?? "") as String) }
      }
    }
  }
}

#Preview("Sidebar") {
  MacPreviewFixture { state in
    MacSidebarView(
      state: state, selection: .constant(.library), onDropAssets: { _, _ in },
      onNewSpace: {}, onNewAlbum: {}
    )
    .frame(width: 260, height: 860)
  }
}
