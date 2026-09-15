import CoreModel
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
        row(.mediaVideos)
        row(.mediaScreenshots)
      }
      Section("Shared Libraries") {
        ForEach(state.spaces, id: \.space.id) { entry in
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
      Section("Shared External Libraries") {
        ForEach(state.libraries, id: \.library.id) { entry in
          row(.externalLibrary(entry.library.id), title: entry.library.name)
        }
      }
      Section("Albums") {
        ForEach(state.albums, id: \.id) { album in
          row(.album(album.id), title: album.name)
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
        row(.hidden)
        row(.archive)
        row(.locked)
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
  func loadText() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      _ = loadObject(ofClass: NSString.self) { object, error in
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: (object as? NSString ?? "") as String) }
      }
    }
  }
}
