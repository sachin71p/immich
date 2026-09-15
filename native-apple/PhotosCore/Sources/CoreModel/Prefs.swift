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

  public init(
    defaultUploadTarget: UploadTarget = .personal,
    showPersonalInTimeline: Bool = true,
    hiddenOwnedLibraryIds: [String] = []
  ) {
    self.defaultUploadTarget = defaultUploadTarget
    self.showPersonalInTimeline = showPersonalInTimeline
    self.hiddenOwnedLibraryIds = hiddenOwnedLibraryIds
  }
}
