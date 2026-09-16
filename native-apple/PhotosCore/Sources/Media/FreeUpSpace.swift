import CoreModel
import Foundation

/// A6 "Free up space" (upstream R14 parity): which device photos may be deleted because
/// the server already holds them. PhotoKit-free so both apps and `swift test` share it —
/// the iOS app adapts `PHAsset` rows into `DevicePhoto`.
public struct DevicePhoto: Sendable, Hashable {
  public var localIdentifier: String
  /// Hex SHA1 of the original bytes (same scheme as `UploadSHA1`), used for the server check.
  public var checksum: String
  public var creationDate: Date?
  public var isFavorite: Bool
  /// Device-album ids containing this photo (for "keep selected albums").
  public var albumIds: Set<String>
  public var estimatedBytes: Int

  public init(
    localIdentifier: String,
    checksum: String,
    creationDate: Date? = nil,
    isFavorite: Bool = false,
    albumIds: Set<String> = [],
    estimatedBytes: Int = 0
  ) {
    self.localIdentifier = localIdentifier
    self.checksum = checksum
    self.creationDate = creationDate
    self.isFavorite = isFavorite
    self.albumIds = albumIds
    self.estimatedBytes = estimatedBytes
  }
}

/// User-facing free-up-space options (persisted via `StoragePrefs` on each platform).
public struct FreeUpSpaceOptions: Sendable, Hashable {
  /// Only offer photos taken before this date (`nil` = no explicit cutoff).
  public var cutoffDate: Date?
  public var keepFavorites: Bool
  public var keepAlbumIds: Set<String>
  /// Only offer photos taken more than N days ago (`nil` = no age window).
  public var keepLastNDays: Int?

  public init(
    cutoffDate: Date? = nil,
    keepFavorites: Bool = true,
    keepAlbumIds: Set<String> = [],
    keepLastNDays: Int? = nil
  ) {
    self.cutoffDate = cutoffDate
    self.keepFavorites = keepFavorites
    self.keepAlbumIds = keepAlbumIds
    self.keepLastNDays = keepLastNDays
  }
}

public enum FreeUpSpacePlanner {
  /// `PHAssetChangeRequest.deleteAssets` batch size for the deletion pass.
  public static let deleteBatchSize = 100

  /// Candidates = device photos whose checksum the server just confirmed as a
  /// non-trashed, accessible asset (`backedUpChecksums`, from `BackedUpChecksumVerifier`
  /// at deletion time — never local-DB-only), minus favorites/kept-albums/recent photos.
  /// Photos with an unknown date are never candidates, and with no date bound at all
  /// nothing is offered (refusing an unbounded wipe).
  public static func selectCandidates(
    photos: [DevicePhoto],
    backedUpChecksums: Set<String>,
    options: FreeUpSpaceOptions,
    now: Date = Date()
  ) -> [DevicePhoto] {
    let windowStart: Date? = options.keepLastNDays.map {
      now.addingTimeInterval(-Double(max($0, 0)) * 86_400)
    }
    guard options.cutoffDate != nil || windowStart != nil else { return [] }
    return photos.filter { photo in
      guard backedUpChecksums.contains(photo.checksum) else { return false }
      if options.keepFavorites && photo.isFavorite { return false }
      if !photo.albumIds.isDisjoint(with: options.keepAlbumIds) { return false }
      guard let date = photo.creationDate else { return false }
      if let cutoff = options.cutoffDate, date >= cutoff { return false }
      if let start = windowStart, date >= start { return false }
      return true
    }
  }

  /// Preview counts + bytes for the confirmation screen.
  public static func preview(_ candidates: [DevicePhoto]) -> (count: Int, bytes: Int) {
    (candidates.count, candidates.reduce(0) { $0 + $1.estimatedBytes })
  }

  /// Splits the deletion pass into confirmation-sized batches.
  public static func batches(_ candidates: [DevicePhoto], size: Int = deleteBatchSize) -> [[DevicePhoto]] {
    guard size > 0 else { return candidates.isEmpty ? [] : [candidates] }
    return stride(from: 0, to: candidates.count, by: size).map {
      Array(candidates[$0..<min($0 + size, candidates.count)])
    }
  }
}

/// System-Photos deep links shown after deletion (Recently Deleted holds iOS deletions
/// for 30 days). Fixed constants: iOS exposes no public Photos-album URL, so callers
/// must check `canOpenURL` and fall back to the explanatory text.
public enum FreeUpSpaceLinks {
  public static let recentlyDeletedAlbum = "photos-redirect://"
}

/// Server proof that checksums are backed up, consulted at deletion time.
/// Implementations must hit the server in batches — a local-DB-only check is not enough
/// (the DB can claim an upload the server later trashed or never stored).
public protocol BackedUpChecksumVerifier: Sendable {
  /// Returns the subset of `checksums` confirmed present on the server as non-trashed,
  /// user-accessible assets. Server-missing and server-trashed checksums are excluded.
  func verified(checksums: [String]) async throws -> Set<String>
}
