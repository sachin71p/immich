import CoreModel
import LocalStore
import SyncEngine
import SwiftUI

// MARK: - collections (WP4: native-15…18 scroll of collapsible sections)

// Native order: Memories · Pinned · Albums › · People › · Shared Albums › ·
// Shared Libraries · Recent Days · Media Types · Utilities · Places, then Reorder.
// Section shells paint immediately (loader stages fill lazily); collapse state and
// section/pinned order persist in @AppStorage.
struct CollectionsView: View {
  @EnvironmentObject var session: AppSession
  @StateObject private var loader = CollectionsLoader()

  @State private var collapsed: Set<String> = Set(CollectionsPrefs.collapsed.split(separator: ",").map(String.init))
  @State private var showReorder = false
  @State private var showPinnedEdit = false
  @State private var showSpaceCreate = false
  @State private var spaceCovers: [String: String] = [:]
  @State private var libraryCovers: [String: String] = [:]

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          ForEach(CollectionsPrefs.orderedSections()) { section in
            if !collapsed.contains(section.rawValue) || !isCollapsible(section) {
              sectionView(section)
            } else {
              collapsedHeader(section)
            }
          }
          reorderFooter
        }
        .padding(.vertical)
      }
      .navigationTitle("Collections")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: 12) {
            Menu {
              Button("Refresh") { Task { await loadAll() } }
            } label: {
              Image(systemName: "ellipsis")
                .frame(width: 32, height: 32)
                .background(.gray.opacity(0.2))
                .clipShape(Circle())
            }
            .accessibilityIdentifier("collections-menu")
            AccountButton()
          }
        }
      }
      .refreshable { await loadAll() }
      .task { await loadAll() }
      .sheet(isPresented: $showReorder) {
        SectionReorderSheet()
      }
      .sheet(isPresented: $showPinnedEdit) {
        PinnedEditSheet()
      }
      .sheet(isPresented: $showSpaceCreate) {
        SpaceCreateSheet()
          .environmentObject(session)
      }
    }
    .accessibilityIdentifier("collections")
  }

  private func loadAll() async {
    await loader.reload(session: session)
    // Key-photo covers for the space/library tiles (containers are few; one
    // limit-1 query each, after the counts stages so first paint never waits).
    guard let store = session.store else { return }
    for space in session.spaces {
      if let scope = try? await session.timelineScope(explicit: .space(space.id)),
        let cover = try? await store.recentAssets(scope: scope, limit: 1).first?.id
      {
        spaceCovers[space.id] = cover
      }
    }
    for library in session.libraries {
      if let scope = try? await session.timelineScope(explicit: .library(library.id)),
        let cover = try? await store.recentAssets(scope: scope, limit: 1).first?.id
      {
        libraryCovers[library.id] = cover
      }
    }
  }

  private func isCollapsible(_ section: CollectionsSection) -> Bool {
    section != .pinned && section != .spaces
  }

  private func toggle(_ section: CollectionsSection) {
    if collapsed.contains(section.rawValue) {
      collapsed.remove(section.rawValue)
      CollectionsPrefs.setCollapsed(section, collapsed: false)
    } else {
      collapsed.insert(section.rawValue)
      CollectionsPrefs.setCollapsed(section, collapsed: true)
    }
  }

  @ViewBuilder
  private func collapsedHeader(_ section: CollectionsSection) -> some View {
    CollectionPlainHeader(
      title: section.title, section: section,
      collapsed: true, onToggleCollapse: { toggle(section) })
      .accessibilityIdentifier("collections-section-\(section.rawValue)")
  }

  @ViewBuilder
  private func sectionView(_ section: CollectionsSection) -> some View {
    switch section {
    case .memories: memoriesSection
    case .pinned: pinnedSection
    case .albums: albumsSection
    case .people: peopleSection
    case .sharedAlbums: sharedAlbumsSection
    case .spaces: spacesSection
    case .recentDays: recentDaysSection
    case .mediaTypes: mediaTypesSection
    case .utilities: utilitiesSection
    case .places: placesSection
    }
  }

  // MARK: memories (large 3:4 cards, horizontal)

  @ViewBuilder
  private var memoriesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      CollectionSectionHeader(
        title: "Memories", section: .memories,
        collapsed: false, onToggleCollapse: { toggle(.memories) },
        destination: { MemoriesView().environmentObject(session) })
        .accessibilityIdentifier("collections-section-memories")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          if let stories = loader.stories {
            if stories.isEmpty {
              Text("No saved memories yet.")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal)
            }
            ForEach(stories) { story in
              NavigationLink {
                MemoriesView().environmentObject(session)
              } label: {
                ZStack(alignment: .bottomLeading) {
                  RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.25))
                    .frame(width: 180, height: 240)
                  if let first = story.assetIds.first {
                    AssetThumbView(assetId: first)
                      .frame(width: 180, height: 240)
                      .clipShape(RoundedRectangle(cornerRadius: 16))
                  }
                  VStack(alignment: .leading) {
                    Text(story.title).font(.headline).foregroundStyle(.white)
                    Text(story.memoryAt, format: .dateTime.month(.abbreviated).day().year())
                      .font(.caption).foregroundStyle(.white.opacity(0.85))
                  }
                  .padding(10)
                  .shadow(color: .black.opacity(0.6), radius: 4)
                }
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("memory-\(story.memoryId)")
            }
          } else {
            RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.15))
              .frame(width: 180, height: 240)
          }
        }
        .padding(.horizontal)
      }
    }
  }

  // MARK: pinned (Favorites / Recently Saved / Map + Edit)

  @ViewBuilder
  private var pinnedSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Pinned").font(.title3).fontWeight(.semibold)
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Edit") { showPinnedEdit = true }
          .font(.subheadline)
          .foregroundStyle(.blue)
          .padding(.horizontal, 12).padding(.vertical, 4)
          .background(.gray.opacity(0.2))
          .clipShape(Capsule())
          .accessibilityIdentifier("pinned-edit")
      }
      .padding(.horizontal)
      .accessibilityIdentifier("collections-section-pinned")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(PinnedItem.ordered()) { item in
            pinnedTile(item)
          }
        }
        .padding(.horizontal)
      }
    }
  }

  @ViewBuilder
  private func pinnedTile(_ item: PinnedItem) -> some View {
    switch item {
    case .favorites:
      NavigationLink {
        FavoritesDetailView().environmentObject(session)
      } label: {
        PhotoTitleTile(
          assetId: loader.favoriteCoverId, title: "Favorites",
          subtitle: loader.counts.map { "\($0.favorites)" })
      }
      .buttonStyle(.plain)
      .frame(width: 160)
    case .recents:
      NavigationLink {
        RecentsDetailView().environmentObject(session)
      } label: {
        PhotoTitleTile(
          assetId: loader.recentCoverId, title: "Recently Saved",
          subtitle: loader.counts.map { "\($0.recents)" })
      }
      .buttonStyle(.plain)
      .frame(width: 160)
    case .map:
      NavigationLink {
        PlacesView().environmentObject(session)
      } label: {
        ZStack(alignment: .bottomLeading) {
          RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.25))
          Image(systemName: "map.fill")
            .font(.largeTitle).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          Text("Map").font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
            .padding(10)
            .shadow(color: .black.opacity(0.6), radius: 4)
        }
        .aspectRatio(1, contentMode: .fit)
      }
      .buttonStyle(.plain)
      .frame(width: 160)
    }
  }

  // MARK: albums › (square tiles with title overlay)

  @ViewBuilder
  private var albumsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      CollectionSectionHeader(
        title: "Albums", section: .albums,
        collapsed: collapsed.contains("albums"), onToggleCollapse: { toggle(.albums) },
        destination: { AlbumsListView().environmentObject(session) })
        .accessibilityIdentifier("collections-section-albums")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          if let albums = loader.albums?.filter({ !$0.isShared }).prefix(6) {
            ForEach(Array(albums)) { tile in
              NavigationLink {
                AlbumDetailView(album: tile.album).environmentObject(session)
              } label: {
                PhotoTitleTile(
                  assetId: tile.coverId, title: tile.album.name,
                  subtitle: "\(tile.assetCount)")
              }
              .buttonStyle(.plain)
              .frame(width: 160)
              .accessibilityIdentifier("album-\(tile.album.name)")
            }
          } else {
            ForEach(0..<2, id: \.self) { _ in
              RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.15))
                .frame(width: 160, height: 160)
            }
          }
        }
        .padding(.horizontal)
      }
    }
  }

  // MARK: people › (face cards, name overlay; C1a: unnamed+zero hidden in loader)

  @ViewBuilder
  private var peopleSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      CollectionSectionHeader(
        title: "People", section: .people,
        collapsed: collapsed.contains("people"), onToggleCollapse: { toggle(.people) },
        destination: { PeopleListView().environmentObject(session) })
        .accessibilityIdentifier("collections-section-people")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          if let people = loader.people {
            if people.isEmpty {
              Text("No people yet.")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal)
            }
            ForEach(Array(people.prefix(6))) { person in
              NavigationLink {
                PersonDetailView(personId: person.id, name: person.summary.name)
                  .environmentObject(session)
              } label: {
                FaceTile(person: person)
              }
              .buttonStyle(.plain)
              .frame(width: 140)
            }
          } else {
            ForEach(0..<2, id: \.self) { _ in
              RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.15))
                .frame(width: 140, height: 140)
            }
          }
        }
        .padding(.horizontal)
      }
    }
  }

  // MARK: shared albums › (owner avatar overlay)

  @ViewBuilder
  private var sharedAlbumsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      CollectionSectionHeader(
        title: "Shared Albums", section: .sharedAlbums,
        collapsed: collapsed.contains("sharedAlbums"), onToggleCollapse: { toggle(.sharedAlbums) },
        destination: { AlbumsListView(sharedOnly: true).environmentObject(session) })
        .accessibilityIdentifier("collections-section-sharedAlbums")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          if let albums = loader.albums?.filter(\.isShared).prefix(6) {
            ForEach(Array(albums)) { tile in
              NavigationLink {
                AlbumDetailView(album: tile.album).environmentObject(session)
              } label: {
                ZStack(alignment: .topTrailing) {
                  PhotoTitleTile(
                    assetId: tile.coverId, title: tile.album.name,
                    subtitle: "\(tile.assetCount)")
                  Circle()
                    .fill(.blue.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .overlay {
                      Text(String(tile.album.name.prefix(1)))
                        .font(.caption).fontWeight(.bold).foregroundStyle(.white)
                    }
                    .padding(8)
                }
              }
              .buttonStyle(.plain)
              .frame(width: 160)
            }
          } else {
            ForEach(0..<1, id: \.self) { _ in
              RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.15))
                .frame(width: 160, height: 160)
            }
          }
        }
        .padding(.horizontal)
      }
    }
  }

  // MARK: shared libraries (space tiles + create; replaces the Shared tab content)

  @ViewBuilder
  private var spacesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Shared Libraries").font(.title3).fontWeight(.semibold)
        Spacer()
        Button { showSpaceCreate = true } label: {
          Image(systemName: "plus")
        }
        .accessibilityIdentifier("spaces-create")
      }
      .padding(.horizontal)
      .accessibilityIdentifier("collections-section-spaces")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(session.spaces) { space in
            NavigationLink {
              SpaceDetailView(spaceId: space.id).environmentObject(session)
            } label: {
              PhotoTitleTile(assetId: spaceCovers[space.id], title: space.name)
            }
            .buttonStyle(.plain)
            .frame(width: 160)
            .accessibilityIdentifier("space-\(space.name)")
          }
          ForEach(session.libraries) { library in
            NavigationLink {
              LibraryDetailView(library: library).environmentObject(session)
            } label: {
              PhotoTitleTile(assetId: libraryCovers[library.id], title: library.name, subtitle: "External")
            }
            .buttonStyle(.plain)
            .frame(width: 160)
          }
        }
        .padding(.horizontal)
      }
    }
  }

  // MARK: recent days (day tiles)

  @ViewBuilder
  private var recentDaysSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      CollectionPlainHeader(
        title: "Recent Days", section: .recentDays,
        collapsed: collapsed.contains("recentDays"), onToggleCollapse: { toggle(.recentDays) })
        .accessibilityIdentifier("collections-section-recentDays")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          if let days = loader.days {
            ForEach(days) { day in
              NavigationLink {
                DayDetailView(day: day).environmentObject(session)
              } label: {
                PhotoTitleTile(
                  assetId: day.keyAssetId, title: day.label,
                  subtitle: "\(day.count)")
              }
              .buttonStyle(.plain)
              .frame(width: 140)
            }
          } else {
            ForEach(0..<2, id: \.self) { _ in
              RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.15))
                .frame(width: 140, height: 140)
            }
          }
        }
        .padding(.horizontal)
      }
    }
  }

  // MARK: media types (2-column pill grid)

  @ViewBuilder
  private var mediaTypesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      CollectionPlainHeader(
        title: "Media Types", section: .mediaTypes,
        collapsed: collapsed.contains("mediaTypes"), onToggleCollapse: { toggle(.mediaTypes) })
        .accessibilityIdentifier("collections-section-mediaTypes")
      LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
        ForEach(NativeMediaCollection.allCases, id: \.self) { collection in
          NavigationLink {
            MediaTypeDetailView(collection: collection).environmentObject(session)
          } label: {
            CollectionPill(
              title: collection.title, systemImage: collection.systemImage,
              count: loader.counts?.media[collection])
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal)
    }
  }

  // MARK: utilities (pill grid; Captured With models underneath)

  @ViewBuilder
  private var utilitiesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      CollectionPlainHeader(
        title: "Utilities", section: .utilities,
        collapsed: collapsed.contains("utilities"), onToggleCollapse: { toggle(.utilities) })
        .accessibilityIdentifier("collections-section-utilities")
      LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
        NavigationLink { FavoritesDetailView().environmentObject(session) } label: {
          CollectionPill(
            title: "Favorites", systemImage: "heart",
            count: loader.counts?.favorites)
        }
        .buttonStyle(.plain)
        NavigationLink { HiddenDetailView().environmentObject(session) } label: {
          CollectionPill(
            title: "Hidden", systemImage: "eye.slash",
            locked: true, count: loader.counts?.hidden)
        }
        .buttonStyle(.plain)
        NavigationLink { TrashDetailView().environmentObject(session) } label: {
          CollectionPill(
            title: "Recently Deleted", systemImage: "trash",
            locked: true, count: loader.counts?.trash)
        }
        .buttonStyle(.plain)
        NavigationLink { DuplicateGroupsView().environmentObject(session) } label: {
          CollectionPill(title: "Duplicates", systemImage: "rectangle.on.rectangle")
        }
        .buttonStyle(.plain)
        NavigationLink { CapturedByMeDetailView().environmentObject(session) } label: {
          CollectionPill(
            title: "Captured by Me", systemImage: "person.crop.rectangle",
            count: loader.counts?.capturedByMe)
        }
        .buttonStyle(.plain)
        NavigationLink { ArchiveDetailView().environmentObject(session) } label: {
          CollectionPill(
            title: "Archive", systemImage: "archivebox",
            count: loader.counts?.archived)
        }
        .buttonStyle(.plain)
        NavigationLink { LockedDetailView().environmentObject(session) } label: {
          CollectionPill(
            title: "Locked", systemImage: "lock",
            locked: true, count: loader.counts?.locked)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal)
      if let cameras = loader.cameras, !cameras.isEmpty {
        NavigationLink {
          CapturedWithListView(cameras: cameras).environmentObject(session)
        } label: {
          HStack {
            Text("Captured With").font(.subheadline)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
          }
          .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("captured-with")
      }
    }
  }

  // MARK: places (map tile)

  @ViewBuilder
  private var placesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      CollectionSectionHeader(
        title: "Places", section: .places,
        collapsed: collapsed.contains("places"), onToggleCollapse: { toggle(.places) },
        destination: { PlacesView().environmentObject(session) })
        .accessibilityIdentifier("collections-section-places")
      NavigationLink {
        PlacesView().environmentObject(session)
      } label: {
        ZStack(alignment: .bottomLeading) {
          RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.25))
            .frame(height: 120)
          Image(systemName: "map.fill")
            .font(.largeTitle).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
          Text(loader.counts.map { "\($0.located) places" } ?? "Map")
            .font(.subheadline).fontWeight(.medium).foregroundStyle(.white)
            .padding(10)
            .shadow(color: .black.opacity(0.6), radius: 4)
        }
      }
      .buttonStyle(.plain)
      .padding(.horizontal)
      .accessibilityIdentifier("places-tile")
    }
  }

  // MARK: reorder footer

  @ViewBuilder
  private var reorderFooter: some View {
    Button("Reorder") { showReorder = true }
      .font(.headline)
      .foregroundStyle(.blue)
      .padding(.horizontal)
      .accessibilityIdentifier("collections-reorder")
  }
}

// MARK: - reorder sheets

/// Bottom "Reorder" sheet: drag sections into the preferred order (persisted).
struct SectionReorderSheet: View {
  @State private var order = CollectionsPrefs.orderedSections()
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(order) { section in
          Text(section.title)
        }
        .onMove { from, to in
          order.move(fromOffsets: from, toOffset: to)
          CollectionsPrefs.sectionOrder = order.map(\.rawValue).joined(separator: ",")
        }
      }
      .navigationTitle("Reorder Sections")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .environment(\.editMode, .constant(.active))
    }
  }
}

/// Pinned "Edit" sheet: reorder Favorites / Recently Saved / Map (persisted).
struct PinnedEditSheet: View {
  @State private var order = PinnedItem.ordered()
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(order) { item in
          Text(item.title)
        }
        .onMove { from, to in
          order.move(fromOffsets: from, toOffset: to)
          CollectionsPrefs.pinnedOrder = order.map(\.rawValue).joined(separator: ",")
        }
      }
      .navigationTitle("Edit Pinned")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .environment(\.editMode, .constant(.active))
    }
  }
}

// MARK: - duplicates (kept list; thumbnails via the pipeline thumb view)

struct DuplicateGroupsView: View {
  @EnvironmentObject var session: AppSession
  @State private var groups: [DuplicateGroup] = []
  @State private var assets: [String: Asset] = [:]
  @State private var error: String?

  var body: some View {
    List {
      if let error {
        ContentUnavailableView("Duplicates unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
      } else if groups.isEmpty {
        ContentUnavailableView("No Duplicates Found", systemImage: "rectangle.on.rectangle")
      } else {
        ForEach(groups) { group in
          Section("Duplicate group · \(group.assetIds.count) items") {
            ForEach(group.assetIds, id: \.self) { id in
              HStack {
                AssetThumbView(assetId: id).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                Text(assets[id]?.originalFileName ?? "Photo")
                Spacer()
                if group.suggestedKeepAssetIds.contains(id) {
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle("Duplicates")
    .task {
      guard let connection = session.connection, let store = session.store else { return }
      do {
        let loaded = try await DuplicateService(connection: connection).groups()
        groups = loaded
        assets = Dictionary(uniqueKeysWithValues: (try await store.assets(ids: loaded.flatMap(\.assetIds))).map { ($0.id, $0) })
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

// MARK: - captured-with list

struct CapturedWithListView: View {
  @EnvironmentObject var session: AppSession
  var cameras: [CameraModel]

  var body: some View {
    List {
      ForEach(CameraCategory.grouped(cameras)) { category in
        NavigationLink {
          CameraCategoryDetailView(category: category).environmentObject(session)
        } label: {
          Text("\(category.name) (\(category.count))")
        }
      }
    }
    .navigationTitle("Captured With")
  }
}
