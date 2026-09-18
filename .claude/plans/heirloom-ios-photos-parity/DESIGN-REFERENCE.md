# Design reference — Heirloom iOS vs Apple Photos

All images live under `assets/`. Captured 2026-09-17 from **Sachin's iPhone 17 Pro Max, iOS 27.0**,
mirrored through Xcode's Device Hub and cropped to the device screen. **Dark appearance only** —
a partial light-appearance pass is in `assets/light/` (see §4).

> **In every `pairs/` image: Apple Photos is on the LEFT (the target), Heirloom is on the RIGHT (today).**

## 1. Start here — the paired comparisons

Open all fifteen before writing any code.

| Pair | Shows | Gaps it proves |
|------|-------|----------------|
| `pairs/01-library.png` | Library grid | G1 duration badges, G2 hearts, G3 badge noise, G6 header |
| `pairs/02-library-pills.png` | Bottom chrome | C1 one bar vs two rows, C2 "All" vs "All Photos" |
| `pairs/03-grid-pinched.png` | Zoomed-out grid | G5 floating date badge |
| `pairs/04-viewer.png` | Photo viewer | V1 title/place/people, V2 LIVE badge, V3 toolbar grouping |
| `pairs/05-info-panel.png` | **Info sheet** | V4 — the single largest gap |
| `pairs/06-editor-photo.png` | Photo editor | **F1 black canvas**, E1 tabs, E3 ruler dial |
| `pairs/07-editor-styles.png` | Styles vs Filters | E2 live thumbnails vs text labels |
| `pairs/08-editor-crop.png` | Crop | E1, crop overlay |
| `pairs/09-video-viewer.png` | Video viewer | **F2 black playback**, V7 filmstrip scrubber |
| `pairs/10-video-editor.png` | Video editor | **E5 trim filmstrip**, E6 Audio Mix |
| `pairs/11-account.png` | Account header | P1 centred identity block, P2 user ID |
| `pairs/12-settings-list.png` | Settings list | P3 missing items, P4 items to preserve |
| `pairs/13-search.png` | Search | P6 natural language vs metadata chips |
| `pairs/14-collections.png` | Collections | P5 empty Memories |
| `pairs/15-longpress.png` | Long-press | G4 — Heirloom has no context menu at all |

## 2. Videos

`assets/video/` — 360 px wide H.264, no audio.

| File | What to watch |
|------|---------------|
| `photos-pinch.mp4` | Continuous density zoom ≈4 → ≈5 → ≈10+ columns; **floating "Aug 2026" badge** appears at high density; header range updates live |
| `heirloom-pinch.mp4` | Density zoom **works** (≈5 ↔ ≈10 columns) but the Years/Months/All pills never move (G7); at ~20 s a pinch on an open photo shrinks it to a floating rect instead of dismissing (V8) |
| `photos-viewer-swipe.mp4` | Horizontal swipe → next/previous photo; the behaviour Heirloom must keep matching |
| `heirloom-viewer-swipe.mp4` | Same gesture in Heirloom — already correct |
| `photos-library-scroll-pills.mp4` | Chrome auto-hide/reveal on scroll; note the library is **oldest-at-top and opens at the bottom** |
| `photos-cold-launch.mp4` | Launch → Library grid (launched from Spotlight) |
| `heirloom-cold-launch.mp4` | Launch → Library grid (launched from the home-screen icon) |

> Launch-source differs between the two launch videos (Spotlight vs home icon) because Photos has no
> home-screen icon on this device. Compare **time-to-first-content**, not the launch animation.

## 3. Raw screens

`assets/photos/` — 23 files, the target. `assets/heirloom/` — 28 files, today.
Filenames are self-describing. The most load-bearing:

- `photos/13-viewer-info.png` + `photos/14-viewer-info-scrolled.png` — the full info panel spec (PLAN §2)
- `photos/05-grid-longpress-menu.png` — exact context-menu contents and order
- `photos/21-editor-video-trim.png` — the trim filmstrip
- `photos/09-account-sheet.png` + `photos/10-settings-bottom.png` — settings target (PLAN §3)
- `heirloom/14`, `heirloom/22`, `heirloom/23` — the black-canvas defects (F1, F2, F3) on the Debug build
- `heirloom/29-RELEASE-editor-still-black.png`, `heirloom/30-RELEASE-editor-chrome-fast-canvas-black.png`
  — **the same defect on a Release build.** `30` is the important one: chrome fully loaded and
  interactive in under 5 s, canvas still pure black. Proof that F1 is not a latency problem.

## 4. Known gaps in this reference

- **Light appearance: partial pass done.** `assets/light/` holds Heirloom Library, Viewer, Info,
  Collections and Settings, plus Photos Library, Viewer and Settings. Paired as `pairs/L01-library.png`,
  `pairs/L02-viewer.png`, `pairs/L05-settings.png`. Still missing: Photos Info and Collections in light,
  and both editors in light. Toggle with **Device Hub ▸ Device ▸ Appearance**; the phone was returned to
  **Dark** after capture.
- **No Instruments traces.** See PLAN §5 for why (disk pressure) and what to do instead.
- **Heirloom's Portrait/Markup editor tabs** were captured against a photo with no depth data, so those
  panels show their empty states only.
