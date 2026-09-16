import Foundation
import ServiceManagement

/// A5 brief task 8 (app half): registers/unregisters the `Heirloom-Agent` login item, which
/// runs sync + the upload queue while the main app is closed (see
/// `Apps/macOS/Agent/Sources/HeirloomAgent.swift`).
///
/// Packaging note (host must confirm): `SMAppService.loginItem` needs the helper embedded as a
/// login item of the main app bundle. The `Heirloom-Agent` target is currently an
/// `app-extension` (A4 scaffold); if host verification shows registration failing with
/// "no such login item", flip that target to an embedded login-item application and keep this
/// call site unchanged — the bundle id below is the contract between them.
enum MacAgentLoginItem {
  static let helperIdentifier = "com.immich.heirloom.agent"

  private static var service: SMAppService {
    SMAppService.loginItem(identifier: helperIdentifier)
  }

  static var isEnabled: Bool {
    service.status == .enabled
  }

  static var statusNote: String {
    switch service.status {
    case .enabled: return "Background sync is on."
    case .notRegistered: return "Not registered yet — flip the toggle to register."
    case .requiresApproval:
      return "Registered but needs approval in System Settings → General → Login Items."
    case .notFound: return "Agent helper is not part of this build (see packaging note)."
    @unknown default: return "Agent status unknown."
    }
  }

  static func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try service.register()
    } else {
      try service.unregister()
    }
  }
}
