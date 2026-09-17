# WP-P — Collections, Search, Map, People, Memories, Albums

Read first: `PLAN.md` (§0, §1 P-rows, §3) and `EVIDENCE.md`. Photos reference:
`evidence/photos-screens/05-search-results.png`, `06-collections-top.png`, `07-map.png`, `09-album.png`.
Heirloom current state: `evidence/heirloom-screens/05-collections.png` (every tile reads 0 items).

Base: the Gate 1 merge (WP-F's cache, indexes and filter builder are in). Current code:
`MacCollectionsView.swift`, `MacSearchView.swift` (`SearchService.searchIds()` vs local
`filterAssets()`, around :215–248), `MacMapPlacesView.swift`, `MacMemoriesView.swift`,
`MacPeopleView.swift`, `MacAllAlbumsView.swift`.

## Steps

1. **Collections zero counts (P1, P0).**
   - Find why the counts, albums, people and memories are empty on first paint. Candidates: counts
     computed before sync, a wrong scope id, or a failed query that is swallowed. Log it and fix it.
   - Counts come from one aggregated SQL query (`LocalStore+Counts`), ≤ 100 ms, and refresh on
     change-center events.
   - Tiles show real key photos, not SF symbols.
2. **Search (P2, P0).**
   - Reproduce "beach" returning everything.
   - Wire Immich smart search (`POST /api/search/smart`, CLIP; check the fork's OpenAPI in `open-api/`
     for the exact shape and paging) and metadata search (`/api/search/metadata` plus place/person name
     matches from the local store). Merge and dedupe the results, preserving server rank.
   - Provide `suggestions(for:)` for WP-C: places, people, albums and CLIP query echo, with counts where
     cheap. Debounce 150 ms and cancel stale requests.
   - Offline: local metadata only, with a "Showing on-device results" banner.
3. **Search results page (P5).**
   - Title "Search", subtitle "Results for <query>".
   - Photos | Collections segmented control.
   - "Top Results" row (first 10 by rank), then "N Results" rendered with WP-G's grid in a filtered-ids
     mode. Collections tab: matching albums, people and places as tiles.
4. **Filter pages (P3).** Verify WP-F's builder is used by Videos, Screenshots, Screen Recordings,
   Selfies, Live Photos, Portrait, Panoramas, the shared libraries (Family, Friends), shared albums and
   albums. `Page.FirstPaint` ≤ 1 s each. Record the numbers.
5. **Collections layout (P4).**
   - A vertical scroll of shelves. Each shelf is a horizontal scroll (trackpad and ‹ › buttons on hover).
     Header: title with "›" (drills into the full page) and a collapse chevron (persisted).
   - **Shelves in order:**
     - Memories: 16:9 cards, title + date, Play.
     - Pinned: tiles with key photos.
     - Albums.
     - People: face tiles with names.
     - Shared Libraries (Heirloom).
     - Featured Photos: favorites-based until Immich offers ranking.
     - Shared Albums: empty-state card as Photos.
     - Recent Days: day cards.
     - Trips: from Immich places + date clustering if available, otherwise hidden.
     - Media Types: list rows with counts.
     - Utilities: list rows with counts — Favorites, Recently Edited, Map, Recently Deleted,
       Recently Saved, Duplicates, Imports, Hidden.
   - Right-click on a tile: Pin to Sidebar / Unpin (WP-C persists the pins).
6. **Map, People, Memories, All Albums audit (P6).**
   - Put each page beside Photos (`07-map.png` and live Photos) and fix the visual deltas:
     - Map: full-bleed under glass, Map/Satellite/Grid segmented control, thumbnail cluster pins with
       counts, zoom controls, search field.
     - People: large face tiles and a Groups shelf.
     - Memories: cards with Play.
     - All Albums: grid with sort.
   - Capture Heirloom screenshots first; this session didn't record them.

## Proof (`reports/WP-P-REPORT.md`)
- Collections before/after screenshots with correct counts (compare them to a SQL count).
- Search "beach" result count vs the server web UI for the same query.
- Page.FirstPaint table.
- Side-by-side screenshots for each page.
- UI tests on the fixture: search finds a known asset; Collections shows non-zero counts.

## Design references (open these before coding)
`DESIGN-REFERENCE.md` pairs: **P1–P7, photos/40b-collections-bottom.png, photos/41-search-*.png**, in `evidence/design/pairs/`. Match the left side (Apple Photos).
Your report must include AFTER captures of the same screens (`scripts/heirloom-parity/pairs.sh` rebuilds
the pairs).

## Regression tests (mandatory; see `TEST-PLAN.md` §2)
Implement every test listed for **P1–P8** in TEST-PLAN §2, in files under `Apps/macOS/Tests/<Area>/`,
`Apps/macOS/UITests/<Area>/` and/or `PhotosCore/Tests`.
- **Red first:** run each new test on base `9b9bb7f2e` (or on your branch before the fix) and record
  the failure, then fix and record the pass.
- Use `AXIDs` identifiers, the fixture library (`-HeirloomFixture`), `SyntheticEvents` for trackpad
  phases, and `GestureInputs` controllers for pinch and smart zoom. All of these come from WP-T.
- Report table: `ID | test(s) | red on base | green now | notes`. Only rows marked **H** in TEST-PLAN
  may lack an automated test.
