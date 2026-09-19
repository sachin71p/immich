import AppKit

/// Viewer/grid context menu (V10, shared with WP-G by call only).
///
/// Photos' order is the contract: `ViewerContextMenuSpec.titles` is the
/// data-driven source of truth (tested in `Tests/Viewer/`); this builder turns
/// it into an `NSMenu` wired to explicit handlers. Rows Immich cannot do are
/// omitted — no disabled placeholders, except where Photos also disables.
/// VisionKit subject items merge at the top via the overlay's menu delegate.
struct ViewerMenuHandlers {
  var getInfo: (() -> Void)?
  var copy: (() -> Void)?
  var share: (() -> Void)?
  var makeAlbumCover: (() -> Void)?
  var showInAllPhotos: (() -> Void)?
  var rotateLeft: (() -> Void)?
  var rotateRight: (() -> Void)?
  var copyEdits: (() -> Void)?
  var pasteEdits: (() -> Void)?
  var revertToOriginal: (() -> Void)?
  var addTo: (() -> Void)?
  var addToAlbum: (() -> Void)?
  var editWith: (() -> Void)?
  var duplicate: (() -> Void)?
  var hide: (() -> Void)?
  var delete: (() -> Void)?
  var removeFromAlbum: (() -> Void)?
  var moveToLibrary: (() -> Void)?
  var favorite: (() -> Void)?
}

enum ViewerMenuBuilder {
  /// Builds the Photos-ordered menu for `ids` in `context`. Key equivalents
  /// match the app menus (single owner per shortcut).
  static func menu(
    for ids: [String],
    kind: ViewerContextMenuSpec.AssetKind,
    library: ViewerContextMenuSpec.Library = .personal,
    scope: ViewerContextMenuSpec.Scope = .library,
    context: ViewerContextMenuSpec.Context = .viewer,
    handlers: ViewerMenuHandlers = ViewerMenuHandlers()
  ) -> NSMenu {
    let menu = NSMenu()
    // (title, handler, keyEquivalent, modifiers). Keys match the app menus —
    // menus own every shortcut, so nothing double-fires.
    let rows: [(String, (() -> Void)?, String, NSEvent.ModifierFlags)] = [
      ("Get Info", handlers.getInfo, "i", .command),
      ("Copy", handlers.copy, "", []),
      ("Share…", handlers.share, "", []),
      ("Make Album Cover", handlers.makeAlbumCover, "", []),
      ("Show in All Photos", handlers.showInAllPhotos, "", []),
      ("Rotate Left", handlers.rotateLeft, "", []),
      ("Rotate Right", handlers.rotateRight, "", []),
      ("Copy Edits", handlers.copyEdits, "", []),
      ("Paste Edits", handlers.pasteEdits, "", []),
      ("Revert to Original", handlers.revertToOriginal, "", []),
      ("Add to", handlers.addTo, "", []),
      ("Add to Album", handlers.addToAlbum, "", []),
      ("Edit With", handlers.editWith, "", []),
      ("Duplicate", handlers.duplicate, "", []),
      ("Hide", handlers.hide, "", []),
      ("Delete", handlers.delete, "\u{8}", .command),
      ("Remove from Album", handlers.removeFromAlbum, "", []),
      ("Move to Library", handlers.moveToLibrary, "", []),
    ]
    let wanted = Set(
      ViewerContextMenuSpec.titles(kind: kind, library: library, scope: scope))
    for (title, handler, key, modifiers) in rows where wanted.contains(title) {
      // No handler: omit the row (no disabled placeholders, V10).
      guard let handler else { continue }
      let item = NSMenuItem(
        title: title, action: #selector(MenuTarget.perform(_:)), keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      // `target` is weak: `representedObject` retains the target.
      item.target = MenuTarget(handler: handler)
      item.representedObject = item.target
      menu.addItem(item)
    }
    return menu
  }

  @objc
  private final class MenuTarget: NSObject {
    let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
    @objc func perform(_ sender: Any?) { handler() }
  }
}
