import CoreModel
import LocalStore
import UIKit
import UniformTypeIdentifiers
import Upload

/// A9.6: "Save to <library>" share extension.
///
/// Receives images/videos from any host app, copies them into the app-group inbox, and
/// enqueues upload rows in the SAME shared `PhotosLocalStore` queue the foreground
/// scheduler and background-upload extension drain (decided A5 #3). The destination list
/// comes from the `ExtensionSnapshot` the main app publishes — personal plus spaces
/// (external libraries are never upload targets, per `UploadTargetResolver`).
@objc(HeirloomShareViewController)
final class HeirloomShareViewController: UIViewController {
  private enum SharedAccess {
    static let groupIdentifier = "group.com.immich.heirloom.shared"
    static let snapshotFileName = "extension-snapshot.json"
    static let inboxDirectoryName = "share-inbox"

    static func containerURL() -> URL? {
      FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    static func snapshotLibraries() -> [(id: String, name: String)] {
      guard let container = containerURL(),
        let data = try? Data(contentsOf: container.appendingPathComponent(snapshotFileName)),
        let snapshot = try? JSONDecoder().decode(ExtensionSnapshot.self, from: data)
      else {
        return [(id: "personal", name: "Personal")]
      }
      return snapshot.libraries.map { ($0.id, $0.name) }
    }

    static func databaseURL() throws -> URL {
      guard let container = containerURL() else { throw ShareError.noSharedContainer }
      try FileManager.default.createDirectory(
        at: container, withIntermediateDirectories: true, attributes: nil)
      return container.appendingPathComponent("heirloom.sqlite")
    }

    static func inboxURL() throws -> URL {
      guard let container = containerURL() else { throw ShareError.noSharedContainer }
      let inbox = container.appendingPathComponent(inboxDirectoryName, isDirectory: true)
      try FileManager.default.createDirectory(
        at: inbox, withIntermediateDirectories: true, attributes: nil)
      return inbox
    }
  }

  private var destinations: [(id: String, name: String)] = []
  private var selectedDestination = 0
  private var itemCount = 0
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let statusLabel = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    title = "Save to Heirloom"
    destinations = SharedAccess.snapshotLibraries()
    itemCount = extensionContext?.inputItems.count ?? 0
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "Save", style: .done, target: self, action: #selector(save))

    statusLabel.text = itemCount == 1
      ? "1 item will upload to the selected library."
      : "\(itemCount) items will upload to the selected library."
    statusLabel.font = .preferredFont(forTextStyle: .footnote)
    statusLabel.textColor = .secondaryLabel
    statusLabel.numberOfLines = 0
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    tableView.dataSource = self
    tableView.delegate = self
    tableView.translatesAutoresizingMaskIntoConstraints = false
    spinner.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(tableView)
    view.addSubview(statusLabel)
    view.addSubview(spinner)
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  @objc private func cancel() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }

  @objc private func save() {
    navigationItem.rightBarButtonItem?.isEnabled = false
    spinner.startAnimating()
    let items = extensionContext?.inputItems ?? []
    let destinationId = destinations[selectedDestination].id
    let context = extensionContext
    Task { @MainActor in
      do {
        let saved = try await Self.saveAttachments(
          from: items,
          destinationId: destinationId)
        await MainActor.run {
          statusLabel.text = saved == 1
            ? "Saved 1 item — it uploads when Heirloom next runs."
            : "Saved \(saved) items — they upload when Heirloom next runs."
        }
        try? await Task.sleep(for: .seconds(1))
        context?.completeRequest(returningItems: nil, completionHandler: nil)
      } catch {
        await MainActor.run {
          self.spinner.stopAnimating()
          statusLabel.text = "Could not save: \(error.localizedDescription)"
          navigationItem.rightBarButtonItem?.isEnabled = true
        }
      }
    }
  }

  private static func explicitTarget(for destinationId: String) -> UploadTargetResolver.ExplicitTarget {
    if destinationId.hasPrefix("space:") {
      return .space(String(destinationId.dropFirst("space:".count)))
    }
    return .personal
  }

  private static func saveAttachments(
    from inputItems: [Any], destinationId: String
  ) async throws -> Int {
    let inbox = try SharedAccess.inboxURL()
    let dbURL = try SharedAccess.databaseURL()
    let store = try PhotosLocalStore(path: dbURL.path)
    let prefs = (try? await store.anyPrefs()) ?? SharedLibraryPrefs()
    var rows: [QueuedUpload] = []
    var staged = 0
    for item in inputItems {
      guard let extensionItem = item as? NSExtensionItem,
        let attachments = extensionItem.attachments
      else { continue }
      for provider in attachments {
        guard
          let stagedFile = try await stageProvider(provider, inbox: inbox, index: staged)
        else {
          continue
        }
        staged += 1
        let spec = FileUploadSpec(
          fileURL: stagedFile.url, fileName: stagedFile.fileName,
          fileCreatedAt: Date(), fileModifiedAt: Date(),
          isVideo: stagedFile.isVideo,
          explicitTarget: explicitTarget(for: destinationId))
        rows.append(try UploadEnqueuePlan.single(spec, prefs: prefs))
      }
    }
    if !rows.isEmpty {
      _ = try await store.enqueueUploads(rows)
    }
    return staged
  }

  private struct StagedFile {
    var url: URL
    var fileName: String
    var isVideo: Bool
  }

  private static func stageProvider(
    _ provider: NSItemProvider, inbox: URL, index: Int
  ) async throws -> StagedFile? {
    let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
    let typeId = isVideo ? UTType.movie.identifier : UTType.image.identifier
    let sourceURL: URL = try await withCheckedThrowingContinuation { continuation in
      _ = provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, error in
        if let url {
          continuation.resume(returning: url)
        } else {
          continuation.resume(throwing: error ?? ShareError.unreadableAttachment)
        }
      }
    }
    let ext = sourceURL.pathExtension.isEmpty
      ? (isVideo ? "mov" : "jpg") : sourceURL.pathExtension
    let base = (provider.suggestedName as NSString?)?.deletingPathExtension
      ?? "share-\(index)"
    let fileName = "\(base).\(ext)"
    let staged = inbox.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    try FileManager.default.copyItem(at: sourceURL, to: staged)
    return StagedFile(url: staged, fileName: fileName, isVideo: isVideo)
  }
}

extension HeirloomShareViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    destinations.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "destination")
      ?? UITableViewCell(style: .default, reuseIdentifier: "destination")
    let destination = destinations[indexPath.row]
    cell.textLabel?.text = destination.name
    cell.accessoryType = indexPath.row == selectedDestination ? .checkmark : .none
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    selectedDestination = indexPath.row
    tableView.reloadData()
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    "Library"
  }
}

enum ShareError: Error {
  case noSharedContainer
  case unreadableAttachment
}
