import CoreModel
import LocalStore
import SwiftUI

// MARK: - Backup settings (A5 brief task 5: on/off, albums, destination rules, network rules, status)

/// Backup on/off, album selection, destination + network rules, queue status, Back Up Now.
struct BackupSettingsSection: View {
  @EnvironmentObject var session: AppSession
  @State private var albums: [PhotoKitBackupScanner.Album] = []
  @State private var pendingCount = 0
  @State private var isBackingUp = false
  @State private var showFreeUpPrompt = false
  @State private var error: String?

  var body: some View {
    Section("Backup") {
      Toggle(
        "Back Up Photos",
        isOn: Binding(
          get: { session.prefs.backupEnabled },
          set: { new in setPrefs { $0.backupEnabled = new } }
        )
      )
      .accessibilityIdentifier("backup-enabled")
      if session.prefs.backupEnabled {
        NavigationLink("Albums (\(session.prefs.backupAlbumIds.count) selected)") {
          BackupAlbumPicker(albums: albums, session: session)
        }
        .accessibilityIdentifier("backup-albums")
        Toggle(
          "Also upload current edits",
          isOn: Binding(
            get: { session.prefs.uploadOriginalPlusEdit },
            set: { new in setPrefs { $0.uploadOriginalPlusEdit = new } }
          )
        )
        .accessibilityIdentifier("backup-original-plus-edit")
        Toggle(
          "Use cellular for photos",
          isOn: Binding(
            get: { session.prefs.useCellularForPhotos },
            set: { new in setPrefs { $0.useCellularForPhotos = new } }
          )
        )
        Toggle(
          "Use cellular for videos",
          isOn: Binding(
            get: { session.prefs.useCellularForVideos },
            set: { new in setPrefs { $0.useCellularForVideos = new } }
          )
        )
        Toggle(
          "Upload in Low Power Mode",
          isOn: Binding(
            get: { session.prefs.allowLowPowerUploads },
            set: { new in setPrefs { $0.allowLowPowerUploads = new } }
          )
        )
        if PhotoKitBackupScanner.isLimitedAccess() {
          Button("Choose More Photos…") {
            PhotoKitBackupScanner.presentLimitedLibraryPicker()
          }
        }
        LabeledContent("Pending uploads", value: "\(pendingCount)")
          .accessibilityIdentifier("backup-pending-count")
        Button(isBackingUp ? "Backing Up…" : "Back Up Now") {
          Task { await runBackupNow() }
        }
        .disabled(isBackingUp)
        .accessibilityIdentifier("backup-now")
      }
      if let error {
        Text(error).foregroundStyle(.red).font(.caption)
      }
    }
    .task {
      albums = PhotoKitBackupScanner.availableAlbums()
      await refreshCount()
    }
    .modifier(FreeUpSpacePromptModifier(isPresented: $showFreeUpPrompt))
  }

  private func setPrefs(_ edit: (inout SharedLibraryPrefs) -> Void) {
    var prefs = session.prefs
    edit(&prefs)
    Task {
      do {
        // A5 prefs persist locally only (the server prefs slice carries no backup keys).
        if let store = session.store {
          try await store.setPrefs(prefs, for: session.userId)
        }
        session.prefs = prefs
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func refreshCount() async {
    pendingCount = (try? await session.store?.pendingUploadCount()) ?? 0
  }

  private func runBackupNow() async {
    isBackingUp = true
    defer { isBackingUp = false }
    await BackupScheduler.runBackup(session: session)
    await refreshCount()
    // A6: explicit prompt only (never silent deletion).
    if let store = session.store,
      let storage = try? await store.storagePrefs(for: session.userId),
      storage.suggestFreeUpAfterBackup
    {
      showFreeUpPrompt = true
    }
  }
}

/// Album multi-select bound to `prefs.backupAlbumIds`. Empty selection = camera-roll equivalent.
struct BackupAlbumPicker: View {
  var albums: [PhotoKitBackupScanner.Album]
  @ObservedObject var session: AppSession

  var body: some View {
    List(albums, id: \.id) { album in
      Button {
        toggle(album.id)
      } label: {
        HStack {
          VStack(alignment: .leading) {
            Text(album.title)
            Text("\(album.count) items").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          if session.prefs.backupAlbumIds.contains(album.id) {
            Image(systemName: "checkmark")
          }
        }
      }
      .accessibilityIdentifier("backup-album-\(album.id)")
    }
    .navigationTitle("Backup Albums")
  }

  private func toggle(_ id: String) {
    var prefs = session.prefs
    if prefs.backupAlbumIds.contains(id) {
      prefs.backupAlbumIds.removeAll { $0 == id }
    } else {
      prefs.backupAlbumIds.append(id)
    }
    Task {
      if let store = session.store {
        try? await store.setPrefs(prefs, for: session.userId)
      }
      session.prefs = prefs
    }
  }
}
