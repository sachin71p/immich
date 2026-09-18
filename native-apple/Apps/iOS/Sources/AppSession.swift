import CoreModel
import Foundation
import ImmichAPI
import LocalStore
import Media
import Rules
import Security
import SyncEngine
import SwiftUI
import Upload

/// The iOS app's session: connection, local mirror, rules contexts, media pipeline, and sync.
/// The local DB is the UI's only data source (A0 Architecture); every screen reads `store` +
/// `access`/`timelineScope`, and every write goes through the `*Mutations` facades (API first,
/// local optimistic update on success).
@MainActor
final class AppSession: ObservableObject {
  @Published var signedIn = false
  @Published var isFixture = false
  @Published var serverURL: URL?
  /// Normalized API base (origin + `/api`) for building server route URLs.
  /// `serverURL` stays the user-entered origin (display, identity,
  /// persistence). Every route/media/fetch construction must use this —
  /// the raw origin serves the SPA's index.html, which media clients
  /// cannot parse (F2: AVPlayer reported it as -11850).
  var apiBaseURL: URL? { connection?.serverURL ?? serverURL }
  @Published var userId = ""
  @Published var access = AccessContext(currentUserId: "")
  @Published var prefs = SharedLibraryPrefs()
  @Published var spaces: [Space] = []
  @Published var libraries: [Library] = []
  @Published var lastError: String?
  /// S1: observable sync state — the Library subtitle, error banner and Settings all read these.
  @Published var isSyncing = false
  @Published var lastSyncAt: Date?
  /// S1: bumped after every successful sync so store-reading views can re-key their reloads.
  @Published var timelineVersion = 0
  /// A9.6: tab the app should land on (set from the intents pending route).
  @Published var requestedTab = "library"

  var connection: ImmichConnection?
  var store: PhotosLocalStore?
  var pipeline: MediaPipeline?
  var sync: SyncCoordinator?
  var uploadQueue: UploadQueue?
  /// S3: token `start()` last built the session from — `reload()` skips the rebuild when the
  /// keychain token and server URL are unchanged.
  private var activeToken: String?

  static let serverURLKey = "Heirloom.serverURL"

  var assetMutations: AssetMutations? {
    guard let connection, let store else { return nil }
    return AssetMutations(connection: connection, localStore: store)
  }

  var spaceMutations: SpaceMutations? {
    guard let connection, let store else { return nil }
    return SpaceMutations(connection: connection, localStore: store)
  }

  var albumMutations: AlbumMutations? {
    guard let connection, let store else { return nil }
    return AlbumMutations(connection: connection, localStore: store)
  }

  var prefsMutations: PrefsMutations? {
    guard let connection, let store else { return nil }
    return PrefsMutations(connection: connection, localStore: store)
  }

  /// Rebuilds the session from the Keychain token (written by `ConnectView`) whenever the app
  /// becomes active, or boots the deterministic fixture world for `-useFixtureStore` (XCUITest).
  func reload() async {
    if CommandLine.arguments.contains("-useFixtureStore") {
      // Fixture mode: the in-memory store survives foregrounding — don't reseed it away.
      if signedIn && isFixture && store != nil { return }
      await startFixture()
      return
    }
    do {
      guard let token = SharedTokenStore.loadBestEffort(), !token.isEmpty,
        let urlString = SharedContainer.serverURLString(),
        let url = URL(string: urlString)
      else {
        signedIn = false
        return
      }
      // S3: already running against this server + token — don't rebuild the connection, store,
      // sync coordinator and pipeline (which also races an in-flight sync). Just top up the sync
      // when it never ran or went stale (> 60 s).
      if signedIn && serverURL?.absoluteString == urlString && activeToken == token && store != nil {
        if lastSyncAt == nil || Date().timeIntervalSince(lastSyncAt!) > 60 {
          await syncNow()
        }
        return
      }
      try await start(serverURL: url, token: token)
    } catch {
      lastError = error.localizedDescription
      signedIn = false
    }
  }

  func start(serverURL: URL, token: String) async throws {
    let connection = try ImmichConnection(serverURL: serverURL, accessToken: token)
    await connection.tokenStore.set(token)
    let userId = try await connection.currentUserId()
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    // A5: shared app-group container so the background-upload extension drains the same queue.
    let dbURL = try SharedContainer.databaseURL()
    HeirloomLog.store.info("store path=\(dbURL.path, privacy: .public)")
    let store = try PhotosLocalStore(path: dbURL.path)
    let cacheRoot = support.appendingPathComponent("media-cache", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    // `connection.serverURL` is `serverURL` normalized to include the `/api` base (see
    // ImmichConnection.normalizedAPIBaseURL) — MediaServer must build asset/thumbnail URLs
    // against that same base, or every request 404s and Nuke fails to decode the error body.
    let mediaServer = MediaServer(
      baseURL: connection.serverURL,
      tokenProvider: {
        let store = connection.tokenStore
        return await store.get()
      })
    let pipeline = MediaPipeline.makeDefault(
      diskCache: TieredMediaCache(rootDirectory: cacheRoot), server: mediaServer)
    self.connection = connection
    self.store = store
    self.pipeline = pipeline
    self.sync = SyncCoordinator(connection: connection, localStore: store)
    self.uploadQueue = UploadQueue(
      store: store, transport: ImmichUploadTransport(connection: connection))
    self.serverURL = serverURL
    self.userId = userId
    self.isFixture = false
    self.activeToken = token
    await connection.tokenStore.set(token)
    try await refresh()
    signedIn = true
    HeirloomLog.sync.info(
      "session start host=\(serverURL.host ?? "?", privacy: .public) user=\(String(userId.prefix(8)), privacy: .public)"
    )
    // S1: a fresh sign-in always syncs — the Library must fill without any user action.
    Task { await syncNow() }
  }

  /// Fixture mode: in-memory store seeded via `FixtureSeed`; network calls fail gracefully behind
  /// per-action error alerts (the smoke test only reads: grid → viewer → move-sheet targets).
  func startFixture() async {
    do {
      let store = try PhotosLocalStore(inMemory: true)
      try await FixtureSeed.seed(into: store)
      let url = URL(string: "https://fixture.local")!
      let connection = try ImmichConnection(serverURL: url, accessToken: "fixture")
      let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
        "fixture-media-cache", isDirectory: true)
      try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
      let pipeline = MediaPipeline.makeDefault(
        diskCache: TieredMediaCache(rootDirectory: cacheRoot),
        server: MediaServer(baseURL: url))
      self.connection = connection
      self.store = store
      self.pipeline = pipeline
      self.sync = nil
      self.serverURL = url
      self.userId = FixtureSeed.userId
      self.isFixture = true
      try await refresh()
      signedIn = true
    } catch {
      lastError = error.localizedDescription
      signedIn = false
    }
  }

  /// Re-reads memberships, prefs, and container lists after any mutation or sync tick.
  func refresh() async throws {
    guard let store else { return }
    access = try await store.accessContext(for: userId)
    prefs = try await store.prefs(for: userId)
    spaces = try await store.spacesForUser(userId)
    libraries = try await store.librariesForUser(userId)
    // A9.5: publish the extension snapshot (never throws; refresh must not fail on it).
    await ExtensionSnapshotWriter.refreshIfNeeded(session: self)
  }

  func timelineScope(explicit filter: ExplicitContainerFilter? = nil) async throws -> ContainerScope {
    guard let store else { return .empty }
    let ctx = try await store.timelineContext(for: userId, explicitFilter: filter)
    return TimelineScope.resolve(purpose: .timeline, context: ctx)
  }

  func manageScope() async throws -> ContainerScope {
    guard let store else { return .empty }
    let ctx = try await store.timelineContext(for: userId)
    return TimelineScope.resolve(purpose: .manage, context: ctx)
  }

  func syncNow() async {
    guard let sync, !isFixture else { return }
    // S1: no overlapping syncs — the coordinator also drops concurrent calls, but only the
    // session flag keeps the UI (subtitle, Settings row) truthful.
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }
    let started = Date()
    HeirloomLog.sync.info("sync start")
    do {
      // The coordinator exposes no progress stream (it returns did-run only), so the UI shows
      // an indeterminate "Syncing…" state while this is in flight.
      let didRun = try await sync.syncNow()
      let duration = Date().timeIntervalSince(started)
      if !didRun {
        HeirloomLog.sync.info("sync dropped (already running)")
        return
      }
      try await refresh()
      lastError = nil
      lastSyncAt = Date()
      timelineVersion += 1
      HeirloomLog.sync.info("sync finish duration=\(duration, privacy: .public)s")
    } catch is CancellationError {
      // A cancelled sync is not an error worth surfacing.
      HeirloomLog.sync.info("sync cancelled")
    } catch {
      let duration = Date().timeIntervalSince(started)
      lastError = error.localizedDescription
      HeirloomLog.sync.error(
        "sync failure duration=\(duration, privacy: .public)s error=\(error.localizedDescription, privacy: .public)"
      )
    }
  }

  func signOut() {
    SharedTokenStore.deleteAll()
    SharedContainer.clearServerURLString()
    connection = nil
    store = nil
    pipeline = nil
    sync = nil
    uploadQueue = nil
    activeToken = nil
    lastSyncAt = nil
    signedIn = false
  }

  /// A9.6: consume the intent pending route written by `OpenSearchIntent` into the
  /// shared defaults (cleared after reading so each intent lands once).
  func checkPendingRoute() {
    let defaults = SharedContainer.sharedDefaults
    guard let route = defaults.string(forKey: "Heirloom.pendingRoute") else { return }
    defaults.removeObject(forKey: "Heirloom.pendingRoute")
    if route == "search" { requestedTab = "search" }
  }

  /// Bearer [REDACTED] for out-of-pipeline authorized requests (video playback, share downloads).
  func bearerToken() async -> String? {
    guard let connection else { return nil }
    return await connection.tokenStore.get()
  }
}

extension SharedTokenStore {
  static func load() throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.immich.heirloom",
      kSecAttrAccount as String: "access-token",
      kSecAttrAccessGroup as String: SharedContainer.keychainAccessGroup,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else {
      if status == errSecItemNotFound { return nil }
      throw KeychainError.unexpectedStatus(status)
    }
    guard let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.immich.heirloom",
      kSecAttrAccount as String: "access-token",
      kSecAttrAccessGroup as String: SharedContainer.keychainAccessGroup,
    ]
    SecItemDelete(query as CFDictionary)
  }
}
