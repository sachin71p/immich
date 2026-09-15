import CoreModel

/// Everything `Permissions` and `MoveTargets` need about the signed-in user's memberships, pre-computed
/// by `LocalStore` from `spaces`/`space_members`/`libraries`/`library_members`/`album_users` so these
/// pure functions never touch the database themselves.
public struct AccessContext: Sendable {
  public var currentUserId: String
  /// Space ids the current user is a member of (owner or contributor) — DECISIONS §4.
  public var memberSpaceIds: Set<String>
  /// Library ids the current user owns or is a member of — DECISIONS §4 "external library sharing".
  public var accessibleLibraryIds: Set<String>
  /// Library ids the current user owns (subset of `accessibleLibraryIds`).
  public var ownedLibraryIds: Set<String>
  /// Library ids that have `uploadPath` set — DECISIONS §6 rule 4.
  public var libraryUploadPathIds: Set<String>
  /// Ids of assets that are locked (`visibility == .locked`) — DECISIONS §6 rule 9, §10 "Locked view".
  public var lockedAssetIds: Set<String>
  /// Album ids containing a given asset that the current user is a member of — filled in per call by the
  /// caller (`LocalStore` knows `album_assets`); DECISIONS §4 favorites note.
  public var memberAlbumIdsByAsset: [String: Set<String>]

  public init(
    currentUserId: String,
    memberSpaceIds: Set<String> = [],
    accessibleLibraryIds: Set<String> = [],
    ownedLibraryIds: Set<String> = [],
    libraryUploadPathIds: Set<String> = [],
    lockedAssetIds: Set<String> = [],
    memberAlbumIdsByAsset: [String: Set<String>] = [:]
  ) {
    self.currentUserId = currentUserId
    self.memberSpaceIds = memberSpaceIds
    self.accessibleLibraryIds = accessibleLibraryIds
    self.ownedLibraryIds = ownedLibraryIds
    self.libraryUploadPathIds = libraryUploadPathIds
    self.lockedAssetIds = lockedAssetIds
    self.memberAlbumIdsByAsset = memberAlbumIdsByAsset
  }

  func memberAlbumIds(for assetId: String) -> Set<String> {
    memberAlbumIdsByAsset[assetId] ?? []
  }
}
