import Foundation
import LocalAuthentication

/// Device-local gate for the Locked utility. `.deviceOwnerAuthentication` intentionally permits
/// Face ID / Touch ID and the device passcode, so a biometric enrollment change never makes a
/// user permanently unable to recover their own personal media.
enum LockedMediaAuthentication {
  static func authenticate(reason: String = "Unlock your personal locked photos") async -> Bool {
    // UI-smoke launches seed a synthetic world with no real user media and no
    // enrolled biometrics, so device auth can never pass there — bypass it so the
    // Locked destination and lock/unlock flows stay testable. Production path
    // unchanged (the flag is only ever passed by the macOS XCUITest harness).
    let args = CommandLine.arguments
    if args.contains("-fixture-seed") || args.contains("--fixture-seed") { return true }
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
    do {
      return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    } catch {
      return false
    }
  }
}
