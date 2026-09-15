import CoreModel
import LocalStore
import MapKit
import SwiftUI

// MARK: - albums (brief task 7, DECISIONS §4 R11)

/// Album detail: album timeline, add/remove assets (any member, R11), share with users, and
/// album-level settings (rename/delete) gated by role — role only gates settings, never
/// add/remove (DECISIONS §4).
struct AlbumDetailView: View {
  @EnvironmentObject var session: AppSession
  var album: Album

  @State private var rows: [TimelineRow] = []
  @State private var members: [AlbumMember] = []
  @State private var myRole: AlbumUserRoleKind?
  @State private var viewerRequest: ViewerRequest?
  @State private var showShare = false
  @State private var showRename = false
  @State private var showDelete = false
  @State private var editMode = false
  @State private var removeIds = Set<String>()
  @State private var error: String?

  var body: some View {
    List {
      Section("Assets (\(rows.count))") {
        ForEach(rows) { row in
          HStack {
            if editMode {
              Button {
                if removeIds.contains(row.id) {
                  removeIds.remove(row.id)
                } else {
                  removeIds.insert(row.id)
                }
              } label: {
                Image(systemName: removeIds.contains(row.id) ? "checkmark.circle.fill" : "circle")
              }
            }
            Button {
              viewerRequest = ViewerRequest(ids: rows.map(\.id), initialId: row.id)
            } label: {
              HStack {
                RowThumbnail(rowId: row.id)
                  .frame(width: 44, height: 44)
                  .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(row.localDateTime?.formatted(date: .abbreviated, time: .shortened) ?? "No date")
                  .font(.subheadline)
              }
            }
            .disabled(editMode)
          }
        }
        if editMode && !removeIds.isEmpty {
          Button("Remove \(removeIds.count) from Album", role: .destructive) {
            removeSelected()
          }
        }
      }
      Section("Members (\(members.count))") {
        ForEach(members, id: \.userId) { member in
          HStack {
            Text(member.userId == session.userId ? "You" : member.userId)
            Spacer()
            Text(member.role.rawValue)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Button("Share with Users") { showShare = true }
      }
      if canManage {
        Section("Manage") {
          Button("Rename") { showRename = true }
          Button("Delete Album", role: .destructive) { showDelete = true }
        }
      }
      if let error {
        Section { Text(error).foregroundStyle(.red).font(.caption) }
      }
    }
    .navigationTitle(album.name)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(editMode ? "Done" : "Edit") {
          editMode.toggle()
          removeIds = []
        }
      }
    }
    .refreshable { await reload() }
    .task { await reload() }
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
    .fullScreenCover(item: $viewerRequest) { request in
      ViewerView(ids: request.ids, initialId: request.initialId)
    }
  }

  /// Album-level settings need editor/owner; add/remove is open to every member (R11).
  private var canManage: Bool { myRole != .viewer }

  private func reload() async {
    guard let store = session.store else { return }
    do {
      rows = try await store.albumAssets(albumId: album.id, limit: 10_000)
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

// MARK: - person detail (DECISIONS §11: per-owner faces)

struct PersonDetailView: View {
  @EnvironmentObject var session: AppSession
  var person: Person
  @State private var rows: [TimelineRow] = []

  var body: some View {
    Group {
      if rows.isEmpty {
        ContentUnavailableView(
          "No Photos", systemImage: "person",
          description: Text("Faces cluster under the contributor's People."))
      } else {
        AssetRowList(title: person.name.isEmpty ? "Person" : person.name, rows: rows)
      }
    }
    .navigationTitle(person.name.isEmpty ? "Person" : person.name)
    .task {
      guard let store = session.store else { return }
      let ids = (try? await store.assetIds(forPerson: person.id)) ?? []
      let assets = (try? await store.assets(ids: ids)) ?? []
      rows = assets.compactMap { asset in
        TimelineRow(
          id: asset.id, thumbhash: asset.thumbhash,
          aspectRatio: Self.ratio(of: asset),
          mediaKind: asset.livePhotoVideoId != nil ? .livePhoto
            : (asset.type == .video ? .video : .photo),
          isFavorite: asset.isFavorite, isTrashed: asset.deletedAt != nil,
          isArchived: asset.visibility == .archive, localDateTime: asset.localDateTime)
      }
      .sorted { ($0.localDateTime ?? .distantPast) > ($1.localDateTime ?? .distantPast) }
    }
  }

  static func ratio(of asset: Asset) -> Double {
    if let w = asset.width, let h = asset.height, h > 0 {
      return Double(w) / Double(h)
    }
    return 1
  }
}

// MARK: - places (map of GPS assets)

struct PlacesView: View {
  @EnvironmentObject var session: AppSession
  @State private var pins: [LocatedAsset] = []
  @State private var rows: [TimelineRow] = []

  var body: some View {
    List {
      Section("Map") {
        PlacesMap(pins: pins)
          .frame(height: 280)
          .clipShape(RoundedRectangle(cornerRadius: 10))
      }
      Section("Located Assets (\(rows.count))") {
        ForEach(rows) { row in
          HStack {
            RowThumbnail(rowId: row.id)
              .frame(width: 44, height: 44)
              .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(row.localDateTime?.formatted(date: .abbreviated, time: .shortened) ?? "No date")
              .font(.subheadline)
          }
        }
      }
    }
    .navigationTitle("Places")
    .task {
      guard let store = session.store,
        let scope = try? await session.timelineScope()
      else { return }
      pins = (try? await store.locatedAssets(scope: scope)) ?? []
      let assets = (try? await store.assets(ids: pins.map(\.id))) ?? []
      rows = assets.map {
        TimelineRow(
          id: $0.id, thumbhash: $0.thumbhash, aspectRatio: PersonDetailView.ratio(of: $0),
          mediaKind: $0.type == .video ? .video : .photo, isFavorite: $0.isFavorite,
          isTrashed: false, isArchived: false, localDateTime: $0.localDateTime)
      }
    }
  }
}

struct PlacesMap: View {
  var pins: [LocatedAsset]

  var body: some View {
    Map(initialPosition: .automatic) {
      ForEach(pins) { pin in
        Marker(
          coordinate: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
        ) {}
      }
    }
    .mapStyle(.standard)
  }
}
