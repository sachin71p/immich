# Heirloom macOS — hands-on UI audit (installed build, 2026-09-16, library 80,361 photos + 22,271 videos)

Severity: P0 = broken/unusable, P1 = wrong behavior, P2 = polish/parity.

| # | Area | Observation | Sev |
|---|------|-------------|-----|
| U1 | Launch | Window not drawn/responsive for ~30s (main thread ~90–105% CPU, RSS spikes to 366 MB). AX tree unavailable to accessibility clients the whole session. | P0 |
| U2 | Library grid | Months / All Photos show a completely blank grid for 60s+ even though footer shows 80,361 photos / 22,271 videos. | P0 |
| U3 | Grouping | Switching to Years shows red banner "The operation couldn't be completed. (Swift.CancellationError error 1.)" and footer flips to "0 Photos, 0 Videos", subtitle "No Photos"; banner persists after load. Cancellation surfaced as user error. | P0 |
| U4 | Grouping | Years/Months/All Photos render the identical flat grid — no month/year headers, no Years summary tiles (section headers never rendered: numberOfSections == 1). | P1 |
| U5 | Toolbar | Toolbar controls shift horizontally when subtitle text changes (date range ↔ "No Photos"). | P2 |
| U6 | Grid | Single click has no visible effect (selection only in explicit Select mode); Photos selects on single click. | P1 |
| U7 | Viewer | Right arrow then Left arrow lands on a third, different photo — paging order inconsistent with grid order. | P0 |
| U8 | Viewer | Title shows raw filename (UUID-like) instead of date/location as Photos does. | P2 |
| U9 | Info | Inspector lacks EXIF (camera, lens, exposure), location/map, file size; "Container: Personal Library" wording. | P2 |
| U10 | Grid | Thumbnails drawn with heavy black borders/rounded frames that don't match Photos' edge-to-edge look. | P2 |
| U11 | Viewer | Rotate is display-only and rotated image overflows its container (not re-fit). | P1 |
| U12 | Move sheet | No Cancel button, Escape does nothing, and app Quit is refused ("User canceled") while sheet is open → user is trapped; only exit is force-quit. Tapping a space target moves immediately without confirm. | P0 |
| U13 | Move sheet | Only destination offered is "Friends" (no Personal Library / albums). Unstyled plain list. | P1 |
| U14 | Launch | Clicks during first ~30s are dropped; window renders greyed/blank (Collections showed blank). | P0 |
| U15 | Collections | Blank page while grid toolbar (Years/Months/zoom/Select) remains visible and enabled. | P1 |
| U16 | Search | Grid toolbar (Years/Months/All Photos/zoom) shown on Search page where it doesn't apply; title duplicated ("Search" twice). | P2 |
| U17 | Recently Saved | Shows empty-framed thumbnails that never load; footer shows full-library count (80,361) instead of section count. | P1 |
| U18 | Map | Located photos capped at "2,000"; several side-panel thumbnails never load; grid toolbar shown on map. | P1 |
| U19 | People | Plain text list of "Unnamed" rows with no face thumbnails, no names, no photo counts → unusable. | P0 |
| U20 | Memories | "On This Day" is a list of identical "September 16, 2020" rows with tiny thumbnails; no cards/playback. | P1 |
| U21 | Photos (media type) | Blank grid (footer says 57,048 photos). | P0 |
| U22 | Videos / Live Photos / Portrait / album | Empty framed placeholders; thumbnails still not loaded after 16s+. Thumbnail loading broadly broken/slow for uncached assets. No thumbhash placeholders visible either. | P0 |
| U23 | Selfies | 0 items and no empty-state message. | P2 |
| U24 | Shared library "Friends" | Page title says "Shared Library" instead of "Friends"; toolbar overflows (»), hiding Manage/Sync. | P1 |
| U25 | Album "Arpan Marriage" | Title shows "Album" not album name; thumbnail doesn't load. | P1 |
| U26 | Diagnostics | App emits no unified logs at all — failures are invisible. | P2 |
| U27 | Grid | Grid Rotate: menu Image›Rotate is a no-op `rotate: {}`; toolbar Rotate only toasts. | P1 |
| — | Not exercised (destructive on real library) | Trash, Lock, Move-confirm, Add-to-album confirm, New Album, New shared library, Import. Verify on a test account. | — |
