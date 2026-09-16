import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI

/// WP6 slice B (U15, Collections): scrollable shelves + See All.
///
/// Every tile navigates via `select` (the existing `selectDestination`, so Hidden
/// and Locked keep their existing auth behavior — Locked authenticates there).
/// Counts come from the cheap `LocalStore+Counts` queries, loaded off-main and
/// cached until `timelineVersion` changes. Covers load their first item's
/// thumbnail through `pipeline.stream(id:)`; counts fill in progressively.
struct MacCollectionsView: View {
  @Bindable var state: MacAppState
  var select: (SidebarDestination) -> Void

  @State private var version = -1
  @State private var kinds: [TimelineMediaKind: Int] = [:]
  @State private var nativeCounts: [NativeMediaCollection: Int] = [:]
  @State private var favoriteCount = 0
  @State private var recentCount = 0
  @State private var hiddenCount = 0
  @State private var trashCount = 0
  @State private var locatedCount = 0
  @State private var albums: [AlbumShelfEntry] = []
  @State private var people: [PersonSummary] = []
  @State private var memories: [MemoryShelfEntry] = []
  @State private var expandLibraries = false

  private var spaces: [(id: String, name: String)] {
    state.spaces.map { (id: $0.space.id, name: $0.space.name) }
  }

  private var libraries: [(id: String, name: String)] {
    state.libraries.map { (id: $0.library.id, name: $0.library.name) }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        shelf(title: "Albums", seeAll: { select(.allAlbums) }) {
          ForEach(albums) { entry in
            MacCoverTile(
              title: entry.name,
              subtitle: "\(entry.count) item\(entry.count == 1 ? "" : "s")",
              coverId: entry.coverId, pipeline: state.pipeline
            ) { select(.album(entry.id)) }
          }
        }
        shelf(
          title: "Shared Libraries",
          seeAll: expandLibraries || spaces.count + libraries.count <= 8 ? nil : {
            expandLibraries = true
          }
        ) {
          // No aggregate destination exists for spaces/libraries, so See All
          // expands the shelf inline instead of navigating.
          let shownSpaces = expandLibraries ? spaces : Array(spaces.prefix(8))
          ForEach(shownSpaces, id: \.id) { space in
            MacIconTile(
              title: space.name, subtitle: nil, systemImage: "person.2.circle"
            ) { select(.space(space.id)) }
          }
          if expandLibraries {
            ForEach(libraries, id: \.id) { library in
              MacIconTile(
                title: library.name, subtitle: nil, systemImage: "externaldrive"
              ) { select(.externalLibrary(library.id)) }
            }
          }
        }
        shelf(title: "People", seeAll: { select(.people) }) {
          ForEach(people.prefix(8)) { person in
            MacPersonTile(person: person, pipeline: state.pipeline) {
              // No per-person destination exists (the People view owns its
              // selection state), so tiles land on People like See All does.
              select(.people)
            }
          }
        }
        shelf(title: "Memories", seeAll: { select(.memories) }) {
          ForEach(memories.prefix(6)) { entry in
            MacCoverTile(
              title: entry.title,
              subtitle:
                "\(entry.count) photo\(entry.count == 1 ? "" : "s")",
              coverId: entry.coverId, pipeline: state.pipeline
            ) { select(.memories) }
          }
        }
        shelf(title: "Pinned", seeAll: nil) {
          MacIconTile(
            title: "Favorites", subtitle: countText(favoriteCount),
            systemImage: "heart"
          ) { select(.favorites) }
          MacIconTile(
            title: "Recently Saved", subtitle: countText(recentCount),
            systemImage: "tray.and.arrow.down"
          ) { select(.recentlySaved) }
          MacIconTile(
            title: "Map", subtitle: countText(locatedCount), systemImage: "map"
          ) { select(.map) }
        }
        shelf(title: "Media Types", seeAll: nil) {
          MacIconTile(
            title: "Photos", subtitle: countText(kinds[.photo] ?? 0),
            systemImage: "photo"
          ) { select(.mediaPhotos) }
          MacIconTile(
            title: "Videos", subtitle: countText(kinds[.video] ?? 0),
            systemImage: "video"
          ) { select(.mediaVideos) }
          MacIconTile(
            title: "Selfies", subtitle: countText(nativeCounts[.selfies] ?? 0),
            systemImage: "person.crop.rectangle"
          ) { select(.media(.selfies)) }
          MacIconTile(
            title: "Live Photos", subtitle: countText(nativeCounts[.livePhotos] ?? 0),
            systemImage: "livephoto"
          ) { select(.media(.livePhotos)) }
          MacIconTile(
            title: "Portrait", subtitle: countText(nativeCounts[.portraits] ?? 0),
            systemImage: "f.cursive"
          ) { select(.media(.portraits)) }
          MacIconTile(
            title: "Panoramas", subtitle: countText(kinds[.panorama] ?? 0),
            systemImage: "pano"
          ) { select(.mediaPanoramas) }
          MacIconTile(
            title: "Screenshots", subtitle: countText(kinds[.screenshot] ?? 0),
            systemImage: "camera.viewfinder"
          ) { select(.mediaScreenshots) }
          MacIconTile(
            title: "Screen Recordings",
            subtitle: countText(nativeCounts[.screenRecordings] ?? 0),
            systemImage: "record.circle"
          ) { select(.media(.screenRecordings)) }
        }
        shelf(title: "Utilities", seeAll: nil) {
          MacIconTile(
            title: "Imports", subtitle: countText(recentCount),
            systemImage: "square.and.arrow.down"
          ) { select(.imports) }
          MacIconTile(
            title: "Duplicates", subtitle: nil,
            systemImage: "rectangle.on.rectangle"
          ) { select(.duplicates) }
          MacIconTile(
            title: "Hidden", subtitle: countText(hiddenCount),
            systemImage: "eye.slash"
          ) { select(.hidden) }
          MacIconTile(
            title: "Recently Deleted", subtitle: countText(trashCount),
            systemImage: "trash"
          ) { select(.recentlyDeleted) }
        }
      }
      .padding(24)
    }
    .navigationTitle("Collections")
    .accessibilityIdentifier("mac-collections")
    .task(id: state.timelineVersion) { await reload() }
  }

  private func countText(_ n: Int) -> String {
    "\(n) item\(n == 1 ? "" : "s")"
  }

  private func shelf<Content: View>(
    title: String, seeAll: (() -> Void)?, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title).font(.title2)
        Spacer()
        if let seeAll {
          Button("See All", action: seeAll)
            .buttonStyle(.link)
            .accessibilityIdentifier("collections-see-all-\(title)")
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: 16) {
          content()
        }
      }
    }
  }

  private func reload() async {
    guard let userId = state.userId else { return }
    // Cached until timelineVersion changes (the .task(id:) re-fires then).
    guard version != state.timelineVersion else { return }
    do {
      let ctx = try await state.store.timelineContext(for: userId)
      let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
      // Each await suspends on the GRDB reader thread — counts are COUNT(*)
      // queries, covers fetch one id each. Nothing O(rows) on-main.
      async let kinds = state.store.mediaKindCounts(scope: scope)
      async let fav = state.store.favoriteCount(scope: scope)
      async let recent = state.store.recentCount(scope: scope)
      async let hidden = state.store.hiddenCount(scope: scope)
      async let trash = state.store.trashCount(scope: scope)
      async let located = state.store.locatedCount(scope: scope)
      async let summaries = state.store.peopleSummaries(userId: userId)
      async let saved = state.store.savedMemories(forOwner: userId)
      self.kinds = try await kinds
      self.favoriteCount = try await fav
      self.recentCount = try await recent
      self.hiddenCount = try await hidden
      self.trashCount = try await trash
      self.locatedCount = try await located
      self.people = (try await summaries).filter { !$0.isHidden }
      for collection in NativeMediaCollection.allCases {
        nativeCounts[collection] = try await state.store.nativeCollectionCount(
          scope: scope, collection: collection)
      }
      var albumEntries: [AlbumShelfEntry] = []
      let sorted = state.albums.map(\.album).sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      for album in sorted.prefix(20) {
        // Cover = newest member id (one row); exact size via COUNT.
        async let cover = state.store.assetIds(inAlbum: album.id, limit: 1)
        async let count = state.store.albumAssetCount(album.id)
        albumEntries.append(
          AlbumShelfEntry(
            id: album.id, name: album.name, count: (try? await count) ?? 0,
            coverId: (try? await cover)?.first))
      }
      self.albums = albumEntries
      var memoryEntries: [MemoryShelfEntry] = []
      for memory in (try await saved).prefix(6) {
        let ids = (try? await state.store.assetIds(forMemory: memory.id)) ?? []
        guard !ids.isEmpty else { continue }
        memoryEntries.append(
          MemoryShelfEntry(
            id: memory.id,
            title: memory.memoryAt.formatted(date: .abbreviated, time: .omitted),
            count: ids.count, coverId: ids[0]))
      }
      self.memories = memoryEntries
      version = state.timelineVersion
    } catch {}
  }
}

/// One album row for the Albums shelf (cover loaded by the tile).
struct AlbumShelfEntry: Sendable, Hashable, Identifiable {
  var id: String
  var name: String
  var count: Int
  var coverId: String?
}

/// One saved memory for the Memories shelf.
struct MemoryShelfEntry: Sendable, Hashable, Identifiable {
  var id: String
  var title: String
  var count: Int
  var coverId: String?
}

/// Cover tile (albums, memories): 160-pt rounded thumbnail + title + count.
/// Internal (not private) so WP6 slice C's All Albums page reuses this exact tile.
struct MacCoverTile: View {
  var title: String
  var subtitle: String
  var coverId: String?
  var pipeline: MediaPipeline
  var action: () -> Void
  @State private var image: NSImage?

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 6) {
        ZStack {
          RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .quaternaryLabelColor))
          if let image {
            Image(nsImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
          } else {
            Image(systemName: "photo.on.rectangle.angled")
              .font(.system(size: 30))
              .foregroundStyle(.secondary)
          }
        }
        .frame(width: 160, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        Text(title).font(.headline).lineLimit(1)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      .frame(width: 160)
    }
    .buttonStyle(.plain)
    .task(id: coverId) {
      guard let coverId else { return }
      do {
        // First yield (placeholder or cached tier) is enough for a cover.
        for try await first in await pipeline.stream(
          id: coverId, thumbhash: nil, tier: .thumbnail
        ) {
          switch first.content {
          case .placeholder(let img): image = img
          case .tier(_, let img, _): image = img
          }
          break
        }
      } catch {}
    }
  }
}

/// Icon tile (pinned, media types, utilities, libraries): system image + title + count.
private struct MacIconTile: View {
  var title: String
  var subtitle: String?
  var systemImage: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        ZStack {
          RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .quaternaryLabelColor))
          Image(systemName: systemImage)
            .font(.system(size: 30))
            .foregroundStyle(.secondary)
        }
        .frame(width: 120, height: 90)
        Text(title).font(.headline).lineLimit(1)
        if let subtitle {
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
      }
      .frame(width: 120)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("collections-tile-\(title)")
  }
}

/// Face tile: 96-pt circle via `personThumbnail`, name + photo count.
private struct MacPersonTile: View {
  var person: PersonSummary
  var pipeline: MediaPipeline
  var action: () -> Void
  @State private var image: NSImage?

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Group {
          if let image {
            Image(nsImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
          } else {
            Circle().fill(Color(nsColor: .quaternaryLabelColor))
          }
        }
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        Text(person.name.isEmpty ? "Add Name" : person.name)
          .font(.headline)
          .lineLimit(1)
          .foregroundStyle(person.name.isEmpty ? .secondary : .primary)
        Text("\(person.assetCount) photo\(person.assetCount == 1 ? "" : "s")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(width: 120)
    }
    .buttonStyle(.plain)
    .task(id: person.id) {
      do {
        for try await loaded in await pipeline.personThumbnail(id: person.id) {
          switch loaded.content {
          case .placeholder(let img): image = img
          case .tier(_, let img, _): image = img
          }
          break
        }
      } catch {}
    }
  }
}
