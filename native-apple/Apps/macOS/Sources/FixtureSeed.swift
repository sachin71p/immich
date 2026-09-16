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

  /// Largest `--fixture-seed-count` honored (brief step 5: N up to 150000).
  static let maxGeneratedCount = 150_000

  /// Reads `--fixture-seed-count=<N>` from the launch arguments (0 / absent =
  /// base fixture only). Parsed here rather than in `MacAppState` so this WP
  /// owns every line of the feature; `seedForSmoke()` keeps calling
  /// `changes()` with no arguments and picks the count up via the default.
  static var requestedCount: Int {
    let prefix = "--fixture-seed-count="
    for arg in CommandLine.arguments where arg.hasPrefix(prefix) {
      if let n = Int(arg.dropFirst(prefix.count)), n > 0 {
        return min(n, maxGeneratedCount)
      }
    }
    return 0
  }

  static func changes(count: Int = requestedCount) -> [SyncChange] {
    var out = baseChanges()
    if count > 0 {
      out += generatedChanges(count: min(count, maxGeneratedCount))
    }
    return out
  }

  static func baseChanges() -> [SyncChange] {
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

  // MARK: - Large synthetic fixture (brief step 5)

  /// One real thumbhash harvested from `MediaPipelineTests` — reused for every
  /// generated asset. Only one genuine sample exists in-tree; per-asset variety
  /// does not matter because the media pipeline runs offline in seeded launches
  /// and cells show placeholders regardless of the hash content.
  private static let generatedThumbhash = "1fsDBYBKeI97iIh4eIiIdweIdIBI"

  /// Cycled (width, height) pairs so the grid exercises varied aspect ratios.
  private static let generatedSizes = [
    (4000, 3000), (3000, 4000), (6000, 4000), (4032, 3024),
    (1920, 1080), (1080, 1920), (1440, 1440),
  ]

  /// Generates `count` primary assets deterministically from the index (no RNG,
  /// so repeated runs seed identical rows). `localDateTime` spreads evenly over
  /// 15 years starting 2011-01-01; the `i % 20` mix yields photos, videos (with
  /// duration), live-photo still+motion pairs and screenshots per the
  /// `TimelineRow(asset:)` classification. Live pairs emit one companion motion
  /// row, so the store ends up with ~5% more rows than `count`.
  static func generatedChanges(count: Int) -> [SyncChange] {
    // 2011-01-01T00:00:00Z through ~2026-01-01 (15 x 365.25 days).
    let base = Date(timeIntervalSince1970: 1_293_840_000)
    let span = 15 * 365.25 * 86_400
    let step = span / Double(max(count, 1))
    var out: [SyncChange] = []
    out.reserveCapacity(count + count / 20 + 1)
    for i in 0..<count {
      let at = base.addingTimeInterval(Double(i) * step)
      let (w, h) = generatedSizes[i % generatedSizes.count]
      let favorite = i % 47 == 0
      let id = "asset-gen-\(i)"
      switch i % 20 {
      case 0:  // Video with duration.
        out.append(.asset(Asset(
          id: id, ownerId: userId, originalFileName: String(format: "VID_%04d.MOV", i),
          thumbhash: generatedThumbhash, checksum: "checksum-\(id)",
          createdAt: at, localDateTime: at, durationSeconds: 10 + (i % 300),
          type: .video, isFavorite: favorite, width: w, height: h
        )))
      case 1:  // Live photo: still linking its motion part via livePhotoVideoId.
        let motionId = "\(id)-motion"
        out.append(.asset(Asset(
          id: motionId, ownerId: userId, originalFileName: String(format: "VID_%04d-live.MOV", i),
          thumbhash: generatedThumbhash, checksum: "checksum-\(motionId)",
          createdAt: at, localDateTime: at, durationSeconds: 3,
          type: .video, width: w, height: h
        )))
        out.append(.asset(Asset(
          id: id, ownerId: userId, originalFileName: String(format: "IMG_%04d-live.HEIC", i),
          thumbhash: generatedThumbhash, checksum: "checksum-\(id)",
          createdAt: at, localDateTime: at, type: .image,
          isFavorite: favorite, livePhotoVideoId: motionId, width: w, height: h
        )))
      case 2:  // Screenshot (`TimelineRow` keys off the filename prefix).
        out.append(.asset(Asset(
          id: id, ownerId: userId, originalFileName: "Screenshot 2020-05-06 at 12.00.\(i % 60).png",
          thumbhash: generatedThumbhash, checksum: "checksum-\(id)",
          createdAt: at, localDateTime: at, type: .image,
          isFavorite: favorite, width: w, height: h
        )))
      default:  // Photo.
        out.append(.asset(Asset(
          id: id, ownerId: userId, originalFileName: String(format: "IMG_%04d.HEIC", i),
          thumbhash: generatedThumbhash, checksum: "checksum-\(id)",
          createdAt: at, localDateTime: at, type: .image,
          isFavorite: favorite, width: w, height: h
        )))
      }
    }
    return out
  }
}
