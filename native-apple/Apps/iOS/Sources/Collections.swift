import CoreModel
import LocalStore
import SyncEngine
import SwiftUI

// MARK: - row list (shared grid-detail host)

/// A simple timeline-row list used by every Collections detail screen. Tapping a row opens the
/// viewer paged over the same id list.
struct AssetRowList: View {
  @EnvironmentObject var session: AppSession
  var title: String
  var rows: [TimelineRow]

  @State private var viewerRequest: ViewerRequest?

  var body: some View {
    List(rows) { row in
      Button {
        viewerRequest = ViewerRequest(ids: rows.map(\.id), initialId: row.id)
      } label: {
        HStack {
          RowThumbnail(rowId: row.id)
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))
          VStack(alignment: .leading) {
            Text(row.localDateTime?.formatted(date: .abbreviated, time: .shortened) ?? "No date")
              .font(.subheadline)
            Text(row.mediaKind.rawValue)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if row.isFavorite { Image(systemName: "heart.fill").foregroundStyle(.red) }
        }
      }
    }
    .navigationTitle(title)
    .fullScreenCover(item: $viewerRequest) { request in
      ViewerView(ids: request.ids, initialId: request.initialId)
    }
  }
}

struct RowThumbnail: View {
  @EnvironmentObject var session: AppSession
  var rowId: String
  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Rectangle().fill(.gray.opacity(0.3))
      }
    }
    .task(id: rowId) {
      guard let store = session.store, let pipeline = session.pipeline,
        let asset = try? await store.asset(id: rowId),
        let loaded = try? await pipeline.load(asset: asset, tier: .thumbnail)
      else { return }
      switch loaded.content {
      case .placeholder(let img): image = img
      case .tier(_, let img, _): image = img
      }
    }
  }
}

// MARK: - collections (brief task 3)

/// Albums, Shared Albums, Shared Libraries, People (per-owner, §11), Places (map), Favorites,
/// Recents, Media Types, Utilities (Recently Deleted = trash manage scope, Hidden, Archive).
struct CollectionsView: View {
  @EnvironmentObject var session: AppSession

  @State private var albums: [Album] = []
  @State private var albumMembers: [String: [AlbumMember]] = [:]
  @State private var favorites: [TimelineRow] = []
  @State private var recents: [TimelineRow] = []
  @State private var videos: [TimelineRow] = []
  @State private var live: [TimelineRow] = []
  @State private var panoramas: [TimelineRow] = []
  @State private var screenshots: [TimelineRow] = []
  @State private var trash: [TimelineRow] = []
  @State private var hidden: [TimelineRow] = []
  @State private var archived: [TimelineRow] = []
  @State private var locked: [TimelineRow] = []
  @State private var capturedByMe: [TimelineRow] = []
  @State private var nativeMedia: [NativeMediaCollection: [TimelineRow]] = [:]
  @State private var cameras: [CameraModel] = []
  @State private var showingLocked = false
  @State private var people: [Person] = []
  @State private var personCounts: [String: Int] = [:]
  @State private var placeCount = 0

  var body: some View {
    NavigationStack {
      List {
        Section("Albums") {
          // Shared albums = more than one member (DECISIONS §4 R11); the member lists load
          // alongside the albums above.
          ForEach(albums.filter { (albumMembers[$0.id]?.count ?? 1) <= 1 }) { album in
            NavigationLink(album.name) {
              AlbumDetailView(album: album)
            }
          }
          NavigationLink("Shared Albums") {
            List(albums.filter { (albumMembers[$0.id]?.count ?? 1) > 1 }) { album in
              NavigationLink(album.name) {
                AlbumDetailView(album: album)
              }
            }
            .navigationTitle("Shared Albums")
          }
        }
        Section("Shared Libraries") {
          ForEach(session.spaces) { space in
            NavigationLink(space.name) {
              SpaceDetailView(spaceId: space.id)
            }
          }
          ForEach(session.libraries) { library in
            NavigationLink {
              LibraryDetailView(library: library)
            } label: {
              Label(library.name, systemImage: "externaldrive")
            }
          }
        }
        Section("People") {
          ForEach(people) { person in
            NavigationLink {
              PersonDetailView(person: person)
            } label: {
              HStack {
                Text(person.name.isEmpty ? "Unnamed" : person.name)
                Spacer()
                Text("\(personCounts[person.id] ?? 0)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        Section("Memories") {
          NavigationLink {
            MemoriesView()
          } label: {
            Label("Memories", systemImage: "clock")
          }
          .accessibilityIdentifier("collections-memories")
        }
        Section("Places") {
          NavigationLink {
            PlacesView()
          } label: {
            HStack {
              Label("Map", systemImage: "map")
              Spacer()
              Text("\(placeCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        Section("Favorites") {
          NavigationLink("Favorites (\(favorites.count))") {
            AssetRowList(title: "Favorites", rows: favorites)
          }
        }
        Section("Recents") {
          NavigationLink("Recents (\(recents.count))") {
            AssetRowList(title: "Recents", rows: recents)
          }
        }
        Section("Media Types") {
          ForEach(NativeMediaCollection.allCases, id: \.self) { collection in
            let rows = nativeMedia[collection] ?? []
            NavigationLink("\(collection.title) (\(rows.count))") {
              AssetRowList(title: collection.title, rows: rows)
            }
          }
        }
        Section("Utilities") {
          // Recently Deleted reads the trash manage scope (DECISIONS §10).
          NavigationLink("Recently Deleted (\(trash.count))") {
            AssetRowList(title: "Recently Deleted", rows: trash)
          }
          NavigationLink("Hidden (\(hidden.count))") {
            AssetRowList(title: "Hidden", rows: hidden)
          }
          NavigationLink("Duplicates") {
            DuplicateGroupsView()
          }
          NavigationLink("Captured by Me (\(capturedByMe.count))") {
            AssetRowList(title: "Captured by Me", rows: capturedByMe)
          }
          NavigationLink("Archive (\(archived.count))") {
            AssetRowList(title: "Archive", rows: archived)
          }
          Button("Locked (\(locked.count))") {
            Task {
              if await LockedMediaAuthentication.authenticate() { showingLocked = true }
            }
          }
        }
        if !cameras.isEmpty {
          Section("Captured With") {
            // Device models are useful EXIF data but noisy navigation. Present the same broad
            // classes as macOS (Phone, DSLR, Drone, Action Camera) and query all member models.
            ForEach(CameraCategory.grouped(cameras)) { category in
              NavigationLink("\(category.name) (\(category.count))") {
                CameraCategoryAssetList(category: category)
              }
            }
          }
        }
      }
      .navigationTitle("Collections")
      .refreshable { await reload() }
      .task { await reload() }
      .navigationDestination(isPresented: $showingLocked) {
        AssetRowList(title: "Locked", rows: locked)
      }
    }
    .accessibilityIdentifier("collections")
  }

  private func reload() async {
    guard let store = session.store else { return }
    do {
      let scope = try await session.timelineScope()
      let manage = try await session.manageScope()
      albums = try await store.albumsForUser(session.userId)
      var members: [String: [AlbumMember]] = [:]
      for album in albums {
        members[album.id] = try await store.membersOfAlbum(album.id)
      }
      albumMembers = members
      favorites = try await store.favoriteAssets(scope: scope)
      recents = try await store.recentAssets(scope: scope)
      videos = try await store.assets(scope: scope, mediaKind: .video)
      live = try await store.assets(scope: scope, mediaKind: .livePhoto)
      panoramas = try await store.assets(scope: scope, mediaKind: .panorama)
      screenshots = try await store.assets(scope: scope, mediaKind: .screenshot)
      trash = try await store.trashedAssets(scope: manage)
      hidden = try await store.visibilityAssets(.hidden, scope: manage)
      archived = try await store.visibilityAssets(.archive, scope: manage)
      locked = try await store.lockedAssets(currentUserId: session.userId)
      capturedByMe = try await store.capturedByUser(session.userId, scope: manage).map(TimelineRow.init(asset:))
      cameras = try await store.cameraModels(scope: manage)
      var media: [NativeMediaCollection: [TimelineRow]] = [:]
      for collection in NativeMediaCollection.allCases {
        media[collection] = try await store.mediaAssets(scope: scope, collection: collection)
      }
      nativeMedia = media
      people = try await store.peopleForOwner(session.userId)
      var counts: [String: Int] = [:]
      for person in people {
        counts[person.id] = try await store.assetIds(forPerson: person.id).count
      }
      personCounts = counts
      placeCount = try await store.locatedAssets(scope: scope).count
    } catch {
      session.lastError = error.localizedDescription
    }
  }
}

struct CameraAssetList: View {
  @EnvironmentObject var session: AppSession
  var camera: CameraModel
  @State private var rows: [TimelineRow] = []

  var body: some View {
    AssetRowList(title: camera.model, rows: rows)
      .task {
        guard let store = session.store, let scope = try? await session.manageScope() else { return }
        rows = (try? await store.assets(cameraModel: camera.model, scope: scope).map(TimelineRow.init(asset:))) ?? []
      }
  }
}

struct CameraCategoryAssetList: View {
  @EnvironmentObject var session: AppSession
  var category: CameraCategory
  @State private var rows: [TimelineRow] = []

  var body: some View {
    AssetRowList(title: category.name, rows: rows)
      .task {
        guard let store = session.store, let scope = try? await session.manageScope() else { return }
        var assets: [Asset] = []
        for model in category.models {
          assets += (try? await store.assets(cameraModel: model, scope: scope, limit: 250_000)) ?? []
        }
        rows = assets.sorted { ($0.localDateTime ?? .distantPast) > ($1.localDateTime ?? .distantPast) }
          .map(TimelineRow.init(asset:))
      }
  }
}

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
                RowThumbnail(rowId: id).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
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
