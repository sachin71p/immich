# WP1 Report — PhotosCore: row model, grid snapshot, grid geometry, media pipeline

Branch `perf/heirloom-macos-wp1`, base `8d8dd706f`. Worktree
`/Users/spatel/workspace/github/projects/immich-wp1`. WP0 logging API used as
specified (`HeirloomLog.media`, `HeirloomSignpost.thumbnailFetch/thumbnailDecode`);
`CoreModel/Log.swift` untouched.

## Commits (5, incremental per section)

- `7213d0772` §1 row fields, single-transaction queries, SQL kind filter
- `939cbf057` §2 `TimelineGridSnapshot` + `TimelineBucketTitle`
- `0dfe18125` §3 `TimelineGridGeometry`
- `64c6fdf87` §4 media pipeline, lazy disk index, all tests + query optimizations
- `dedf543d0` docs touch-up (`Media.swift` module comment)

## Final public API (verbatim — WP2/WP3 contract)

```swift
// CoreModel/Timeline.swift
public struct TimelineRow {
  // + ownerId: String (= ""), isEdited: Bool (= false), durationSeconds: Int? (= nil)
  // init(asset:) sets all three; old call sites compile via defaults.
}
public struct LocatedPoint: Sendable {
  public var id: String; public var latitude: Double; public var longitude: Double
  public var localDateTime: Date?
  public init(id: String, latitude: Double, longitude: Double, localDateTime: Date? = nil)
}
// CoreModel/Album.swift
public struct PersonSummary: Sendable, Identifiable, Hashable {
  public var id: String; public var name: String; public var isHidden: Bool
  public var assetCount: Int; public var birthDate: Date?
  public init(id: String, name: String, isHidden: Bool, assetCount: Int, birthDate: Date? = nil)
}

// CoreModel/TimelineGridSnapshot.swift
public enum TimelineSectionKind: Sendable { case none, year, month }
public struct TimelineSourceSection: Sendable {
  public var header: String?; public var kind: TimelineSectionKind; public var rows: [TimelineRow]
  public init(header: String? = nil, kind: TimelineSectionKind, rows: [TimelineRow])
}
public enum TimelineOrder: Sendable { case newestFirst, oldestFirst }
public final class TimelineGridSnapshot: Sendable {
  public struct Section: Sendable {
    public let header: String?; public let kind: TimelineSectionKind; public let range: Range<Int>
  }
  public let generation: Int; public let revision: Int
  public let rows: [TimelineRow]; public let sections: [Section]
  public let indexById: [String: Int]; public let dayKeys: [String]
  public let photoCount: Int; public let videoCount: Int
  public let dateRange: ClosedRange<Date>?
  public var ids: [String]
  public static let empty: TimelineGridSnapshot
  public static func build(
    sections: [TimelineSourceSection], order: TimelineOrder,
    include: @Sendable (TimelineRow) -> Bool, generation: Int
  ) -> TimelineGridSnapshot
  public func patching(ids: Set<String>, _ transform: (inout TimelineRow) -> Void)
    -> (TimelineGridSnapshot, changedIndexes: [Int])
  public func removing(ids: Set<String>, generation: Int) -> TimelineGridSnapshot
  public func sectionAndItem(forIndex: Int) -> (section: Int, item: Int)
  public func flatIndex(section: Int, item: Int) -> Int
}
public enum TimelineBucketTitle {
  public enum Kind: Sendable { case month, day, year }
  public static func title(forKey key: String, kind: Kind) -> String
}

// CoreModel/TimelineGridGeometry.swift
public struct TimelineGridGeometry: Sendable, Equatable {
  public struct Insets: Sendable, Equatable {
    public var top, left, bottom, right: CGFloat  // default 8,8,8,8
  }
  public struct Config: Sendable, Equatable {
    public var width: CGFloat; public var targetItemSide: CGFloat
    public var spacing: CGFloat = 2; public var insets = Insets()
    public var yearHeaderHeight: CGFloat = 56; public var monthHeaderHeight: CGFloat = 40
  }
  public init(config: Config, sections: [(count: Int, kind: TimelineSectionKind)])
  public let config: Config; public let columns: Int; public let itemSide: CGFloat
  public let contentHeight: CGFloat
  public var sectionCount: Int
  public func headerFrame(section: Int) -> CGRect?
  public func itemFrame(section: Int, item: Int) -> CGRect
  public func sections(intersecting rect: CGRect) -> Range<Int>
  public func items(in section: Int, intersecting rect: CGRect) -> Range<Int>
  public func indexPathNearest(y: CGFloat) -> (section: Int, item: Int)?
  public func originY(section: Int, item: Int) -> CGFloat
}

// LocalStore (PhotosLocalStore)
public func timelineRows(scope: ContainerScope, bucketKeys: [String]? = nil,
  granularity: Granularity = .month) async throws -> [TimelineRow]
public func assetIdsInAnyAlbum(userId: String) async throws -> Set<String>
public func locatedAssetPoints(scope: ContainerScope) async throws -> [LocatedPoint]
public func peopleSummaries(userId: String) async throws -> [PersonSummary]
// assets(scope:mediaKind:) now filters in SQL (same signature).

// Media
public func stream(id: String, thumbhash: String?, tier: MediaTier, edited: Bool = false,
  pixelSize: Int? = nil, format: MediaFormatInfo = .standardDefault)
  -> AsyncThrowingStream<MediaLoadedImage, any Error>   // (existing stream(asset:…) forwards)
public final class MediaMemoryCache: @unchecked Sendable  // NSCache-backed, documented
public nonisolated let memory: MediaMemoryCache  // on MediaPipeline
public nonisolated func cachedImage(id: String, tier: MediaTier, edited: Bool = false) -> CGImage?
public nonisolated func cachedPlaceholder(id: String) -> CGImage?
public func placeholder(id: String, thumbhash: String?) async -> CGImage?
public func prefetch(_ items: [(id: String, thumbhash: String?)], tier: MediaTier) async
public func cancelPrefetch(keeping ids: Set<String>)
public func personThumbnail(id: String) -> AsyncThrowingStream<MediaLoadedImage, any Error>
public static func personThumbnailURL(serverURL: URL, personID: String) -> URL  // MediaEndpoint
public static let standardDefault: MediaFormatInfo  // SDR, non-original
```

## Files changed

Sources: `CoreModel/Timeline.swift` (row fields, `LocatedPoint`),
`CoreModel/Album.swift` (`PersonSummary`), `CoreModel/TimelineGridSnapshot.swift` (new),
`CoreModel/TimelineGridGeometry.swift` (new), `LocalStore/LocalStore+Timeline.swift`
(projection/decoder/kind-filter/`timelineRows`/`assetIdsInAnyAlbum`/`locatedAssetPoints`/
`peopleSummaries`), `LocalStore/Schema.swift` (`v3_timeline_cover_index`),
`Media/MediaPipeline.swift` (rewrite), `Media/MediaMemoryCache.swift` (new),
`Media/TieredMediaCache.swift` (lazy index, off-actor I/O), `Media/MediaEndpoint.swift`
(person route), `Media/MediaFormat.swift` (`standardDefault`), `Media/Media.swift` (docs).
Tests: `TimelineGridSnapshotTests.swift`, `TimelineGridGeometryTests.swift`,
`TimelineStoreWP1Tests.swift` (new); `MediaPipelineTests.swift`,
`TieredMediaCacheTests.swift`, `TimelinePerformanceTests.swift` (extended).

## Test results

- `swift test --package-path native-apple/PhotosCore`: **158 tests / 21 suites, all pass**.
- `make build-macos CONFIGURATION=Release`: **BUILD SUCCEEDED** (app compiles; old
  `stream(asset:)`, `load(asset:)`, `prefetch(ids:)`, `cancelPrefetch()` kept, none
  deprecated; iOS still calls `prefetch(ids:)`).
- Only warnings: pre-existing `SyncEngine missing dependency on Media/Nuke` (from
  `FreeUpSpaceVerification.swift`, untouched).

## Perf numbers (M-series, this host)

| Check | Release (`-c release`) | Debug | Budget |
|---|---|---|---|
| snapshot `build`, 102k rows | pass (< 60 ms) | ~114 ms | 60 ms |
| `timelineRows`, 102k rows, 1 txn | pass (< 400 ms) | ~1085 ms | 400 ms |
| geometry `init`, 300 sections | < 1 ms | 0.001 s | 1 ms |
| disk-cache `init`, 20k files | instant (< 5 ms assert) | pass | 5 ms |
| 50k bucket/page queries | — | < 50 ms asserts pass | 50 ms |

Two optimizations were needed to meet Release budgets: the row projection is
decode-light (`julianday` double + boolean flags instead of per-row string date
parsing/comparison; ~380 → ~280 ms Release with margin), and snapshot `dayKeys`
use integer civil-date math (verified against `Calendar` GMT output for 2700+
dates, 1970–2035 + pre-epoch) with a fused single build pass. Perf tests use
`#if DEBUG` conditional budgets (table above documents the Debug numbers); the
true budgets are enforced by `-c release` runs.

## Deviations from WP1-CORE.md (all deliberate, WP2/WP3-visible ones are in the API above)

1. Stream failure type is `any Error`, not `Error` (Swift 6 spelling; identical type).
2. `TimelineBucketTitle.title(forKey:kind:)` — `kind` is the nested
   `TimelineBucketTitle.Kind` (month/day/year); the brief left the type blank and only
   implied month/day. Day format `"EEEE, MMMM d, yyyy"` and year passthrough are new
   (month output matches the old `MacGridView.bucketTitle`).
3. `personThumbnailURL` is `static func personThumbnailURL(serverURL:personID:)` — the
   route has no asset id to hang an instance method on.
4. Geometry adds `sectionCount` (+ public `config`, `Insets` type name) — WP3 needs loop
   bounds; `sections(intersecting: fullRect)` would otherwise be the only way.
5. `oldestFirst` reversal is year-group-aware (headers stay attached to their months);
   without year markers it is exactly "reverse sections and rows".
6. `mediaAssets` already filtered in SQL — only `assets(scope:mediaKind:)` needed the fix.
7. `TieredMediaCache.store/retrieve/evict/setBudget/usage/totalUsage/remove` are now
   `async` (off-actor I/O requirement); every existing call site already awaited them.
8. `MediaImageService.prefetch/stopPrefetching` removed per the brief's allowance;
   `NukeMediaImageService.init` simplified to `init(pipeline:)` (sole caller: `makeDefault`).
9. Perf tests use conditional Debug budgets (see table), not unconditional asserts.

## Open issues / notes for WP2/WP3

- `patching` contract: `transform` must not reorder rows or change dates (`dateRange` is
  carried; dayKeys are patched at changed indexes; counts + index are rebuilt).
- `photoCount` counts every non-video kind (livePhoto/panorama/screenshot count as photos).
- `usage()` awaits the lazy index (accurate after restart); `cachedTiers`/`retrieve`
  use the `fileExists` fallback until the scan lands. Eviction races a concurrent
  `store` safely (size-checked index drop).
- Bucket titles use `Locale.current` for month/day names (same as the old code for months).
- Two real bugs were found and fixed during testing (not in the brief): `removing()`
  appended year markers after their months (now emitted before the first surviving
  month), and `dayKey` used per-row `Calendar`+`String(format:)` (~4× over budget).
