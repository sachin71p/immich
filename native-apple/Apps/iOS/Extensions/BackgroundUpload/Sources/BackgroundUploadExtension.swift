import CoreModel
import Foundation
import ImmichAPI
import LocalStore
import Security
import Upload

/// A5 brief task 4: system-scheduled photo-library upload jobs (iOS 26.1+).
///
/// OPEN QUESTION 1 (host must confirm): whether this extension point needs a restricted
/// entitlement under the repo's signing setups, and the exact `NSExtensionPointIdentifier` /
/// job-ack API the iOS 26.1 SDK exposes. The target's `Info.plist` keeps the provisional
/// extension point `com.apple.photos.background-resource-upload` (see
/// `native-apple/project.yml`); if the SDK names it differently, only that one line changes,
/// and if the SDK vends a job object with its own ack/termination callbacks, the drain call
/// below moves inside them. No special entitlement is declared beyond the shared app-group +
/// keychain-access-group entitlements: if host verification shows the system refuses to
/// launch the extension under ad-hoc signing, that failure and the required entitlement go here.
///
/// Design: the handler drains the SAME shared `PhotosLocalStore` queue the foreground
/// scheduler writes (decided A5 #3). Rows are crash-safe (a kill mid-upload leaves `uploading`,
/// reclaimed to pending on the next drain) and idempotent (checksum dedupe), so termination
/// needs no special handling — un-acked work is simply picked up by the next launch.
@objc(HeirloomBackgroundUploadHandler)
final class HeirloomBackgroundUploadHandler: NSObject, NSExtensionRequestHandling {
  func beginRequest(with context: NSExtensionContext) {
    Task {
      await Self.drainSharedQueue()
      context.completeRequest(returningItems: nil, completionHandler: nil)
    }
  }

  /// Shared-container coordinates. Mirrors `SharedContainer` (Apps/Shared), which this target
  /// cannot import (it drags SwiftUI along); the group id string is the contract between them.
  private enum SharedAccess {
    static let groupIdentifier = "group.com.immich.heirloom.shared"
    static let serverURLKey = "Heirloom.serverURL"

    static func databaseURL() throws -> URL {
      if let group = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: groupIdentifier)
      {
        try FileManager.default.createDirectory(
          at: group, withIntermediateDirectories: true)
        return group.appendingPathComponent("heirloom.sqlite")
      }
      throw ExtensionError.noSharedContainer
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

  private static func drainSharedQueue() async {
    guard let serverURL = SharedAccess.serverURL(),
      let token = SharedAccess.accessToken(),
      let dbPath = try? SharedAccess.databaseURL(),
      let store = try? PhotosLocalStore(path: dbPath.path)
    else { return }
    guard let connection = try? ImmichConnection(serverURL: serverURL, accessToken: token) else {
      return
    }
    let prefs = (try? await store.anyPrefs()) ?? SharedLibraryPrefs()
    let queue = UploadQueue(
      store: store, transport: ImmichUploadTransport(connection: connection))
    _ = await queue.drain(prefs: prefs)
  }
}

enum ExtensionError: Error { case noSharedContainer }
