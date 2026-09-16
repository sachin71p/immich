import CoreModel
import SwiftUI
import WidgetKit

/// A9.5: memories + favorites widgets. The extension never opens the live database —
/// it reads the `ExtensionSnapshot` JSON + thumbnail JPEGs the main app publishes into
/// the shared app-group container (see `ExtensionSnapshotWriter` in the app target).
/// The group id string is the contract (BackgroundUpload precedent).
enum WidgetSharedAccess {
  static let groupIdentifier = "group.com.immich.heirloom.shared"

  static func containerURL() -> URL? {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: groupIdentifier)
  }

  static func loadSnapshot() -> ExtensionSnapshot? {
    guard let container = containerURL(),
      let data = try? Data(
        contentsOf: container.appendingPathComponent(ExtensionSnapshot.fileName))
    else { return nil }
    return try? JSONDecoder().decode(ExtensionSnapshot.self, from: data)
  }

  static func thumbnail(named fileName: String) -> UIImage? {
    guard let container = containerURL() else { return nil }
    let url = container
      .appendingPathComponent(ExtensionSnapshot.thumbnailsDirectoryName)
      .appendingPathComponent(fileName)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
  }
}

struct SnapshotEntry: TimelineEntry {
  var date: Date
  var snapshot: ExtensionSnapshot?
}

struct SnapshotProvider: TimelineProvider {
  func placeholder(in context: Context) -> SnapshotEntry {
    SnapshotEntry(date: Date(), snapshot: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
    completion(SnapshotEntry(date: Date(), snapshot: WidgetSharedAccess.loadSnapshot()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
    let entry = SnapshotEntry(date: Date(), snapshot: WidgetSharedAccess.loadSnapshot())
    // The app rewrites the snapshot after every refresh; polling hourly only bounds
    // staleness when the app has not run.
    let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    completion(Timeline(entries: [entry], policy: .after(next)))
  }
}

struct FavoritesWidgetView: View {
  var entry: SnapshotEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label("Favorites", systemImage: "heart.fill")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("\(entry.snapshot?.favoritesCount ?? 0)")
        .font(.title)
        .bold()
      HStack(spacing: 4) {
        ForEach(entry.snapshot?.favoriteThumbnailFileNames.prefix(3) ?? [], id: \.self) { name in
          if let image = WidgetSharedAccess.thumbnail(named: name) {
            Image(uiImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: 44, height: 44)
              .clipShape(RoundedRectangle(cornerRadius: 6))
          }
        }
      }
      Spacer(minLength: 0)
      Text("\(entry.snapshot?.locatedCount ?? 0) places")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding()
  }
}

struct MemoriesWidgetView: View {
  var entry: SnapshotEntry

  var body: some View {
    Group {
      if let memory = entry.snapshot?.memory {
        ZStack(alignment: .bottomLeading) {
          if let name = memory.thumbnailFileName,
            let image = WidgetSharedAccess.thumbnail(named: name)
          {
            Image(uiImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
          } else {
            Rectangle().fill(.gray.opacity(0.3))
          }
          VStack(alignment: .leading) {
            Text(memory.title)
              .font(.headline)
              .foregroundStyle(.white)
            Text(memory.memoryAt.formatted(date: .abbreviated, time: .omitted))
              .font(.caption)
              .foregroundStyle(.white.opacity(0.85))
          }
          .padding(8)
          .background(.black.opacity(0.35))
        }
      } else {
        VStack {
          Label("Memories", systemImage: "clock")
            .font(.headline)
          Text("No saved memories yet.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
      }
    }
  }
}

struct FavoritesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "com.immich.heirloom.widgets.favorites", provider: SnapshotProvider()) {
      entry in
      FavoritesWidgetView(entry: entry)
    }
    .configurationDisplayName("Favorites")
    .description("Favorite counts and recent favorite thumbnails.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct MemoriesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "com.immich.heirloom.widgets.memories", provider: SnapshotProvider()) {
      entry in
      MemoriesWidgetView(entry: entry)
    }
    .configurationDisplayName("Memories")
    .description("Your latest saved memory.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct HeirloomWidgets: WidgetBundle {
  var body: some Widget {
    FavoritesWidget()
    MemoriesWidget()
  }
}
