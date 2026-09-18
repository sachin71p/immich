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

  /// Snapshot backing viewer paging, in display order (set when the viewer opens).
  var viewerContext: TimelineGridSnapshot?
  /// Toolbar-search handoff (WP6 slice C, U16): the toolbar field lives in `MacMainWindow`,
  /// while the query executes in `MacSearchView`. Return in the toolbar stashes the trimmed
  /// query here and navigates to `.search`; the search view consumes (applies, executes,
  /// clears) it on appear. A plain String is safe on `@Observable` (PLAN rule 5 covers
  /// large Equatable collections only).
  var pendingSearchQuery: String?
  /// Launch-gate bound for server session validation (`revalidateSession`,
  /// `adoptKeychainSession`): generous for one small GET on a slow link, tight
  /// enough that a dead network degrades to the offline session in seconds.
  static let sessionValidationTimeoutSeconds = 8.0
  /// Bumped by `syncNow` only when the session warrants a grid reload (see
  /// `SyncCoordinator.SyncResult.shouldReloadTimeline`). The applied-changes signal is
  /// `SyncResult.appliedChanges` — true when the session called `PhotosLocalStore.apply`
  /// or `wipe` at least once. The grid's `reloadKey` includes this version so a reload
  /// keeps the old snapshot until the new one is ready (same destination). Idle no-change
  /// syncs skip the bump entirely, so they no longer rebuild the grid and re-issue the
  /// prefetch storm behind the Gate-3 hangs. Mutations post change-center events and never
  /// go through this path.
  var timelineVersion = 0

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
    // Chunked (one SQLite transaction per batch): bounds peak memory on the large
    // fixture and avoids a single all-or-nothing apply of 100k+ rows whose throw
    // the app-shell call site would swallow (`try?`), leaving an empty grid.
    let batches = FixtureSeed.batchedChanges()
    for (index, batch) in batches.enumerated() {
      try await store.apply(batch, currentUserId: FixtureSeed.userId)
      // First paint doesn't wait for the full 102k seed: the base batch carries
      // every curated row, so publish the moment it lands — the grid appears in
      // seconds while the bulk backfills underneath, and the closing bump below
      // converges on the full set. Single-batch seeds (small fixture) skip this;
      // their closing bump already paints everything at once.
      if index == 0 && batches.count > 1 {
        timelineVersion += 1
      }
    }
    // Mirror the hydrated `getLibrary` state (A1): the Archive library accepts uploads,
    // so DECISIONS §6 rule 4 offers it as a move target in the seeded world.
    try await store.setLibraryUploadPath(libraryId: FixtureSeed.libraryId, uploadPath: "/import/archive")
    await refresh()
    // The grid's `.task(id: reloadKey)` fires on appear — against the still-empty store
    // while this seed is in flight — and nothing else changes reloadKey once the rows
    // land, so without this the grid keeps its first empty snapshot forever.
    timelineVersion += 1
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
    if let userId { SharedContainer.setSavedUserID(userId) }
    await refresh()
  }

  /// WP-F F3: synchronous relaunch — restores the persisted session (server URL +
  /// user id + Keychain token presence) with no async work, so the launch gate can
  /// decide before the first scene renders. Returns whether a session was restored.
  @discardableResult
  func restorePersistedSession(tokenPresent: Bool) -> Bool {
    guard userId == nil else { return true }
    guard
      LaunchGate.isSignedIn(
        serverURLString: SharedContainer.serverURLString(), tokenPresent: tokenPresent,
        userID: SharedContainer.savedUserID())
    else { return false }
    userId = SharedContainer.savedUserID()
    return true
  }

  /// Revalidates a synchronously restored session against the server without ever
  /// flashing the connect screen: on network failure the restored (offline) session
  /// stays — the local DB is the UI's data source — and only a confirmed identity
  /// change replaces the user id. Bounded: a blackholed network must not stall
  /// launch past the gate timeout (URLSession's own timeouts run to 60 s+).
  func revalidateSession() async {
    guard userId != nil else {
      await adoptKeychainSession()
      return
    }
    let connection = connection
    if let id = try? await LaunchGate.withLaunchTimeout(
      seconds: Self.sessionValidationTimeoutSeconds,
      operation: { try await connection.currentUserId() })
    {
      userId = id
      SharedContainer.setSavedUserID(id)
      await refresh()
    }
  }

  /// Relaunch: a Keychain token from a previous session restores the user without
  /// showing the connect screen (network failure just leaves the connect screen up).
  /// Bounded like `revalidateSession` above.
  func adoptKeychainSession() async {
    guard userId == nil else { return }
    if await connection.tokenStore.get() == nil { return }
    let connection = connection
    if let id = try? await LaunchGate.withLaunchTimeout(
      seconds: Self.sessionValidationTimeoutSeconds,
      operation: { try await connection.currentUserId() })
    {
      userId = id
      SharedContainer.setSavedUserID(id)
      await refresh()
    }
  }

  func logout() async {
    await connection.tokenStore.set(nil)
    SharedContainer.sharedDefaults.removeObject(forKey: SharedContainer.serverURLKey)
    SharedContainer.clearSavedUserID()
    userId = nil
    spaces = []
    libraries = []
    albums = []
    cameras = []
    cameraCategories = []
  }

  func refresh() async {
    guard let userId else { return }
    // Smoke usage for the WP0 logging API: proves the app target sees CoreModel's
    // loggers (no re-export file needed) and gives the perf harness a sync marker.
    HeirloomLog.sync.debug("refresh userId=\(userId, privacy: .public)")
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

  /// - Parameter userInitiated: true for foreground, pull-to-refresh, Sync-Now, login and
  ///   launch syncs (all current call sites) — those keep the historical always-reload
  ///   behavior. A background timer (see `SyncCoordinator.startActiveTimer`, currently
  ///   unwired) passes false so idle no-change sessions skip the grid rebuild.
  func syncNow(userInitiated: Bool = true) async {
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }
    do {
      let result = try await sync.syncWithResult()
      lastSyncError = nil
      lastCompletedSyncAt = Date()
      // No-change syncs leave the grid (and the metadata refresh feeding the sidebar)
      // untouched: nothing in the mirror moved, so there is nothing to re-read.
      guard result.shouldReloadTimeline(userInitiated: userInitiated) else { return }
      timelineVersion += 1
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
