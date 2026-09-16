import Foundation

/// A9.5/A9.6: the snapshot the iOS app writes into the shared app-group container for the
/// widget, share, and intents extensions to read.
///
/// Extensions must not open the live LocalStore database (it may be write-locked by the app),
/// so the app publishes this small JSON file plus thumbnail JPEGs after each refresh. The
/// group id string is the contract — extension targets mirror it (BackgroundUpload precedent)
/// instead of importing app sources.
public struct ExtensionSnapshot: Sendable, Hashable, Codable {
  public static let fileName = "extension-snapshot.json"
  public static let thumbnailsDirectoryName = "extension-thumbnails"
  public static let inboxDirectoryName = "share-inbox"

  /// Upload destinations the share sheet and upload intent can offer.
  public struct LibraryOption: Sendable, Hashable, Codable {
    /// "personal", "space:<id>", or "library:<id>".
    public var id: String
    public var name: String

    public init(id: String, name: String) {
      self.id = id
      self.name = name
    }
  }

  public struct MemorySummary: Sendable, Hashable, Codable {
    public var title: String
    public var memoryAt: Date
    /// Basename of the memory cover thumbnail inside `thumbnailsDirectoryName`, if written.
    public var thumbnailFileName: String?

    public init(title: String, memoryAt: Date, thumbnailFileName: String? = nil) {
      self.title = title
      self.memoryAt = memoryAt
      self.thumbnailFileName = thumbnailFileName
    }
  }

  public var updatedAt: Date
  public var favoritesCount: Int
  public var locatedCount: Int
  public var favoriteThumbnailFileNames: [String]
  public var memory: MemorySummary?
  public var libraries: [LibraryOption]

  public init(
    updatedAt: Date = Date(),
    favoritesCount: Int = 0,
    locatedCount: Int = 0,
    favoriteThumbnailFileNames: [String] = [],
    memory: MemorySummary? = nil,
    libraries: [LibraryOption] = []
  ) {
    self.updatedAt = updatedAt
    self.favoritesCount = favoritesCount
    self.locatedCount = locatedCount
    self.favoriteThumbnailFileNames = favoriteThumbnailFileNames
    self.memory = memory
    self.libraries = libraries
  }

  /// Resolve a share/intent destination string to an explicit upload target:
  /// nil = personal library, otherwise the space id.
  public func spaceId(forDestination id: String?) -> String? {
    guard let id, id.hasPrefix("space:") else { return nil }
    return String(id.dropFirst("space:".count))
  }
}
