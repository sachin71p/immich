# Heirloom iOS → Apple Photos parity

Target: make **Heirloom-iOS** look, feel and perform like **Apple Photos on iOS 27**, while keeping
Heirloom's own capabilities (server sync, shared libraries, upload targets, cache control).

- **Repo:** `/Users/spatel/workspace/github/projects/immich`
- **App source:** `native-apple/Apps/iOS/Sources/`, scheme `Heirloom-iOS`, shared package `native-apple/PhotosCore`
- **Bundle id (device):** `com.immich.heirloom.ios`
- **Evidence captured:** 2026-09-17 against **Sachin's iPhone 17 Pro Max, iOS 27.0**, Heirloom library
  **102,627 items**, Apple Photos library **12,169 items**, both in **dark appearance**.
- **All assets:** `.claude/plans/heirloom-ios-photos-parity/assets/` — see `DESIGN-REFERENCE.md`.

---

## §0 Hard rules

1. **Evidence before claims.** Every "fixed" claim cites a re-capture or a test. Do not mark a gap closed
   from reading code.
2. **P0 correctness first.** F1–F3 make editing and video effectively unusable today. Nothing cosmetic
   ships before those.
3. **Performance work is measured in Release builds on the physical device**, never the Simulator.
   The Simulator's photo pipeline does not represent this library's behaviour.
4. **Nothing O(number of assets) on the main thread.** The library is 102k items; a single main-thread
   pass over rows will stall the grid.
5. **Never modify or delete the owner's real assets.** Editors must be exercised with Cancel, not Done,
   unless a test fixture asset is used. During capture a stray tap opened a *Delete Photo?* dialog —
   treat destructive controls as hazards and keep them away from automated paths.
6. **No "download all originals" mode, ever.** The library lives on the owner's ZFS server. Only a
   budgeted originals cache plus a per-album keep list are permitted. This is a standing owner decision.
7. **PhotosCore is shared with other live worktrees.** Check overlap before merging; do not touch
   sibling iOS worktrees.
8. **Red-first tests.** Every gap with an ID below gets a test that fails against today's build.
9. **Design fidelity is judged against the paired screenshots**, not from memory of iOS.

---

## §1 Gap inventory

Priority: **P0** blocks use · **P1** visible parity break · **P2** polish.

### F — Correctness & performance (measured on device)

| ID | Pri | Gap | Evidence |
|----|-----|-----|----------|
| F1 | **P0** | **The photo editor canvas NEVER renders the image** — black for 45 s+ with chrome fully interactive, on multiple photos, in **both Debug and Release** (§5b). It is not slow; the image never arrives. The viewer displays the same photo correctly, so the data is on device. | `heirloom/14`, `heirloom/30-RELEASE-editor-chrome-fast-canvas-black.png`, pair `06` |
| F2 | **P0** | **Video playback renders black.** Play toggles to pause, but no frames draw and the scrubber thumb never advances. | `heirloom/21`, `heirloom/22-video-playback-black.png`, pair `09` |
| F3 | **P0** | **Video editor: same black canvas as F1**, plus a *separate, intermittent* chrome stall — on some assets the editor chrome does not appear at all until the app is backgrounded and foregrounded (§5b Defect 2). Earlier "~60 s" was a measurement error and is withdrawn. | `heirloom/23-video-editor-hung-black.png`, `heirloom/24` |
| F3b | **P0** | **Editor chrome intermittently never appears until the app is backgrounded and foregrounded.** A *separate root cause* from the black canvas (F1/F3) — one asset showed chrome in <5 s untouched, another showed none until an app switch. Track and fix it as its own defect. | §5b Defect 2 |
| F4 | P1 | Library grid renders **blank for ~4 s** after switching tabs back to Library. | observed; reproduce per `TEST-PLAN.md` |
| F5 | P1 | Thumbnail pipeline **lags fast scroll** — black/placeholder tiles persist behind the scroll position. **Profiled: frames are NOT being dropped** (1 hitch of 8.33 ms in 30 s). The frames render on time with no image content, so this is a thumbnail *throughput/prefetch* problem, not a rendering one. | §5a |

| F6 | **P0** | **The build installed on the device is a Debug build.** `Makefile:83` installs from `Debug-iphoneos`, and profiler stacks name `Heirloom-iOS.debug.dylib`. Unoptimised SwiftUI/AttributeGraph is routinely several times slower than Release, so **every latency number below was measured against an unfair baseline**. Re-measure on Release before optimising anything. | `Makefile:83`, §5a |

> Apple Photos for comparison: editor opens with the photo visible effectively instantly; video plays
> immediately; video editor was usable in ~8 s **including an iCloud download**.

### V — Viewer

| ID | Pri | Gap | Evidence |
|----|-----|-----|----------|
| V1 | P1 | Title shows **date + time only**. Photos shows **place name** (e.g. "Richmond · Windstone"), weekday + time, and a **people badge**. | pair `04` |
| V2 | P1 | No **LIVE badge / Live Photo control** pill under the top bar, and no auto-enhance affordance on the right. | `photos/12` |
| V3 | P1 | Bottom toolbar is **one 5-icon pill**. Photos uses **three groups**: `[share]` · `[♡ ⓘ ⚙]` · `[🗑]`. | pair `04` |
| V4 | **P0** | **Info sheet contains only date + raw filename.** Missing everything else — see §2. | pair `05` |
| V5 | P1 | Info sheet **cannot be dismissed by swipe**; only the toolbar button closes it. Photos dismisses on a downward drag from the sheet's top edge. | verified both apps |
| V6 | P2 | **Long-press in the viewer is a no-op.** | verified |
| V7 | P1 | Video scrubber is a **plain bar**. Photos uses a **frame-thumbnail filmstrip** plus CC and mute controls. | pair `09` |
| V8 | P2 | **Pinch-in on an open photo shrinks it to a small floating rect** instead of completing a zoom-out dismiss back to the grid. | `heirloom/28-photo-pinch-shrink.png` |

**Working already — do not regress:** swipe left/right → next/previous photo; swipe up → info;
swipe down on the photo → exit viewer. Videos `heirloom-viewer-swipe.mp4`, `photos-viewer-swipe.mp4`.

### G — Grid

| ID | Pri | Gap | Evidence |
|----|-----|-----|----------|
| G1 | P1 | **No video duration badges** on thumbnails. Photos shows `0:15`, `0:07` bottom-right on every video. | pair `01` |
| G2 | P1 | **No favourite heart overlay** on favourited items. | pair `01` |
| G3 | P2 | Heirloom paints a **people badge on nearly every cell**; Photos shows it selectively. Reads as visual noise. | pair `01` |
| G4 | **P0** | **Long-press on a grid cell opens the photo** instead of presenting the context menu. Photos shows preview + Copy/Duplicate/Hide, Share, Favorite, Add To, Adjust Info, Delete, Ask Siri. | pair `15`, `photos/05` |
| G5 | P1 | **No floating date badge** while scrolling a zoomed-out grid. Photos overlays e.g. "Aug 2026". | pair `03`, `photos/22` |
| G6 | P2 | Header subtitle is **always a date range**. Photos shows **item count** at rest and swaps to the date range while scrolling. | pair `01`, `photos/02` |
| G7 | P1 | Pinch changes **column density only**; the Years/Months/All selection stays pinned. In Photos the zoom level and the time level are one continuum. | `heirloom-pinch.mp4` vs `photos-pinch.mp4` |

**Working already:** pinch-to-zoom the grid **does** change column density in Heirloom (≈5 ↔ ≈10 columns).
This was better than expected — do not rewrite it, extend it.

### C — Chrome & navigation

| ID | Pri | Gap | Evidence |
|----|-----|-----|----------|
| C1 | P1 | Bottom chrome is **two stacked rows** (pills row above a tab bar). Photos merges into **one floating bar**: `[library] [Years │ Months │ All] [search]`. | pair `02` |
| C2 | P2 | Label reads **"All Photos"**; Photos uses **"All"**. | pair `02` |
| C3 | P1 | Tab bar is **collapsed by default and expands on tap**. Photos keeps Library/Collections visible with a **separate search circle**. | `heirloom/04-tabbar-expanded.png` |
| C4 | P2 | **"102,627 Items"** sits as a persistent line under the pills; Photos puts the count in the header. | pair `01` |
| C5 | P1 | Select-mode toolbar offers **Share + Delete only**. Photos offers Add To, Favorite and more. | `heirloom/19` |

### E — Editing

| ID | Pri | Gap | Evidence |
|----|-----|-----|----------|
| E1 | P1 | Tab taxonomy differs. Heirloom: **Adjust / Filters / Crop / Portrait / Markup**. Photos: **Styles / Live / Adjust / Crop / Tools**. | pair `06` |
| E2 | P1 | Filters are **text labels only**. Photos' Styles shows **live thumbnail previews** of the photo plus a CUSTOMIZE button. | pair `07` |
| E3 | P2 | Value control is a **plain horizontal slider**. Photos uses a **tick-ruler dial** with a centre marker. | pair `06` |
| E4 | P2 | No **Clean Up / Extend / Reframe**. | `photos/18` |
| E5 | P1 | Video editor has **no trim filmstrip** — the signature Photos control (frame thumbnails, yellow handles, play button). Heirloom offers only Mute + speed. | pair `10` |
| E6 | P2 | No **Audio Mix** tab for video. | `photos/21` |
| E7 | P2 | **Portrait tab is a dead stub** ("No depth data in this photo"). Photos surfaces portrait controls only when applicable rather than as a permanent empty tab. | `heirloom/17` region |

### L — Light appearance

Captured after the main sweep by toggling **Device Hub ▸ Device ▸ Appearance ▸ Light**. The phone was
returned to Dark afterwards.

| ID | Pri | Gap | Evidence |
|----|-----|-----|----------|
| L1 | P1 | **Heirloom's viewer stays hard-coded dark in light appearance.** Photos' viewer follows the system appearance and renders white chrome around the photo. | pair `L02-viewer` |
| L2 | P1 | In light appearance Heirloom draws the **"Library" title as dark text directly over the grid**, so it collides with light photos. Photos keeps **white title text over a blur scrim** in both appearances. | pair `L01-library` |
| L3 | P2 | Re-verify the info sheet, editor and Collections in light appearance once L1 is fixed — Heirloom's info sheet and editor are also dark-only today, which may be correct (Photos' editor is dark in both) but was not confirmed. | `light/heirloom-03-info.png` |

**Confirmed correct in light appearance:** Heirloom's Collections and Settings both render proper light
surfaces (white background, dark text) — `light/heirloom-04-collections.png`, `light/heirloom-05-settings.png`.

### P — Pages & settings

| ID | Pri | Gap | Evidence |
|----|-----|-----|----------|
| P1 | P1 | Account header is a **left-aligned card** (small avatar, name, email, server host). Photos **centres** a large avatar, the name, `N Photos, M Videos`, and `Last Synced …`. | pair `11` |
| P2 | **P0** | **Settings must show the user name together with the user ID and email.** Today only name + email + server host are shown; there is no user ID. Standing owner requirement, same as the macOS program. | `heirloom/09` |
| P3 | P1 | Heirloom lacks Photos' in-app settings items — see §3. | pair `12` |
| P4 | — | Heirloom-only settings that **must be preserved** — see §3. | `heirloom/09`,`10` |
| P5 | P1 | **Memories renders empty** ("No saved memories yet"). Photos shows generated memory cards and a "Type to Create" affordance. | pair `14` |
| P6 | P1 | Search is **metadata chips** (Places/Camera/Lens/File type). Photos has **natural-language suggestions** ("Swimming last month"), thumbnail Recents, and a **persistent bottom search field**. | pair `13` |
| P7 | P2 | Collections lacks **Trips** and **Wallpaper Suggestions**. | `photos/07` |

**Collections is already close.** Both apps use the same two-column chip layout for Media Types and
Utilities. Heirloom additionally has Places, People, Shared Albums, Shared Libraries and Recent Days —
**keep all of them**.

---

## §2 Info panel specification (closes V4)

Photos' panel, top to bottom — reproduce this order and grouping. Reference: `photos/13`, `photos/14`,
pair `05`.

1. Photo shrinks upward; sheet slides over it with a grabber.
2. Two side-by-side pill buttons: **Ask Siri** · **Image Search**.
   *Heirloom substitution:* server-side semantic search if available, otherwise omit the row entirely —
   do not ship dead buttons.
3. **Add a Caption** field (rounded, placeholder grey). Must write back to the Immich asset description.
4. Card: `Friday · Aug 21, 2026 · 7:13 PM` with a blue **Adjust** link on the right; second row is a
   cloud/status glyph plus the filename.
5. Card: device — `Apple iPhone 17 Pro Max`, right-aligned badges `HEIF`, HDR, lens glyphs.
6. Card: capture — `Main Camera — 24 mm ƒ/1.78` with a right-aligned quality badge;
   `12 MP · 3024 × 4032 · 1.8 MB`; then a divided EXIF strip: `ISO 80 │ 24 mm │ 0 ev │ ƒ/1.78 │ 1/95 s`.
7. **Map card** with the location pin, then place name (`Richmond · Harvest Green`) and an **Adjust** link.
8. **Add Keywords** field.
9. Provenance row: `Added by <name> to the Shared Library` with avatar.
10. The viewer's bottom toolbar stays visible over the sheet throughout.

Heirloom today renders **only item 4's first row plus a filename**. Everything else is missing.

---

## §3 Settings merge (closes P1–P4)

**Adopt from Photos** (target layout `photos/09`, `photos/10`):
centred avatar · name · `N Photos, M Videos` · `Last Synced …` · section `Shared Albums` →
`Invitations and Access Requests` (badge + chevron) · `Shared Library — Manage` · `Manage Keywords` ·
`Zoom to Fill Screen` (toggle + explanatory caption) · `Show Ratings Controls` · section `Featured` →
`Show Featured Content`, `Show Holiday Events` (each with caption) · `Reset Suggested Memories` ·
`Reset People & Pets Suggestions`.

**Preserve from Heirloom — these have no Photos equivalent and must not be dropped:**
`Sync Now` · `Last synced` · `Default Upload Target` · `Back Up Photos` · `Timeline Sources…` ·
`Free Up Space…` · `Optimize Storage` · `Cache Usage` (Thumbnail / Preview / Fullsize / Original) ·
`Shared Libraries → Manage…` · `Sign Out` · `About → Version`.

**Owner decisions — SETTLED 2026-09-17. Implement exactly this; do not re-open.**

1. **Identity block (closes P2).** Photos-style, centred under the avatar:
   line 1 display name, line 2 `N Photos, M Videos`, line 3 `Last synced <relative>`.
   The **user ID and email move into a tappable "Account" detail row** beneath that block — the user ID
   must be shown, not just the email. Server host stays in its own row.
2. **Sync — keep both.** Show the Photos-style `Last synced …` line under the name *and* keep Heirloom's
   explicit **`Sync Now`** button in a Sync section. Nothing is dropped.
3. **Shared libraries — merge into one section.** Combine Heirloom's `Shared Libraries → Manage…` with
   Photos' `Shared Library → Manage` and `Invitations and Access Requests` under a single
   **Shared Libraries** heading.
4. **Storage — keep Heirloom's wording.** `Optimize Storage`, `Free Up Space…` and the `Cache Usage`
   breakdown stay as they are. Photos' iCloud-storage phrasing would misdescribe a server-backed cache,
   so it is **not** adopted.
5. **Adopt Photos' view settings:** `Zoom to Fill Screen`, `Show Ratings Controls`,
   `Show Featured Content`, `Show Holiday Events`, `Reset Suggested Memories`,
   `Reset People & Pets Suggestions`.
6. **Add `Manage Keywords`**, pairing with the Add Keywords field in the §2 info panel.

---

## §4 Work packages

One owner per package; no two packages edit the same file.

| WP | Scope | Gaps | Depends on |
|----|-------|------|-----------|
| **WP-R** Asset-load **correctness** | The editor/video canvas never receives an image, and a continuation stalls until scene-phase change. **Not an optimisation package** — see §5a/§5b. | F1, F2, F3 | — |
| **WP-F** Thumbnail throughput | Blank-on-return, and tile *content* trailing fast scroll. Frame pacing already passes — do not touch the renderer. | F4, F5 | — |
| **WP-G** Grid surface | Duration badges, favourite hearts, badge density, floating date badge, header count/range, zoom↔time-level coupling | G1, G2, G3, G5, G6, G7 | — |
| **WP-M** Context menus | Grid long-press menu, viewer long-press, select-mode actions | G4, V6, C5 | — |
| **WP-C** Chrome | Single floating bar, labels, persistent tabs, count placement | C1, C2, C3, C4 | — |
| **WP-V** Viewer | Title/place/people, LIVE badge, three-group toolbar, swipe-dismiss, pinch-close, video scrubber | V1, V2, V3, V5, V7, V8 | WP-R (F2) |
| **WP-I** Info panel | Full §2 panel | V4 | WP-R |
| **WP-E** Editor | Tab taxonomy, style thumbnails, ruler dial, video trim filmstrip, Portrait handling | E1–E7 | WP-R (F1, F3) |
| **WP-L** Appearance | Light-appearance parity for viewer chrome and grid title | L1, L2, L3 | — |
| **WP-P** Pages | Account header, settings merge, identity line, Memories, Search, Collections additions | P1–P7 | §3 settled — unblocked |
| **WP-T** Test infra | Harness for the tests in `TEST-PLAN.md` | — | — |
| **WP-B** Build config | Add a Release device-install target; no perf work may be measured on Debug | F6 | — |
| **WP-X** Verify | Re-capture every pair, diff against baseline, sign off | all | all |

### Waves

- **Wave 1 (parallel):** WP-B (Release build target — do this first, it gates honest measurement),
  WP-R (asset-load correctness), WP-F (thumbnail throughput), WP-T (test harness).
- **Wave 2 (parallel):** WP-G, WP-M, WP-C, WP-L — surface work that does not depend on the render fix.
- **Wave 3 (parallel):** WP-V, WP-I, WP-E — need Wave 1's render fixes landed.
- **Wave 4:** WP-P — unblocked; build §3 verbatim.
- **Wave 5:** WP-X.

---

## §5 Budgets

Measured on the physical device, **Release** build, 102k-item library. "Today" reflects the verified
state after the Release-build check in §5b — the earlier "~11 s"/"~60 s" figures were measurement
artifacts and are **withdrawn**.

| Metric | Today (verified) | Budget |
|--------|------------------|--------|
| Photo editor → photo visible | **never** — black at 45 s+, Debug and Release | **< 400 ms** to first pixels |
| Video → first frame drawn | **never** | **< 500 ms** |
| Editor chrome → interactive | **< 5 s on some assets; never on others** until the app is backgrounded (§5b Defect 2) | **< 300 ms**, unconditional |
| Library grid after tab switch | blank ~4 s | **< 150 ms** to first tiles |
| Grid scroll — frame pacing | **already passing**: 1 hitch of 8.33 ms in 30 s | **no frame > 16.7 ms** during a 5 s flick |
| Grid scroll — content | black/placeholder tiles trail the scroll | **no empty tile on screen > 250 ms** after scroll settles |

Note the last two are deliberately separate. Frame pacing is **not** the problem and needs no work;
tile *content* is. Do not conflate them.

**Profiling method — use narrow instruments.** Instruments' *Animation Hitches* template wrote
**5.9 GB in 40 s** and had to be aborted with the disk at 99%. Recording with explicit narrow
instruments instead produced **11-16 MB** traces for the same work:

```
xcrun xctrace record --device <UDID> --instrument "Hitches" --instrument "Core Animation FPS" \
  --attach <pid> --time-limit 30s --no-prompt --output out.trace
xcrun xctrace record --device <UDID> --instrument "Time Profiler" \
  --attach <pid> --time-limit 35s --no-prompt --output out.trace
```

Get the pid with `xcrun devicectl device info processes --device <UDID> | grep -i heirloom`.
Export with `xctrace export --input out.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="hitches"]'`.
**Parsing caveat:** Instruments XML de-duplicates repeated values via `ref` attributes — a naive regex
undercounts rows badly. Resolve `ref` against `id` or you will read 6 samples where there are 31.

---

## §5a Profiler results (2026-09-17, device, **Debug build**)

Recorded with narrow instruments (`--instrument Hitches`, `Core Animation FPS`, `Time Profiler`) rather
than the full *Animation Hitches* template — 11-16 MB traces instead of 5.9 GB.

**Grid scroll, 30 s of sustained flicking**
- **Hitches: 1**, duration **8.33 ms**, labelled "Potentially expensive app update(s)".
- Core Animation FPS, 1 s samples:
  `0,1,1,1,1,2,0,1,1,1,0,2,2,0,2,1,0,60,60,60,60,60,60,60,43,3,2,2,0,0,0`
  Strongly bimodal — a sustained 60 FPS window and long 0-2 FPS stretches. Part of the low period is
  genuine idle between synthetic drags, so **do not treat the low numbers as proven frame loss**;
  re-measure with continuous scrolling on a Release build.
- **Conclusion:** the grid is not dropping frames. The visible black tiles are frames that rendered on
  time with no image content. Target the thumbnail prefetch/decode pipeline (F5), not the renderer.

**Video editor open (F3), 35 s Time Profiler covering 18+ s of black screen**
- **Total CPU consumed: ~376 ms across 35 s (~1%).** Main thread: **161 ms**.
- Hottest main-thread leaves are trivial SwiftUI housekeeping: `objc_msgSend` (6 samples),
  `AG::Graph::UpdateStack::update()` (4), `CA::Layer::commit_if_needed` (3).
- `__CFRunLoopRun` present in **162 of 376** samples; `completeTaskWithClosure`
  (Swift Concurrency) in 92.
- **Conclusion: F1/F3 are not performance bugs.** The app is idle in its run loop, waiting on an
  unresolved continuation or a server fetch with no timeout and no fallback to the already-decoded
  preview. Optimisation will not fix them; the asset-load path must be fixed. **WP-R is a correctness
  work package, not an optimisation one.**

**Build-configuration caveat (F6).** The scroll and Time Profiler numbers above are from a **Debug**
build. A Release build was subsequently produced and tested — see §5b.

---

## §5b Release-build verification (2026-09-17)

Built with `-configuration Release -destination generic/platform=iOS DEVELOPMENT_TEAM=599Z443923`
(plus `-allowProvisioningUpdates -allowProvisioningDeviceRegistration -skipPackagePluginValidation`),
installed with `devicectl`. **Release did not fix F1.**

**The decisive finding — two separate defects, not one slow screen.**

Tested on Release across multiple photos, with the app left untouched:

1. **The editor canvas NEVER renders the image. Unconditional and fully reproducible.** Observed black
   for **45 s+** with the editor chrome fully present and interactive, on multiple different photos, in
   both Debug and Release. It does not eventually appear. This is the core bug.
2. **Chrome load time is variable and separate.** On one photo the chrome appeared in **under 5 s**
   untouched. On another it did not appear at all until the app was **backgrounded and foregrounded**
   (confirmed by the owner performing the app switch).

The earlier "~11 s" (F1) and "~60 s" (F3) figures were **measurement errors** and are withdrawn: in
both cases the chrome appeared because the app had been backgrounded — the Device Hub Home button was
pressed — not because work completed. Treat those numbers as void.

Combined with §5a (~1% CPU, idle in `__CFRunLoopRun`, 92 samples in `completeTaskWithClosure`):

- **Defect 1 (canvas):** the image never reaches the canvas. Since the app burns no CPU, nothing is
  being decoded or drawn — the editor is most likely awaiting a full-resolution original that never
  arrives, with no timeout and no fallback to the preview that the *viewer* already displays correctly.
  That the viewer shows the same photo fine is the key contrast: the data exists on device.
- **Defect 2 (chrome stall):** a suspended continuation that only resumes on a scene-phase transition.

**Where WP-R should look first:**
- Every `await` on the path from "Edit tapped" → "canvas has an image", and what supplies that image.
  Compare it against the viewer's loader, which works.
- Why the editor does not fall back to the already-decoded preview image.
- Any `scenePhase` / `willEnterForeground` observer touching editor state (Defect 2).
- Reproduce by opening the editor and **not touching the device** — any tap or app switch invalidates
  the observation.

**Build-config note:** `make install-ios` (`Makefile:75,83`) hardcodes `-configuration Debug` and passes
no `DEVELOPMENT_TEAM`, so a Release device build is not possible through the Makefile as written.
Add a `install-ios-release` target before any performance work (F6).

---

## §6 Not gaps — do not "fix" these

- Grid pinch-to-zoom **works** in Heirloom (density zoom).
- Swipe left/right, swipe up → info, swipe down → exit viewer all **work**.
- Collections' Media Types / Utilities chip layout is already close to Photos.
- Heirloom's extra Collections sections (Places, People, Shared Albums, Shared Libraries, Recent Days)
  are **deliberate extras**, not deviations.
- Heirloom's library count (102,627) vastly exceeds Photos' (12,169) because Heirloom shows the whole
  server library. Never compare the two counts as if they were the same set.
