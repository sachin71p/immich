import CoreModel
import LocalStore
import SwiftUI

// MARK: - shared libraries (brief task 6, DECISIONS §4 + §8)

struct SpacesListView: View {
  @EnvironmentObject var session: AppSession
  @State private var showCreate = false

  var body: some View {
    List(session.spaces) { space in
      NavigationLink(space.name) {
        SpaceDetailView(spaceId: space.id)
      }
    }
    .navigationTitle("Shared Libraries")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { showCreate = true } label: { Label("New Shared Library", systemImage: "plus") }
      }
    }
    .sheet(isPresented: $showCreate) {
      SpaceCreateSheet()
        .environmentObject(session)
    }
  }
}

struct SpaceCreateSheet: View {
  @EnvironmentObject var session: AppSession
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
      .navigationTitle("New Shared Library")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            Task {
              do {
                // Any user can create shared libraries; the creator becomes owner (R2).
                try await session.spaceMutations?.createSpace(name: name)
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

/// Space detail: timeline scoped by spaceId (DECISIONS §9 explicit filter), rename, members
/// (add/remove, leave, transfer), delete with the §8 consequences text.
struct SpaceDetailView: View {
  @EnvironmentObject var session: AppSession
  var spaceId: String

  @State private var space: Space?
  @State private var members: [SpaceMember] = []
  @State private var rows: [TimelineRow] = []
  @State private var viewerRequest: ViewerRequest?
  @State private var showRename = false
  @State private var showAddMember = false
  @State private var showTransfer = false
  @State private var showDelete = false
  @State private var error: String?

  var body: some View {
    List {
      Section("Timeline") {
        if rows.isEmpty {
          Text("No assets yet.").foregroundStyle(.secondary)
        } else {
          ForEach(rows) { row in
            Button {
              viewerRequest = ViewerRequest(ids: rows.map(\.id), initialId: row.id)
            } label: {
              HStack {
                RowThumbnail(rowId: row.id)
                  .frame(width: 44, height: 44)
                  .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(row.localDateTime?.formatted(date: .abbreviated, time: .shortened) ?? "No date")
                  .font(.subheadline)
                Spacer()
                if row.isFavorite { Image(systemName: "heart.fill").foregroundStyle(.red) }
              }
            }
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
            // Owner and contributors alike may add/remove contributors (DECISIONS §4); only the
            // owner row and one's own row are protected here (leave covers self-removal).
            if isMember && member.userId != session.userId && member.role == .contributor {
              Button("Remove") { removeMember(member.userId) }
                .font(.caption)
            }
          }
        }
        if isMember {
          Button("Add Members") { showAddMember = true }
        }
      }
      if isMember {
        Section("Manage") {
          Button("Rename") { showRename = true }
          if isOwner {
            Button("Transfer Ownership…") { showTransfer = true }
            Button("Delete Shared Library…", role: .destructive) { showDelete = true }
          } else {
            // Contributors may leave; the owner must delete or transfer first (§4).
            Button("Leave", role: .destructive) { leave() }
          }
        }
      }
      if let error {
        Section { Text(error).foregroundStyle(.red).font(.caption) }
      }
    }
    .navigationTitle(space?.name ?? "Shared Library")
    .refreshable { await reload() }
    .task { await reload() }
    .sheet(isPresented: $showRename) {
      SpaceRenameSheet(spaceId: spaceId, currentName: space?.name ?? "")
        .environmentObject(session)
    }
    .sheet(isPresented: $showAddMember) {
      SpaceAddMemberSheet(spaceId: spaceId) {
        Task { await reload() }
      }
      .environmentObject(session)
    }
    .sheet(isPresented: $showTransfer) {
      SpaceTransferSheet(spaceId: spaceId, members: members) {
        Task { await reload() }
      }
      .environmentObject(session)
    }
    .alert(
      "Delete this shared library?",
      isPresented: $showDelete
    ) {
      Button("Delete", role: .destructive) { deleteSpace() }
      Button("Cancel", role: .cancel) {}
    } message: {
      // Consequences text from DECISIONS §8.
      Text(
        "All its assets return to each contributor's personal library. Albums are untouched.")
    }
    .fullScreenCover(item: $viewerRequest) { request in
      ViewerView(ids: request.ids, initialId: request.initialId)
    }
  }

  private var isMember: Bool {
    members.contains { $0.userId == session.userId }
  }

  private var isOwner: Bool {
    members.first { $0.userId == session.userId }?.role == .owner
  }

  private func reload() async {
    guard let store = session.store else { return }
    do {
      space = try await store.space(id: spaceId)
      members = try await store.membersOfSpace(spaceId)
      // Timeline scoped by spaceId — the explicit filter overrides preferences (§9), access-checked
      // by Rules.TimelineScope (non-members resolve to an empty scope).
      let scope = try await session.timelineScope(explicit: .space(spaceId))
      rows = try await store.recentAssets(scope: scope)
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func removeMember(_ userId: String) {
    Task {
      do {
        try await session.spaceMutations?.removeMember(userId: userId, fromSpace: spaceId)
        try await session.refresh()
        await reload()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func leave() {
    Task {
      do {
        try await session.spaceMutations?.removeMember(userId: session.userId, fromSpace: spaceId)
        try await session.refresh()
        await reload()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func deleteSpace() {
    Task {
      do {
        try await session.spaceMutations?.deleteSpace(id: spaceId)
        try await session.refresh()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

struct SpaceRenameSheet: View {
  @EnvironmentObject var session: AppSession
  var spaceId: String
  var currentName: String
  @State private var name: String = ""
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
      .navigationTitle("Rename")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear { name = currentName }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task {
              do {
                // Renaming never moves files (R7-01); only the space row changes.
                try await session.spaceMutations?.updateSpace(id: spaceId, name: name)
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

struct SpaceAddMemberSheet: View {
  @EnvironmentObject var session: AppSession
  var spaceId: String
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
      .navigationTitle("Add Member")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            Task {
              do {
                try await session.spaceMutations?.addMembers(userIds: [userId], toSpace: spaceId)
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

struct SpaceTransferSheet: View {
  @EnvironmentObject var session: AppSession
  var spaceId: String
  var members: [SpaceMember]
  var onDone: () -> Void
  @State private var selection: String?
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        // Owner ↔ contributor role swap in one transaction (DECISIONS §8).
        Picker("New owner", selection: $selection) {
          Text("Pick a contributor").tag(nil as String?)
          ForEach(members.filter { $0.role == .contributor }, id: \.userId) { member in
            Text(member.userId).tag(member.userId as String?)
          }
        }
        if let error {
          Text(error).foregroundStyle(.red).font(.caption)
        }
      }
      .navigationTitle("Transfer Ownership")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Transfer") {
            Task {
              do {
                guard let newOwner = selection else { return }
                try await session.spaceMutations?.transferOwnership(
                  spaceId: spaceId, fromUserId: session.userId, toUserId: newOwner)
                try await session.refresh()
                onDone()
                dismiss()
              } catch {
                self.error = error.localizedDescription
              }
            }
          }
          .disabled(selection == nil)
        }
      }
    }
  }
}

/// External-library detail (read-mostly): timeline scoped by libraryId. Library member/settings
/// management stays admin-only upstream (DECISIONS §4) — see the handoff open issues.
struct LibraryDetailView: View {
  @EnvironmentObject var session: AppSession
  var library: Library
  @State private var rows: [TimelineRow] = []

  var body: some View {
    List(rows) { row in
      HStack {
        RowThumbnail(rowId: row.id)
          .frame(width: 44, height: 44)
          .clipShape(RoundedRectangle(cornerRadius: 6))
        Text(row.localDateTime?.formatted(date: .abbreviated, time: .shortened) ?? "No date")
          .font(.subheadline)
      }
    }
    .navigationTitle(library.name)
    .task {
      guard let store = session.store else { return }
      if let scope = try? await session.timelineScope(explicit: .library(library.id)) {
        rows = (try? await store.recentAssets(scope: scope)) ?? []
      }
    }
  }
}
