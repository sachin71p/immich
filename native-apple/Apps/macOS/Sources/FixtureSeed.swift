import CoreModel
import Foundation
import LocalStore

/// Deterministic in-memory world for `--fixture-seed` UI-smoke launches and previews.
/// Built only through the public `PhotosLocalStore.apply()` path, so the seeded rows exercise
/// the same mapping production sync data flows through. Small on purpose: one asset per exercised
/// container/flag, dates across three years for the Years/Months/All control.
enum FixtureSeed {
  static let userId = "user-alice"
  static let bobId = "user-bob"
  static let spaceId = "space-family"
  static let libraryId = "library-archive"
  static let albumId = "album-trip"

  private static func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 0)
  }

  private static func asset(
    _ id: String, owner: String, name: String, dateISO: String,
    type: AssetKind = .image, space: String? = nil, library: String? = nil,
    favorite: Bool = false, visibility: AssetVisibilityKind = .timeline, trashed: Bool = false
  ) -> Asset {
    Asset(
      id: id, ownerId: owner, originalFileName: name, checksum: "checksum-\(id)",
      createdAt: date(dateISO), localDateTime: date(dateISO), type: type,
      deletedAt: trashed ? date("2024-07-01T00:00:00Z") : nil,
      isFavorite: favorite, visibility: visibility,
      libraryId: library, spaceId: space, width: 4000, height: 3000
    )
  }

  static func changes() -> [SyncChange] {
    let alice = User(id: userId, name: "Alice", email: "alice@example.com")
    let bob = User(id: bobId, name: "Bob", email: "bob@example.com")
    let space = Space(
      id: spaceId, name: "Family", description: "Seed space",
      createdAt: date("2023-01-01T00:00:00Z"), updatedAt: date("2023-01-01T00:00:00Z")
    )
    let library = Library(
      id: libraryId, name: "Archive", ownerId: userId,
      createdAt: date("2023-01-01T00:00:00Z"), updatedAt: date("2023-01-01T00:00:00Z")
    )
    let album = Album(
      id: albumId, name: "Trip", description: "Seed album",
      createdAt: date("2024-05-01T00:00:00Z"), updatedAt: date("2024-05-01T00:00:00Z")
    )
    return [
      .user(alice), .user(bob),
      .space(space),
      .spaceMember(SpaceMember(spaceId: spaceId, userId: userId, role: .owner, showInTimeline: true)),
      .spaceMember(SpaceMember(spaceId: spaceId, userId: bobId, role: .contributor, showInTimeline: true)),
      .library(library),
      .album(album),
      .albumUser(AlbumMember(albumId: albumId, userId: userId, role: .editor)),
      .albumUser(AlbumMember(albumId: albumId, userId: bobId, role: .viewer)),
      .asset(asset("asset-personal-1", owner: userId, name: "IMG_0001.HEIC", dateISO: "2024-06-01T12:00:00Z", favorite: true)),
      .asset(asset("asset-personal-2", owner: userId, name: "IMG_0002.JPG", dateISO: "2023-01-15T12:00:00Z")),
      .assetExif(AssetExif(assetId: "asset-personal-2", latitude: 37.7749, longitude: -122.4194, make: "SeedCam")),
      .asset(asset("asset-space-video", owner: userId, name: "VID_0003.MOV", dateISO: "2024-06-02T12:00:00Z", type: .video, space: spaceId)),
      .asset(asset("asset-space-shot", owner: bobId, name: "Screenshot 2022-11-20.png", dateISO: "2022-11-20T12:00:00Z", space: spaceId)),
      .asset(asset("asset-library-1", owner: userId, name: "IMG_0005.DNG", dateISO: "2023-05-10T12:00:00Z", library: libraryId)),
      .asset(asset("asset-trashed", owner: userId, name: "IMG_0006.JPG", dateISO: "2024-01-01T12:00:00Z", trashed: true)),
      .asset(asset("asset-archived", owner: userId, name: "IMG_0007.JPG", dateISO: "2023-08-08T12:00:00Z", visibility: .archive)),
      .albumAsset(albumId: albumId, assetId: "asset-personal-1"),
      .albumAsset(albumId: albumId, assetId: "asset-space-video"),
    ]
  }
}
