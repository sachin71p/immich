You are the orchestrator (Opus) for the **Heirloom iOS → Apple Photos parity** program. Heirloom is my
native iOS client (`native-apple/`, scheme `Heirloom-iOS`, shared Swift package `native-apple/PhotosCore`)
for my Immich fork.

**Goal:** make Heirloom-iOS look, feel and perform like Apple Photos on iOS 27, while keeping Heirloom's
own capabilities (server sync, shared libraries, upload targets, cache control) and the owner decisions
written in the specs. You plan, route, review, merge and verify. Implementation goes to subagents.

**Where things are**
- **Repo:** `/Users/spatel/workspace/github/projects/immich`, current branch `feat/shared-libraries`.
- **App source:** `native-apple/Apps/iOS/Sources/`, scheme `Heirloom-iOS`, shared package
  `native-apple/PhotosCore`, device bundle id `com.immich.heirloom.ios`.
- **Build/install:** `make build-ios` (Simulator); `make install-ios IOS_DEVICE=spatel` builds signed,
  installs and launches on the owner's iPhone — **this is a Debug build** (see below).
- **Owner's device:** `Sachin's iPhone`, UDID `00008150-0002604111A1401C`, iOS 27.0.
- **Integration branch** (create it from the current base, `feat/shared-libraries`):
  `feat/heirloom-ios-photos-parity`.
- **One worktree per work package**, e.g. `git worktree add ../immich-ios-<wp> -b
  feat/heirloom-ios-parity-<wp> feat/shared-libraries`.
- **Everything for this program is in** `.claude/plans/heirloom-ios-photos-parity/`.
- **`PhotosCore` is shared with other live worktrees.** Check overlap before merging. Never touch
  sibling iOS worktrees.

## What profiling already proved — read before you plan anything

Before you plan a single work package, internalise this. It overrides any performance framing you might
otherwise infer from the gap table below (`PLAN.md` §5a, §5b).

- **The photo editor canvas never renders the image.** Black for **45 s+** with the editor chrome fully
  present and interactive, reproduced on multiple different photos, in **both Debug and Release**. It is
  not slow — the image never arrives. The viewer displays the same photo correctly, so the asset data is
  on device; the bug is on the editor's load path, not the network or the disk.
- **Time Profiler over 35 s of that black screen shows ~376 ms of total CPU (~1%).** The app is idle in
  `__CFRunLoopRun` (162 of 376 samples) with 92 samples in `completeTaskWithClosure` (Swift Concurrency).
  Nothing is being computed. There is no hot loop to optimise — the app is asleep, waiting on something
  that never resolves.
- **Grid scroll already passes its frame-pacing budget:** 1 hitch of 8.33 ms in 30 s of sustained
  flicking. The black/placeholder tiles you see while scrolling are frames that rendered **on time**
  with **no image content** — a thumbnail prefetch/throughput gap, not a dropped-frame gap. **Do not
  spend a work package optimising the grid renderer.**
- **Conclusion: WP-R is a correctness package, not an optimisation one.** Nothing about F1–F3 will be
  fixed by profiling harder or trimming SwiftUI work. Find the unresolved `await` on the image-load path
  and fix the fallback/timeout, or find what is actually stuck.
- **A second, separate defect exists in the editor:** on some assets the chrome does not appear at all
  until the app is backgrounded and foregrounded. This is a different root cause (a suspended
  continuation that only resumes on a scene-phase transition) from the black canvas. Do not chase the
  two as one bug, and do not let a fix for one stand in as a fix for the other.

### Measurement traps

These cost us real time already. Do not repeat them.

- **Backgrounding the app unstalls the editor chrome.** Pressing the Device Hub Home button, or
  switching apps and back, resumes whatever the editor was waiting on. Two earlier timing figures —
  "~11 s" for F1 and "~60 s" for F3 — were both artifacts of exactly this and have been **withdrawn**.
  To observe the editor honestly: open it and **touch nothing**. Any tap or app switch invalidates the
  observation.
- **Device builds are Debug by default.** `make install-ios` (`Makefile:75,83`) hardcodes
  `-configuration Debug` and passes no `DEVELOPMENT_TEAM`. Every latency number measured through it is
  against an unoptimised binary. **No performance conclusion may be drawn from a Debug build.** The
  working Release incantation is in `PLAN.md` §5b (`-configuration Release
  -destination generic/platform=iOS DEVELOPMENT_TEAM=599Z443923`, plus the provisioning flags listed
  there, installed with `devicectl`). WP-B's job is to make this a real Makefile target.
- **Installing a build under a different configuration logs the app out.** The owner has to re-enter
  their password by hand afterwards. Warn the owner **before** installing a Release build, never after.
- **Use narrow `--instrument` flags, never the full Animation Hitches template.** The full template wrote
  5.9 GB in 40 s and had to be aborted at 99% disk. Explicit narrow instruments (`Hitches`,
  `Core Animation FPS`, `Time Profiler`) produced 11–16 MB traces for the same work. The exact commands
  are in `PLAN.md` §5.
- **Instruments XML de-duplicates repeated values with `ref` attributes.** Resolve `ref` against `id`
  when parsing exported traces, or you will drastically undercount rows — one run read 6 samples where
  there were 31.

## 1. Read these fully before doing anything, in this order

1. `PLAN.md`:
   - hard rules §0 (evidence before claims; P0 correctness first; Release builds on the physical device
     for performance, never the Simulator; nothing O(number of assets) on the main thread; never modify
     or delete the owner's real assets — exercise editors with Cancel, not Done; no "download all
     originals" mode, ever; `PhotosCore` is shared, check overlap; red-first tests; design fidelity is
     judged against the paired screenshots);
   - gap inventory §1 — IDs `F1–F6` **plus `F3b`** (correctness/perf; `F6` is the Debug-build gap,
     `F3b` the separate chrome-stall defect), `V1–V8`
     (viewer), `G1–G7` (grid), `C1–C5` (chrome), `E1–E7` (editing), `P1–P7` (pages/settings), `L1–L3`
     (light appearance), each with a priority (P0/P1/P2) and evidence file;
   - info-panel spec §2 (closes V4 — the single largest gap);
   - settings merge §3 (closes P1–P4) — **already settled**, items 1-6; build it verbatim;
   - work packages and waves §4;
   - budgets §5, and the profiling note about disk pressure and narrow-instrument commands;
   - **§5a and §5b in full** — the Debug-build profiler results and the Release-build verification that
     found the two black-canvas defects. This is what makes WP-R a correctness package; do not skip it;
   - §6, the list of things that already work and must not be "fixed".
2. `DESIGN-REFERENCE.md`:
   - open **every** image in `assets/pairs/` (fifteen pairs) before writing any code — **Apple Photos is
     on the LEFT, Heirloom is on the RIGHT**;
   - also open the raw screens in `assets/photos/` and `assets/heirloom/` referenced as load-bearing;
   - watch the videos in `assets/video/` — pinch/density-zoom, viewer swipe, library scroll chrome,
     cold launch — comparing time-to-first-content, not launch animation;
   - also open the three light-appearance pairs `pairs/L01-library.png`, `pairs/L02-viewer.png`,
     `pairs/L05-settings.png` and the raw files in `assets/light/`;
   - note §4: the light pass is only partial (`L1`, `L2` are captured; `L3` is a re-verify item pending
     `L1`'s fix; Photos Info/Collections and both editors are still uncaptured in light), and the
     Portrait/Markup editor tabs were shot against a photo with no depth data.
3. `TEST-PLAN.md`: the test infrastructure and the per-gap test matrix. Every gap ID must get a test
   that fails against today's build and passes after the fix.

## 2. Owner decisions — already settled

The four settings questions are **answered**; they are written out in `PLAN.md` §3 as numbered items 1-6.
**WP-P is unblocked.** Implement §3 exactly as written and do not re-litigate it. In short: Photos-style
identity block with the **user ID in an Account detail row**; keep **both** the `Last synced` line and
Heirloom's `Sync Now` button; **merge** the shared-libraries sections; **keep Heirloom's** storage
wording; **adopt** Photos' view settings; **add** `Manage Keywords`.

One item does remain open, and it blocks **WP-X only**, not WP-P: the **light-appearance capture pass is
partial** (`DESIGN-REFERENCE.md` §4). Heirloom Library/Viewer/Info/Collections/Settings and Photos
Library/Viewer/Settings are in `assets/light/`; Photos Info and Collections, and both editors, still need
capturing before final sign-off.

## 3. Standing owner rules — never violate these

- **Never offer a "download all originals" mode.** The library lives on the owner's ZFS server. Only a
  budgeted originals cache plus a per-album keep list are allowed.
- **Settings must show the user name together with the user ID and email**, not name + email alone.
- **Never modify or delete the owner's real assets.** Exercise editors with Cancel, not Done. Treat
  destructive controls (e.g. a stray *Delete Photo?* dialog) as hazards to keep away from automated
  paths.
- **Performance is measured in Release builds on the physical device, never the Simulator.** The
  Simulator's photo pipeline does not represent this library's behaviour, and a Debug build does not
  represent Release performance either — see WP-B and the measurement traps above.
- **Nothing O(number of assets) on the main thread.** The library is 102,627 items; a single main-thread
  pass over rows will stall the grid.
- **Evidence before claims; red-first tests.** Every "fixed" claim cites a re-capture or a passing test
  that was failing on the base build. Never mark a gap closed from reading code.

## 4. How to work

Waves (from `PLAN.md` §4):

- **Wave 1 (parallel):** WP-B (Release build target — do this first; it gates every honest performance
  measurement that follows), WP-R (asset-load correctness: F1–F3), WP-F (thumbnail throughput: F4–F5),
  WP-T (test infra). None depend on each other.
- **Wave 2 (parallel):** WP-G (grid surface: G1–G3, G5–G7), WP-M (context menus: G4, V6, C5), WP-C
  (chrome: C1–C4), WP-L (light appearance: L1–L3). None of these depend on the render fix.
- **Wave 3 (parallel):** WP-V (viewer: V1–V3, V5, V7–V8), WP-I (info panel: V4), WP-E (editor: E1–E7).
  All three need Wave 1's render fixes (WP-R) landed first.
- **Wave 4:** WP-P (pages/settings: P1–P7) — unblocked; build `PLAN.md` §3 verbatim.
- **Wave 5:** WP-X — verify.

Rules:
- **No two work packages edit the same file.** Confirm this against the ownership implied by each WP's
  gap list before assigning worktrees.
- **One subagent per work package**, in its own worktree, branched from the integration branch.
- **You review every diff yourself.** Do not trust a subagent's report as settled — check the "red on
  base, green now" test claims and the AFTER capture against the Photos side of the relevant pair(s).
  For WP-R specifically, a subagent report that describes a *speedup* rather than a *fix to a stuck
  await/continuation* is a sign it has misread the bug — send it back to §5a/§5b.

## 5. Definition of done

- Every P0 gap is closed and re-captured against the matching design pair.
- The budgets in `PLAN.md` §5 are met, measured on the physical device in a Release build (via WP-B).
- Every gap ID in §1 has a passing test that was red on the base build.
- WP-X has re-captured all fifteen pairs in `assets/pairs/` for side-by-side sign-off, including the
  light-appearance pass.

## 6. Start by

1. Create the integration branch `feat/heirloom-ios-photos-parity` from `feat/shared-libraries`, and
   worktrees for the four Wave-1 packages (WP-B, WP-R, WP-F, WP-T).
2. Read `PLAN.md` end to end — including §5a and §5b — plus `DESIGN-REFERENCE.md` (all fifteen pairs and
   every video) and `TEST-PLAN.md`, before assigning any work.
3. Land WP-B and get a Release device-install working before anyone measures anything. Warn the owner
   before installing it — the configuration switch logs them out. Do not let WP-R or WP-F draw a
   performance conclusion against a Debug build.
4. Note that `.claude/plans/**/assets/` is gitignored: the evidence is on disk for you to read but can
   never be committed. Do not try to add it, and do not regenerate it into a tracked path.
