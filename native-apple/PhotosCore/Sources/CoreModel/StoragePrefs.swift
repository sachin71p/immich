/// A6 storage-optimization preferences — mirrors the `SharedLibraryPrefs` pattern
/// (local-only JSON in `LocalStore`'s `userMetadata` slot under key `"storage"`, never
/// `PUT /users/me/preferences`): the server prefs slice carries no storage keys.
public struct StoragePrefs: Sendable, Hashable, Codable {
  /// "Optimize storage": shrink the original-tier disk budget and keep thumbnails.
  public var optimizeStorage: Bool
  /// Original-tier budget in bytes, `nil` = unlimited ("Download originals" mode).
  public var originalTierBudgetBytes: Int?
  /// Per-library/album container ids whose originals stay on this Mac ("Keep originals
  /// on this Mac"). Consulted when originals download; pins protect bytes from eviction.
  public var pinnedContainerIds: [String]
  /// Free-up-space: keep favorites (default on, upstream parity).
  public var keepFavoritesOnFreeUp: Bool
  /// Free-up-space: only offer photos older than N days (`nil` = no age window).
  public var freeUpKeepLastNDays: Int?
  /// Free-up-space: device-album ids to keep (multi-select, empty = keep none specially).
  public var freeUpKeepAlbumIds: [String]
  /// Post-backup: show the explicit free-up-space prompt (never delete silently).
  public var suggestFreeUpAfterBackup: Bool

  public init(
    optimizeStorage: Bool = false,
    originalTierBudgetBytes: Int? = nil,
    pinnedContainerIds: [String] = [],
    keepFavoritesOnFreeUp: Bool = true,
    freeUpKeepLastNDays: Int? = 30,
    freeUpKeepAlbumIds: [String] = [],
    suggestFreeUpAfterBackup: Bool = true
  ) {
    self.optimizeStorage = optimizeStorage
    self.originalTierBudgetBytes = originalTierBudgetBytes
    self.pinnedContainerIds = pinnedContainerIds
    self.keepFavoritesOnFreeUp = keepFavoritesOnFreeUp
    self.freeUpKeepLastNDays = freeUpKeepLastNDays
    self.freeUpKeepAlbumIds = freeUpKeepAlbumIds
    self.suggestFreeUpAfterBackup = suggestFreeUpAfterBackup
  }

  // MARK: - cache budget slider (iOS + macOS share the steps; defaults differ)

  /// Slider steps in bytes, `0` = purge originals down to nothing. Both platforms step
  /// through this same range; macOS just defaults higher (desktop-sized).
  public static let budgetStepsBytes: [Int] = [
    0,
    256 * 1_000_000,
    512 * 1_000_000,
    1_000_000_000,
    2_000_000_000,
    4_000_000_000,
    8_000_000_000,
  ]

  /// iOS default original-tier budget — matches `CacheBudgets.defaults[.original]`.
  public static let iOSDefaultOriginalBudgetBytes = 256 * 1_000_000
  /// macOS default original-tier budget — desktop-sized mirror of the iOS default.
  public static let macDefaultOriginalBudgetBytes = 2_000_000_000

  public func isPinnedContainer(_ id: String) -> Bool {
    pinnedContainerIds.contains(id)
  }
}
