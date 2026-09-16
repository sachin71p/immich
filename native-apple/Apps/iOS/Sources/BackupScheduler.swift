@preconcurrency import BackgroundTasks
import CoreModel
import Foundation
import LocalStore
import Upload

/// A5 brief task 4 (fallback half): `BGProcessingTask` backup scheduling for foreground-adjacent
/// execution. The `PHBackgroundResourceUploadExtension` target handles system-scheduled photo
/// jobs; this scheduler covers everything else (scan + drain while the app is backgrounded).
enum BackupScheduler {
  static let taskIdentifier = "com.immich.heirloom.backup-processing"

  static func register(session: AppSession) {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: taskIdentifier, using: nil
    ) { task in
      guard let processing = task as? BGProcessingTask else {
        task.setTaskCompleted(success: false)
        return
      }
      scheduleNext()
      Task { @MainActor in
        await runBackup(session: session)
        processing.setTaskCompleted(success: session.lastError == nil)
      }
      processing.expirationHandler = {
        processing.setTaskCompleted(success: false)
      }
    }
  }

  static func scheduleNext() {
    let request = BGProcessingTaskRequest(identifier: taskIdentifier)
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = false
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  /// Foreground trigger (Settings "Back Up Now", app-activate): scan, then drain.
  @MainActor
  static func runBackup(session: AppSession) async {
    guard let store = session.store, let queue = session.uploadQueue else { return }
    #if canImport(Photos)
    do {
      _ = try await PhotoKitBackupScanner.scanAndEnqueue(store: store, prefs: session.prefs)
    } catch {
      session.lastError = error.localizedDescription
      return
    }
    #endif
    _ = await queue.drain(prefs: session.prefs)
    session.lastError = nil
  }
}
