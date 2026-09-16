# WP1 — PhotosCore: row model, grid snapshot, grid geometry, media pipeline

Read `PLAN.md` first. You own `native-apple/PhotosCore/**` exclusively. Fixes the core-side parts of
R1, R2, R3, R4, R5 and R9, plus the data needed by WP6. Everything here is pure or actor code with unit
tests. The app wiring happens in WP2/WP3, so keep public APIs exactly as named below (they are the
contract other WPs code against). If you must deviate, document it at the top of `reports/WP1-REPORT.md`.

Modules (see `PhotosCore/Package.swift`): CoreModel, LocalStore (GRDB), Media (Nuke 13.2), Rules,
SyncEngine, ImmichAPI, Search, Editing. Tests: `PhotosCoreTests`
(`swift test --package-path native-apple/PhotosCore`).

## 1. TimelineRow additions (CoreModel/Timeline.swift:15)
- Add stored properties `ownerId: String`, `isEdited: Bool`, `durationSeconds: Int?`. Give them defaults
  in the designated init, so existing call sites compile, and set them in `init(asset:)`.
- Update **every** row SELECT to return them (`asset.ownerId`, `asset.isEdited`, `asset.durationSeconds`;
  check the real column names in `LocalStore/Schema.swift`). The shared select is in
  `LocalStore+Timeline.swift` (~L32–47, used by `timelineAssets`, `favoriteAssets`, `recentAssets`,
  `assets(scope:mediaKind:)`, `trashedAssets`, `lockedAssets`). Also `LocalStore+Browse.swift`:
  `albumAssets`, `visibilityAssets`, `mediaAssets`.
- Check the row decoder that maps SQL → TimelineRow and extend it.
- `assets(scope:mediaKind:)` and `mediaAssets` currently filter by kind **client-side** (see 06-facts §2).
  Move the filter into SQL (`WHERE <mediaKind CASE expr> = ?`) so the Photos destination doesn't pull 102k
  rows to keep 57k.
- Add an index if it's missing and a query plan shows a scan: `asset(localDateTime)` and
  `asset(deletedAt, visibility, localDateTime)`. Check existing migrations in `Schema.swift`; add a new
  migration, never edit an old one.
- Add `func assetIdsInAnyAlbum(userId: String) async throws -> Set<String>`: a single
  `SELECT DISTINCT assetId FROM <album-asset table>` joined to the albums the user can see. It replaces
  the app's per-album loop.
- Add `func timelineRows(scope:bucketKeys:granularity:)` (or reuse the existing function) so a whole
  timeline loads in **one** read transaction, not one `dbQueue.read` per bucket. Target: ≤ 400 ms for
  102k rows on an M-series Mac, measured in `TimelinePerformanceTests`.
- Add `func locatedAssetPoints(scope:) async throws -> [LocatedPoint]` with
  `public struct LocatedPoint: Sendable { id: String; latitude: Double; longitude: Double; localDateTime: Date? }`,
  **no limit**. Keep the existing `locatedAssets(limit: 2000)` for the side list.
- People (for WP6):
  - Find the person/face tables in `Schema.swift`. Add
    `func peopleSummaries(userId:) async throws -> [PersonSummary]`, where `PersonSummary` holds
    `id, name, isHidden, assetCount, birthDate?`, sorted by assetCount desc, named first.
  - If the schema has no asset↔person link, report it; don't invent a sync change.

## 2. Grid snapshot (new CoreModel/TimelineGridSnapshot.swift)
```swift
public enum TimelineSectionKind: Sendable { case none, year, month }

public struct TimelineSourceSection: Sendable {
  public var header: String?; public var kind: TimelineSectionKind; public var rows: [TimelineRow]
}

public enum TimelineOrder: Sendable { case newestFirst, oldestFirst }   // if the app already has one, move it here

/// Immutable, reference-typed so SwiftUI/Observation compare it by identity — never by value.
public final class TimelineGridSnapshot: Sendable {
  public struct Section: Sendable { public let header: String?; public let kind: TimelineSectionKind; public let range: Range<Int> }
  public let generation: Int          // bumps on structural change (reloadData)
  public let revision: Int            // bumps on in-place patch (reloadItems)
  public let rows: [TimelineRow]      // flat, display order
  public let sections: [Section]      // empty sections dropped; header-only year sections allowed (see below)
  public let indexById: [String: Int]
  public let dayKeys: [String]        // "yyyy-MM-dd" per row, "" if unknown (type-to-jump)
  public let photoCount: Int, videoCount: Int
  public let dateRange: ClosedRange<Date>?
  public var ids: [String] { rows.map(\.id) }   // only for viewer context; O(n) by design, call once
  public static let empty: TimelineGridSnapshot

  public static func build(
    sections: [TimelineSourceSection], order: TimelineOrder,
    include: @Sendable (TimelineRow) -> Bool, generation: Int
  ) -> TimelineGridSnapshot

  public func patching(ids: Set<String>, _ transform: (inout TimelineRow) -> Void) -> (TimelineGridSnapshot, changedIndexes: [Int])
  public func removing(ids: Set<String>, generation: Int) -> TimelineGridSnapshot
  public func sectionAndItem(forIndex: Int) -> (section: Int, item: Int)   // binary search on ranges
  public func flatIndex(section: Int, item: Int) -> Int
}
```
Rules:
- `build` makes a single pass that filters, orders (reversing sections and rows for `oldestFirst`),
  computes ranges, the index map, counts, the date range and dayKeys.
- dayKeys: use `Calendar(identifier: .gregorian)` with a fixed `TimeZone(secondsFromGMT: 0)`, because
  `localDateTime` is stored as local time in UTC, the Immich convention. Verify against the existing
  `MacLibraryBrowser.dateString`, which uses `DateFormatter` in the current zone, and match its output.
  Build the string from `dateComponents` with integer formatting. **No DateFormatter per row.**
- Year grouping: the app wants a big "2025" header **and** month headers under it. Represent this as a
  year section with an empty range, followed by that year's month sections. The layout (WP3) renders
  an empty-range section as a header only.
- Must be fast: `build` for 102k rows ≤ 60 ms in Release. Add a `measure` test with synthetic rows,
  plus correctness tests (filters, order, ranges, index map, counts, patching, removing,
  `sectionAndItem` round trip).
- Also add `public enum TimelineBucketTitle { static func title(forKey: String, kind:) -> String }`, with
  a cached `DateFormatter` per format (`static let`, created once) and results memoized per key in a
  lock-protected dictionary. This fixes R5.

## 3. Grid geometry (new CoreModel/TimelineGridGeometry.swift) — pure math for WP3's layout
Photos uses square cells in both modes; "aspect ratio grid" only changes how the image fits inside the
square. So the geometry is always square: **no per-item storage and no per-item work in prepare.**
```swift
public struct TimelineGridGeometry: Sendable, Equatable {
  public struct Config: Sendable, Equatable {
    public var width: CGFloat; public var targetItemSide: CGFloat   // from zoom slider, 64…400
    public var spacing: CGFloat = 2; public var insets = NSEdgeInsets-like (top 8, left 8, bottom 8, right 8) — define your own Sendable struct
    public var yearHeaderHeight: CGFloat = 56; public var monthHeaderHeight: CGFloat = 40
  }
  public init(config: Config, sections: [(count: Int, kind: TimelineSectionKind)])
  public let columns: Int; public let itemSide: CGFloat           // itemSide fills width exactly (floor to pixel)
  public let contentHeight: CGFloat
  public func headerFrame(section: Int) -> CGRect?               // nil for kind == .none
  public func itemFrame(section: Int, item: Int) -> CGRect
  public func sections(intersecting rect: CGRect) -> Range<Int>   // binary search on section origins
  public func items(in section: Int, intersecting rect: CGRect) -> Range<Int>  // arithmetic on row index
  public func indexPathNearest(y: CGFloat) -> (section: Int, item: Int)?       // zoom anchor
  public func originY(section: Int, item: Int) -> CGFloat
}
```
- columns = `max(1, floor((width − left − right + spacing) / (target + spacing)))`.
  itemSide = `floor((contentWidth − (columns−1)·spacing) / columns)`.
- Section layout: header (if any), then `ceil(count/columns)` rows, then `spacing * 4` bottom gap.
- Prepare cost is O(sections), not O(items). Tests:
  - column math at several widths;
  - frame continuity, with no overlaps and every item inside the content height;
  - the visible-range query agrees with brute force on random rects (102k items, 300 sections);
  - init ≤ 1 ms for 300 sections.

## 4. Media pipeline (Media/*)
1. **Row-based API** (no full `Asset` needed):
   `public func stream(id: String, thumbhash: String?, tier: MediaTier, edited: Bool = false, pixelSize: Int? = nil, format: MediaFormatInfo = .standardDefault) -> AsyncThrowingStream<MediaLoadedImage, Error>`.
   The existing `stream(asset:…)` forwards to it. Use whatever default `MediaFormatInfo` means "SDR, not
   RAW" in `MediaFormat.swift`, and add a static if one is missing.
2. **Single network fetch.** Replace `service.data(for:)` followed by `service.image(for:)` with one
   `service.data(for:)`, then `diskCache.store`, then `decodeImage(data, pixelSize:)` on a
   non-main executor. Don't call `service.image` in the thumbnail/preview path. Update
   `MediaPipelineTests`: a stub service counts `data` calls, which must be 1, and `image` calls, which
   must be 0.
3. **Synchronous memory cache.** Add `public final class MediaMemoryCache: @unchecked Sendable`, wrapping
   `NSCache<NSString, CGImageBox>`. NSCache is thread-safe, so document that as the reason for the
   unchecked conformance. The key is `"\(id)|\(tier)|\(edited)"`, the cost is `bytesPerRow*height`, and
   the limit is the existing `memoryCacheCostLimit()`. Expose it as `public nonisolated let memory` on
   `MediaPipeline`, plus `public nonisolated func cachedImage(id:tier:edited:) -> CGImage?`, so a cell can
   hit it synchronously on the main thread. `stream` yields from memory first and finishes if the tier
   matches.
4. **Also cache decoded thumbhash placeholders** in a separate small NSCache (count limit 5000), with a
   `nonisolated func cachedPlaceholder(id:) -> CGImage?` and
   `func placeholder(id:thumbhash:) async -> CGImage?`.
5. **In-flight de-duplication.** An actor-held `[Key: Task<CGImage, Error>]` makes a visible cell join an
   existing prefetch task instead of starting a new fetch. When the last visible consumer cancels, the
   task is cancelled unless a prefetch still wants it (reference count).
6. **Prefetch.** Replace the Nuke `ImagePrefetcher` path with
   `public func prefetch(_ items: [(id: String, thumbhash: String?)], tier: MediaTier)` and
   `public func cancelPrefetch(keeping ids: Set<String>)`.
   - Work is capped at 8 concurrent network loads for prefetch; visible loads are uncapped but
     `.high` priority. Use Nuke `ImageRequest.priority`: visible `.high`, prefetch `.low`.
   - Prefetch writes the memory and disk caches.
   - Keep `MediaImageService.prefetch`/`stopPrefetching` in the protocol only if still used; otherwise
     remove them and update the stub.
7. **TieredMediaCache** (actor):
   - `init` must not touch the filesystem. The index is built lazily by `ensureIndexed()`, a detached
     scan started on the first budget/usage/evict call. Until it's ready, `cachedTiers`/`retrieve` fall
     back to `FileManager.fileExists` on the computed path.
   - File reads and writes must not run while holding the actor. Compute the URL on the actor, then do
     the I/O in a `nonisolated` helper, then update the index back on the actor. Many cells must be able
     to read concurrently.
   - Keep the existing tests passing, and add a test that init returns in < 5 ms with 20k files present.
8. **Endpoints.** Add `MediaEndpoint.personThumbnailURL(personID:)` (`GET /people/{id}/thumbnail`) and a
   pipeline method `personThumbnail(id:) -> AsyncThrowingStream` reusing the same cache path with tier
   `.thumbnail` and key prefix `person:`.
9. Log failures with `HeirloomLog.media`. WP0 step 2 lands before you start; if it's missing, stop and
   report. Don't create `Log.swift` yourself.
10. Add signposts `ThumbnailFetch` and `ThumbnailDecode` around network and decode.

## Acceptance
- `swift test --package-path native-apple/PhotosCore` passes, including the new tests above and the
  perf tests with their stated budgets (use `measure` + `XCTAssertLessThan` on the median, Release
  `-c release` for perf tests if the suite supports it; otherwise document the Debug numbers).
- The app target still compiles. Keep `stream(asset:)` and other old signatures until WP2/WP3 migrate;
  mark them `@available(*, deprecated)` only if that doesn't break `-warningsAsErrors`.
- Report: `reports/WP1-REPORT.md`, listing the final public API signatures verbatim (WP2/WP3 depend on
  them).
