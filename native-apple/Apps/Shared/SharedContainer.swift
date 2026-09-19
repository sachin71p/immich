import Foundation
import Security

/// Decided A5 #3: one NEW app-group container shared by the iOS app, the background-upload
/// extension, the macOS app and the menu-bar agent — shared LocalStore, shared defaults and
/// shared Keychain (via the `keychain-access-groups` entitlement in `Heirloom.entitlements`).
///
/// Everything degrades to per-app storage when the group container is unavailable (ad-hoc
/// signing, which cannot resolve access groups or app groups; simulator; fixture mode), so
/// local verify and fresh installs keep working without entitlements.
public enum SharedContainer {
  public static let groupIdentifier = "group.com.immich.heirloom.shared"
  /// S6: build-setting variables are NOT expanded in Swift string literals, so the historical
  /// literal `"$(AppIdentifierPrefix)…"` was never a valid `kSecAttrAccessGroup` — every
  /// group-scoped Keychain call failed and `saveBestEffort`/`loadBestEffort` silently survived
  /// on the no-group fallback (which is why login worked at all). The real prefix is resolved
  /// at runtime from the `HeirloomAppIdentifierPrefix` Info.plist key (set via `project.yml`,
  /// where `$(AppIdentifierPrefix)` IS expanded during Info.plist processing). Callers keep
  /// trying this group first, then no group, so tokens written by older builds keep working.
  public static var keychainAccessGroup: String {
    if let prefix = Bundle.main.object(forInfoDictionaryKey: "HeirloomAppIdentifierPrefix") as? String,
      !prefix.isEmpty, !prefix.hasPrefix("$(")
    {
      let dotted = prefix.hasSuffix(".") ? prefix : prefix + "."
      return dotted + "com.immich.heirloom.shared"
    }
    return "$(AppIdentifierPrefix)com.immich.heirloom.shared"
  }
  public static let databaseFileName = "heirloom.sqlite"
  public static let serverURLKey = "Heirloom.serverURL"
  /// WP-F F3: persisted signed-in user id — read synchronously at launch so the
  /// sign-in decision never waits on the Keychain async path or the network.
  public static let userIDKey = "Heirloom.userID"

  /// `containerURL(forSecurityApplicationGroupIdentifier:)` returns a non-nil URL even when the
  /// process's code signature can't actually use it (e.g. ad-hoc signing with entitlements
  /// stripped) — the denial only surfaces later, as an opaque SQLite "authorization denied" once
  /// something tries to open a file inside it. Probe with a real write so callers get a clean
  /// nil up front and take the Application Support fallback below.
  public static func groupURL() -> URL? {
    guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    else { return nil }
    guard (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil
    else { return nil }
    let probe = url.appendingPathComponent(".heirloom-access-probe")
    guard (try? Data().write(to: probe)) != nil else { return nil }
    try? FileManager.default.removeItem(at: probe)
    return url
  }

  public static var isSharedStorageAvailable: Bool { groupURL() != nil }

  /// File-backed DB location: app-group container when present, else Application Support.
  /// `groupURL()` already verified the directory exists and is writable.
  public static func databaseURL() throws -> URL {
    if let group = groupURL() {
      return group.appendingPathComponent(databaseFileName)
    }
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)
      .appendingPathComponent("Heirloom", isDirectory: true)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    return support.appendingPathComponent(databaseFileName)
  }

  /// Group suite when present, else standard (server URL, import destination, agent flag —
  /// all non-secret cross-process settings live here).
  ///
  /// Decided once per process (S4): re-probing on every access could return the group suite on
  /// one call and `.standard` on another, so a server URL written through this accessor would
  /// later read back as missing.
  ///
  /// `UserDefaults(suiteName:)` practically never returns nil, even when the process's code
  /// signature can't actually use the group suite (ad-hoc signing) — it hands back an instance
  /// backed by a domain the process can't persist to. A plain set-then-read probe would still
  /// report success (the in-memory cache echoes it back regardless), so force a real disk write
  /// via `synchronize()` — the same probe pattern as `groupURL()`, just at the plist layer.
  /// `UserDefaults` is thread-safe (concurrent reads/writes are serialized by the class),
  /// so sharing one decided instance across actors needs no further synchronization.
  nonisolated(unsafe) public static let sharedDefaults: UserDefaults = resolveSharedDefaults()

  private static func resolveSharedDefaults() -> UserDefaults {
    guard let suite = UserDefaults(suiteName: groupIdentifier) else { return .standard }
    suite.set(UUID().uuidString, forKey: ".heirloom-access-probe")
    guard suite.synchronize() else { return .standard }
    suite.removeObject(forKey: ".heirloom-access-probe")
    return suite
  }

  /// Reads the server URL through the shared suite. `ConnectView` used to write it into
  /// `.standard` while readers consulted the group suite (S4) — when the chosen suite has no
  /// value but `.standard` does, the value is migrated into the chosen suite. Pure in
  /// `chosen`/`fallback` so the logic stays unit-testable without an app host.
  public static func resolveServerURLString(chosen: UserDefaults, fallback: UserDefaults) -> String? {
    if let current = chosen.string(forKey: serverURLKey), !current.isEmpty { return current }
    guard fallback !== chosen else { return nil }
    guard let migrated = fallback.string(forKey: serverURLKey), !migrated.isEmpty else { return nil }
    chosen.set(migrated, forKey: serverURLKey)
    return migrated
  }

  /// Every read/write of the server URL goes through here so writers and readers can never
  /// disagree on the suite again (S4).
  public static func serverURLString() -> String? {
    resolveServerURLString(chosen: sharedDefaults, fallback: .standard)
  }

  public static func setServerURLString(_ value: String) {
    sharedDefaults.set(value, forKey: serverURLKey)
  }

  public static func clearServerURLString() {
    sharedDefaults.removeObject(forKey: serverURLKey)
  }

  /// WP-F F3 synchronous sign-in state (see `userIDKey`).
  public static func savedUserID() -> String? {
    let id = sharedDefaults.string(forKey: userIDKey)
    return (id?.isEmpty == false) ? id : nil
  }

  public static func setSavedUserID(_ value: String) {
    sharedDefaults.set(value, forKey: userIDKey)
  }

  public static func clearSavedUserID() {
    sharedDefaults.removeObject(forKey: userIDKey)
  }
}

extension SharedTokenStore {
  /// Group write first (extension + agent share it); plain item fallback when the access
  /// group is unresolvable (ad-hoc signing). Never throws — login must not fail on Keychain.
  static func saveBestEffort(_ token: String) {
    try? save(token, accessGroup: SharedContainer.keychainAccessGroup)
    if load(accessGroup: SharedContainer.keychainAccessGroup) == nil {
      try? save(token, accessGroup: nil)
    }
  }

  static func loadBestEffort() -> String? {
    load(accessGroup: SharedContainer.keychainAccessGroup)
      ?? load(accessGroup: nil)
  }

  static func deleteAll() {
    try? delete(accessGroup: SharedContainer.keychainAccessGroup)
    try? delete(accessGroup: nil)
  }

  static func save(_ token: String, accessGroup: String?) throws {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.immich.heirloom",
      kSecAttrAccount as String: "access-token",
      kSecValueData as String: Data(token.utf8),
    ]
    if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
    SecItemDelete(query as CFDictionary)
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
  }

  static func load(accessGroup: String?) -> String? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.immich.heirloom",
      kSecAttrAccount as String: "access-token",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete(accessGroup: String?) throws {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.immich.heirloom",
      kSecAttrAccount as String: "access-token",
    ]
    if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
    SecItemDelete(query as CFDictionary)
  }
}
