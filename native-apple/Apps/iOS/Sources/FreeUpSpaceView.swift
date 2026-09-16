import CoreModel
import LocalStore
import Media
import Photos
import SyncEngine
import SwiftUI

// MARK: - Free Up Space (A6, upstream R14 parity)

// Cutoff date, keep favorites (default on), keep selected albums, keep-last-N-days.
// Candidates are verified against the server at deletion time (batched bulk-check, never
// local-DB-only); the preview shows counts + bytes, deletion runs in batches with the
// system confirmation, and afterwards the Recently Deleted explainer offers a Photos link.
struct FreeUpSpaceView: View {
  @EnvironmentObject var session: AppSession
  @State private var storage = StoragePrefs()
  @State private var cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
  @State private var useCutoffDate = false
  @State private var keepLastNDays = 30
  @State private var useAgeWindow = true
  @State private var albums: [PhotoKitBackupScanner.Album] = []
  @State private var phase: Phase = .options
  @State private var candidates: [DevicePhoto] = []
  @State private var skippedUnmatched = 0
  @State private var error: String?

  enum Phase: Sendable, Hashable {
    case options
    case working(String)
    case preview
    case deleting(deleted: Int, total: Int)
    case done(deleted: Int)
  }

  var body: some View {
    List {
      switch phase {
      case .options:
        optionsSection
        Button("Check What's Backed Up") { Task { await runCheck() } }
          .accessibilityIdentifier("freeup-check")
      case .working(let status):
        Section { ProgressView(status) }
      case .preview:
        previewSection
      case .deleting(let deleted, let total):
        Section {
          ProgressView("Deleting \(deleted) of \(total)…")
        }
      case .done(let deleted):
        doneSection(deleted: deleted)
      }
      if let error {
        Section { Text(error).foregroundStyle(.red).font(.caption) }
      }
    }
    .navigationTitle("Free Up Space")
    .task {
      albums = PhotoKitBackupScanner.availableAlbums()
      await loadStorage()
    }
  }

  // MARK: - options

  private var optionsSection: some View {
    Group {
      Section("Which Photos") {
        Toggle("Keep favorites", isOn: $storage.keepFavoritesOnFreeUp)
          .accessibilityIdentifier("freeup-keep-favorites")
        Toggle("Only older than a date", isOn: $useCutoffDate)
        if useCutoffDate {
          DatePicker("Taken before", selection: $cutoffDate, displayedComponents: .date)
        }
        Toggle("Keep last N days", isOn: $useAgeWindow)
        if useAgeWindow {
          Stepper("Keep last \(keepLastNDays) days", value: $keepLastNDays, in: 1...365)
        }
      }
      Section("Keep Albums") {
        if albums.isEmpty {
          Text("No device albums found.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        ForEach(albums, id: \.id) { album in
          Button {
            toggleKeepAlbum(album.id)
          } label: {
            HStack {
              Text(album.title)
              Spacer()
              if storage.freeUpKeepAlbumIds.contains(album.id) {
                Image(systemName: "checkmark")
              }
            }
          }
          .accessibilityIdentifier("freeup-keep-album-\(album.id)")
        }
      }
      Section {
        Toggle(
          "Suggest after each backup",
          isOn: Binding(
            get: { storage.suggestFreeUpAfterBackup },
            set: { value in
              storage.suggestFreeUpAfterBackup = value
              Task { await saveStorage() }
            }))
          .accessibilityIdentifier("freeup-suggest-after-backup")
        Text("Deletion is never automatic — after a backup finishes you get a prompt.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - preview / delete

  private var previewSection: some View {
    Group {
      Section("Ready to Delete") {
        let (count, bytes) = FreeUpSpacePlanner.preview(candidates)
        LabeledContent("Photos", value: "\(count)")
        LabeledContent("About to free", value: Self.formatBytes(bytes))
        if skippedUnmatched > 0 {
          Text("\(skippedUnmatched) device photos couldn't be matched to an upload and were skipped.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text("Only photos the server just confirmed as backed up (not trashed) are listed.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section {
        Button("Delete from This iPhone", role: .destructive) {
          Task { await runDelete() }
        }
        .accessibilityIdentifier("freeup-delete")
        Button("Back to Options") { phase = .options }
      }
    }
  }

  private func doneSection(deleted: Int) -> some View {
    Group {
      Section {
        Text("Deleted \(deleted) photos from this iPhone. The server copies are untouched.")
        Text("iOS keeps deleted photos in Recently Deleted for 30 days — empty it there to reclaim the space now.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section {
        Button("Open Photos…") { openRecentlyDeleted() }
          .accessibilityIdentifier("freeup-open-photos")
          .disabled(!canOpenRecentlyDeleted)
        Button("Done") { phase = .options }
      }
    }
  }

  // MARK: - pipeline

  private var effectiveOptions: FreeUpSpaceOptions {
    FreeUpSpaceOptions(
      cutoffDate: useCutoffDate ? cutoffDate : nil,
      keepFavorites: storage.keepFavoritesOnFreeUp,
      keepAlbumIds: Set(storage.freeUpKeepAlbumIds),
      keepLastNDays: useAgeWindow ? keepLastNDays : nil
    )
  }

  private func runCheck() async {
    error = nil
    guard let store = session.store, let connection = session.connection else {
      error = "Sign in first."
      return
    }
    guard await PhotoKitBackupScanner.requestAccess() else {
      error = "Photos access is required to list device photos."
      return
    }
    await saveStorage()
    phase = .working("Listing device photos…")
    do {
      let devicePhotos = await scanDevicePhotos(store: store)
      guard !devicePhotos.isEmpty else {
        error = "No device photos matched an upload — back up first."
        phase = .options
        return
      }
      phase = .working("Verifying with the server…")
      let verifier = ServerChecksumVerifier(connection: connection)
      let backed = try await verifier.verified(checksums: devicePhotos.map(\.checksum))
      candidates = FreeUpSpacePlanner.selectCandidates(
        photos: devicePhotos, backedUpChecksums: backed, options: effectiveOptions)
      phase = .preview
    } catch {
      self.error = error.localizedDescription
      phase = .options
    }
  }

  /// Device photos with a locally-known upload checksum (+ server-known byte size).
  /// Photos that never uploaded through this app have no checksum row and are counted
  /// as skipped rather than hashed on-device.
  private func scanDevicePhotos(store: PhotosLocalStore) async -> [DevicePhoto] {
    let checksums = (try? await store.checksumByLocalIdentifier()) ?? [:]
    let sizes = (try? await store.fileSizeByLocalIdentifier()) ?? [:]
    let keepAlbumMembers = keepAlbumMemberIdentifiers()
    var out: [DevicePhoto] = []
    var skipped = 0
    let fetchOptions: PHFetchOptions? = nil
    let fetch = PHAsset.fetchAssets(with: fetchOptions)
    for index in 0..<fetch.count {
      let asset = fetch.object(at: index)
      guard let checksum = checksums[asset.localIdentifier] else {
        skipped += 1
        continue
      }
      var albumIds: Set<String> = []
      for (albumId, members) in keepAlbumMembers where members.contains(asset.localIdentifier) {
        albumIds.insert(albumId)
      }
      out.append(
        DevicePhoto(
          localIdentifier: asset.localIdentifier,
          checksum: checksum,
          creationDate: asset.creationDate,
          isFavorite: asset.isFavorite,
          albumIds: albumIds,
          estimatedBytes: sizes[asset.localIdentifier] ?? 0
        ))
    }
    skippedUnmatched = skipped
    return out
  }

  private func keepAlbumMemberIdentifiers() -> [String: Set<String>] {
    var map: [String: Set<String>] = [:]
    for albumId in storage.freeUpKeepAlbumIds {
      let collections = PHAssetCollection.fetchAssetCollections(
        withLocalIdentifiers: [albumId], options: nil)
      guard let collection = collections.firstObject else { continue }
      var members = Set<String>()
      let assets = PHAsset.fetchAssets(in: collection, options: nil)
      for index in 0..<assets.count {
        members.insert(assets.object(at: index).localIdentifier)
      }
      map[albumId] = members
    }
    return map
  }

  private func runDelete() async {
    error = nil
    let total = candidates.count
    var deleted = 0
    phase = .deleting(deleted: 0, total: total)
    do {
      for batch in FreeUpSpacePlanner.batches(candidates) {
        let ids = batch.map(\.localIdentifier)
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        try await PHPhotoLibrary.shared().performChanges {
          PHAssetChangeRequest.deleteAssets(fetch as NSFastEnumeration)
        }
        deleted += batch.count
        phase = .deleting(deleted: deleted, total: total)
      }
      candidates = []
      phase = .done(deleted: deleted)
    } catch {
      self.error = error.localizedDescription
      phase = .preview
    }
  }

  // MARK: - Recently Deleted link

  private var canOpenRecentlyDeleted: Bool {
    guard let url = URL(string: FreeUpSpaceLinks.recentlyDeletedAlbum) else { return false }
    #if canImport(UIKit)
    return UIApplication.shared.canOpenURL(url)
    #else
    return false
    #endif
  }

  private func openRecentlyDeleted() {
    guard let url = URL(string: FreeUpSpaceLinks.recentlyDeletedAlbum) else { return }
    #if canImport(UIKit)
    if UIApplication.shared.canOpenURL(url) {
      UIApplication.shared.open(url)
    } else {
      error = "Open the Photos app's Recently Deleted album to reclaim the space."
    }
    #endif
  }

  // MARK: - storage prefs

  private func loadStorage() async {
    guard let store = session.store else { return }
    storage = (try? await store.storagePrefs(for: session.userId)) ?? StoragePrefs()
    if let n = storage.freeUpKeepLastNDays {
      keepLastNDays = n
      useAgeWindow = true
    } else {
      useAgeWindow = false
    }
  }

  private func saveStorage() async {
    guard let store = session.store else { return }
    storage.freeUpKeepLastNDays = useAgeWindow ? keepLastNDays : nil
    try? await store.setStoragePrefs(storage, for: session.userId)
  }

  private func toggleKeepAlbum(_ id: String) {
    if storage.freeUpKeepAlbumIds.contains(id) {
      storage.freeUpKeepAlbumIds.removeAll { $0 == id }
    } else {
      storage.freeUpKeepAlbumIds.append(id)
    }
    Task { await saveStorage() }
  }

  static func formatBytes(_ bytes: Int) -> String {
    let mb = Double(bytes) / 1_000_000
    if mb < 1000 { return String(format: "%.1f MB", mb) }
    return String(format: "%.2f GB", mb / 1000)
  }
}

// MARK: - post-backup prompt (explicit UI, never silent deletion)

/// Presented after a backup batch when `suggestFreeUpAfterBackup` is on: an explicit
/// prompt offering to open Free Up Space. Wired from the backup settings' "Back Up Now".
struct FreeUpSpacePromptModifier: ViewModifier {
  @EnvironmentObject var session: AppSession
  @Binding var isPresented: Bool
  @State private var showSheet = false

  func body(content: Content) -> some View {
    content
      .alert("Backup finished", isPresented: $isPresented) {
        Button("Free Up Space…") { showSheet = true }
        Button("Not Now", role: .cancel) {}
      } message: {
        Text("Your photos are backed up. Review what can be safely deleted from this iPhone?")
      }
      .sheet(isPresented: $showSheet) {
        NavigationStack {
          FreeUpSpaceView()
            .environmentObject(session)
        }
      }
  }
}
