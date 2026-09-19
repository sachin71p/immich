import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI
import UIKit

// MARK: - grid long-press menu (WP-M, G4)

// Photos' grid-cell long-press: preview + Copy/Duplicate/Hide, Share, Favorite,
// Add To, Adjust Info, Delete, Ask Siri (PLAN §1 G4). What this menu can offer is
// bounded by what `AssetMutations` can execute:
//
// - Offered: Copy (pasteboard, offline-safe preview tier), Hide/Unhide, Share
//   (activity sheet), Favorite/Unfavorite, Add To (album picker), Delete (trash
//   behind a confirmation — §0.5: present, never auto-tapped by tests).
// - Omitted, no dead buttons: Duplicate and Adjust Info — `AssetMutations`
//   exposes neither operation and the server has no asset-duplicate endpoint
//   (same precedent as `SelectMoreMenu`, which omits both for the same reason);
//   Ask Siri — no Siri integration exists. If those backends land, add cases to
//   `GridContextMenuAction` and they flow into the sheet below.
//
// Gating mirrors the select-mode surfaces: `Rules.Permissions` decides;
// unavailable actions hide, never offered-then-rejected.

/// The feasible G4 action set. Raw values are the accessibility identifiers the
/// red-first test asserts (`ContextMenuUITests`), owned by WP-M.
enum GridContextMenuAction: String, CaseIterable, Sendable {
  case copy = "grid-context-copy"
  case hide = "grid-context-hide"
  case share = "grid-context-share"
  case favorite = "grid-context-favorite"
  case addTo = "grid-context-addto"
  case delete = "grid-context-delete"

  var title: String {
    switch self {
    case .copy: return "Copy"
    case .hide: return "Hide"
    case .share: return "Share"
    case .favorite: return "Favorite"
    case .addTo: return "Add to Album"
    case .delete: return "Delete"
    }
  }

  var systemImage: String {
    switch self {
    case .copy: return "doc.on.doc"
    case .hide: return "eye.slash"
    case .share: return "square.and.arrow.up"
    case .favorite: return "heart"
    case .addTo: return "rectangle.stack.badge.plus"
    case .delete: return "trash"
    }
  }
}

/// Pure, permission-gated action list — the unit of logic the sheet renders.
/// `isHidden`/`isFavorite` flip Hide→Unhide / Favorite→Unfavorite titles.
enum GridContextMenuModel {
  static func actions(for asset: Asset, in access: AccessContext) -> [GridContextMenuAction] {
    var out: [GridContextMenuAction] = []
    if Permissions.hasContainerAccess(asset.container, in: access) {
      out.append(.copy)
    }
    if Permissions.canEdit(asset, in: access) {
      out.append(.hide)
    }
    if Permissions.hasContainerAccess(asset.container, in: access) {
      out.append(.share)
    }
    if Permissions.canFavorite(asset, in: access) {
      out.append(.favorite)
    }
    if Permissions.canEdit(asset, in: access) {
      out.append(.addTo)
    }
    if Permissions.canDelete(asset, in: access) {
      out.append(.delete)
    }
    return out
  }

  static func title(for action: GridContextMenuAction, asset: Asset) -> String {
    switch action {
    case .hide: return asset.visibility == .hidden ? "Unhide" : "Hide"
    case .favorite: return asset.isFavorite ? "Unfavorite" : "Favorite"
    default: return action.title
    }
  }
}

/// Sheet content for a grid long-press: preview over the permission-gated action
/// list. Loads its own asset from the session store (the presenter only passes
/// the id plus an optional preview seed), so the root identifier exists even
/// before the load lands. Delete is destructive-role behind a confirmation
/// alert; automation asserts presence and never taps through it (§0.5).
struct GridContextMenuSheet: View {
  @EnvironmentObject var session: AppSession
  @Environment(\.dismiss) private var dismiss

  var assetId: String
  var preview: UIImage? = nil

  @State private var asset: Asset?
  @State private var image: UIImage?
  @State private var actionError: String?
  @State private var showDeleteConfirm = false
  @State private var showAlbumPicker = false

  var body: some View {
    VStack(spacing: 12) {
      previewView
      if let asset {
        actionList(asset)
      } else {
        ProgressView()
          .tint(.secondary)
          .accessibilityIdentifier("grid-context-loading")
      }
    }
    .padding(.vertical, 12)
    // NARROW AX CONTRACT: the identifier names the menu, but the container
    // must expose its children as separate elements — without `.contain`,
    // SwiftUI merges the whole VStack into one AX node and the per-action
    // identifiers below become invisible to XCUITest (seen on G4: the root
    // matched while every item id missed).
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("grid-context-menu")
    .task(id: assetId) { await load() }
    .alert("Move this item to Trash?", isPresented: $showDeleteConfirm) {
      Button("Cancel", role: .cancel) {}
        .accessibilityIdentifier("grid-context-delete-cancel")
      Button("Move to Trash", role: .destructive) { trash() }
        .accessibilityIdentifier("grid-context-delete-confirm")
    } message: {
      Text("This photo moves to Recently Deleted.")
    }
    .alert("Action failed", isPresented: Binding(
      get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    ) {
      Button("OK") { actionError = nil }
    } message: {
      Text(actionError ?? "")
    }
    .sheet(isPresented: $showAlbumPicker) {
      AlbumPickerSheet(assetIds: [assetId])
        .environmentObject(session)
    }
  }

  private var previewView: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxHeight: 220)
          .clipShape(RoundedRectangle(cornerRadius: 12))
      } else {
        RoundedRectangle(cornerRadius: 12)
          .fill(.quaternary)
          .frame(height: 160)
      }
    }
    .padding(.horizontal, 16)
  }

  private func actionList(_ asset: Asset) -> some View {
    VStack(spacing: 0) {
      ForEach(GridContextMenuModel.actions(for: asset, in: session.access), id: \.rawValue) { action in
        Button(role: action == .delete ? .destructive : nil) {
          run(action, asset: asset)
        } label: {
          Label(GridContextMenuModel.title(for: action, asset: asset), systemImage: action.systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .accessibilityIdentifier(action.rawValue)
      }
    }
  }

  private func run(_ action: GridContextMenuAction, asset: Asset) {
    switch action {
    case .copy: copyAsset(asset)
    case .hide:
      mutate {
        guard let mutations = session.assetMutations else { return }
        try await mutations.setHidden(ids: [asset.id], isHidden: asset.visibility != .hidden)
      }
    case .share: share(asset)
    case .favorite:
      mutate {
        guard let mutations = session.assetMutations else { return }
        try await mutations.setFavorite(ids: [asset.id], isFavorite: !asset.isFavorite)
      }
    case .addTo: showAlbumPicker = true
    case .delete: showDeleteConfirm = true
    }
  }

  private func load() async {
    image = preview
    guard let store = session.store else { return }
    guard let loaded = try? await store.asset(id: assetId) else { return }
    asset = loaded
    if image == nil, let pipeline = session.pipeline {
      if let cg = pipeline.cachedImage(id: assetId, tier: .preview) {
        image = UIImage(cgImage: cg)
      } else if let result = try? await pipeline.load(asset: loaded, tier: .preview) {
        switch result.content {
        case .placeholder(let img), .tier(_, let img, _): image = img
        }
      }
    }
  }

  /// Single-asset copy through the production image path (offline-safe: warmed
  /// caches serve fixture art — same pattern as `SelectMoreMenu.copySelected`).
  private func copyAsset(_ asset: Asset) {
    Task {
      guard let store = session.store, let pipeline = session.pipeline,
        let loaded = try? await store.asset(id: asset.id),
        let result = try? await pipeline.load(asset: loaded, tier: .preview)
      else { return }
      switch result.content {
      case .placeholder(let img), .tier(_, let img, _):
        UIPasteboard.general.images = [img]
      }
    }
  }

  private func trash() {
    mutate {
      guard let mutations = session.assetMutations else { return }
      try await mutations.trash(ids: [assetId])
    }
  }

  private func share(_ asset: Asset) {
    Task {
      guard let base = session.apiBaseURL,
        let token = await session.bearerToken(),
        let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene }).first?.windows.first
      else { return }
      do {
        var request = URLRequest(
          url: MediaEndpoint(serverURL: base, assetID: asset.id).originalURL())
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(asset.originalFileName)
        try data.write(to: tmp)
        let activity = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
          popover.sourceView = window
        }
        window.rootViewController?.present(activity, animated: true)
      } catch {
        if !error.isCancellation { actionError = error.localizedDescription }
      }
    }
  }

  private func mutate(_ work: @escaping () async throws -> Void) {
    Task {
      do {
        try await work()
        try await session.refresh()
        dismiss()
      } catch {
        if !error.isCancellation { actionError = error.localizedDescription }
      }
    }
  }
}
