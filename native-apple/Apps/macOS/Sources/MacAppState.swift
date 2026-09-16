import CoreModel
import Foundation
import ImmichAPI
import Security
import LocalStore
import Media
import Rules
import SyncEngine
import SwiftUI
import Upload

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
  var uploadQueue: UploadQueue
  var pipeline: MediaPipeline
  var diskCache: TieredMediaCache

  var prefs = SharedLibraryPrefs()
  var spaces: [(space: Space, role: SharedSpaceRoleKind)] = []
  var libraries: [(library: Library, isOwner: Bool)] = []
  var albums: [(album: Album, role: AlbumUserRoleKind, isShared: Bool)] = []
  var cameras: [CameraModel] = []
  var cameraCategories: [CameraCategory] = []
  var lastSyncError: String?
  /// A completed stream is the strongest signal the sync protocol exposes.  It is deliberately
  /// not presented as "up to date": the server does not expose a remote asset total for us to
  /// verify against the local database.
  var lastCompletedSyncAt: Date?
  var isSyncing = false

  /// Import-drop staging (brief task 5): picked files wait here for a destination-library choice.
  /// A5 wires the upload queue; this phase owns only the UI + chooser.
  var pendingImportURLs: [URL] = []
  var showingImportChooser = false
  var showingCameraImport = false

  /// Row ids backing viewer paging (set when the viewer opens).
  var viewerContext: [String] = []

  /// Connection, sync, upload queue and media pipeline all key off `serverURL`+token, so a
  /// server switch (fresh init, or a successful login to a different host in `completeLogin`)
  /// rebuilds every one of them together — reusing only `store` and `diskCache`, which don't.
  private struct ConnectionState {
    let serverURL: URL
    let connection: ImmichConnection
    let sync: SyncCoordinator
    let uploadQueue: UploadQueue
    let pipeline: MediaPipeline
  }

  private static func makeConnectionState(
    serverURL: URL, token: String?, store: PhotosLocalStore, diskCache: TieredMediaCache
  ) throws -> ConnectionState {
    let connection = try ImmichConnection(serverURL: serverURL, accessToken: token)
    let tokenStore = connection.tokenStore
    // `connection.serverURL` is `serverURL` normalized to include the `/api` base (see
    // ImmichConnection.normalizedAPIBaseURL) — MediaServer must build asset/thumbnail URLs
    // against that same base, or every request 404s and Nuke fails to decode the error body.
    let server = MediaServer(
      baseURL: connection.serverURL,
      tokenProvider: { @Sendable in await tokenStore.get() }
    )
    return ConnectionState(
      serverURL: serverURL,
      connection: connection,
      sync: SyncCoordinator(connection: connection, localStore: store),
      uploadQueue: UploadQueue(store: store, transport: ImmichUploadTransport(connection: connection)),
      pipeline: MediaPipeline.makeDefault(diskCache: diskCache, server: server)
    )
  }

  private init(serverURL: URL, token: String?, store: PhotosLocalStore) throws {
    let diskCache = TieredMediaCache(
      rootDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Heirloom/Media", isDirectory: true)
    )
    let built = try Self.makeConnectionState(
      serverURL: serverURL, token: token, store: store, diskCache: diskCache)

    self.serverURL = built.serverURL
    self.store = store
    self.connection = built.connection
    sync = built.sync
    uploadQueue = built.uploadQueue
    self.diskCache = diskCache
    pipeline = built.pipeline
  }

  /// Normal launch: file-backed DB in Application Support, token from the Keychain.
  static func standard(serverURL: URL) throws -> MacAppState {
    // A5: shared app-group container so the menu-bar agent drains the same queue.
    let store = try PhotosLocalStore(path: SharedContainer.databaseURL().path)
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
    // `connection` (and `sync`/`uploadQueue`/`pipeline`, which key off it) was built at launch
    // against whatever server was previously configured — on a fresh install, an unreachable
    // placeholder. Rebuild them against the server that was just verified with `probe.ping()`,
    // or `currentUserId()` below still hits the stale host.
    let built = try Self.makeConnectionState(
      serverURL: serverURL, token: token, store: store, diskCache: diskCache)
    self.serverURL = built.serverURL
    connection = built.connection
    sync = built.sync
    uploadQueue = built.uploadQueue
    pipeline = built.pipeline
    SharedTokenStore.saveBestEffort(token)
    SharedContainer.sharedDefaults.set(serverURL.absoluteString, forKey: SharedContainer.serverURLKey)
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
    SharedContainer.sharedDefaults.removeObject(forKey: SharedContainer.serverURLKey)
    userId = nil
    spaces = []
    libraries = []
    albums = []
    cameras = []
    cameraCategories = []
  }

  func refresh() async {
    guard let userId else { return }
    do {
      prefs = try await store.prefs(for: userId)
      async let s = store.memberSpaces(for: userId)
      async let l = store.accessibleLibraries(for: userId)
      async let a = store.memberAlbums(for: userId)
      let timelineContext = try await store.timelineContext(for: userId)
      let manageScope = TimelineScope.resolve(purpose: .manage, context: timelineContext)
      async let c = store.cameraModels(scope: manageScope)
      spaces = try await s
      libraries = try await l
      albums = try await a
      cameras = try await c
      cameraCategories = CameraCategory.grouped(cameras)
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
      lastSyncError = nil
      lastCompletedSyncAt = Date()
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
    SharedTokenStore.loadBestEffort()
  }
}
