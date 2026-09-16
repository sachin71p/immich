import AppKit
import CoreModel
import Foundation
import LocalStore
import SwiftUI
import Upload

import ImageCaptureCore

/// A5 brief task 6: file/folder import + camera/SD-card import via ImageCaptureCore.
///
/// Supported file types mirror the server's still/video ingestion (still ingestion detail
/// belongs to the server; the client filters by extension to avoid enqueueing sidecars).
enum MacFileImporter {
  static let supportedExtensions: Set<String> = [
    "heic", "heif", "jpg", "jpeg", "png", "dng", "tif", "tiff", "webp", "gif",
    "mp4", "mov", "m4v",
  ]
  static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

  /// Destination tag from the chooser ("default" | "personal" | "space:<id>").
  static func explicitTarget(
    for destination: String, prefs: SharedLibraryPrefs
  ) -> UploadTargetResolver.ExplicitTarget {
    if destination == "personal" { return .personal }
    if destination.hasPrefix("space:") {
      return .space(String(destination.dropFirst("space:".count)))
    }
    switch prefs.defaultUploadTarget {
    case .personal: return .personal
    case .space(let id): return .space(id)
    }
  }

  /// Expands dropped files/folders to importable file URLs (recursive, extension-filtered).
  static func expand(urls: [URL]) -> [URL] {
    var out: [URL] = []
    let keys: [URLResourceKey] = [.isDirectoryKey]
    for url in urls {
      guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
      if values.isDirectory == true {
        guard let enumerator = FileManager.default.enumerator(
          at: url, includingPropertiesForKeys: [.isDirectoryKey])
        else { continue }
        for case let file as URL in enumerator {
          if (try? file.resourceValues(forKeys: Set(keys)).isDirectory) == true { continue }
          if supportedExtensions.contains(file.pathExtension.lowercased()) {
            out.append(file)
          }
        }
      } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
        out.append(url)
      }
    }
    return out
  }

  static func spec(
    for file: URL, explicitTarget: UploadTargetResolver.ExplicitTarget
  ) -> FileUploadSpec {
    let values = try? file.resourceValues(
      forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
    let isVideo = videoExtensions.contains(file.pathExtension.lowercased())
    return FileUploadSpec(
      fileURL: file, fileName: file.lastPathComponent,
      fileCreatedAt: values?.creationDate, fileModifiedAt: values?.contentModificationDate,
      isVideo: isVideo, explicitTarget: explicitTarget)
  }
}

extension MacAppState {
  /// A5 wiring for the A4 import chooser: expands, checksums, dedupes and enqueues.
  /// Returns the rows actually inserted.
  @discardableResult
  func enqueueImport(urls: [URL], destination: String) async throws -> [QueuedUpload] {
    let target = MacFileImporter.explicitTarget(for: destination, prefs: prefs)
    let rows = try MacFileImporter.expand(urls: urls).map { file in
      try UploadEnqueuePlan.single(
        MacFileImporter.spec(for: file, explicitTarget: target), prefs: prefs)
    }
    return try await store.enqueueUploads(rows)
  }
}

/// Camera/SD-card browser + importer (brief task 6). "Import all new" skips fingerprints
/// recorded in shared defaults; delete-after-import follows `prefs.deleteAfterImport`
/// (decided A5 #2 — defaults to KEEP).
@MainActor
final class MacCameraBrowser: NSObject, ObservableObject {
  @Published var devices: [ICCameraDevice] = []
  @Published var items: [ICCameraItem] = []
  @Published var selectedIDs: Set<String> = []
  @Published var status: String?
  @Published var isImporting = false

  private let browser = ICDeviceBrowser()
  private var state: MacAppState?

  override init() {
    super.init()
    browser.delegate = self
    browser.browsedDeviceTypeMask = .camera
  }

  func attach(_ state: MacAppState) {
    self.state = state
    browser.start()
  }

  func detach() {
    browser.stop()
  }

  var importedFingerprints: Set<String> {
    get { Set(SharedContainer.sharedDefaults.stringArray(forKey: "Heirloom.importedCamera") ?? []) }
    set { SharedContainer.sharedDefaults.set(Array(newValue), forKey: "Heirloom.importedCamera") }
  }

  static func fingerprint(for item: ICCameraItem) -> String {
    let fileSize = (item as? ICCameraFile)?.fileSize ?? 0
    return "\(item.name ?? "?")|\(fileSize)|\(item.uti ?? "?")"
  }

  /// Downloads each item to staging, enqueues it, and optionally deletes it from the device.
  func importItems(_ items: [ICCameraItem]) async {
    guard let state else { return }
    isImporting = true
    defer { isImporting = false }
    let target = MacFileImporter.explicitTarget(
      for: SharedContainer.sharedDefaults.string(forKey: "Heirloom.importDestination")
        ?? "default",
      prefs: state.prefs)
    var fingerprints = importedFingerprints
    for item in items {
      do {
        guard let file = item as? ICCameraFile else { continue }
        let staged = try await download(file: file)
        let spec = MacFileImporter.spec(for: staged, explicitTarget: target)
        _ = try await state.store.enqueueUploads(
          [try UploadEnqueuePlan.single(spec, prefs: state.prefs)])
        fingerprints.insert(Self.fingerprint(for: item))
        // Decided A5 #2: delete-after-import defaults to KEEP; only delete on explicit opt-in.
        if state.prefs.deleteAfterImport, let device = file.device as? ICCameraDevice {
          device.requestDeleteFiles([file])
        }
      } catch is CancellationError {
        // Cancellation isn't a failure: skip the item with no status noise.
      } catch {
        HeirloomLog.ui.error(
          "Camera import failed: \(error.localizedDescription, privacy: .public)")
        status = "Import failed for \(item.name ?? "item"): \(error.localizedDescription)"
      }
    }
    importedFingerprints = fingerprints
  }

  func importAllNew() async {
    let known = importedFingerprints
    await importItems(items.filter { !known.contains(Self.fingerprint(for: $0)) })
  }

  private func download(file: ICCameraFile) async throws -> URL {
    let staging = FileManager.default.temporaryDirectory
      .appendingPathComponent("HeirloomStaging", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let saveAsName = "\(UUID().uuidString)-\(file.name ?? "import")"
    let options: [ICDownloadOption: Any] = [
      .downloadsDirectoryURL: staging,
      .saveAsFilename: saveAsName,
    ]
    try await file.device?.requestOpenSession()
    return try await withCheckedThrowingContinuation { continuation in
      _ = file.requestDownload(options: options) { savedFilename, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: staging.appendingPathComponent(savedFilename ?? saveAsName))
        }
      }
    }
  }
}

extension MacCameraBrowser: @MainActor ICDeviceBrowserDelegate {
  func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
    Task { try? await device.requestOpenSession() }
    if let camera = device as? ICCameraDevice {
      devices.append(camera)
    }
  }

  func deviceBrowser(
    _ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool
  ) {
    devices.removeAll { $0 === (device as AnyObject) }
  }
}

extension MacCameraBrowser: @MainActor ICDeviceDelegate {
  func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
    if let error { status = "Could not open device: \(error.localizedDescription)" }
  }

  func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
    if let error { status = "Could not close device: \(error.localizedDescription)" }
  }

  func didRemove(_ device: ICDevice) {
    devices.removeAll { $0 === (device as AnyObject) }
  }

  func deviceDidBecomeReady(_ device: ICDevice) {
    guard let camera = device as? ICCameraDevice else { return }
    items = camera.mediaFiles ?? []
  }

  func cameraDevice(_ camera: ICCameraDevice, didAddItems items: [ICCameraItem]) {
    self.items.append(contentsOf: items)
  }

  func cameraDevice(_ camera: ICCameraDevice, didRemoveItems items: [ICCameraItem]) {
    let removed = Set(items.map { ObjectIdentifier($0) })
    self.items.removeAll { removed.contains(ObjectIdentifier($0)) }
  }

  func device(_ device: ICDevice, didEncounterError error: Error?) {
    if let error { status = error.localizedDescription }
  }
}

/// Camera/SD import sheet (brief task 6): device picker, thumbnails, select, "import all new",
/// destination follows the import-destination default, delete-after-import toggle (KEEP by
/// default — decided A5 #2), duplicate skip via queue checksum dedupe + bulk-upload-check.
struct MacCameraImportView: View {
  @Bindable var state: MacAppState
  @StateObject private var browser = MacCameraBrowser()
  @State private var selectedDeviceName: String?
  @State private var pendingCount = 0
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Import from Camera").font(.headline)
      if browser.devices.isEmpty {
        Text("No cameras or SD cards found. Connect a device and make sure it is unlocked.")
          .foregroundStyle(.secondary)
      } else {
        Picker("Device", selection: $selectedDeviceName) {
          ForEach(browser.devices, id: \.name) { device in
            Text(device.name ?? "Camera").tag(device.name as String?)
          }
        }
        .accessibilityIdentifier("camera-device-picker")
        .onChange(of: selectedDeviceName) { _, _ in browser.selectedIDs.removeAll() }
        List {
          ForEach(visibleItems.indices, id: \.self) { index in
            let item = visibleItems[index]
            let fingerprint = MacCameraBrowser.fingerprint(for: item)
            Button {
              if browser.selectedIDs.contains(fingerprint) {
                browser.selectedIDs.remove(fingerprint)
              } else {
                browser.selectedIDs.insert(fingerprint)
              }
            } label: {
              HStack {
                CameraThumbnail(item: item)
                VStack(alignment: .leading) {
                  Text(item.name ?? "Photo").font(.body)
                  Text(Self.detail(for: item)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if browser.importedFingerprints.contains(fingerprint) {
                  Text("Imported").font(.caption).foregroundStyle(.secondary)
                } else if browser.selectedIDs.contains(fingerprint) {
                  Image(systemName: "checkmark")
                }
              }
            }
            .buttonStyle(.plain)
          }
        }
        .frame(minHeight: 240)
        .accessibilityIdentifier("camera-item-list")
        Toggle(
          "Delete from device after import",
          isOn: Binding(
            get: { state.prefs.deleteAfterImport },
            set: { value in Task { await updatePrefs { $0.deleteAfterImport = value } } }
          )
        )
        .help("Off (default) keeps the files on the camera/SD card.")
        .accessibilityIdentifier("camera-delete-after-import")
        HStack {
          Button("Import All New") {
            Task {
              await browser.importItems(newItems)
              await refreshPending()
            }
          }
          .disabled(browser.isImporting)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("camera-import-new")
          Button("Import Selected") {
            Task {
              await browser.importItems(
                visibleItems.filter { browser.selectedIDs.contains(
                  MacCameraBrowser.fingerprint(for: $0)) })
              await refreshPending()
            }
          }
          .disabled(browser.isImporting || browser.selectedIDs.isEmpty)
          .accessibilityIdentifier("camera-import-selected")
          Spacer()
          if pendingCount > 0 {
            Text("\(pendingCount) queued").font(.caption).foregroundStyle(.secondary)
          }
          Button("Done") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
      }
      if let status = browser.status {
        Text(status).foregroundStyle(.red).font(.caption)
      }
    }
    .padding()
    .frame(minWidth: 520, minHeight: 420)
    .task {
      browser.attach(state)
      if selectedDeviceName == nil {
        selectedDeviceName = browser.devices.first?.name
      }
      await refreshPending()
    }
    .onDisappear { browser.detach() }
  }

  private var visibleItems: [ICCameraItem] {
    guard let name = selectedDeviceName else { return browser.items }
    return browser.items.filter { ($0.device as? ICCameraDevice)?.name == name }
  }

  private var newItems: [ICCameraItem] {
    let known = browser.importedFingerprints
    return visibleItems.filter { !known.contains(MacCameraBrowser.fingerprint(for: $0)) }
  }

  private static func detail(for item: ICCameraItem) -> String {
    let mb = Double((item as? ICCameraFile)?.fileSize ?? 0) / 1_000_000
    return String(format: "%.1f MB · %@", mb, item.uti ?? "image")
  }

  private func updatePrefs(_ mutate: (inout SharedLibraryPrefs) -> Void) async {
    guard let userId = state.userId else { return }
    var prefs = state.prefs
    mutate(&prefs)
    try? await state.store.setPrefs(prefs, for: userId)
    state.prefs = prefs
  }

  private func refreshPending() async {
    pendingCount = (try? await state.store.pendingUploadCount()) ?? 0
    // Best-known count for the WP4 quit guard (rechecked live before prompting).
    HeirloomQuitGuard.shared.pendingUploads = pendingCount
  }
}

/// Camera-file thumbnail (requests the device-provided thumbnail blob; falls back to a glyph).
struct CameraThumbnail: View {
  var item: ICCameraItem
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Image(systemName: "photo")
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 48, height: 48)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .task(id: item.name) {
      guard let file = item as? ICCameraFile else { return }
      let data: Data? = await withCheckedContinuation { continuation in
        file.requestThumbnailData(options: nil) { data, _ in
          continuation.resume(returning: data)
        }
      }
      if let data, let loaded = NSImage(data: data) {
        image = loaded
      }
    }
  }
}
