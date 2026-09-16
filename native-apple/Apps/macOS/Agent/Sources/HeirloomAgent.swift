import CoreModel
import Foundation
import ImmichAPI
import LocalStore
import Security
import SyncEngine
import Upload

/// A5 brief task 8 (agent half): menu-bar/login-item helper that runs sync + the upload queue
/// while the main app is closed, against the SAME shared container (decided A5 #3).
///
/// The group coordinates mirror `SharedContainer` (Apps/Shared), which this target cannot
/// import; the group id string is the contract. Work is crash-safe by construction: sync
/// resumes from `syncAck` checkpoints and the upload queue reclaims `uploading` rows, so the
/// agent can simply run once per launch and exit — relaunch (interval or login) repeats it.
/// There is deliberately no `@main` here: the entry point belongs to the target-type decision
/// in `project.yml` (see `MacAgentLoginItem`'s packaging note) — the host wires
/// `HeirloomAgent.runOnce()` into whatever executable wrapper wins.
public enum HeirloomAgent {
  private enum SharedAccess {
    static let groupIdentifier = "group.com.immich.heirloom.shared"
    static let serverURLKey = "Heirloom.serverURL"

    static func databaseURL() throws -> URL {
      if let group = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: groupIdentifier)
      {
        return group.appendingPathComponent("heirloom.sqlite")
      }
      throw AgentError.noSharedContainer
    }

    static func serverURL() -> URL? {
      let defaults = UserDefaults(suiteName: groupIdentifier) ?? .standard
      guard let string = defaults.string(forKey: serverURLKey) else { return nil }
      return URL(string: string)
    }

    static func accessToken() -> String? {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.immich.heirloom",
        kSecAttrAccount as String: "access-token",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var item: CFTypeRef?
      guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
        let data = item as? Data
      else { return nil }
      return String(data: data, encoding: .utf8)
    }
  }

  public static func runOnce() async {
    guard let serverURL = SharedAccess.serverURL(),
      let token = SharedAccess.accessToken(),
      let dbPath = try? SharedAccess.databaseURL(),
      let store = try? PhotosLocalStore(path: dbPath.path),
      let connection = try? ImmichConnection(serverURL: serverURL, accessToken: token)
    else { return }
    // Sync first so membership-gated upload targets resolve against fresh rules state.
    try? await SyncCoordinator(connection: connection, localStore: store).syncOnDemand()
    let prefs = (try? await store.anyPrefs()) ?? SharedLibraryPrefs()
    let queue = UploadQueue(
      store: store, transport: ImmichUploadTransport(connection: connection))
    _ = await queue.drain(prefs: prefs)
  }
}

enum AgentError: Error { case noSharedContainer }
