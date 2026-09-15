import CoreModel
import SwiftUI

/// Shared library / album management sheets (brief task 6) — same Core calls as iOS
/// (`SpaceMutations` / `AlbumMutations`).

struct MacNewSpaceSheet: View {
  @Bindable var state: MacAppState
  var onDone: () -> Void
  @State private var name = ""
  @State private var description = ""
  @State private var error: String?
  @State private var isWorking = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("New Shared Library").font(.headline)
      TextField("Name", text: $name).accessibilityIdentifier("new-space-name")
      TextField("Description (optional)", text: $description)
      if let error { Text(error).foregroundStyle(.red).font(.caption) }
      HStack {
        Spacer()
        Button("Cancel") { onDone() }
        Button("Create") { Task { await create() } }
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
          .accessibilityIdentifier("new-space-create")
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding()
    .frame(minWidth: 320)
  }

  private func create() async {
    isWorking = true
    defer { isWorking = false }
    do {
      _ = try await state.spaceMutations().createSpace(
        name: name.trimmingCharacters(in: .whitespaces),
        description: description.isEmpty ? nil : description
      )
      await state.refresh()
      onDone()
    } catch {
      self.error = error.localizedDescription
    }
  }
}

struct MacSpaceManageSheet: View {
  @Bindable var state: MacAppState
  var space: Space
  var role: SharedSpaceRoleKind
  var onDone: () -> Void
  @State private var name: String = ""
  @State private var description: String = ""
  @State private var members: [SpaceMember] = []
  @State private var newMemberId = ""
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(space.name).font(.headline)
      TextField("Name", text: $name)
      TextField("Description", text: $description)
      Button("Save") { Task { await save() } }.accessibilityIdentifier("space-save")
      Divider()
      Text("Members").font(.subheadline)
      ForEach(members, id: \.userId) { member in
        HStack {
          Text(member.userId)
          Spacer()
          Text(member.role.rawValue).foregroundStyle(.secondary)
          // Owner and contributor both manage members (DECISIONS §4); nobody changes their
          // own membership here — leaving/deleting live below.
          if member.userId != state.userId {
            Button("Remove") { Task { await removeMember(member.userId) } }
              .buttonStyle(.link)
          }
        }
      }
      HStack {
        TextField("User id or email", text: $newMemberId)
        Button("Add") { Task { await addMember() } }.disabled(newMemberId.isEmpty)
      }
      Divider()
      HStack {
        // DECISIONS §4: owner cannot leave (delete or transfer first); contributor can.
        if role == .contributor {
          Button("Leave") { Task { await leave() } }
        }
        if role == .owner {
          Button("Delete Library", role: .destructive) { Task { await deleteSpace() } }
            .accessibilityIdentifier("space-delete")
        }
        Spacer()
        Button("Done") { onDone() }
      }
      if let error { Text(error).foregroundStyle(.red).font(.caption) }
    }
    .padding()
    .frame(minWidth: 360)
    .task {
      name = space.name
      description = space.description
      members = (try? await state.store.spaceMembers(spaceId: space.id)) ?? []
    }
  }

  private func save() async {
    do {
      try await state.spaceMutations().updateSpace(
        id: space.id,
        name: name == space.name ? nil : name,
        description: description == space.description ? nil : description
      )
      await state.refresh()
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func addMember() async {
    do {
      try await state.spaceMutations().addMembers(userIds: [newMemberId], toSpace: space.id)
      newMemberId = ""
      members = (try? await state.store.spaceMembers(spaceId: space.id)) ?? []
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func removeMember(_ userId: String) async {
    do {
      try await state.spaceMutations().removeMember(userId: userId, fromSpace: space.id)
      members = (try? await state.store.spaceMembers(spaceId: space.id)) ?? []
      await state.refresh()
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func leave() async {
    guard let me = state.userId else { return }
    await removeMember(me)
    onDone()
  }

  private func deleteSpace() async {
    do {
      try await state.spaceMutations().deleteSpace(id: space.id)
      await state.refresh()
      onDone()
    } catch {
      self.error = error.localizedDescription
    }
  }
}

struct MacNewAlbumSheet: View {
  @Bindable var state: MacAppState
  var seedAssetIds: [String]
  var onDone: () -> Void
  @State private var name = ""
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("New Album").font(.headline)
      TextField("Name", text: $name).accessibilityIdentifier("new-album-name")
      if let error { Text(error).foregroundStyle(.red).font(.caption) }
      HStack {
        Spacer()
        Button("Cancel") { onDone() }
        Button("Create") { Task { await create() } }
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding()
    .frame(minWidth: 300)
  }

  private func create() async {
    do {
      _ = try await state.albumMutations().createAlbum(
        name: name.trimmingCharacters(in: .whitespaces), assetIds: seedAssetIds
      )
      await state.refresh()
      onDone()
    } catch {
      self.error = error.localizedDescription
    }
  }
}

/// "Add to album" picker (brief task 3): every album member may add any asset (DECISIONS §4 R11).
struct MacAddToAlbumSheet: View {
  @Bindable var state: MacAppState
  var assetIds: [String]
  var onDone: () -> Void
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Add to Album").font(.headline)
      List(state.albums, id: \.id) { album in
        Button {
          Task { await add(to: album.id) }
        } label: {
          Label(album.name, systemImage: "rectangle.stack")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add-to-album-\(album.id)")
      }
      .frame(minHeight: 160)
      if let error { Text(error).foregroundStyle(.red).font(.caption) }
    }
    .padding()
    .frame(minWidth: 300)
  }

  private func add(to albumId: String) async {
    do {
      _ = try await state.albumMutations().addAssets(assetIds, toAlbum: albumId)
      onDone()
    } catch {
      self.error = error.localizedDescription
    }
  }
}
