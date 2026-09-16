import Foundation
import LocalAuthentication

/// Device-local gate for the Locked utility. `.deviceOwnerAuthentication` intentionally permits
/// Face ID / Touch ID and the device passcode, so a biometric enrollment change never makes a
/// user permanently unable to recover their own personal media.
enum LockedMediaAuthentication {
  static func authenticate(reason: String = "Unlock your personal locked photos") async -> Bool {
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
