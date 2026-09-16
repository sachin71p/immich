import CoreModel
import Foundation
import LocalStore
import UIKit
import WidgetKit

/// A9.5 publisher: after each session refresh, publish the `ExtensionSnapshot` JSON +
/// thumbnail JPEGs the widgets/share/intents extensions read from the shared app-group
/// container. Never throws and never blocks refresh — failures stay silent and the
/// extensions keep showing their last snapshot.
enum ExtensionSnapshotWriter {
  /// Minimum age of the published snapshot before thumbnails are re-rendered. The JSON
  /// (counts, libraries) rewrites every refresh; JPEGs only when stale.
  static let thumbnailTTL: TimeInterval = 12 * 3600
  static let maxFavoriteThumbnails = 4

  @MainActor
  static func refreshIfNeeded(session: AppSession) async {
    guard let group = SharedContainer.groupURL(),
      let store = session.store,
      let pipeline = session.pipeline,
      !session.userId.isEmpty
    else { return }
    do {
      let snapshotURL = group.appendingPathComponent(ExtensionSnapshot.fileName)
      let thumbsDir = group.appendingPathComponent(
        ExtensionSnapshot.thumbnailsDirectoryName, isDirectory: true)
      try FileManager.default.createDirectory(
        at: thumbsDir, withIntermediateDirectories: true, attributes: nil)
      let previous: ExtensionSnapshot? = {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(ExtensionSnapshot.self, from: data)
      }()
      let scope = try await session.timelineScope()
      let favorites = try await store.favoriteAssets(scope: scope, limit: maxFavoriteThumbnails)
      let locatedCount = try await store.locatedAssets(scope: scope).count
      var libraries = [ExtensionSnapshot.LibraryOption(id: "personal", name: "Personal")]
      libraries += session.spaces.map {
        ExtensionSnapshot.LibraryOption(id: "space:\($0.id)", name: $0.name)
      }
      var memory: ExtensionSnapshot.MemorySummary?
      if let first = try await store.savedMemories(forOwner: session.userId).first {
        var coverName: String?
        let ids = try await store.assetIds(forMemory: first.id)
        if let coverId = ids.first,
          let asset = try? await store.asset(id: coverId),
          let loaded = try? await pipeline.load(asset: asset, tier: .thumbnail)
        {
          let uiImage: UIImage? = switch loaded.content {
          case .placeholder(let img): img
          case .tier(_, let img, _): img
          }
          if let data = uiImage?.jpegData(compressionQuality: 0.7) {
            coverName = "memory-cover.jpg"
            try? data.write(
              to: thumbsDir.appendingPathComponent("memory-cover.jpg"), options: .atomic)
          }
        }
        memory = ExtensionSnapshot.MemorySummary(
          title: MemoryStory.title(for: first), memoryAt: first.memoryAt,
          thumbnailFileName: coverName)
      }
      let thumbsStale = previous.map {
        Date().timeIntervalSince($0.updatedAt) > thumbnailTTL
      } ?? true
      var favoriteNames = previous?.favoriteThumbnailFileNames ?? []
      if thumbsStale || favoriteNames.isEmpty {
        favoriteNames = []
        for (index, row) in favorites.enumerated() {
          guard let asset = try? await store.asset(id: row.id),
            let loaded = try? await pipeline.load(asset: asset, tier: .thumbnail)
          else { continue }
          let uiImage: UIImage? = switch loaded.content {
          case .placeholder(let img): img
          case .tier(_, let img, _): img
          }
          guard let data = uiImage?.jpegData(compressionQuality: 0.7) else { continue }
          let name = "fav-\(index).jpg"
          try? data.write(to: thumbsDir.appendingPathComponent(name), options: .atomic)
          favoriteNames.append(name)
        }
      }
      let snapshot = ExtensionSnapshot(
        favoritesCount: (try? await store.favoriteAssets(scope: scope, limit: 1_000_000).count) ?? 0,
        locatedCount: locatedCount,
        favoriteThumbnailFileNames: favoriteNames,
        memory: memory,
        libraries: libraries)
      let data = try JSONEncoder().encode(snapshot)
      try data.write(to: snapshotURL, options: .atomic)
      WidgetCenter.shared.reloadAllTimelines()
    } catch {}
  }
}
