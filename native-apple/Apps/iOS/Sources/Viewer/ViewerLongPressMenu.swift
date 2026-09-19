import CoreModel
import Rules
import SwiftUI
import UIKit

// MARK: - viewer long-press menu (WP-M, V6)

// V6: a long-press on the open photo is a documented no-op today. This is the
// action sheet it should present instead: preview plus the single-asset actions
// the viewer's own "…" menu (`ViewerMoreMenu`) already proves executable —
// Share, Favorite, Copy, Add to Album, Hide, Delete — with the same closure
// style, so `ViewerView` reuses its existing helpers (share/mutate/refresh)
// and no action logic is duplicated here.
//
// Like the grid menu: Delete is destructive-role behind a confirmation alert;
// automation asserts presence and never taps through it (§0.5).
// Identifiers (`viewer-context-*`) are owned by WP-M.

struct ViewerLongPressMenu: View {
  @Environment(\.dismiss) private var dismiss

  var asset: Asset
  var access: AccessContext
  var preview: UIImage? = nil
  var onShare: () -> Void
  var onFavorite: () -> Void
  var onCopy: () -> Void
  var onAddToAlbum: () -> Void
  var onHide: () -> Void
  var onTrash: () -> Void

  @State private var showDeleteConfirm = false

  var body: some View {
    VStack(spacing: 12) {
      if let preview {
        Image(uiImage: preview)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxHeight: 220)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .padding(.horizontal, 16)
      }
      VStack(spacing: 0) {
        if Permissions.hasContainerAccess(asset.container, in: access) {
          menuButton(id: "viewer-context-share", title: "Share", systemImage: "square.and.arrow.up") {
            dismiss()
            onShare()
          }
          menuButton(id: "viewer-context-copy", title: "Copy", systemImage: "doc.on.doc") {
            dismiss()
            onCopy()
          }
        }
        if Permissions.canFavorite(asset, in: access) {
          menuButton(
            id: "viewer-context-favorite",
            title: asset.isFavorite ? "Unfavorite" : "Favorite",
            systemImage: "heart"
          ) {
            dismiss()
            onFavorite()
          }
        }
        if Permissions.canEdit(asset, in: access) {
          menuButton(
            id: "viewer-context-add-to-album", title: "Add to Album",
            systemImage: "rectangle.stack.badge.plus"
          ) {
            dismiss()
            onAddToAlbum()
          }
          menuButton(
            id: "viewer-context-hide",
            title: asset.visibility == .hidden ? "Unhide" : "Hide",
            systemImage: "eye.slash"
          ) {
            dismiss()
            onHide()
          }
        }
        if Permissions.canDelete(asset, in: access) {
          menuButton(
            id: "viewer-context-delete", title: "Delete", systemImage: "trash",
            role: .destructive
          ) {
            showDeleteConfirm = true
          }
        }
      }
    }
    .padding(.vertical, 12)
    // Same AX contract as the grid menu: name the container but keep children
    // as separate elements, or the item ids below go invisible to XCUITest.
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("viewer-context-menu")
    .alert("Move this item to Trash?", isPresented: $showDeleteConfirm) {
      Button("Cancel", role: .cancel) {}
        .accessibilityIdentifier("viewer-context-delete-cancel")
      Button("Move to Trash", role: .destructive) {
        dismiss()
        onTrash()
      }
      .accessibilityIdentifier("viewer-context-delete-confirm")
    } message: {
      Text("This photo moves to Recently Deleted.")
    }
  }

  private func menuButton(
    id: String, title: String, systemImage: String,
    role: ButtonRole? = nil, action: @escaping () -> Void
  ) -> some View {
    Button(role: role, action: action) {
      Label(title, systemImage: systemImage)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    .accessibilityIdentifier(id)
  }
}
