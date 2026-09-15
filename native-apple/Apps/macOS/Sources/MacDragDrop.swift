import CoreModel
import Foundation
import Media
import SwiftUI

/// Drag & drop out (brief task 5): export originals to Finder through the collection-view
/// promised-files flow. The grid's pasteboard writer keeps carrying the asset id (so sidebar
/// drop targets work); when the drop lands in Finder, `namesOfPromisedFilesDroppedAtDestination`
/// materializes the original bytes there. Prefetch starts when the drag begins so the common
/// case never blocks the drop.
/// Download helper behind the promised-files flow.
struct MacExporter: Sendable {
  var serverURL: URL
  var tokenProvider: @Sendable () async -> String?

  func downloadOriginal(asset: Asset) async throws -> Data {
    var request = URLRequest(
      url: MediaEndpoint(serverURL: serverURL, assetID: asset.id).originalURL())
    if let token = await tokenProvider() {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw MacExportError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    return data
  }
}

/// Lock-guarded staging area for drag-out prefetches: the prefetch tasks run off the main
/// thread while the drop callback reads on it.
final class MacDragPrefetchState: @unchecked Sendable {
  private let lock = NSLock()
  private var staged: [String: URL] = [:]
  private var tasks: [String: Task<Void, Never>] = [:]

  func reset() {
    lock.withLock {
      tasks.values.forEach { $0.cancel() }
      tasks = [:]
      staged = [:]
    }
  }

  func prefetch(asset: Asset, with exporter: MacExporter) {
    let task = Task {
      do {
        let data = try await exporter.downloadOriginal(asset: asset)
        let url = FileManager.default.temporaryDirectory
          .appendingPathComponent("PhotosForkExport-\(asset.id)-\(asset.originalFileName)")
        try data.write(to: url, options: .atomic)
        lock.withLock { staged[asset.id] = url }
      } catch {}
    }
    lock.withLock { tasks[asset.id]?.cancel(); tasks[asset.id] = task }
  }

  func stagedFile(for assetID: String) -> URL? {
    lock.withLock { staged[assetID] }
  }
}

enum MacExportError: Error, LocalizedError {
  case badStatus(Int)
  case missingAsset(String)

  var errorDescription: String? {
    switch self {
    case .badStatus(let code): return "Download failed (HTTP \(code))."
    case .missingAsset(let id): return "Asset \(id) is not in the local store."
    }
  }
}

/// Import drop (brief task 5): files/folders land here for a destination-library choice.
/// A5 wires the upload queue; this phase owns the UI + chooser only.
struct MacImportChooserSheet: View {
  @Bindable var state: MacAppState
  var urls: [URL]
  var onDone: () -> Void
  @State private var destination = SharedContainer.sharedDefaults.string(
    forKey: "PhotosFork.importDestination") ?? "default"
  @State private var staged = false
  @State private var enqueuedNote = ""
  @State private var importError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Import \(urls.count) file\(urls.count == 1 ? "" : "s")").font(.headline)
      ForEach(urls.prefix(5), id: \.self) { url in
        Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
      }
      if urls.count > 5 {
        Text("…and \(urls.count - 5) more").font(.caption).foregroundStyle(.secondary)
      }
      Picker("Destination library", selection: $destination) {
        Text("Default upload target (\(state.prefs.defaultUploadTargetLabel(spaces: state.spaces)))")
          .tag("default")
        Text("Personal Library").tag("personal")
        ForEach(state.spaces, id: \.space.id) { entry in
          Text(entry.space.name).tag("space:\(entry.space.id)")
        }
      }
      .accessibilityIdentifier("import-destination-picker")
      if staged {
        Text(enqueuedNote)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if let importError {
        Text(importError).foregroundStyle(.red).font(.caption)
      }
      HStack {
        Spacer()
        Button("Cancel") { onDone() }
        Button(staged ? "Done" : "Upload") {
          if staged {
            onDone()
          } else {
            SharedContainer.sharedDefaults.set(
              destination, forKey: "PhotosFork.importDestination")
            Task { await enqueue() }
          }
        }
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("import-stage-button")
      }
    }
    .padding()
    .frame(minWidth: 360)
  }

  /// A5: the A4 "stage" step now enqueues into the durable upload queue (checksum dedupe
  /// makes re-imports free; duplicates resolve at drain time via bulk-upload-check).
  private func enqueue() async {
    do {
      let rows = try await state.enqueueImport(urls: urls, destination: destination)
      enqueuedNote = rows.isEmpty
        ? "Nothing new — these files are already queued or uploaded."
        : "Queued \(rows.count) file\(rows.count == 1 ? "" : "s") for upload."
      staged = true
    } catch {
      importError = error.localizedDescription
    }
  }
}

extension SharedLibraryPrefs {
  func defaultUploadTargetLabel(spaces: [(space: Space, role: SharedSpaceRoleKind)]) -> String {
    switch defaultUploadTarget {
    case .personal: return "Personal"
    case .space(let id):
      return spaces.first(where: { $0.space.id == id })?.space.name ?? "Shared Library"
    }
  }
}
