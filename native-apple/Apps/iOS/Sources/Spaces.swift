import CoreModel
import LocalStore
import Rules
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

// MARK: - space detail (WP4 §7: hero cover + grid, date desc)

// Space timeline scoped by spaceId (DECISIONS §9 explicit filter), rendered by the
// WP1 grid over a live `.timeline` scope — date desc comes from the index (C5).
// Rename/members/delete keep the §4 + §8 behaviours below the grid.
struct SpaceDetailView: View {
  @EnvironmentObject var session: AppSession
  var spaceId: String

  @State private var space: Space?
  @State private var members: [SpaceMember] = []
  @State private var scope: ContainerScope?
  @State private var coverId: String?
  @State private var showRename = false
  @State private var showAddMember = false
  @State private var showTransfer = false
  @State private var showDelete = false
  @State private var error: String?

  var body: some View {
    Group {
      if let scope {
        GridDetailView(
          title: space?.name ?? "Shared Library",
          source: .timeline(scope: scope, granularity: .day),
          header: AnyView(HeroCoverHeader(
            coverId: coverId, title: space?.name ?? "Shared Library",
            subtitle: "\(members.count) Members")))
      } else {
        ProgressView().navigationTitle("Shared Library")
      }
    }
    .task { await reload() }
    .refreshable { await reload() }
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
    .safeAreaInset(edge: .bottom) {
      spaceMemberBar
    }
  }

  private var isMember: Bool {
    members.contains { $0.userId == session.userId }
  }

  private var isOwner: Bool {
    members.first { $0.userId == session.userId }?.role == .owner
  }

  @ViewBuilder
  private var spaceMemberBar: some View {
    Menu {
      Section("Members (\(members.count))") {
        ForEach(members, id: \.userId) { member in
          Text("\(member.userId == session.userId ? "You" : member.userId) · \(member.role.rawValue)")
        }
      }
      if isMember {
        Button("Add Members") { showAddMember = true }
        Button("Rename") { showRename = true }
        if isOwner {
          Button("Transfer Ownership…") { showTransfer = true }
          Button("Delete Shared Library…", role: .destructive) { showDelete = true }
        } else {
          // Contributors may leave; the owner must delete or transfer first (§4).
          Button("Leave", role: .destructive) { leave() }
        }
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
    .accessibilityIdentifier("space-members")
  }

  private func reload() async {
    guard let store = session.store else { return }
    do {
      space = try await store.space(id: spaceId)
      members = try await store.membersOfSpace(spaceId)
      // Timeline scoped by spaceId — the explicit filter overrides preferences (§9),
      // access-checked by Rules.TimelineScope (non-members resolve to an empty scope).
      scope = try await session.timelineScope(explicit: .space(spaceId))
      if let scope {
        coverId = try await store.recentAssets(scope: scope, limit: 1).first?.id
      }
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
  @State private var scope: ContainerScope?
  @State private var coverId: String?

  var body: some View {
    Group {
      if let scope {
        GridDetailView(
          title: library.name,
          source: .timeline(scope: scope, granularity: .day),
          header: AnyView(HeroCoverHeader(
            coverId: coverId, title: library.name,
            subtitle: "External Library")))
      } else {
        ProgressView().navigationTitle(library.name)
      }
    }
    .task { await load() }
    .refreshable { await load() }
  }

  private func load() async {
    guard let store = session.store else { return }
    guard let scope = try? await session.timelineScope(explicit: .library(library.id)) else { return }
    self.scope = scope
    coverId = try? await store.recentAssets(scope: scope, limit: 1).first?.id
  }
}
