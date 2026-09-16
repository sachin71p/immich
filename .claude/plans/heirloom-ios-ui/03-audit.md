# Heirloom iOS — UI / UX / perf audit (2026-09-16)

Audited on the owner's **iPhone 17 Pro Max, iOS 27.0** (live data: ~102k assets, signed in to
`heirloom.sapatel.duckdns.org`), driven through Device Hub's live view. Controls without visible
thumbnails were also exercised in the **iPhone 17 Pro Max simulator** with `-useFixtureStore`.
Build under test: `b38ea8217` (`fix/heirloom-ios-sync`).

Reference = **native Photos app on the same phone** (iOS 27), captured screen by screen.

Evidence (all in `shots/`; git-ignored because they contain personal photos):
- `device-native-NN-*.png`: native Photos reference (23 screens).
- `device-heirloom-NN-*.png`: Heirloom on the same device.
- `sim-*.png`: simulator (fixture + native Photos sample library).

Profiling: `02-profile.md` (verifier). Control inventory: `01-controls.md` (scout; 177 controls).

Severity:
- **S1**: broken or unusable.
- **S2**: works, but wrong or ugly vs native.
- **S3**: polish.

## A. Performance (measured)

| # | Sev | Finding | Evidence | Root cause (file:line @ b38ea8217) |
|---|---|---|---|---|
| P1 | S1 | Cold start shows "No Photos · Pull down to sync" for about 10 s, then the grid appears. | `device-heirloom-00-coldstart-empty.png` | `LibraryGridLoader.load` (`LibraryGrid.swift:~83`) queries **every bucket's rows** in a loop, then `store.assets(ids:)` for **all ~102k ids**, then publishes one giant struct. |
| P2 | S1 | 10 hangs per session (worst 2.10 s idle-with-sync, 0.90 s on viewer open). Scrolling stutters; thumbnails lag several seconds behind a fling. | `02-profile.md` | See P3–P7. |
| P3 | S1 | `PhotoGridViewController.render()` takes 41% of main-thread time. | `02-profile.md` | `render()` (`LibraryGrid.swift:~288`), on **every** SwiftUI update: `setCollectionViewLayout(makeLayout())`, a signature string joining all bucket keys, and a full snapshot rebuild. Then `setSelected` walks every row (`:~307`). `updateUIViewController` copies the whole model each time. |
| P4 | S1 | `ThumbHash.decode` takes 23–34% of main-thread time. | `02-profile.md` | `configure(_:id:)` (`:~360`) decodes the thumbhash synchronously on main for every dequeued cell, with no cache. |
| P5 | S1 | `LibraryView.body` takes about 14% of main-thread time. | `02-profile.md` | `librarySubtitle` (`:~705`) sorts all ~102k dates and allocates a `DateFormatter` on every body evaluation. `bucketTitle` allocates 2 `DateFormatter`s per header. |
| P6 | S1 | Opening the viewer from Library hangs (0.9 s). | `02-profile.md` hang @12.95 s | `ViewerView` is a SwiftUI `TabView(.page)` over `ForEach(ids)` with **all ~102k ids** (`Viewer.swift:172`). `ViewerRequest.id` can join all ids (`LibraryGrid.swift:~750`). |
| P7 | S2 | Every sync completion rebuilds the whole library (`.task(id: …timelineVersion)`). The first sync bumps it repeatedly. | code | `LibraryGrid.swift:~671` |
| P8 | S2 | Background CPU is 94–97% GRDB reads. | `02-profile.md` | P1 loader, plus Collections loading full arrays (P9). |
| P9 | S2 | Collections loads full row arrays for favorites, recents, trash, hidden, archive, captured-by-me, locked, every media type and located assets, just to show counts. It then runs one query **per person** (hundreds). | code | `Collections.swift:~240–268` |

## B. Library tab

Native reference: `device-native-01…10`.

| # | Sev | Finding | Heirloom evidence | Native reference |
|---|---|---|---|---|
| L1 | S1 | The default grid (Square **off**) is broken: tall thin strips, black holes, overlapping slices. Search results show the same bug. | `device-heirloom-01-library-months-aspect.png`, `heirloom-05-search` | `native-02` (square 5-col grid, 1 pt gaps) |
| L1a | | Root cause: the non-square layout uses `.estimated(120)` item/group heights, so cells self-size to the `UIImageView` intrinsic image size (`LibraryGrid.swift:~337–350`). | | |
| L2 | S1 | "The operation couldn't be completed (Swift.CancellationError error 1.)" banner is shown permanently. | `heirloom-07-select-mode` | — |
| L2a | | Root cause: `LibraryView.reload()` catch sets `session.lastError` for `CancellationError` when `.task(id:)` restarts (`:~717`). The same text shows in Settings. | | |
| L3 | S1 | Selected cells have **no visual state** ("1 selected", nothing highlighted). | `heirloom-07-select-mode` | `native-09` (empty circle on every cell, blue check when selected) |
| L3a | | Root cause: `selectedBackgroundView` sits behind `contentView`, which the image view fills (`:~147`). | | |
| L4 | S1 | Entering Select mode jumps the scroll position (to Sep 2018 in the test). | device walk | — |
| L4a | | Root cause: `render()` resets layout and snapshot because `editMode` is part of the signature. | | |
| L5 | S2 | Per-section "Select" buttons stay visible after tapping Done. | `device-library-state.png` | — |
| L5a | | Root cause: headers aren't reconfigured when `editMode` changes. | | |
| L6 | S2 | Chrome is not native: small inline "Library" + tiny subtitle, a top-left photo-stack switcher button, and a "− + Select" capsule. | all heirloom library shots | `native-02`: **large title "Library"** + date-range subtitle (or "12,165 Items" at the bottom), right-side glass **filter** button + **Select** |
| L7 | S2 | Bottom chrome is stacked and cluttered: segmented Years/Months/Days/All Photos, then a "Square" toggle row, then the tab bar (three bars; selection adds a fourth). | `heirloom-01`, `heirloom-07` | `native-02`: while scrolling, the tab bar minimizes to a Library icon + a glass **Years · Months · All** control + a search button. No "Days", no toggle row. |
| L8 | S2 | Years and Months are just 2- and 3-column grids of variable-height photos. | device walk | `native-05`: **one large rounded card per year** (key photo, year label). `native-04`: month header, one hero card, and day cards with day-number overlay. Tapping drills down. |
| L9 | S2 | Zoom via "−/+" buttons; the Square toggle is a separate row. | | `native-08`: filter menu → **View Options**: Zoom In, Zoom Out, **Aspect Ratio Grid**, and Show toggles (Screenshots, Shared with You, Shared Library Badge). Pinch zooms. |
| L10 | S2 | The library switcher is a top-left menu with no checkmark on the current source. | | `native-06/07`: filter menu → **Library View** ▸ Both Libraries / Personal Library / Shared Library, with a checkmark. |
| L11 | S2 | No sort or filter. | | `native-06`: Added/Captured sort; All Items, Favorites, Edited, Shared with You, Captured by Me, Not in an Album; Media Types ▸ |
| L12 | S2 | Date scrubber is a rotated `Slider` whose white knob floats over the photos. No date bubble. | all heirloom shots | Native: draggable scroll indicator with a date label. |
| L13 | S2 | Badges use text glyphs (`♥`, `⌂`, `▤`, "LIVE") in the wrong corners. | | `native-02`: SF Symbol heart (bottom-left), duration (bottom-right), shared-library person badge (top-right). |
| L14 | S2 | **Duration badge appears on most cells** with implausible values (`1249:26`, `571:41`, `100:00`), including cells that look like photos. | device walk (fling) | — |
| L14a | | **Confirmed:** the server's `duration` is integer **milliseconds** (migration `1777667825574-ChangeDurationToInteger`). `SyncEngine/WireTypes.swift:104` stores it as seconds, so values are 1000× too large ("1845:08" is 110,708 ms, really 1:51). The format also lacks hours. The macOS app is affected too (shared PhotosCore). | | |
| L15 | S2 | Cells have no placeholder colour. Before thumbnails decode, the grid is white (light) or black (dark) with orphan badges. | `sim-01/02` | Native: neutral fill placeholder. |
| L16 | S2 | Selection action bar is a horizontally overflowing row of text pills ("Share Favorite Add to Album Archive Mov…"), plus "Clear". | `heirloom-07` | `native-09/10`: top bar = filter, **…** menu (Copy, Duplicate, Hide, Favorite, Slideshow, Add To ▸, Move To ▸, Adjust Info ▸), ✕. Bottom bar = Share, "Show Selected (N)", Trash. |
| L17 | S3 | Header titles are plain 17 pt bold with no sticky behaviour. The All view has headers although native shows none. | | Native All: no section headers; the title subtitle shows the visible date range. |
| L18 | S3 | "Timeline Sources" sheet shows developer text: "Library timeline toggles need a wired library-member endpoint (open issue)." | device walk | — |

## C. Photo viewer

Native reference: `native-11…14`.

| # | Sev | Finding | Evidence | Native |
|---|---|---|---|---|
| V1 | S1 | **Bottom toolbar buttons do nothing on device**: Info tapped twice, "…" once; nothing opens. Close (✕) works. | `heirloom-04-viewer`, device walk | — |
| V1a | | Suspected cause (verify): the `.gesture(DragGesture())` on the NavigationStack (`Viewer.swift:~235`) swallowing bar-button touches, or bottom-bar items inside a full-screen cover over a paging TabView. **Reproduce with a UI test first.** | | |
| V2 | S1 | Swipe-up does nothing. | device walk | `native-13`: swipe up reveals an Info panel **under** the photo (Ask Siri / Image Search row, date card, camera + EXIF card, map). |
| V3 | S1 | Viewer over all 102k ids (P6). | | |
| V4 | S2 | Top bar: a lone ✕, no title. | `heirloom-04` | `native-12`: back chevron; centre glass pill with **location + date/time**; "…" on the right; badges row (LIVE, "From <owner>"). |
| V5 | S2 | Bottom bar has 6 small icons (share, heart, info, adjust, trash, …). No filmstrip. | | `native-12`: **filmstrip** of neighbouring thumbnails above a bottom bar with Share, (Favorite / Info / Adjust in photo mode), and Trash. |
| V6 | S2 | Info opens as a `.sheet` List (medium/large) with a "Container" row. | code | Native inline panel (see V2) |
| V7 | S3 | Video: no native-style scrubber row or mute button. | | `native-11` |

## D. Collections

Native reference: `native-15…23`.

| # | Sev | Finding | Evidence | Native |
|---|---|---|---|---|
| C1 | S1 | People: hundreds of rows reading "Unnamed · 0" with no faces. Every section below People (Memories, Places, Favorites, Utilities…) is effectively unreachable. | `heirloom-02-collections`, device walk | `native-21`: grid of **face cards**; unnamed faces are hidden. |
| C1a | | **Unexplained: investigate** why person asset counts are 0 (`store.assetIds(forPerson:)`; face sync may be missing). | | |
| C2 | S1 | Album, space, favorites, recents, media-type, utility, camera and person detail screens are `List` rows (44 pt thumb + blue date text), **not a grid**. Thumbnails load slowly one by one. | `heirloom-03-album-detail` | `native-20`: **hero cover** (key photo, title, item count, slideshow button) above a 5-column square grid. |
| C2a | | Root cause: `AssetRowList` (`Collections.swift:10`) is used 11× (Collections ×10, Albums ×1). | | |
| C3 | S2 | The whole screen is a plain inset `List` of text rows. | `heirloom-02` | `native-15…18`: a scroll view of **collapsible sections with horizontal carousels**, in this order: Memories (large cards) · Pinned (Favorites / Recently Saved / Map tiles, Edit) · Albums › · People › · Featured Photos · Shared Albums (Activity) · Recent Days · Trips · Media Types (2-col pill grid) · Utilities (pill grid with lock icons) · Reorder. Header has a "…" button and an account avatar. |
| C4 | S2 | "Albums" has no all-albums page with tiles. | | `native-19`: Albums page with Personal / Shared / Activity segments, a 2-col rounded tile grid, "+", and "…" |
| C5 | S2 | Space (Shared Library) timeline rows are **unsorted** (Jan 31, Feb 2, Jan 29…). | device walk (Family) | Sorted grid |
| C6 | S3 | Memories page. | | `native-23`: full-width cards with title/date and a play button; "Create". |

## E. Search

Native reference: `native-22`.

| # | Sev | Finding | Evidence | Native |
|---|---|---|---|---|
| S1 | S1 | Result grid uses the broken aspect layout (L1). | `device walk` | Square grid |
| S2 | S1 | People suggestion chip lists **blank rows**. Places and Camera say "No suggestions" despite 102k assets. | device walk | Suggestions with thumbnails |
| S2a | | **Unexplained: investigate** (place/camera indexes, unnamed people). | | |
| S3 | S2 | Custom top text field with a separate blue "Search" button, "All ⌄" picker, chip row, "Filters ›" row, and "Recent searches" list with a lone "a". | `heirloom-05-search` | `native-22`: large title; **Recents** as image cards (Clear, ›); suggestion pills near the bottom; the **search field sits at the bottom** next to a close ✕ (iOS 26+ `Tab(role: .search)`). |
| S4 | S3 | Typing through Device Hub dropped characters and the search fired on "a". There's no debounce. | device walk | — |

## F. App structure, Shared, Settings

| # | Sev | Finding | Evidence | Native |
|---|---|---|---|---|
| T1 | S2 | 5 tabs: Library, Collections, Search, Shared, Settings. | all | `native-02/15`: **2 tabs (Library, Collections) + a separate search button** (search role). Shared libraries live in the filter menu (Library View) and in Collections (Shared Albums section). Account/settings live behind the **avatar** in Collections. |
| T2 | S2 | Shared tab is a bare list (Family, Friends) with "+". | device walk | Fold into Collections → "Shared Libraries" section (tiles), with "+" in the section header or the avatar sheet. |
| T3 | S2 | Settings shows the **user UUID** instead of name/email, and shows the CancellationError text (L2). | `heirloom-06-settings` | Account sheet: avatar, name, email |
| T4 | S3 | Settings About footer shows developer text: "Follow Apple Photos interaction patterns; never Apple artwork or the Photos name." | device walk | — |
| T5 | S3 | Launch banner: `Registration rejected… backup-processing not advertised` (from the earlier sync brief, F1 in its REPORT). Still open. | `heirloom-ios-sync/REPORT.md` | — |

## G. What works (keep)
- Pull-to-refresh and auto-sync (the sync fix landed); Timeline Sources sheet toggles.
- Square grid when Square is ON (`device-library-square.png`): close to native already.
- Viewer paging by swipe, Close button, photo rendering quality.
- Library switcher menu actions; "−" column change; Settings Sync Now.
