# WP6 — Parity pages: People, Memories, Map, Collections, Search

Read `PLAN.md` first. **Prerequisite:** WP3 and WP4 are merged; you reuse `MacCollectionGridView`
with a `TimelineGridSnapshot`. Owned files:
- `MacMemoriesView.swift`, `MacMapPlacesView.swift`, `MacAllAlbumsView.swift`, `MacSearchView.swift`,
  `MacDuplicatesView.swift`
- new `MacPeopleView.swift`: move `MacPeopleView` out of `MacMainWindow.swift`, which is the only edit
  allowed there
- new `MacCollectionsView.swift`
- `MacSidebarModel.swift`, only for new destination cases

You may add new files under `PhotosCore/Sources/LocalStore/` for read-only queries.

## 1. People (U19)
- A grid of circular face thumbnails:
  - loaded via `pipeline.personThumbnail(id:)` (WP1);
  - 120 pt circles with the name below (or "Add Name" in secondary colour) and the photo count;
  - sorted with named people first, then by count.
- A search field filters by name. A "Show Hidden" toggle.
- Click → a new destination `.person(id)` showing that person's photos in the standard grid
  (Months grouping), titled with the person's name.
  - Needs `personAssets(personId:scope:) -> [TimelineRow]`. If WP1 didn't add it, add it in a new
    `LocalStore+People.swift`.
  - If the local schema has no asset↔face link, report it with the exact missing table/sync endpoint.
    Show People with thumbnails and counts from the server API instead, if `ImmichConnection` exposes
    `/people`, and state the limitation.
- Rename a person: only if the API client has `updatePerson`; otherwise omit the control (no dead
  buttons).

## 2. Memories (U20)
- Replace the row list with Photos-style **cards**:
  - a large cover (preview tier, 16:10, 12 pt radius);
  - title ("On This Day", "September 16, 2020 · 6 years ago") and item count.
- Group "On This Day" by year, one card per year, newest first.
- Existing stories get cards in the top section.
- Clicking a card plays `MacStoryPlayerView` (verify it works: Close button, arrow keys, auto-advance,
  pause on click). "Show all photos" opens a grid of that memory's photos.
- Empty state for no memories.

## 3. Map (U18)
- Load **all** located points with `store.locatedAssetPoints(scope:)` (WP1), off-main.
- Clustering must stay smooth with 100k points. On region change (debounced 150 ms):
  1. Grid-bin points in screen space (cell ≈ 60 pt) **off-main**.
  2. Produce ≤ 1,500 annotations with count and representative id.
  3. Diff against the current annotations: remove/add only the changed ones.
- Annotation view: a rounded-square thumbnail of the representative photo (memory cache, then async),
  with a count badge (Photos style).
- Clicking a cluster zooms in if its count > 1 and the zoom isn't at max; otherwise the side panel shows
  those photos in `MacCollectionGridView` (a snapshot built from their ids via a row query).
- Remove the "2,000" cap text. The side panel header shows "N photos in this area" for the visible
  region, from binned counts.

## 4. Collections (U15, currently blank)
Build `MacCollectionsView`, a scrollable page of horizontal shelves, each with a "See All" button:
- Albums: cover thumbnail, name and count; See All → All Albums.
- Shared Libraries.
- People: top 8 faces → People.
- Memories: recent cards → Memories.
- Pinned: Favorites, Recently Saved, Map.
- Media Types: Photos, Videos, Selfies, Live Photos, Portrait, Panoramas, Screenshots, Screen
  Recordings, each with its count.
- Utilities: Imports, Duplicates, Hidden, Recently Deleted. Hidden and Locked keep the existing auth.

Every tile navigates via the existing `selectDestination` callback. Counts use cheap COUNT queries
(new `LocalStore+Counts.swift` if needed), loaded off-main and cached until `timelineVersion` changes.

## 5. Search (U16)
- Remove the duplicated "Search" title.
- Results render in `MacCollectionGridView` via a snapshot, with no custom grid.
- The suggestion chips (People, Places, Camera, Lens, File type) must each open a working picker or be
  removed.
- Scope segmented control (All/Personal/Friends) must filter.
- Pressing Return in the toolbar search field lands on Search with the query applied and executed.
- Verify the Filters disclosure works. Record every control in `reports/WP6-REPORT.md`.

## 6. All Albums / Duplicates
- All Albums: a grid of album covers (reuse the Collections album tile), sortable (name / recent),
  with New Album.
- Duplicates: groups show thumbnails, and "Keep best / Trash others" only if the API supports it.
  Otherwise the control isn't shown.

## Acceptance
- Release build and tests pass.
- Each page renders against the real library within 1 s (People/Collections counts may fill in
  progressively).
- Map pans and zooms with no hang ≥ 250 ms (profile with `profile.sh wp6 90`).
- No dead controls.
- Report: `reports/WP6-REPORT.md`.
