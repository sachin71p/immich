import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI
import UIKit

// MARK: - selection action bar (brief task 5)

/// Multi-select action bar: share, favorite, add to album, move to…, archive, delete.
/// Every action is gated by `Rules.Permissions` (brief task 9) — unavailable actions are hidden,
/// never offered-then-rejected.
struct SelectionActionBar: View {
  @EnvironmentObject var session: AppSession
  var selectedIds: Set<String>
  var onClear: () -> Void
  var onMove: () -> Void
  var onError: (String) -> Void

  @State private var assets: [Asset] = []
  @State private var showAlbumPicker = false

  var body: some View {
    VStack(spacing: 2) {
      Text("\(selectedIds.count) selected")
        .font(.caption)
        .foregroundStyle(.secondary)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 16) {
          if canShare {
            Button("Share") { shareSelected() }
          }
          if canFavorite {
            Button("Favorite") {
              mutate {
                guard let mutations = session.assetMutations else { return }
                try await mutations.setFavorite(ids: ids, isFavorite: true)
              }
            }
          }
          if canEdit {
            Button("Add to Album") { showAlbumPicker = true }
            Button("Archive") {
              mutate {
                guard let mutations = session.assetMutations else { return }
                try await mutations.setArchived(ids: ids, isArchived: true)
              }
            }
          }
          if canMove {
            Button("Move to…") { onMove() }
          }
          if canDelete {
            Button("Delete", role: .destructive) {
              mutate {
                guard let mutations = session.assetMutations else { return }
                try await mutations.trash(ids: ids)
              }
            }
          }
          Button("Clear") { onClear() }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
      }
    }
    .padding(.vertical, 6)
    .task(id: selectedIds) {
      if let store = session.store {
        assets = (try? await store.assets(ids: ids)) ?? []
      }
    }
    .sheet(isPresented: $showAlbumPicker) {
      AlbumPickerSheet(assetIds: ids)
        .environmentObject(session)
    }
  }

  private var ids: [String] { Array(selectedIds) }

  private var ctx: AccessContext { session.access }

  private var canShare: Bool {
    !assets.isEmpty && assets.allSatisfy { Permissions.hasContainerAccess($0.container, in: ctx) }
  }

  private var canFavorite: Bool {
    !assets.isEmpty && assets.allSatisfy { Permissions.canFavorite($0, in: ctx) }
  }

  private var canEdit: Bool {
    !assets.isEmpty && assets.allSatisfy { Permissions.canEdit($0, in: ctx) }
  }

  private var canMove: Bool {
    !assets.isEmpty && assets.contains { !MoveTargets.allowed(for: $0, in: ctx).isEmpty }
  }

  private var canDelete: Bool {
    !assets.isEmpty && assets.allSatisfy { Permissions.canDelete($0, in: ctx) }
  }

  private func shareSelected() {
    Task {
      guard let base = session.serverURL,
        let token = await session.bearerToken(),
        let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene }).first?.windows.first
      else { return }
      do {
        var files: [URL] = []
        for asset in assets {
          var request = URLRequest(
            url: MediaEndpoint(serverURL: base, assetID: asset.id).originalURL())
          request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          let (data, _) = try await URLSession.shared.data(for: request)
          let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(asset.id)-\(asset.originalFileName)")
          try data.write(to: tmp)
          files.append(tmp)
        }
        let activity = UIActivityViewController(activityItems: files, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
          popover.sourceView = window
        }
        window.rootViewController?.present(activity, animated: true)
      } catch {
        // L2: cancellation is never a user-facing error.
        if !error.isCancellation { onError(error.localizedDescription) }
      }
    }
  }

  private func mutate(_ work: @escaping () async throws -> Void) {
    Task {
      do {
        try await work()
        try await session.refresh()
      } catch {
        // L2: cancellation is never a user-facing error.
        if !error.isCancellation { onError(error.localizedDescription) }
      }
    }
  }
}

// MARK: - move sheet (brief task 5: Rules.MoveTargets + per-asset results)

/// Move sheet: lists every container the selection may move to, then shows per-asset
/// moved/noop/error results (DECISIONS §6 rule 5 groups, rule 7 noops, rule 8 duplicates).
struct MoveSheet: View {
  @EnvironmentObject var session: AppSession
  var selectedIds: [String]
  var onDone: () -> Void

  @State private var assets: [Asset] = []
  @State private var results: [MoveResult]?
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        if let results {
          Section("Results") {
            ForEach(results, id: \.assetId) { result in
              HStack {
                Text(shortId(result.assetId))
                Spacer()
                Text(resultLabel(result))
                  .font(.caption)
                  .foregroundStyle(result.status == .error ? .red : .secondary)
              }
            }
          }
        } else {
          Section("Move \(selectedIds.count) asset(s) to") {
            ForEach(targetRows, id: \.target.key) { row in
              Button {
                move(to: row.target)
              } label: {
                HStack {
                  Text(row.title)
                  Spacer()
                  Text("\(row.eligibleCount)/\(selectedIds.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .disabled(row.eligibleCount == 0)
            }
          }
          .accessibilityIdentifier("move-targets")
        }
        if let error {
          Section { Text(error).foregroundStyle(.red).font(.caption) }
        }
      }
      .navigationTitle("Move to…")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
    }
    .task {
      if let store = session.store {
        assets = (try? await store.assets(ids: selectedIds)) ?? []
      }
    }
  }

  private struct TargetRow {
    var target: MoveTarget
    var title: String
    var eligibleCount: Int
  }

  private var targetRows: [TargetRow] {
    let ctx = session.access
    var titles: [MoveTarget: String] = [:]
    var counts: [MoveTarget: Int] = [:]
    for asset in assets {
      for target in MoveTargets.allowed(for: asset, in: ctx) {
        titles[target] = targetTitle(target)
        counts[target, default: 0] += 1
      }
    }
    return titles.keys.sorted { titles[$0]! < titles[$1]! }.map {
      TargetRow(target: $0, title: titles[$0]!, eligibleCount: counts[$0] ?? 0)
    }
  }

  private func targetTitle(_ target: MoveTarget) -> String {
    switch target {
    case .personal: return "Personal Library"
    case .space(let id): return session.spaces.first { $0.id == id }?.name ?? "Shared Library"
    case .library(let id): return session.libraries.first { $0.id == id }?.name ?? "External Library"
    }
  }

  private func move(to target: MoveTarget) {
    Task {
      do {
        // Expand the selection to live-photo pairs + stack siblings first (DECISIONS §6 rule 5:
        // one failing member fails its whole group, other groups proceed).
        let groups = try await expandGroups(ids: selectedIds)
        guard let mutations = session.assetMutations else { return }
        let flat = groups.flatMap { $0 }.map(\.id)
        let outcome = try await mutations.move(ids: flat, to: target)
        results = outcome
        try await session.refresh()
        onDone()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func expandGroups(ids: [String]) async throws -> [[Asset]] {
    guard let store = session.store else { return [] }
    var groups: [[Asset]] = []
    var seen = Set<String>()
    for id in ids {
      if seen.contains(id) { continue }
      guard let asset = try await store.asset(id: id) else { continue }
      var group = [asset]
      seen.insert(id)
      if let stackId = asset.stackId {
        for member in try await store.stackMembers(stackId: stackId) where !seen.contains(member.id) {
          seen.insert(member.id)
          group.append(member)
        }
      }
      if let motionId = asset.livePhotoVideoId, !seen.contains(motionId),
        let motion = try await store.asset(id: motionId)
      {
        seen.insert(motionId)
        group.append(motion)
      }
      groups.append(group)
    }
    return groups
  }

  private func shortId(_ id: String) -> String { String(id.prefix(8)) }

  private func resultLabel(_ result: MoveResult) -> String {
    switch result.status {
    case .moved: return "Moved"
    case .noop: return "Already there"
    case .error: return result.reason ?? "Error"
    }
  }
}

extension MoveTarget {
  var key: String {
    switch self {
    case .personal: return "personal"
    case .space(let id): return "space-\(id)"
    case .library(let id): return "library-\(id)"
    }
  }
}
