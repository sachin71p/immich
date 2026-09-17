import CoreModel
import Rules
import SwiftUI
import UIKit

// MARK: - select-mode "…" menu (WP2 §4, spec native-09/10)

// Holds the bulk actions that don't fit the bottom toolbar: Copy, Hide,
// Favorite, Add To ▸ (albums via the existing picker), Move To ▸ (the existing
// `MoveSheet`), Archive. Duplicate and Adjust Date are omitted — `AssetMutations`
// exposes no duplicate or date-adjust operation (see WP2 report). Every action is
// gated by `Rules.Permissions` like the bottom bar; unavailable actions hide.

struct SelectMoreMenu: View {
  @EnvironmentObject var session: AppSession
  var selectedIds: Set<String>
  @Binding var showAlbumPicker: Bool
  @Binding var showMoveSheet: Bool
  var onError: (String) -> Void

  @State private var assets: [Asset] = []

  var body: some View {
    Menu {
      if canCopy {
        Button("Copy") { copySelected() }
          .accessibilityIdentifier("select-action-copy")
      }
      if canHide {
        Button("Hide") {
          mutate {
            guard let mutations = session.assetMutations else { return }
            try await mutations.setHidden(ids: ids, isHidden: true)
          }
        }
        .accessibilityIdentifier("select-action-hide")
      }
      if canFavorite {
        Button("Favorite") {
          mutate {
            guard let mutations = session.assetMutations else { return }
            try await mutations.setFavorite(ids: ids, isFavorite: true)
          }
        }
        .accessibilityIdentifier("select-action-favorite")
      }
      if canEdit {
        Button("Add to Album…") { showAlbumPicker = true }
          .accessibilityIdentifier("select-action-add-to-album")
      }
      if canMove {
        Button("Move To…") { showMoveSheet = true }
          .accessibilityIdentifier("select-action-move-to")
      }
      if canEdit {
        Button("Archive") {
          mutate {
            guard let mutations = session.assetMutations else { return }
            try await mutations.setArchived(ids: ids, isArchived: true)
          }
        }
        .accessibilityIdentifier("select-action-archive")
      }
    } label: {
      Label("More actions", systemImage: "ellipsis")
    }
    .accessibilityIdentifier("select-more-menu")
    .task(id: selectedIds) {
      if let store = session.store {
        assets = (try? await store.assets(ids: ids)) ?? []
      }
    }
  }

  private var ids: [String] { Array(selectedIds) }

  private var ctx: AccessContext { session.access }

  private var canCopy: Bool {
    !assets.isEmpty && assets.allSatisfy { Permissions.hasContainerAccess($0.container, in: ctx) }
  }

  private var canHide: Bool {
    !assets.isEmpty && assets.allSatisfy { Permissions.canEdit($0, in: ctx) }
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

  /// Copies preview images to the pasteboard through the production image path
  /// (offline-safe: warmed caches serve fixture art). Capped so a 100+ selection
  /// can't spike memory; the cap is reported, not silent.
  private func copySelected() {
    Task {
      do {
        guard let store = session.store, let pipeline = session.pipeline else { return }
        var images: [UIImage] = []
        for id in ids.prefix(SelectMoreMenu.copyLimit) {
          guard let asset = try? await store.asset(id: id),
            let loaded = try? await pipeline.load(asset: asset, tier: .preview)
          else { continue }
          switch loaded.content {
          case .placeholder(let img): images.append(img)
          case .tier(_, let img, _): images.append(img)
          }
        }
        if !images.isEmpty {
          UIPasteboard.general.images = images
        }
      } catch {
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
        if !error.isCancellation { onError(error.localizedDescription) }
      }
    }
  }

  /// Pasteboard cap for Copy (memory safety on huge selections).
  static let copyLimit = 25
}
