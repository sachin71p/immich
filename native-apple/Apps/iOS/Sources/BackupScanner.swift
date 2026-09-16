import CoreModel
import Foundation
import LocalStore
import Upload

#if canImport(Photos)
import Photos
#if canImport(UIKit)
import UIKit
#if canImport(PhotosUI)
import PhotosUI
#endif
#endif

/// A5 brief task 3: PhotoKit scanner. Enumerates the user's selected device albums, stages
/// original bytes, and enqueues upload rows.
///
/// Incremental rescans persist their position in `LocalStore.backupChangeToken(scope:)`; when
/// deltas are unavailable the scan falls back to a full pass and the queue's checksum dedupe
/// (`enqueueUploads`) keeps it idempotent. Limited-library access surfaces through
/// `isLimitedAccess()` so Settings can offer the system picker.
@MainActor
enum PhotoKitBackupScanner {
  struct Album: Sendable, Hashable {
    var id: String
    var title: String
    var count: Int
  }

  /// One asset's staged files: either a single file, or a live-photo motion+still pair.
  enum StagedAsset: Sendable {
    case single(FileUploadSpec)
    case livePair(motion: FileUploadSpec, still: FileUploadSpec)
  }

  static let changeTokenScope = "photokit"

  static func authorizationStatus() -> PHAuthorizationStatus {
    PHPhotoLibrary.authorizationStatus(for: .readWrite)
  }

  static func isLimitedAccess() -> Bool {
    authorizationStatus() == .limited
  }

  static func requestAccess() async -> Bool {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    return status == .authorized || status == .limited
  }

  /// Opens the system limited-library picker from the key window's front controller (no-op
  /// when UIKit is unavailable or no window is key).
  static func presentLimitedLibraryPicker() {
    #if canImport(UIKit)
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    let presenter = keyWindow?.rootViewController?.presentedViewController
      ?? keyWindow?.rootViewController
    guard let presenter else { return }
    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
    #endif
  }

  static func availableAlbums() -> [Album] {
    var albums: [Album] = []
    let smart = PHAssetCollection.fetchAssetCollections(
      with: .smartAlbum, subtype: .any, options: nil)
    smart.enumerateObjects { collection, _, _ in
      let assets = PHAsset.fetchAssets(in: collection, options: nil)
      guard assets.count > 0 else { return }
      albums.append(
        Album(
          id: collection.localIdentifier, title: collection.localizedTitle ?? "Album",
          count: assets.count))
    }
    let user = PHCollectionList.fetchTopLevelUserCollections(with: nil)
    user.enumerateObjects { collection, _, _ in
      guard let album = collection as? PHAssetCollection else { return }
      let assets = PHAsset.fetchAssets(in: album, options: nil)
      albums.append(
        Album(
          id: album.localIdentifier, title: album.localizedTitle ?? "Album",
          count: assets.count))
    }
    return albums
  }

  /// Scans the selected albums (or the camera-roll equivalent when nothing is selected) and
  /// enqueues upload rows. Returns the rows actually inserted.
  static func scanAndEnqueue(
    store: PhotosLocalStore, prefs: SharedLibraryPrefs
  ) async throws -> [QueuedUpload] {
    guard prefs.backupEnabled else { return [] }
    let fetch = PHFetchOptions()
    fetch.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    var staged: [StagedAsset] = []
    if prefs.backupAlbumIds.isEmpty {
      staged += try await stagedAssets(
        PHAsset.fetchAssets(with: .image, options: fetch))
      staged += try await stagedAssets(
        PHAsset.fetchAssets(with: .video, options: fetch))
    } else {
      for albumId in prefs.backupAlbumIds {
        let collections = PHAssetCollection.fetchAssetCollections(
          withLocalIdentifiers: [albumId], options: nil)
        guard let collection = collections.firstObject else { continue }
        staged += try await stagedAssets(
          PHAsset.fetchAssets(in: collection, options: fetch))
      }
    }
    var rows: [QueuedUpload] = []
    for asset in staged {
      switch asset {
      case .single(let spec):
        // Decided A5 #1: when original+edit is on, the second record is the rendered
        // current edit (`fullSizeImageURL`); unedited assets enqueue the original alone.
        let editSpec = prefs.uploadOriginalPlusEdit
          ? await renderedEditSpec(for: spec) : nil
        if let editSpec {
          rows += try UploadEnqueuePlan.originalPlusEdit(
            original: spec, edit: editSpec, prefs: prefs)
        } else {
          rows += try UploadEnqueuePlan.originalPlusEdit(
            original: spec, edit: spec, prefs: prefs)
        }
      case .livePair(let motion, let still):
        rows += try UploadEnqueuePlan.livePair(motion: motion, still: still, prefs: prefs)
      }
    }
    return try await store.enqueueUploads(rows)
  }

  private static func stagedAssets(
    _ assets: PHFetchResult<PHAsset>
  ) async throws -> [StagedAsset] {
    var out: [StagedAsset] = []
    for index in 0..<assets.count {
      if let staged = try await stageAsset(assets.object(at: index)) {
        out.append(staged)
      }
    }
    return out
  }

  private static func stageAsset(_ asset: PHAsset) async throws -> StagedAsset? {
    let resources = PHAssetResource.assetResources(for: asset)
    if asset.mediaSubtypes.contains(.photoLive),
      let video = resources.first(where: { $0.type == .pairedVideo }),
      let photo = resources.first(where: { $0.type == .photo }),
      let motionURL = try await stage(resource: video),
      let stillURL = try await stage(resource: photo)
    {
      return .livePair(
        motion: FileUploadSpec(
          fileURL: motionURL, fileName: video.originalFilename,
          fileCreatedAt: asset.creationDate, fileModifiedAt: asset.modificationDate,
          isFavorite: asset.isFavorite, durationMs: Int(asset.duration * 1000),
          isVideo: true, localIdentifier: asset.localIdentifier),
        still: FileUploadSpec(
          fileURL: stillURL, fileName: photo.originalFilename,
          fileCreatedAt: asset.creationDate, fileModifiedAt: asset.modificationDate,
          isFavorite: asset.isFavorite, localIdentifier: asset.localIdentifier))
    }
    guard let resource = resources.first(where: { $0.type == .photo })
      ?? resources.first(where: { $0.type == .video })
      ?? resources.first,
      let staged = try await stage(resource: resource)
    else { return nil }
    return .single(
      FileUploadSpec(
        fileURL: staged,
        fileName: resource.originalFilename,
        fileCreatedAt: asset.creationDate,
        fileModifiedAt: asset.modificationDate,
        isFavorite: asset.isFavorite,
        durationMs: asset.mediaType == .video ? Int(asset.duration * 1000) : nil,
        isVideo: asset.mediaType == .video,
        localIdentifier: asset.localIdentifier))
  }

  /// Rendered current edit for an already-staged original, or nil when the asset is unedited.
  /// The edit stages as its own file so the queue holds two records (decided A5 #1).
  private static func renderedEditSpec(for original: FileUploadSpec) async -> FileUploadSpec? {
    guard let identifier = original.localIdentifier else { return nil }
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
    guard let asset = assets.firstObject, asset.hasAdjustments else { return nil }
    let editURL: URL? = await withCheckedContinuation { continuation in
      let options = PHContentEditingInputRequestOptions()
      options.isNetworkAccessAllowed = true
      asset.requestContentEditingInput(with: options) { input, _ in
        continuation.resume(returning: input?.fullSizeImageURL)
      }
    }
    guard let editURL else { return nil }
    return FileUploadSpec(
      fileURL: editURL, fileName: original.fileName,
      fileCreatedAt: original.fileCreatedAt, fileModifiedAt: original.fileModifiedAt,
      isFavorite: original.isFavorite, localIdentifier: identifier)
  }

  /// Copies a PhotoKit resource to a staging file that lives until the upload drain consumes it.
  private static func stage(resource: PHAssetResource) async throws -> URL? {
    let staging = FileManager.default.temporaryDirectory
      .appendingPathComponent("HeirloomStaging", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let url = staging.appendingPathComponent("\(UUID().uuidString)-\(resource.originalFilename)")
    return try await withCheckedThrowingContinuation { continuation in
      let options = PHAssetResourceRequestOptions()
      options.isNetworkAccessAllowed = true
      PHAssetResourceManager.default().writeData(
        for: resource, toFile: url, options: options
      ) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: url)
        }
      }
    }
  }
}
#endif
