import AppIntents
import CoreModel
import Foundation
import LocalStore
import UniformTypeIdentifiers
import Upload

/// A9.6: Shortcuts / App Intents — "Save to Heirloom Library" (upload to library) and
/// "Open Heirloom Search" (open search).
///
/// Both intents run against the shared app-group container: the upload intent stages
/// `IntentFile` inputs into the inbox and enqueues rows in the shared `PhotosLocalStore`
/// queue (same drain path as the share extension and A5 scheduler); the search intent
/// records a pending route and opens the app, which lands on the Search tab.
enum IntentSharedAccess {
  static let groupIdentifier = "group.com.immich.heirloom.shared"
  static let pendingRouteKey = "Heirloom.pendingRoute"
  static let inboxDirectoryName = "share-inbox"

  static func containerURL() -> URL? {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: groupIdentifier)
  }

  static func inboxURL() throws -> URL {
    guard let container = containerURL() else { throw IntentError.noSharedContainer }
    let inbox = container.appendingPathComponent(inboxDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(
      at: inbox, withIntermediateDirectories: true, attributes: nil)
    return inbox
  }

  static func databaseURL() throws -> URL {
    guard let container = containerURL() else { throw IntentError.noSharedContainer }
    try FileManager.default.createDirectory(
      at: container, withIntermediateDirectories: true, attributes: nil)
    return container.appendingPathComponent("heirloom.sqlite")
  }
}

enum IntentError: Error {
  case noSharedContainer
}

/// Save photos/videos into a Heirloom library (Shortcuts action). The destination is a
/// snapshot id ("personal" or "space:<id>"); anything else falls back to the user's
/// default upload target.
struct UploadToLibraryIntent: AppIntent {
  static let title: LocalizedStringResource = "Save to Heirloom Library"
  static let description = IntentDescription(
    "Saves photos or videos into your Heirloom library. They upload on the next sync.")

  @Parameter(title: "Photos")
  var photos: [IntentFile]

  @Parameter(title: "Destination")
  var destination: String?

  static var parameterSummary: some ParameterSummary {
    Summary("Save \(\.$photos) to the Heirloom library")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let inbox = try IntentSharedAccess.inboxURL()
    let store = try PhotosLocalStore(path: IntentSharedAccess.databaseURL().path)
    let prefs = (try? await store.anyPrefs()) ?? SharedLibraryPrefs()
    var rows: [QueuedUpload] = []
    var staged = 0
    for photo in photos {
      let ext = photo.type?.preferredFilenameExtension ?? "jpg"
      let fileName = photo.filename.isEmpty ? "shortcut-\(staged).\(ext)" : photo.filename
      let stagedURL = inbox.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
      try photo.data.write(to: stagedURL, options: .atomic)
      staged += 1
      let isVideo = photo.type?.conforms(to: .movie) ?? false
      let spec = FileUploadSpec(
        fileURL: stagedURL, fileName: fileName,
        fileCreatedAt: Date(), fileModifiedAt: Date(),
        isVideo: isVideo,
        explicitTarget: Self.explicitTarget(for: destination, prefs: prefs))
      rows.append(try UploadEnqueuePlan.single(spec, prefs: prefs))
    }
    if !rows.isEmpty {
      _ = try await store.enqueueUploads(rows)
    }
    return .result(dialog: staged == 1
      ? "Saved 1 item — it uploads when Heirloom next runs."
      : "Saved \(staged) items — they upload when Heirloom next runs.")
  }

  private static func explicitTarget(
    for destination: String?, prefs: SharedLibraryPrefs
  ) -> UploadTargetResolver.ExplicitTarget {
    if let destination, destination.hasPrefix("space:") {
      return .space(String(destination.dropFirst("space:".count)))
    }
    if destination == nil || destination == "personal" {
      return .personal
    }
    return .inherit
  }
}

/// Open Heirloom on the Search tab (Shortcuts action).
struct OpenSearchIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Heirloom Search"
  static let description = IntentDescription("Opens Heirloom on the Search tab.")
  static var openAppWhenRun: Bool { true }

  func perform() async throws -> some IntentResult {
    let defaults = UserDefaults(suiteName: IntentSharedAccess.groupIdentifier) ?? .standard
    defaults.set("search", forKey: IntentSharedAccess.pendingRouteKey)
    return .result()
  }
}
