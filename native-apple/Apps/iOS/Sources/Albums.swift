import CoreModel
import LocalStore
import MapKit
import SwiftUI

// MARK: - album detail (WP4 §4: hero cover + grid; brief task 7 behaviours kept)

// Album timeline as a grid under the native-20 hero (key photo, title, item count).
// Add/remove stays open to every member (R11); rename/delete stay role-gated.
struct AlbumDetailView: View {
  @EnvironmentObject var session: AppSession
  var album: Album

  @State private var ids: [String]?
  @State private var members: [AlbumMember] = []
  @State private var myRole: AlbumUserRoleKind?
  @State private var showShare = false
  @State private var showRename = false
  @State private var showDelete = false
  @State private var editMode = false
  @State private var removeIds = Set<String>()
  @State private var error: String?

  var body: some View {
    Group {
      if let ids {
        IdListDetail(
          title: album.name, ids: ids,
          header: AnyView(HeroCoverHeader(
            coverId: ids.first, title: album.name,
            subtitle: "\(ids.count) Items")))
      } else {
        ProgressView().navigationTitle(album.name)
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(editMode ? "Done" : "Edit") {
          editMode.toggle()
          removeIds = []
        }
      }
    }
    .task { await reload() }
    .refreshable { await reload() }
    .sheet(isPresented: $showShare) {
      AlbumShareSheet(albumId: album.id) {
        Task { await reload() }
      }
      .environmentObject(session)
    }
    .sheet(isPresented: $showRename) {
      AlbumRenameSheet(album: album)
        .environmentObject(session)
    }
    .alert("Delete this album?", isPresented: $showDelete) {
      Button("Delete", role: .destructive) { deleteAlbum() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Assets stay in their libraries; only the album is removed.")
    }
    .safeAreaInset(edge: .bottom) {
      if editMode {
        albumEditBar
      } else {
        albumMemberBar
      }
    }
  }

  /// Album-level settings need editor/owner; add/remove is open to every member (R11).
  private var canManage: Bool { myRole != .viewer }

  @ViewBuilder
  private var albumEditBar: some View {
    HStack {
      Text(removeIds.isEmpty ? "Select items to remove" : "\(removeIds.count) selected")
        .font(.caption).foregroundStyle(.secondary)
      Spacer()
      if !removeIds.isEmpty {
        Button("Remove from Album", role: .destructive) { removeSelected() }
          .font(.subheadline)
      }
    }
    .padding()
    .background(.thinMaterial)
  }

  // Member management lives below the grid (members, share, rename/delete).
  @ViewBuilder
  private var albumMemberBar: some View {
    Menu {
      Section("Members (\(members.count))") {
        ForEach(members, id: \.userId) { member in
          Text("\(member.userId == session.userId ? "You" : member.userId) · \(member.role.rawValue)")
        }
      }
      Button("Share with Users") { showShare = true }
      if canManage {
        Button("Rename") { showRename = true }
        Button("Delete Album", role: .destructive) { showDelete = true }
      }
    } label: {
      HStack {
        Image(systemName: "person.2.fill").font(.caption)
        Text("\(members.count) Members").font(.caption)
        Spacer()
        if let error {
          Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
      .background(.thinMaterial)
    }
    .accessibilityIdentifier("album-members")
  }

  private func reload() async {
    guard let store = session.store else { return }
    do {
      // Removal selection is id-based, so it survives grid reloads.
      let rows = try await store.albumAssets(albumId: album.id, limit: 100_000)
      ids = rows.map(\.id)
      members = try await store.membersOfAlbum(album.id)
      myRole = try await store.albumMemberRole(albumId: album.id, userId: session.userId)
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func removeSelected() {
    Task {
      do {
        try await session.albumMutations?.removeAssets(Array(removeIds), fromAlbum: album.id)
        removeIds = []
        editMode = false
        await reload()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func deleteAlbum() {
    Task {
      do {
        try await session.albumMutations?.deleteAlbum(id: album.id)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

// MARK: - albums › page (C4, native-19)

/// All-albums page: Personal / Shared segments, a 2-column rounded tile grid, "+"
/// (existing create flow) and "…" (sort). Shared = more than one member (R11).
struct AlbumsListView: View {
  @EnvironmentObject var session: AppSession
  var sharedOnly = false

  @State private var tiles: [AlbumTileData]?
  @State private var segment = 0
  @State private var showCreate = false
  @State private var sortByName = false

  private var shown: [AlbumTileData] {
    let tiles = tiles ?? []
    let filtered = segment == 1 ? tiles.filter(\.isShared) : tiles.filter { !$0.isShared }
    if sortByName {
      return filtered.sorted { $0.album.name.localizedCompare($1.album.name) == .orderedAscending }
    }
    return filtered
  }

  var body: some View {
    Group {
      if tiles == nil {
        ProgressView().navigationTitle("Albums")
      } else {
        ScrollView {
          LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
            ForEach(shown) { tile in
              NavigationLink {
                AlbumDetailView(album: tile.album).environmentObject(session)
              } label: {
                PhotoTitleTile(
                  assetId: tile.coverId, title: tile.album.name,
                  subtitle: "\(tile.assetCount)")
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("album-\(tile.album.name)")
            }
          }
          .padding()
        }
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            HStack {
              Button { showCreate = true } label: { Image(systemName: "plus") }
                .accessibilityIdentifier("albums-create")
              Menu {
                Button("Sort by Name") { sortByName = true }
                Button("Sort by Recent") { sortByName = false }
              } label: {
                Image(systemName: "ellipsis")
              }
              .accessibilityIdentifier("albums-menu")
            }
          }
        }
      }
    }
    .safeAreaInset(edge: .top) {
      Picker("Albums", selection: $segment) {
        Text("Personal").tag(0)
        Text("Shared").tag(1)
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      .accessibilityIdentifier("albums-segment")
    }
    .task { await load() }
    .refreshable { await load() }
    .onAppear { if sharedOnly { segment = 1 } }
    .sheet(isPresented: $showCreate) {
      AlbumCreateSheet { _ in Task { await load() } }
        .environmentObject(session)
    }
    .accessibilityIdentifier("albums-list")
  }

  private func load() async {
    guard let store = session.store else { return }
    let all = (try? await store.albumsForUser(session.userId)) ?? []
    var tiles: [AlbumTileData] = []
    for album in all {
      let members = (try? await store.membersOfAlbum(album.id)) ?? []
      let cover = try? await store.albumAssets(albumId: album.id, limit: 1)
      let count = (try? await store.albumAssetCount(album.id)) ?? 0
      tiles.append(AlbumTileData(
        album: album, memberCount: members.count,
        coverId: cover?.first?.id, assetCount: count))
    }
    self.tiles = tiles
  }
}

struct AlbumCreateSheet: View {
  @EnvironmentObject var session: AppSession
  var assetIds: [String] = []
  var onDone: (Album) -> Void = { _ in }
  @State private var name = ""
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $name)
        if let error {
          Text(error).foregroundStyle(.red).font(.caption)
        }
      }
      .navigationTitle("New Album")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            Task {
              do {
                guard let mutations = session.albumMutations else { return }
                let album = try await mutations.createAlbum(name: name, assetIds: assetIds)
                try await session.refresh()
                onDone(album)
                dismiss()
              } catch {
                self.error = error.localizedDescription
              }
            }
          }
          .disabled(name.isEmpty)
        }
      }
    }
  }
}

struct AlbumRenameSheet: View {
  @EnvironmentObject var session: AppSession
  var album: Album
  @State private var name = ""
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $name)
        if let error {
          Text(error).foregroundStyle(.red).font(.caption)
        }
      }
      .navigationTitle("Rename Album")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear { name = album.name }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task {
              do {
                try await session.albumMutations?.renameAlbum(id: album.id, name: name)
                try await session.refresh()
                dismiss()
              } catch {
                self.error = error.localizedDescription
              }
            }
          }
          .disabled(name.isEmpty)
        }
      }
    }
  }
}

/// Shares the album with new viewers (`PUT /albums/{id}/users`).
struct AlbumShareSheet: View {
  @EnvironmentObject var session: AppSession
  var albumId: String
  var onDone: () -> Void
  @State private var userId = ""
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        TextField("User ID or email", text: $userId)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        if let error {
          Text(error).foregroundStyle(.red).font(.caption)
        }
      }
      .navigationTitle("Share Album")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Share") {
            Task {
              do {
                try await session.albumMutations?.shareWithUsers([userId], albumId: albumId)
                try await session.refresh()
                onDone()
                dismiss()
              } catch {
                self.error = error.localizedDescription
              }
            }
          }
          .disabled(userId.isEmpty)
        }
      }
    }
  }
}

/// Picks an album to add assets to (or creates one) — used by the selection bar and viewer.
struct AlbumPickerSheet: View {
  @EnvironmentObject var session: AppSession
  var assetIds: [String]
  @State private var albums: [Album] = []
  @State private var showCreate = false
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(albums) { album in
          Button(album.name) {
            Task {
              do {
                try await session.albumMutations?.addAssets(assetIds, toAlbum: album.id)
                dismiss()
              } catch {
                self.error = error.localizedDescription
              }
            }
          }
        }
        if let error {
          Section { Text(error).foregroundStyle(.red).font(.caption) }
        }
      }
      .navigationTitle("Add to Album")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button { showCreate = true } label: { Label("New Album", systemImage: "plus") }
        }
      }
      .task {
        if let store = session.store {
          albums = (try? await store.albumsForUser(session.userId)) ?? []
        }
      }
      .sheet(isPresented: $showCreate) {
        AlbumCreateSheet(assetIds: assetIds) { _ in dismiss() }
          .environmentObject(session)
      }
    }
  }
}

// MARK: - person detail (WP4 §4: hero cover + grid)

struct PersonDetailView: View {
  @EnvironmentObject var session: AppSession
  var personId: String
  var name: String
  @State private var ids: [String]?
  @State private var faceAssetId: String?

  private var title: String { name.isEmpty ? "Person" : name }

  var body: some View {
    Group {
      if let ids {
        if ids.isEmpty {
          ContentUnavailableView(
            "No Photos", systemImage: "person",
            description: Text("Faces cluster under the contributor's People."))
            .navigationTitle(title)
        } else {
          IdListDetail(
            title: title, ids: ids,
            header: AnyView(PersonHeroHeader(
              personId: personId, faceAssetId: faceAssetId,
              title: title, subtitle: "\(ids.count) Items")))
        }
      } else {
        ProgressView().navigationTitle(title)
      }
    }
    .task { await load() }
    .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store else { return }
    ids = (try? await store.assetIds(forPerson: personId, limit: 100_000)) ?? []
    faceAssetId = (try? await store.peopleForOwner(session.userId))?
      .first { $0.id == personId }?.faceAssetId
  }
}

private struct PersonHeroHeader: View {
  var personId: String
  var faceAssetId: String?
  var title: String
  var subtitle: String

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Rectangle().fill(.gray.opacity(0.25)).frame(height: 240)
      PersonFaceView(personId: personId, faceAssetId: faceAssetId)
        .frame(height: 240)
        .clipped()
      LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        .frame(height: 240)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.title2).fontWeight(.bold).foregroundStyle(.white)
        Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.9))
      }
      .padding()
    }
  }
}

// MARK: - people › page (WP4 §6: 3-column face grid + Sort; groups omitted — no data)

/// Groups are omitted: Immich has no group API, so there is nothing to render
/// (plan §6: omit unless the data exists).
struct PeopleListView: View {
  @EnvironmentObject var session: AppSession
  @State private var people: [PersonTileData]?
  @State private var sortByName = false

  private var shown: [PersonTileData] {
    let people = people ?? []
    if sortByName {
      return people.sorted { $0.summary.name.localizedCompare($1.summary.name) == .orderedAscending }
    }
    return people
  }

  var body: some View {
    Group {
      if let people {
        if people.isEmpty {
          ContentUnavailableView(
            "No People", systemImage: "person.2",
            description: Text("Faces appear here once they sync."))
            .navigationTitle("People")
        } else {
          ScrollView {
            LazyVGrid(
              columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())],
              spacing: 12
            ) {
              ForEach(shown) { person in
                NavigationLink {
                  PersonDetailView(personId: person.id, name: person.summary.name)
                    .environmentObject(session)
                } label: {
                  FaceTile(person: person)
                }
                .buttonStyle(.plain)
              }
            }
            .padding()
          }
          .navigationTitle("People")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .primaryAction) {
              Menu {
                Button("Sort by Name") { sortByName = true }
                Button("Sort by Count") { sortByName = false }
              } label: {
                Text("Sort").font(.subheadline)
              }
              .accessibilityIdentifier("people-sort")
            }
          }
        }
      } else {
        ProgressView().navigationTitle("People")
      }
    }
    .task { await load() }
    .refreshable { await load() }
    .accessibilityIdentifier("people-list")
  }

  private func load() async {
    guard let store = session.store else { return }
    let summaries = (try? await store.peopleSummaries(userId: session.userId)) ?? []
    let persons = (try? await store.peopleForOwner(session.userId)) ?? []
    let faces = Dictionary(uniqueKeysWithValues: persons.map { ($0.id, $0.faceAssetId) })
    people = summaries
      .filter { !($0.name.isEmpty && $0.assetCount == 0) }
      .map { PersonTileData(summary: $0, faceAssetId: faces[$0.id] ?? nil) }
  }
}

// MARK: - places (map of GPS assets; selection opens the grid)

/// Clustered map (annotations from the shared `MapClusterer`) + the tapped
/// marker/cluster selection as a grid below it.
struct PlacesView: View {
  @EnvironmentObject var session: AppSession
  @State private var pins: [LocatedAsset] = []
  @State private var zoomLevel: Double = 3
  @State private var selectedIds: [String] = []
  @State private var columns = 5
  @State private var viewerRequest: ViewerRequest?

  private var clusters: [MapCluster] {
    MapClusterer.cluster(
      pins.map { MapClusterItem(id: $0.id, latitude: $0.latitude, longitude: $0.longitude) },
      zoomLevel: zoomLevel)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        ClusteredMapView(
          clusters: clusters,
          onSelect: { selectedIds = $0 },
          onZoomChange: { zoomLevel = $0 }
        )
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .accessibilityIdentifier("places-map")
        if !selectedIds.isEmpty {
          Text("Selection (\(selectedIds.count))")
            .font(.headline)
            .padding(.horizontal)
          selectionGrid
            .frame(height: 400)
        }
      }
      .padding(.vertical)
    }
    .navigationTitle("Places")
    .task { await load() }
    .refreshable { await load() }
    .fullScreenCover(item: $viewerRequest) { request in
      ViewerView(ids: request.ids, initialId: request.initialId)
    }
  }

  @ViewBuilder
  private var selectionGrid: some View {
    AssetGridView(
      source: .ids(selectedIds),
      store: session.store,
      pipeline: session.pipeline,
      columns: $columns,
      onOpen: { route in
        viewerRequest = ViewerRequest(ids: route.resolveIds(), initialId: route.startId)
      },
      showsSectionHeaders: false,
      session: session
    )
  }

  private func load() async {
    guard let store = session.store,
      let scope = try? await session.timelineScope()
    else { return }
    pins = (try? await store.locatedAssets(scope: scope)) ?? []
  }
}
