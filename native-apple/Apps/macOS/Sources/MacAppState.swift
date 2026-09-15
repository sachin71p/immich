import CoreModel
import Foundation
import ImmichAPI
import Security
import LocalStore
import Media
import Rules
import SyncEngine
import SwiftUI

/// Shared observable state for the macOS shell. Thin over PhotosCore: the local DB is the UI's
/// only data source (A0 Architecture); every mutation goes through the SyncEngine `*Mutations`
/// types first (same Core calls as iOS — brief task 6) and the grid re-reads the store.
@MainActor
@Observable
final class MacAppState {
  var serverURL: URL
  var userId: String?
  var isConnected: Bool { userId != nil }

  var store: PhotosLocalStore
  var connection: ImmichConnection
  var sync: SyncCoordinator
  var pipeline: MediaPipeline
  var diskCache: TieredMediaCache

  var prefs = SharedLibraryPrefs()
  var spaces: [(space: Space, role: SharedSpaceRoleKind)] = []
  var libraries: [(library: Library, isOwner: Bool)] = []
  var albums: [Album] = []
  var lastSyncError: String?
  var isSyncing = false

  /// Import-drop staging (brief task 5): picked files wait here for a destination-library choice.
  /// A5 wires the upload queue; this phase owns only the UI + chooser.
  var pendingImportURLs: [URL] = []
  var showingImportChooser = false

  /// Row ids backing viewer paging (set when the viewer opens).
  var viewerContext: [String] = []

  private init(serverURL: URL, token: String?, store: PhotosLocalStore) throws {
    let connection = try ImmichConnection(serverURL: serverURL, accessToken: token)
    let diskCache = TieredMediaCache(
      rootDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PhotosFork/Media", isDirectory: true)
    )
    let tokenStore = connection.tokenStore
    let server = MediaServer(
      baseURL: serverURL,
      tokenProvider: { @Sendable in await tokenStore.get() }
    )

    self.serverURL = serverURL
    self.store = store
    self.connection = connection
    sync = SyncCoordinator(connection: connection, localStore: store)
    self.diskCache = diskCache
    pipeline = MediaPipeline.makeDefault(diskCache: diskCache, server: server)
  }

  /// Normal launch: file-backed DB in Application Support, token from the Keychain.
  static func standard(serverURL: URL) throws -> MacAppState {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("PhotosFork", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try PhotosLocalStore(path: dir.appendingPathComponent("photos.sqlite").path)
    return try MacAppState(serverURL: serverURL, token: MacKeychain.loadToken(), store: store)
  }

  /// UI-smoke launch (`--fixture-seed`): in-memory store seeded through the public `apply()`
  /// path — no server, no Keychain. The committed XCUITest drives this mode.
  static func seeded() throws -> MacAppState {
    let store = try PhotosLocalStore(inMemory: true)
    let state = try MacAppState(
      serverURL: URL(string: "https://fixture.invalid")!, token: nil as String?, store: store
    )
    state.userId = FixtureSeed.userId
    return state
  }

  func seedForSmoke() async throws {
    try await store.apply(FixtureSeed.changes(), currentUserId: FixtureSeed.userId)
    // Mirror the hydrated `getLibrary` state (A1): the Archive library accepts uploads,
    // so DECISIONS §6 rule 4 offers it as a move target in the seeded world.
    try await store.setLibraryUploadPath(libraryId: FixtureSeed.libraryId, uploadPath: "/import/archive")
    await refresh()
  }

  func completeLogin(serverURL: URL, token: String) async throws {
    self.serverURL = serverURL
    await connection.tokenStore.set(token)
    try SharedTokenStore.save(token)
    UserDefaults.standard.set(serverURL.absoluteString, forKey: "PhotosFork.serverURL")
    userId = try await connection.currentUserId()
    await refresh()
  }

  /// Relaunch: a Keychain token from a previous session restores the user without
  /// showing the connect screen (network failure just leaves the connect screen up).
  func adoptKeychainSession() async {
    guard userId == nil else { return }
    if await connection.tokenStore.get() == nil { return }
    if let id = try? await connection.currentUserId() {
      userId = id
      await refresh()
    }
  }

  func logout() async {
    await connection.tokenStore.set(nil)
    UserDefaults.standard.removeObject(forKey: "PhotosFork.serverURL")
    userId = nil
    spaces = []
    libraries = []
    albums = []
  }

  func refresh() async {
    guard let userId else { return }
    do {
      prefs = try await store.prefs(for: userId)
      async let s = store.memberSpaces(for: userId)
      async let l = store.accessibleLibraries(for: userId)
      async let a = store.memberAlbums(for: userId)
      spaces = try await s
      libraries = try await l
      albums = try await a
    } catch {
      lastSyncError = error.localizedDescription
    }
  }

  func syncNow() async {
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }
    do {
      _ = try await sync.syncNow()
      await refresh()
    } catch {
      lastSyncError = error.localizedDescription
    }
  }

  // MARK: - Mutations (same Core calls as iOS)

  func assetMutations() -> AssetMutations { AssetMutations(connection: connection, localStore: store) }
  func spaceMutations() -> SpaceMutations { SpaceMutations(connection: connection, localStore: store) }
  func albumMutations() -> AlbumMutations { AlbumMutations(connection: connection, localStore: store) }
  func prefsMutations() -> PrefsMutations { PrefsMutations(connection: connection, localStore: store) }

  /// Stack/live-photo group expansion for a move/trash selection — DECISIONS §6 rule 5 (I3).
  func expandGroups(ids: [String]) async throws -> [[Asset]] {
    let assets = try await store.assets(ids: ids)
    var groups: [[Asset]] = []
    var seenStacks = Set<String>()
    for asset in assets {
      if let stackId = asset.stackId {
        guard !seenStacks.contains(stackId) else { continue }
        seenStacks.insert(stackId)
        groups.append(try await store.stackMembers(stackId: stackId))
      } else if let liveId = asset.livePhotoVideoId {
        var group = [asset]
        group += try await store.assets(ids: [liveId])
        groups.append(group)
      } else {
        groups.append([asset])
      }
    }
    return groups
  }
}

enum MacKeychain {
  /// Read-only mirror of the Keychain item `SharedTokenStore` (Apps/Shared) writes.
  static func loadToken() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.immich.photosfork",
      kSecAttrAccount as String: "access-token",
      kSecReturnData as String: true,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
