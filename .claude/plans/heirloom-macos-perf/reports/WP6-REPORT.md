# WP6 — Parity pages close-out report (slices A + B + C)

Branch `perf/heirloom-macos-wp6` (worktree `/Users/spatel/workspace/github/projects/immich-wp6`),
8 commits. Slices A (People, Memories) and B (Map, Collections) landed first; slice C
(Search, All Albums, Duplicates + this report) closes the WP. No dead controls remain that
the brief requires; two omissions are brief-mandated (API lacks the endpoint).

## Commits (all end `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`)

Slice A — People + Memories:
- `f9e2b9ce8` `perf(photoscore)`: `personAssets` + `timelineRows(ids:)` read-only queries
  (new LocalStore files only).
- `b82859c51` `feat(macos)`: People face grid + person detail, `.person` destination case.
- `46b671ac7` `feat(macos)`: Photos-style memory cards + player controls + show-all grid.

Slice B — Map + Collections:
- `fcd781182` `perf(photoscore)`: collection COUNT queries for Collections shelves
  (new `LocalStore+Counts`).
- `ca6d9cd90` `feat(macos)`: screen-space clustered map over all located points.
- `b00142740` `feat(macos)`: Collections shelves + panorama destination + native counts.

Slice C — Search + All Albums + Duplicates:
- `cddd39063` `feat(macos)`: toolbar query handoff, shared cover tile.
- `db1a69084` `feat(macos)`: albums sort/New Album, duplicates thumbnails.

## Files changed

- Slice A: `MacPeopleView.swift` (new; moved out of `MacMainWindow.swift` — the only edit
  there), `MacMemoriesView.swift`, `MacSidebarModel.swift` (`.person` case only),
  new `LocalStore+People.swift`.
- Slice B: `MacMapPlacesView.swift`, `MacCollectionsView.swift` (new), `MacSidebarModel.swift`
  (new cases only), new `LocalStore+Counts.swift`.
- Slice C owned: `MacSearchView.swift` (pending-query consume, Filters identifiers),
  `MacAllAlbumsView.swift` (rewrite on shared tile + sort + New Album),
  `MacDuplicatesView.swift` (pipeline thumbnails + keep badge).
- Slice C prior-slice edits (LOUD, minimal): `MacCollectionsView.swift`
  (`MacCoverTile` private→internal, 1 word + comment), `MacAppState.swift`
  (new `pendingSearchQuery`, mirrors `viewerContext` precedent), `MacMainWindow.swift`
  (toolbar Return stashes query then navigates). No PhotosCore file touched in slice C.

## Verification (this session)

- `make build-macos` (Release): **BUILD SUCCEEDED**.
- `swift test --package-path native-apple/PhotosCore`: **174 tests in 24 suites passed**.
- No destructive action taken against the real library (build + unit tests only, no fixture
  seed run, no trash/resolve/delete exercised).

## Per-page render status

Code + build verified for all pages; on-screen render against the owner's 102k library,
1 s budgets, and `profile.sh wp6 90` map profiling are **host-only** (need the Release app
on the owner's server + Instruments; agents can't drive the GUI or reach the library).

- People: face grid (120 pt circles, named-first-then-count, search filter, Show Hidden),
  `.person(id)` detail in standard grid. Rename omitted — client has no `updatePerson`.
- Memories: cards (16:10 cover, title, count), On-This-Day per-year grouping, player
  (Close/arrows/auto-advance/click-pause), show-all grid, empty state.
- Map: all located points off-main, 60 pt screen-space bins, ≤1,500 annotations, add/remove
  diffing, count badges, cluster-click zoom-or-panel, "N photos in this area" header, no cap text.
- Collections: Albums / Shared Libraries / People / Memories / Pinned / Media Types /
  Utilities shelves with See All, native counts filling progressively, Hidden/Locked auth kept.
- Search: single "Search" navigation title (no duplicate in-body title); results in
  `MacCollectionGridView` via fresh `TimelineGridSnapshot`; toolbar Return applies+executes.
- All Albums: shared `MacCoverTile`, Name/Recent sort, New Album sheet, empty state.
- Duplicates: groups with pipeline thumbnails, suggested-keep badge, view-to-review;
  no resolve controls (see deviations).

## Every Search control — disposition

| Control | Disposition |
|---|---|
| Duplicated "Search" title | None present — view has only `.navigationTitle`; no removal needed |
| Results grid | `MacCollectionGridView` + snapshot, no custom grid (kept) |
| Chip People | Working picker: local owner-people list → `personIds` filter → executes |
| Chip Places | Working picker: server `city` suggestions → `city` filter → executes |
| Chip Camera | Working picker: server `camera-make` suggestions → `make` field → executes |
| Chip Lens | Working picker: server `camera-lens-model` suggestions → `lensModel` → executes |
| Chip File type | Working picker: server `file-extension` suggestions → `fileExtensions` → executes |
| Scope segmented | All / Personal / per-space / per-library; re-runs on change via `SearchScope.resolve` |
| Toolbar search Return | Navigates to Search with query applied + executed, then cleared |
| Filters disclosure | Working: make, favorites, media type, location + Apply; identifiers added |
| Recent searches | Working: record / re-run / clear |

## Deviations from WP6-PARITY.md

1. No literal "Friends" scope segment: `SearchScope` has All/Personal/space/library only.
   Friends' content is reachable via per-space segments (superset of the brief's trio).
2. Duplicates "Keep best / Trash others" not shown, per §6's else-clause: the generated
   client filter (`openapi-generator-config.yaml`) includes only `getAssetDuplicates`;
   adding `resolveDuplicates`/`deleteDuplicates` means editing an existing PhotosCore file,
   which WP6 forbids. Server supports it (`/duplicates/resolve`, v3.0.0+); a follow-up WP
   owning PhotosCore can add the op + buttons.
3. People rename omitted per §1's else-clause (no `updatePerson` in client).

## Open issues / handoff to WP7

- Host must confirm: each page ≤1 s on the real library, map no hang ≥250 ms
  (`profile.sh wp6 90`), toolbar-search and Filters disclosure by hand.
- Follow-up (needs PhotosCore ownership): duplicates resolve buttons; People rename if the
  server/client gains `updatePerson`.
- `MacCoverTile` is now internal — future tile changes affect Collections + All Albums together.
