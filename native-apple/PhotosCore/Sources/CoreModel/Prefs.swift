/// Mirrors the fork's `sharedLibraries.*` user preferences — DECISIONS §9. Synced via `UserMetadataV1`
/// (`server/src/enum.ts` `UserMetadataKey`, key `sharedLibraries`) and pushed back with
/// `PUT /users/me/preferences`.
public struct SharedLibraryPrefs: Sendable, Hashable, Codable {
  public enum UploadTarget: Sendable, Hashable, Codable {
    case personal
    case space(String)
  }

  public var defaultUploadTarget: UploadTarget
  public var showPersonalInTimeline: Bool
  public var hiddenOwnedLibraryIds: [String]

  // A5 backup & upload (DECISIONS §9; the server prefs slice only carries the three fields
  // above — the rest persist locally via `LocalStore.setPrefs`, never `PUT /users/me/preferences`).
  public var backupEnabled: Bool
  /// Selected device-album ids (iOS) or named sources feeding the backup scanner.
  public var backupAlbumIds: [String]
  public var useCellularForPhotos: Bool
  public var useCellularForVideos: Bool
  public var allowLowPowerUploads: Bool
  /// Decided A5 #1: original only vs original + a rendered-edit copy (two records, paired).
  public var uploadOriginalPlusEdit: Bool
  /// Decided A5 #2: camera/SD delete-after-import. Defaults to KEEP (false).
  public var deleteAfterImport: Bool

  public init(
    defaultUploadTarget: UploadTarget = .personal,
    showPersonalInTimeline: Bool = true,
    hiddenOwnedLibraryIds: [String] = [],
    backupEnabled: Bool = false,
    backupAlbumIds: [String] = [],
    useCellularForPhotos: Bool = false,
    useCellularForVideos: Bool = false,
    allowLowPowerUploads: Bool = false,
    uploadOriginalPlusEdit: Bool = false,
    deleteAfterImport: Bool = false
  ) {
    self.defaultUploadTarget = defaultUploadTarget
    self.showPersonalInTimeline = showPersonalInTimeline
    self.hiddenOwnedLibraryIds = hiddenOwnedLibraryIds
    self.backupEnabled = backupEnabled
    self.backupAlbumIds = backupAlbumIds
    self.useCellularForPhotos = useCellularForPhotos
    self.useCellularForVideos = useCellularForVideos
    self.allowLowPowerUploads = allowLowPowerUploads
    self.uploadOriginalPlusEdit = uploadOriginalPlusEdit
    self.deleteAfterImport = deleteAfterImport
  }
}
