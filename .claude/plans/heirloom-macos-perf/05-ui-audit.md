# Heirloom macOS — hands-on UI audit (installed build, 2026-09-16, library 80,361 photos + 22,271 videos)

Severity: P0 = broken/unusable, P1 = wrong behavior, P2 = polish/parity.
Status (Wave 4): fixed = code-complete + unit-verified (visual confirm still wanted);
partially = improved, needs visual; open = needs host/hands. No regressions observed.

| # | Area | Observation | Sev | Status |
|---|---|---|---|---|
| U1 | Launch | Window not drawn/responsive for ~30s (main thread ~90–105% CPU, RSS spikes to 366 MB). AX tree unavailable to accessibility clients the whole session. | P0 | partially — GridLoad 3.9–5.5 s, hangs 2–4 micros; responsiveness unconfirmed visually |
| U2 | Library grid | Months / All Photos show a completely blank grid for 60s+ even though footer shows 80,361 photos / 22,271 videos. | P0 | partially — R1 mechanism fixed (cache-first row loads), needs visual |
| U3 | Grouping | Switching to Years shows red banner "The operation couldn't be completed. (Swift.CancellationError error 1.)" and footer flips to "0 Photos, 0 Videos", subtitle "No Photos"; banner persists after load. Cancellation surfaced as user error. | P0 | fixed — silent cancel + Retry banner (visual confirm wanted) |
| U4 | Grouping | Years/Months/All Photos render the identical flat grid — no month/year headers, no Years summary tiles (section headers never rendered: numberOfSections == 1). | P1 | fixed — custom layout + year/month headers (visual confirm wanted) |
| U5 | Toolbar | Toolbar controls shift horizontally when subtitle text changes (date range ↔ "No Photos"). | P2 | fixed — fixed title frame |
| U6 | Grid | Single click has no visible effect (selection only in explicit Select mode); Photos selects on single click. | P1 | fixed — single-click selects (needs click) |
| U7 | Viewer | Right arrow then Left arrow lands on a third, different photo — paging order inconsistent with grid order. | P0 | fixed — display-order clamp (needs →← check) |
| U8 | Viewer | Title shows raw filename (UUID-like) instead of date/location as Photos does. | P2 | fixed — date/place title (visual confirm wanted) |
| U9 | Info | Inspector lacks EXIF (camera, lens, exposure), location/map, file size; "Container: Personal Library" wording. | P2 | fixed — Photos-style inspector + EXIF (visual confirm wanted) |
| U10 | Grid | Thumbnails drawn with heavy black borders/rounded frames that don't match Photos' edge-to-edge look. | P2 | fixed — border mechanism removed (needs fling check) |
| U11 | Viewer | Rotate is display-only and rotated image overflows its container (not re-fit). | P1 | fixed — re-fit + persist path (needs rotate×4 check) |
| U12 | Move sheet | No Cancel button, Escape does nothing, and app Quit is refused ("User canceled") while sheet is open → user is trapped; only exit is force-quit. Tapping a space target moves immediately without confirm. | P0 | fixed — Cancel/Escape/quit/confirm (sheet tests still env-gated) |
| U13 | Move sheet | Only destination offered is "Friends" (no Personal Library / albums). Unstyled plain list. | P1 | fixed — destinations + Current row (visual confirm wanted) |
| U14 | Launch | Clicks during first ~30s are dropped; window renders greyed/blank (Collections showed blank). | P0 | partially — launch 3.9–5.5 s, needs visual |
| U15 | Collections | Blank page while grid toolbar (Years/Months/zoom/Select) remains visible and enabled. | P1 | fixed — Collections shelves page (visual confirm wanted) |
| U16 | Search | Grid toolbar (Years/Months/All Photos/zoom) shown on Search page where it doesn't apply; title duplicated ("Search" twice). | P2 | fixed — scoped toolbar (visual confirm wanted) |
| U17 | Recently Saved | Shows empty-framed thumbnails that never load; footer shows full-library count (80,361) instead of section count. | P1 | fixed — per-destination footer + row loads (visual confirm wanted) |
| U18 | Map | Located photos capped at "2,000"; several side-panel thumbnails never load; grid toolbar shown on map. | P1 | fixed — cap removed, clustering (needs pan/zoom) |
| U19 | People | Plain text list of "Unnamed" rows with no face thumbnails, no names, no photo counts → unusable. | P0 | fixed — face grid + detail (visual confirm wanted) |
| U20 | Memories | "On This Day" is a list of identical "September 16, 2020" rows with tiny thumbnails; no cards/playback. | P1 | fixed — cards + player (needs verify) |
| U21 | Photos (media type) | Blank grid (footer says 57,048 photos). | P0 | partially — same fix as U2, needs visual |
| U22 | Videos / Live Photos / Portrait / album | Empty framed placeholders; thumbnails still not loaded after 16s+. Thumbnail loading broadly broken/slow for uncached assets. No thumbhash placeholders visible either. | P0 | partially — same fix as U2, needs visual |
| U23 | Selfies | 0 items and no empty-state message. | P2 | fixed — per-destination empty states |
| U24 | Shared library "Friends" | Page title says "Shared Library" instead of "Friends"; toolbar overflows (»), hiding Manage/Sync. | P1 | fixed — resolved titles (proven: AX shows "Family") |
| U25 | Album "Arpan Marriage" | Title shows "Album" not album name; thumbnail doesn't load. | P1 | fixed — resolved titles (proven: AX shows "Library") |
| U26 | Diagnostics | App emits no unified logs at all — failures are invisible. | P2 | fixed — HeirloomLog + signposts (storm diagnosed via them) |
| U27 | Grid | Grid Rotate: menu Image›Rotate is a no-op `rotate: {}`; toolbar Rotate only toasts. | P1 | fixed — persists via edits path |
| U28 | Video badges | Server duration is ms, stored as seconds → badges 1000× (found Wave 3). | P1 | fixed — wire ms→s + v4 backfill, tested |
| U29 | Prefetch storm | Idle prefetch churn (3,210 cancels, 138 404s/899 ids) → hang clusters (found Gate 3). | P0 | fixed — gated reload, window no-op, 404 hold, quiet cancels; re-gate 2/0.69 s |
| U30 | Launch variance | GridLoad 5.2→3.6 s after pool migration; attributed: 229 MB cold DB file, all-local fetch, main idle (page-cache IO wait). | P1 | open — last-mile is mmap/covering-index/prewarm, future work |
| U31 | Main-thread warnings | "Should not be called on the main thread" runtime warnings in UI runs. | P2 | open — attribute harness vs app |
| U32 | UI-test gate | Seeded app foregrounds but never renders sidebar/content in test env (13/13 gated; 3 pass past other gates). | P1 | open — environmental, host re-run |
| — | Not exercised (destructive on real library) | Trash, Lock, Move-confirm, Add-to-album confirm, New Album, New shared library, Import. Verify on a test account. | — | open |

Responsible WP for opens: U30 → perf harness re-sample (WP7); U31 → WP2/WP4 triage;
U32 → host run; destructive list → WP4/WP7 fixture or test account.
