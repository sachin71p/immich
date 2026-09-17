import AVFoundation
import CoreGraphics
import CoreModel
import CoreVideo
import Foundation
import ImageIO
import LocalStore
import UniformTypeIdentifiers

/// Deterministic fixture world for UI tests and previews (WP-T, TEST-PLAN T0).
///
/// Two launch arguments select it (in addition to `-fixture-seed`, which the app
/// shell still requires and which keeps meaning "seeded in-memory world with no
/// server"; the legacy `--fixture-seed` spelling is still accepted):
/// - `-HeirloomFixture small|large`: `small` seeds ~2,000 asset rows, `large` ~102k.
///   Without the flag the fixture is the small curated base set only, so the
///   pre-existing UI tests keep their exact world.
/// - `-HeirloomUITestNoAnimation`: contract flag — see `HeirloomUITestFlags`.
///   Feature WPs check it to skip non-essential animations; UITests always pass it.
///
/// Everything is built only through the public `PhotosLocalStore.apply()` path, so the
/// seeded rows exercise the same mapping production sync data flows through.
///
/// Base-asset dates are all >= 2022 while generated rows span 2011-2021, so the curated
/// assets sort above the generated bulk and stay visible on first paint (the smoke and
/// functional tests address them by identifier without scrolling).
enum FixtureSeed {
  static let userId = "user-alice"
  static let bobId = "user-bob"
  static let spaceId = "space-family"
  static let spaceCousinsId = "space-cousins"
  static let libraryId = "library-archive"
  static let albumId = "album-trip"
  static let sharedAlbumId = "album-shared"

  /// Asset rows seeded by `small` / `large` (companions and EXIF rows add a few
  /// percent on top; tests assert ranges, not exact totals).
  static let smallAssetTarget = 2_000
  static let largeAssetTarget = 102_000

  enum FixtureSize: String {
    case small
    case large
  }

  /// Reads `-HeirloomFixture=<small|large>` (one self-contained token). The legacy
  /// two-token form (`-HeirloomFixture small`) is still accepted, but tests must
  /// not pass it: a bare value token reaches AppKit as an open-documents event
  /// that suppresses SwiftUI's initial scene (zero windows).
  static var launchSize: FixtureSize? {
    let args = CommandLine.arguments
    for (i, arg) in args.enumerated() {
      if arg.hasPrefix("-HeirloomFixture=") {
        return FixtureSize(rawValue: String(arg.dropFirst("-HeirloomFixture=".count)))
      }
      if arg == "-HeirloomFixture", i + 1 < args.endIndex {
        return FixtureSize(rawValue: args[i + 1])
      }
    }
    return nil
  }

  private static func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 0)
  }

  private static func asset(
    _ id: String, owner: String, name: String, dateISO: String,
    type: AssetKind = .image, space: String? = nil, library: String? = nil,
    favorite: Bool = false, visibility: AssetVisibilityKind = .timeline, trashed: Bool = false,
    isEdited: Bool = false, livePhotoVideoId: String? = nil
  ) -> Asset {
    Asset(
      id: id, ownerId: owner, originalFileName: name, checksum: "checksum-\(id)",
      createdAt: date(dateISO), localDateTime: date(dateISO), type: type,
      deletedAt: trashed ? date("2024-07-01T00:00:00Z") : nil,
      isFavorite: favorite, visibility: visibility,
      livePhotoVideoId: livePhotoVideoId,
      libraryId: library, spaceId: space, width: 4000, height: 3000,
      isEdited: isEdited
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

  static var hasExplicitCount: Bool {
    CommandLine.arguments.contains { $0.hasPrefix("--fixture-seed-count=") }
  }

  static func changes(count: Int = requestedCount) -> [SyncChange] {
    // The only entry point on the fixture launch path this WP owns
    // (`seedForSmoke` calls it right after building the in-memory store), so the
    // stub server is registered here rather than in app-shell files owned by WP-F.
    activateStubServer()
    if let size = launchSize, !hasExplicitCount {
      switch size {
      case .small: return sizedChanges(assetTarget: smallAssetTarget)
      case .large: return sizedChanges(assetTarget: largeAssetTarget)
      }
    }
    var out = baseChanges()
    if count > 0 {
      out += generatedChanges(count: min(count, maxGeneratedCount))
    }
    return out
  }

  /// `changes()` split into apply-sized chunks. `PhotosLocalStore.apply(_:)` runs
  /// one SQLite transaction per call; chunking bounds peak memory on the large
  /// fixture while staying well under the 20 s budget (measured in
  /// `FixtureSeedTests.testLargeFixtureSeedsUnder20Seconds`).
  static func batchedChanges(batchSize: Int = 10_000) -> [[SyncChange]] {
    let all = changes()
    return stride(from: 0, to: all.count, by: batchSize).map { start in
      Array(all[start..<min(start + batchSize, all.count)])
    }
  }

  static func baseChanges() -> [SyncChange] {
    let alice = User(id: userId, name: "Alice", email: "alice@example.com")
    let bob = User(id: bobId, name: "Bob", email: "bob@example.com")
    let family = Space(
      id: spaceId, name: "Family", description: "Seed space",
      createdAt: date("2023-01-01T00:00:00Z"), updatedAt: date("2023-01-01T00:00:00Z")
    )
    let cousins = Space(
      id: spaceCousinsId, name: "Cousins", description: "Second seed space",
      createdAt: date("2023-06-01T00:00:00Z"), updatedAt: date("2023-06-01T00:00:00Z")
    )
    let library = Library(
      id: libraryId, name: "Archive", ownerId: userId,
      createdAt: date("2023-01-01T00:00:00Z"), updatedAt: date("2023-01-01T00:00:00Z")
    )
    func album(_ id: String, _ name: String, cover: String? = nil) -> Album {
      Album(
        id: id, name: name, description: "Seed album \(name)",
        createdAt: date("2024-05-01T00:00:00Z"), updatedAt: date("2024-05-01T00:00:00Z"),
        thumbnailAssetId: cover
      )
    }
    let albums = [
      album(albumId, "Trip", cover: "asset-personal-1"),
      album("album-summer", "Summer 2024", cover: "asset-base-beach-1"),
      album("album-beach", "Beach Days", cover: "asset-space-shot"),
      album(sharedAlbumId, "Shared Trip", cover: "asset-personal-2"),
      album("album-winter", "Winter Holidays"),
      album("album-birthday", "Birthday"),
      album("album-hiking", "Hiking"),
      album("album-city", "City Nights"),
      album("album-portraits", "Portraits"),
      album("album-keepers", "Screenshot Keepers"),
      album("album-print", "To Print"),
      album("album-backup", "Favorites Backup"),
    ]
    var out: [SyncChange] = [
      .user(alice), .user(bob),
      .space(family), .space(cousins),
      .spaceMember(SpaceMember(spaceId: spaceId, userId: userId, role: .owner, showInTimeline: true)),
      .spaceMember(SpaceMember(spaceId: spaceId, userId: bobId, role: .contributor, showInTimeline: true)),
      .spaceMember(SpaceMember(spaceId: spaceCousinsId, userId: userId, role: .owner, showInTimeline: true)),
      .spaceMember(SpaceMember(spaceId: spaceCousinsId, userId: bobId, role: .contributor, showInTimeline: true)),
      .library(library),
    ]
    out += albums.map { .album($0) }
    out += [
      .albumUser(AlbumMember(albumId: albumId, userId: userId, role: .editor)),
      .albumUser(AlbumMember(albumId: albumId, userId: bobId, role: .viewer)),
      .albumUser(AlbumMember(albumId: sharedAlbumId, userId: userId, role: .editor)),
      .albumUser(AlbumMember(albumId: sharedAlbumId, userId: bobId, role: .viewer)),
      .asset(asset("asset-personal-1", owner: userId, name: "IMG_0001.HEIC", dateISO: "2024-06-01T12:00:00Z", favorite: true)),
      .asset(asset("asset-personal-2", owner: userId, name: "IMG_0002.JPG", dateISO: "2023-01-15T12:00:00Z")),
      .assetExif(AssetExif(
        assetId: "asset-personal-2", latitude: 37.7749, longitude: -122.4194,
        city: "San Francisco", state: "California", country: "United States", make: "SeedCam")),
      .asset(asset("asset-space-video", owner: userId, name: "VID_0003.MOV", dateISO: "2024-06-02T12:00:00Z", type: .video, space: spaceId)),
      .asset(asset("asset-space-shot", owner: bobId, name: "IMG_0004.JPG", dateISO: "2022-11-20T12:00:00Z", space: spaceId)),
      .assetExif(AssetExif(assetId: "asset-space-shot", description: "beach day with cousins")),
      .asset(asset("asset-library-1", owner: userId, name: "IMG_0005.DNG", dateISO: "2023-05-10T12:00:00Z", library: libraryId)),
      .asset(asset("asset-trashed", owner: userId, name: "IMG_0006.JPG", dateISO: "2024-01-01T12:00:00Z", trashed: true)),
      .asset(asset("asset-archived", owner: userId, name: "IMG_0007.JPG", dateISO: "2023-08-08T12:00:00Z", visibility: .archive)),
      .asset(asset(
        "asset-base-live", owner: userId, name: "IMG_0008-live.HEIC", dateISO: "2024-04-10T12:00:00Z",
        livePhotoVideoId: "asset-base-live-motion")),
      .asset(asset(
        "asset-base-live-motion", owner: userId, name: "VID_0008-live.MOV", dateISO: "2024-04-10T12:00:00Z",
        type: .video)),
      .asset(asset("asset-base-edited-1", owner: userId, name: "IMG_0009.HEIC", dateISO: "2023-09-01T12:00:00Z", isEdited: true)),
      .asset(asset("asset-base-edited-2", owner: userId, name: "IMG_0010.HEIC", dateISO: "2024-02-14T12:00:00Z", isEdited: true)),
      .asset(asset("asset-base-beach-1", owner: userId, name: "IMG_0011.HEIC", dateISO: "2024-03-12T12:00:00Z")),
      .assetExif(AssetExif(
        assetId: "asset-base-beach-1", description: "beach sunset",
        latitude: 21.3099, longitude: -157.8581,
        city: "Honolulu", state: "Hawaii", country: "United States")),
      .asset(asset("asset-base-beach-2", owner: userId, name: "IMG_0012.HEIC", dateISO: "2023-07-04T12:00:00Z")),
      .assetExif(AssetExif(
        assetId: "asset-base-beach-2", description: "beach morning",
        latitude: 34.0259, longitude: -118.7798,
        city: "Malibu", state: "California", country: "United States")),
      .asset(asset("asset-base-cousins-1", owner: userId, name: "IMG_0013.HEIC", dateISO: "2024-05-20T12:00:00Z", space: spaceCousinsId)),
      .albumAsset(albumId: albumId, assetId: "asset-personal-1"),
      .albumAsset(albumId: albumId, assetId: "asset-space-video"),
      .albumAsset(albumId: "album-summer", assetId: "asset-base-beach-1"),
      .albumAsset(albumId: "album-summer", assetId: "asset-base-beach-2"),
      .albumAsset(albumId: "album-beach", assetId: "asset-space-shot"),
      .albumAsset(albumId: "album-beach", assetId: "asset-base-beach-1"),
      .albumAsset(albumId: "album-beach", assetId: "asset-base-beach-2"),
      .albumAsset(albumId: sharedAlbumId, assetId: "asset-personal-2"),
      .albumAsset(albumId: sharedAlbumId, assetId: "asset-base-live"),
    ]
    // People: 6 named + 2 unnamed (empty name renders as "Add Name" per WP-P P8).
    let people: [(id: String, name: String, faceAsset: String)] = [
      ("person-mom", "Mom", "asset-personal-1"),
      ("person-dad", "Dad", "asset-personal-2"),
      ("person-zoe", "Zoe", "asset-base-beach-1"),
      ("person-max", "Max", "asset-space-shot"),
      ("person-ava", "Ava", "asset-base-edited-1"),
      ("person-leo", "Leo", "asset-base-live"),
      ("person-unnamed-1", "", "asset-base-beach-2"),
      ("person-unnamed-2", "", "asset-base-edited-2"),
    ]
    for (id, name, faceAsset) in people {
      out.append(.person(Person(
        id: id, createdAt: date("2024-01-01T00:00:00Z"), updatedAt: date("2024-01-01T00:00:00Z"),
        ownerId: userId, name: name, faceAssetId: faceAsset)))
      out.append(.face(Face(
        id: "face-\(id)", assetId: faceAsset, personId: id,
        imageWidth: 4000, imageHeight: 3000,
        boundingBoxX1: 1500, boundingBoxY1: 900, boundingBoxX2: 2500, boundingBoxY2: 2100,
        sourceType: "fixture")))
    }
    // Memories: 3, each with asset links.
    let memories: [(id: String, at: String, assets: [String])] = [
      ("memory-summer", "2024-08-01T12:00:00Z",
        ["asset-base-beach-1", "asset-base-beach-2", "asset-space-shot"]),
      ("memory-family", "2024-06-10T12:00:00Z", ["asset-personal-1", "asset-space-video"]),
      ("memory-year", "2023-12-31T12:00:00Z", ["asset-personal-2", "asset-base-edited-1"]),
    ]
    for (id, at, assets) in memories {
      out.append(.memory(Memory(
        id: id, createdAt: date("2024-01-01T00:00:00Z"), updatedAt: date("2024-01-01T00:00:00Z"),
        ownerId: userId, type: "on-this-day",
        dataJSON: "{\"title\":\"\(id)\"}", memoryAt: date(at))))
      for assetId in assets {
        out.append(.memoryAsset(memoryId: id, assetId: assetId))
      }
    }
    return out
  }

  // MARK: - Sized fixtures (small ~2k, large ~102k)

  static func assetRowCount(_ changes: [SyncChange]) -> Int {
    changes.reduce(0) { count, change in
      if case .asset = change { return count + 1 }
      return count
    }
  }

  /// Primary (non-companion) generated rows needed so the total asset rows reach
  /// `target`. Each 20-cycle emits ~21 rows, hence the 20/21 factor; the top-up
  /// loop in `sizedChanges` closes the remainder exactly.
  static func primaryCount(forTarget target: Int) -> Int {
    let baseAssets = assetRowCount(baseChanges())
    return max(0, target - baseAssets) * 20 / 21
  }

  /// Base set plus generated bulk topped up to exactly `assetTarget` asset rows.
  /// Deterministic: same target always yields the same rows in the same order.
  static func sizedChanges(assetTarget: Int) -> [SyncChange] {
    var out = baseChanges()
    out += generatedChanges(count: primaryCount(forTarget: assetTarget))
    var rows = assetRowCount(out)
    var i = 0
    while rows < assetTarget {
      let at = Date(timeIntervalSince1970: 1_293_840_000 + Double(i) * 86_400)
      out.append(.asset(Asset(
        id: "asset-topup-\(i)", ownerId: userId,
        originalFileName: String(format: "IMG_TOP_%04d.HEIC", i),
        thumbhash: generatedThumbhash, checksum: "checksum-asset-topup-\(i)",
        createdAt: at, localDateTime: at, type: .image, width: 4000, height: 3000
      )))
      i += 1
      rows += 1
    }
    return out
  }

  // MARK: - Beach tag

  /// Base assets tagged "beach" (via `AssetExif.description`, the local-metadata
  /// search carrier). Generated bulk adds one beach asset per 97 primaries.
  static let baseBeachAssetIDs = ["asset-space-shot", "asset-base-beach-1", "asset-base-beach-2"]

  static func generatedBeachIDs(primaryCount: Int) -> [String] {
    (0..<primaryCount).filter { $0 % 97 == 0 }.map { "asset-gen-\($0)" }
  }

  /// Every beach-tagged id in the currently launched fixture (base + bulk).
  /// The stub `/search/smart` and `/search/metadata` endpoints serve this list,
  /// and WP-P's "beach returns exactly the fixture beach count" test asserts it.
  static func beachAssetIDs() -> [String] {
    switch launchSize {
    case .small: return baseBeachAssetIDs + generatedBeachIDs(primaryCount: primaryCount(forTarget: smallAssetTarget))
    case .large: return baseBeachAssetIDs + generatedBeachIDs(primaryCount: primaryCount(forTarget: largeAssetTarget))
    case nil: return baseBeachAssetIDs
    }
  }

  // MARK: - Large synthetic fixture (brief step 5)

  /// One real thumbhash harvested from `MediaPipelineTests` — reused for every
  /// generated asset. Only one genuine sample exists in-tree; per-asset variety
  /// does not matter because the media pipeline runs offline in seeded launches
  /// and cells show placeholders regardless of the hash content.
  static let generatedThumbhash = "1fsDBYBKeI97iIh4eIiIdweIdIBI"

  /// Cycled (width, height) pairs so the grid exercises varied aspect ratios.
  private static let generatedSizes = [
    (4000, 3000), (3000, 4000), (6000, 4000), (4032, 3024),
    (1920, 1080), (1080, 1920), (1440, 1440),
  ]

  /// Generates `count` primary assets deterministically from the index (no RNG,
  /// so repeated runs seed identical rows). `localDateTime` spreads evenly over
  /// 2011-2021 — deliberately below every curated base asset (>= 2022) so the
  /// base set sorts first and stays visible on first paint. The `i % 20` mix
  /// yields photos, videos (with duration), live-photo still+motion pairs and
  /// screenshots per the `TimelineRow(asset:)` classification. Live pairs emit
  /// one companion motion row, so the store ends up with ~5% more rows than
  /// `count`. Every 97th primary is tagged "beach" via an `AssetExif`
  /// description row (see `beachAssetIDs()`).
  static func generatedChanges(count: Int) -> [SyncChange] {
    // 2011-01-01T00:00:00Z through ~2021-12-31 (11 x 365.25 days).
    let base = Date(timeIntervalSince1970: 1_293_840_000)
    let span = 11 * 365.25 * 86_400
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
      if i % 97 == 0 {
        out.append(.assetExif(AssetExif(assetId: id, description: "beach")))
      }
    }
    return out
  }
}

/// Launch-flag contract for UI tests (WP-T, TEST-PLAN T0).
///
/// UITests always pass `-HeirloomUITestNoAnimation`. Feature WPs honor it in
/// their own views by checking `HeirloomUITestFlags.animationsDisabled` and
/// skipping non-essential animations (e.g. `NSAnimationContext` duration 0,
/// SwiftUI `.animation(nil)`), keeping transition tests on the default path by
/// simply not passing the flag.
enum HeirloomUITestFlags {
  static var animationsDisabled: Bool {
    CommandLine.arguments.contains("-HeirloomUITestNoAnimation")
  }
}

/// Raw-argv launch-mode checks (WP-T T0). Test booleans must be SINGLE-DASH
/// (`-fixture-seed`, `-ui-testing`): a `--double-dash` flag swallows the following
/// argv token during system argument parsing, and the stranded token arrives as a
/// bare open-documents event that suppresses SwiftUI's initial scene — the app runs
/// foreground with menus but zero windows. Guarded by
/// `testLaunchMakesMainWindowAccessible`.
enum HeirloomLaunchFlag {
  static func isPresent(_ singleDash: String, legacy doubleDash: String) -> Bool {
    let args = CommandLine.arguments
    return args.contains(singleDash) || args.contains(doubleDash)
  }
}

/// Deterministic synthetic media for the fixture (WP-T, TEST-PLAN T0).
///
/// Images are gradients + a disc derived from a stable hash of the seed string —
/// fixed seeds, no network, never personal photos (snapshot baselines in T2
/// render only these). Videos are short H.264 clips written with AVAssetWriter
/// at seed time and cached in the fixture directory.
enum FixtureMedia {
  static var fixtureDirectory: URL {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("HeirloomFixture", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Stable 0..<UInt64 hash (djb2) — `String.hashValue` is per-launch random and
  /// must not feed deterministic media.
  static func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 5381
    for b in s.utf8 { h = h &* 33 &+ UInt64(b) }
    return h
  }

  /// Deterministic PNG: vertical hue gradient + offset disc, both derived from
  /// `seed`. Same seed, same bytes, every launch.
  static func pngData(seed: String, width: Int = 256, height: Int = 256) -> Data {
    let h = stableHash(seed)
    let hue = CGFloat(h % 360) / 360.0
    guard let ctx = CGContext(
      data: nil, width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return Data() }
    for y in 0..<height {
      let t = CGFloat(y) / CGFloat(max(height - 1, 1))
      let color = CGColor(
        red: hue * (1 - t) + 0.12, green: 0.25 + 0.55 * t,
        blue: 0.75 - 0.45 * t, alpha: 1.0)
      ctx.setFillColor(color)
      ctx.fill(CGRect(x: 0, y: y, width: width, height: 1))
    }
    let cx = CGFloat(h >> 11).truncatingRemainder(dividingBy: CGFloat(max(width - 40, 1)))
    let cy = CGFloat(h >> 21).truncatingRemainder(dividingBy: CGFloat(max(height - 40, 1)))
    ctx.setFillColor(CGColor(red: 1 - hue, green: 0.9, blue: 0.35, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: 20 + cx, y: 20 + cy, width: 44, height: 44))
    guard let image = ctx.makeImage() else { return Data() }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
      data, UTType.png.identifier as CFString, 1, nil) else { return Data() }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return Data() }
    return data as Data
  }

  /// Cached H.264 clip for `seed` (8 variants shared by seed hash). 160x120,
  /// 12 fps, 1 s — small enough to generate at seed time, valid enough for
  /// AVPlayer readiness probes in V3 tests. Uses the macOS 26+ receiver API
  /// (`inputPixelBufferReceiver`, `appendImmediately`); the `AVAssetWriterInput`
  /// + adaptor path is deprecated in macOS 27.
  static func videoFileURL(seed: String) throws -> URL {
    let variant = Int(stableHash(seed) % 8)
    let url = fixtureDirectory.appendingPathComponent("video-\(variant).mp4")
    if FileManager.default.fileExists(atPath: url.path) { return url }
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: 160, AVVideoHeightKey: 120,
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
    try writer.start()
    writer.startSession(atSourceTime: .zero)
    guard let pool = receiver.pixelBufferPool else { throw FixtureMediaError.encodeFailed }
    for frame in 0..<12 {
      var px = try pool.makeMutablePixelBuffer()
      let r = UInt8((CGFloat(variant) * 32 + CGFloat(frame) * 8).truncatingRemainder(dividingBy: 255))
      let g = UInt8(frame * 20)
      px.accessUnsafeMutableRawPlaneBytes { planes in
        guard let plane = planes.first,
          let base = plane.bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        for i in 0..<(plane.bytes.count / 4) {
          base[i * 4] = 255; base[i * 4 + 1] = r; base[i * 4 + 2] = g; base[i * 4 + 3] = 120
        }
      }
      _ = try receiver.appendImmediately(
        CVReadOnlyPixelBuffer(px), with: CMTime(value: CMTimeValue(frame), timescale: 12))
    }
    receiver.finish()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else { throw writer.error ?? FixtureMediaError.encodeFailed }
    return url
  }
}

enum FixtureMediaError: Error {
  case encodeFailed
}

/// Fake signed-in backend for fixture launches (WP-T, TEST-PLAN T0).
///
/// `MacAppState.seeded()` already presents a signed-in session (`userId` set, so
/// `isConnected` is true) against `https://fixture.invalid`. This protocol answers
/// every request to that host: thumbnails / originals / person thumbnails serve
/// deterministic `FixtureMedia` PNGs, `video/playback` serves the cached H.264
/// clip, and `/search/smart` + `/search/metadata` serve the fixture beach ids.
/// Anything else (including a missing `Authorization` header on the search
/// routes) gets an error status, so tests can assert the auth contract without
/// cross-process shared state. Registered from `FixtureSeed.changes()`; no
/// network ever leaves the host.
final class FixtureStubURLProtocol: URLProtocol {
  static let fixtureHost = "fixture.invalid"

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == fixtureHost
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url else {
      finish(status: 400, contentType: "text/plain", body: Data("bad request".utf8))
      return
    }
    let path = url.path
    if path.contains("search/smart") || path.contains("search/metadata") {
      guard (request.value(forHTTPHeaderField: "Authorization") ?? "").hasPrefix("Bearer ") else {
        finish(status: 401, contentType: "text/plain", body: Data("missing auth".utf8))
        return
      }
      let ids = FixtureSeed.beachAssetIDs()
      let items = ids.map { "{\"id\":\"\($0)\"}" }.joined(separator: ",")
      finish(status: 200, contentType: "application/json",
        body: Data("{\"assets\":{\"items\":[\(items)]}}".utf8))
      return
    }
    if path.contains("search/suggestions") {
      finish(status: 200, contentType: "application/json", body: Data("[\"beach\"]".utf8))
      return
    }
    if path.contains("exif/full") {
      finish(status: 200, contentType: "application/json", body: Data("{\"groups\":{}}".utf8))
      return
    }
    if path.contains("video/playback") {
      let seed = assetID(from: path) ?? "fixture-video"
      if let file = try? FixtureMedia.videoFileURL(seed: seed),
        let bytes = try? Data(contentsOf: file) {
        finish(status: 200, contentType: "video/mp4", body: bytes)
      } else {
        finish(status: 503, contentType: "text/plain", body: Data("no video".utf8))
      }
      return
    }
    if path.contains("/original") {
      finish(status: 200, contentType: "image/png",
        body: FixtureMedia.pngData(seed: assetID(from: path) ?? "fixture", width: 512, height: 512))
      return
    }
    if path.contains("assets/") || path.contains("people/") {
      finish(status: 200, contentType: "image/png",
        body: FixtureMedia.pngData(seed: assetID(from: path) ?? "fixture", width: 256, height: 256))
      return
    }
    finish(status: 404, contentType: "text/plain", body: Data("unknown fixture route".utf8))
  }

  override func stopLoading() {}

  private func assetID(from path: String) -> String? {
    let parts = path.split(separator: "/").map(String.init)
    if let i = parts.firstIndex(of: "assets"), i + 1 < parts.count { return parts[i + 1] }
    if let i = parts.firstIndex(of: "people"), i + 1 < parts.count { return parts[i + 1] }
    return nil
  }

  private func finish(status: Int, contentType: String, body: Data) {
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": contentType, "Content-Length": "\(body.count)"])
    else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }
}

extension FixtureSeed {
  /// Idempotent: `URLProtocol.registerClass` is process-wide and safe to repeat.
  static func activateStubServer() {
    URLProtocol.registerClass(FixtureStubURLProtocol.self)
  }

  private static func ensureStubServerRegistered() {
    activateStubServer()
  }
}
