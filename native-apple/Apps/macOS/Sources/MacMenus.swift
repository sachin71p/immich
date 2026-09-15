import SwiftUI

/// The asset action set the key window's focused view provides. The grid publishes
/// selection-based actions; the viewer publishes current-asset actions. Menus own every
/// shortcut (brief task 4), so nothing double-fires.
struct MacAssetActions {
  var favorite: () -> Void
  var rotate: () -> Void
  var trash: () -> Void
  var move: () -> Void
  var addToAlbum: () -> Void
  var toggleInspector: () -> Void
  var openViewer: () -> Void
  var preview: () -> Void
}

extension FocusedValues {
  @Entry var macAssetActions: MacAssetActions?
}

extension Notification.Name {
  static let macSelectAll = Notification.Name("PhotosFork.MacSelectAll")
  static let macSyncNow = Notification.Name("PhotosFork.MacSyncNow")
}

/// Photos-for-Mac menu conventions (brief task 4): File / Edit / Image / View / Window.
struct MacCommands: Commands {
  @FocusedValue(\.macAssetActions) private var actions
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Library Window") { openWindow(value: MacWindow.library) }
        .keyboardShortcut("n", modifiers: [.command, .shift])
      Button("New Viewer Window") { actions?.openViewer() }
        .disabled(actions == nil)
    }
    CommandGroup(after: .newItem) {
      Button("Import Files…") {
        NotificationCenter.default.post(name: .macImportFiles, object: nil)
      }
      .keyboardShortcut("o", modifiers: .command)
    }
    CommandMenu("Image") {
      Button("Favorite") { actions?.favorite() }
        .keyboardShortcut(".", modifiers: [])
        .disabled(actions == nil)
      Button("Rotate Clockwise") { actions?.rotate() }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(actions == nil)
      Divider()
      Button("Add to Album…") { actions?.addToAlbum() }
        .disabled(actions == nil)
      Button("Move to…") { actions?.move() }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .disabled(actions == nil)
      Divider()
      Button("Delete") { actions?.trash() }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(actions == nil)
    }
    CommandMenu("View") {
      Button("Show Info") { actions?.toggleInspector() }
        .keyboardShortcut("i", modifiers: .command)
        .disabled(actions == nil)
      Divider()
      Button("Select All") {
        NotificationCenter.default.post(name: .macSelectAll, object: nil)
      }
      .keyboardShortcut("a", modifiers: .command)
      Button("Quick Look Preview") { actions?.preview() }
        .keyboardShortcut(" ", modifiers: [])
        .disabled(actions == nil)
    }
    CommandGroup(after: .windowList) {
      Button("Sync Now") {
        NotificationCenter.default.post(name: .macSyncNow, object: nil)
      }
      .keyboardShortcut("s", modifiers: [.command, .option])
    }
  }
}

extension Notification.Name {
  static let macImportFiles = Notification.Name("PhotosFork.MacImportFiles")
}
