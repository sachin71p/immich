# WP-F — Timeline cache, query plans, launch path, filter pages, micro thumbnails

Read first: `PLAN.md` (§0, §1 F-rows, §2.5, §3) and `EVIDENCE.md` (measurements, the `sample` files in
`evidence/traces/`, and `CUR-heirloom-cold-launch.mp4`).

Known facts (verify them):
- The stall stack is `MacGridLoader.load` (MacGridLoader.swift:99) → `fetch` (:249) →
  `timelineSections` (:320) → `PhotosLocalStore.timelineRows` (LocalStore+Timeline.swift:241) →
  `Row.fetchAll` → `sqlite3_step` (≈2 min once, 18 s another time).
- The query projects asset columns and LEFT JOINs `assetExif`, filtering on deletedAt / visibility /
  scope / mediaKind.
- Indexes (LocalStore/Schema.swift:59–62): `asset_on_localDateTime`, `asset_on_spaceId`,
  `asset_on_libraryId`, `asset_on_ownerId`.
- The DB is `~/Library/Application Support/Heirloom/heirloom.sqlite` (229 MB).
- `DatabasePool` is already in use.

## Steps

1. **Reproduce and measure.**
   - Copy the owner's DB to a temp path (read-only; **never** write to the live DB outside the app).
   - Run every timeline/filter query with `EXPLAIN QUERY PLAN` and with timing, cold (`purge`, then open)
     and warm.
   - Record the plans and times in the report.
2. **Fix the query (F2).**
   - Add a migration with covering indexes that match the WHERE + ORDER BY, e.g.
     `CREATE INDEX asset_timeline ON asset(visibility, deletedAt IS NULL, localDateTime DESC, id)`,
     plus variants with the scope/library/space column and `type`.
   - Choose the exact columns from the plans. Partial indexes (`WHERE deletedAt IS NULL`) are fine.
   - Remove the `assetExif` join from the grid projection. If the grid needs a field from it (e.g.
     ratio), denormalize it into `asset` during sync with a backfill migration.
   - Enable `PRAGMA mmap_size = 268435456` on reader connections.
   - Target: cold ≤ 1.5 s, warm ≤ 300 ms.
3. **Snapshot cache (F1).**
   - `TimelineSnapshotCache` holds built snapshots keyed by (scope, filter, grouping, sort).
   - The loader returns the cached snapshot synchronously on navigation, then revalidates in the
     background only if the change center or a sync delta marked it dirty.
   - Evict with an LRU of 6 entries and on memory-pressure notifications.
   - Target: `Library.Return` ≤ 150 ms.
4. **Launch (F3).**
   - The signed-in decision must be synchronous: read the persisted server URL and a keychain-token
     presence flag in `HeirloomMacOSApp`, so `MacConnectView` never renders for a signed-in user.
   - Persist the last Library snapshot's compact columns (ids, ratios, thumbhash, bucket boundaries) to
     `Caches/…/timeline-<scope>.bin` after each successful build.
   - On launch, show it immediately (thumbhash placeholders, then disk-cached thumbnails), then revalidate.
   - The footer must never show "0 Photos" while loading: show a spinner or the cached counts.
   - Add signposts `Launch.FirstThumbnails` and `Library.Return`.
5. **Filter pages (F4).** Media types, shared library, shared album and album pages use the same builder
   with the filter in SQL and matching indexes. Add signpost `Page.FirstPaint`. Target ≤ 1 s.
6. **Micro thumbnails (F5).**
   - Add a ≤ 64 px tier for mosaic zoom: downsample from the cached thumbnail with ImageIO off-main and
     memory-cache it.
   - Prefetch is velocity-aware: skip decoding cells that will pass the viewport within 100 ms.
   - Expose this API to WP-G (don't edit grid files).

## Constraints
- Migrations must be additive and idempotent, and must run off-main at launch with a progress log. A
  backfill on 102k rows must finish in < 10 s.
- Keep public PhotosCore API source-compatible for iOS. Run
  `xcodebuild -scheme Heirloom-iOS -destination 'generic/platform=iOS Simulator' build`.

## Proof (`reports/WP-F-REPORT.md`)
- Before/after query plans and timings (cold/warm, median of 3).
- Signpost numbers for launch cold/warm, Library.Return and Page.FirstPaint for Videos, Screen Recordings,
  Family and a shared album.
- The after-launch recording (no connect flash, no "0 Photos").
- PhotosCore test results.

## Design references (open these before coding)
`DESIGN-REFERENCE.md` pairs: **F1-launch-early, F2-launch-grid-vs-zero, P5-videos**, in `evidence/design/pairs/`. Match the left side (Apple Photos).
Your report must include AFTER captures of the same screens (`scripts/heirloom-parity/pairs.sh` rebuilds
the pairs).

## Regression tests (mandatory; see `TEST-PLAN.md` §2)
Implement every test listed for **F1–F5** in TEST-PLAN §2, in files under `Apps/macOS/Tests/<Area>/`,
`Apps/macOS/UITests/<Area>/` and/or `PhotosCore/Tests`.
- **Red first:** run each new test on base `9b9bb7f2e` (or on your branch before the fix) and record
  the failure, then fix and record the pass.
- Use `AXIDs` identifiers, the fixture library (`-HeirloomFixture`), `SyntheticEvents` for trackpad
  phases, and `GestureInputs` controllers for pinch and smart zoom. All of these come from WP-T.
- Report table: `ID | test(s) | red on base | green now | notes`. Only rows marked **H** in TEST-PLAN
  may lack an automated test.
