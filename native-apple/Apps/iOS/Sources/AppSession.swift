import CoreModel
import Foundation
import ImmichAPI
import LocalStore
import Media
import Rules
import Security
import SyncEngine
import SwiftUI

/// The iOS app's session: connection, local mirror, rules contexts, media pipeline, and sync.
/// The local DB is the UI's only data source (A0 Architecture); every screen reads `store` +
/// `access`/`timelineScope`, and every write goes through the `*Mutations` facades (API first,
/// local optimistic update on success).
@MainActor
final class AppSession: ObservableObject {
  @Published var signedIn = false
  @Published var isFixture = false
  @Published var serverURL: URL?
  @Published var userId = ""
  @Published var access = AccessContext(currentUserId: "")
  @Published var prefs = SharedLibraryPrefs()
  @Published var spaces: [Space] = []
  @Published var libraries: [Library] = []
  @Published var lastError: String?

  var connection: ImmichConnection?
  var store: PhotosLocalStore?
  var pipeline: MediaPipeline?
  var sync: SyncCoordinator?

  static let serverURLKey = "PhotosFork.serverURL"

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
      await startFixture()
      return
    }
    do {
      guard let token = try SharedTokenStore.load(), !token.isEmpty,
        let urlString = UserDefaults.standard.string(forKey: Self.serverURLKey),
        let url = URL(string: urlString)
      else {
        signedIn = false
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
    let store = try PhotosLocalStore(
      path: support.appendingPathComponent("photosfork.sqlite").path)
    let cacheRoot = support.appendingPathComponent("media-cache", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let mediaServer = MediaServer(
      baseURL: serverURL,
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
    self.serverURL = serverURL
    self.userId = userId
    self.isFixture = false
    await connection.tokenStore.set(token)
    try await refresh()
    signedIn = true
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
    do {
      try await sync.syncNow()
      try await refresh()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func signOut() {
    try? SharedTokenStore.delete()
    UserDefaults.standard.removeObject(forKey: Self.serverURLKey)
    connection = nil
    store = nil
    pipeline = nil
    sync = nil
    signedIn = false
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
      kSecAttrService as String: "com.immich.photosfork",
      kSecAttrAccount as String: "access-token",
      kSecAttrAccessGroup as String: "$(AppIdentifierPrefix)com.immich.photosfork.shared",
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
      kSecAttrService as String: "com.immich.photosfork",
      kSecAttrAccount as String: "access-token",
      kSecAttrAccessGroup as String: "$(AppIdentifierPrefix)com.immich.photosfork.shared",
    ]
    SecItemDelete(query as CFDictionary)
  }
}
