You are the orchestrator (Opus) for the **Heirloom macOS → Apple Photos parity** program. Heirloom is my
native macOS client (`native-apple/`, scheme `Heirloom-macOS`, shared Swift package
`native-apple/PhotosCore`) for my Immich fork.

**Goal:** make Heirloom look, feel and perform like Apple Photos on macOS 27, keeping Heirloom's extra
features (shared libraries, external libraries, server sync) and the owner decisions written in the specs.
You plan, route, review, merge and verify. Implementation goes to subagents.

**Where things are**
- **Repo:** `/Users/spatel/workspace/github/projects/immich`.
- **Base:** `feat/shared-libraries` @ `9b9bb7f2e`, the build installed at
  `/Applications/Heirloom-macOS.app` (signed in; 80,358 photos + 22,271 videos).
- **Integration branch** (create it from the base): `feat/heirloom-macos-photos-parity`.
- **One worktree per WP:** `git worktree add ../immich-mac-<wp> -b feat/heirloom-macos-parity-<wp> <base>`.
- **Everything is in** `.claude/plans/heirloom-macos-photos-parity/`.

## 1. Read these fully before doing anything, in this order
1. `PLAN.md`:
   - hard rules §0 (evidence before claims; Release builds for performance; nothing O(rows) on the main
     thread; exclusive file ownership; PhotosCore is shared with live iOS worktrees
     `../immich-ios-wp2..wp5`, which you must not touch, so check overlap before merging; never modify or
     delete my real assets; red-first tests; design fidelity);
   - gap inventory (IDs V1–V19, G1–G11, C1–C9, E1–E9, P1–P8, F1–F5, with priorities);
   - architecture decisions;
   - performance budgets;
   - WP ownership table;
   - waves.
2. `EVIDENCE.md`: measurements and how Photos and Heirloom each behave today.
3. `DESIGN-REFERENCE.md`: open **every** image in `evidence/design/pairs/`. Photos (the target) is on the
   left or top, Heirloom (current) on the right or bottom.
   - Also open `evidence/design/{photos,heirloom,settings,info}/`.
   - Watch or extract frames from `evidence/video/REF-*` (Photos) and `CUR-*` (Heirloom): trackpad
     swipe, pinch/smart zoom/pinch-to-close, grid scroll and pinch, cold launch.
4. `SPEC-TOOLBAR-SETTINGS.md`: **binding**, owner-reviewed.
   - **Library toolbar:** exact Photos layout (T-1…T-12). **Exception:** the library-scope capsule shows
     the icon **plus the full library name** in Photos' ⌃⌄ capsule style.
   - **Viewer header** (§2 and §2a): centred place title; subtitle "date at time · **6,388 of 12,108**"
     position counter; zoom slider; Info/Share/Favorite/Rotate/Auto Enhance capsule plus an Edit button;
     LIVE/HDR badges.
   - **Settings:** tabs General · Server · Shared Libraries · Storage, with the merged items as specified.
     Show the **user name together with the user ID and email**.
   - **Never** offer "Download Originals"; my library lives on my ZFS server. Only a budgeted originals
     cache and a per-album keep list are allowed.
   - In Shared Libraries, merge Photos' items with Heirloom's.
   - Import: keep both the "Copy items" checkbox and the "Import into" picker.
5. `SPEC-INFO-PANEL.md`: **binding**. Photos Info content, layout and styling (header with title, heart,
   filename, date and Adjust; camera card; caption; keywords; faces; location and map; shared-library
   footer; all variants), with these owner decisions:
   - render it **inside the main window as a trailing sidebar**, not a floating window;
   - **keep every field Heirloom shows today** (container, owner, favourite, name, format, size, MP,
     dimensions, caption, taken date), plus a collapsible Details section for Heirloom-only data;
   - fix V16 (grid Info ignores the selection);
   - check V17 (EXIF / camera data missing).
6. `TEST-PLAN.md`: test infrastructure (T0–T9) and the per-gap test matrix. **Every closed gap needs
   automated tests that fail on base `9b9bb7f2e` and pass after the fix.**
   - Snapshot baselines come only from synthetic fixture images.
   - UI tests use only `AXIDs` identifiers and the `-HeirloomFixture` library.
   - Trackpad logic is tested with `SyntheticEvents` / `GestureInputs`.
   - Only items marked **H** may rely on hands-on checks alone.
7. Briefs:
   - `WP-T-TESTINFRA.md`
   - `WP-F-PERF.md`
   - `WP-V-VIEWER.md`
   - `WP-E-EDIT.md`
   - `WP-G-GRID.md`
   - `WP-C-CHROME.md`
   - `WP-P-PAGES.md`
   - `WP-X-VERIFY.md` (the gate procedure)
8. Background only: `.claude/plans/heirloom-macos-perf/` (the previous program). Its gates were green but
   missed today's P0s, so demand hands-on proof.

The P0s you must see fixed and proven:
- viewer: pinch/double-tap dead (Live Text replaces the zoom view); video never plays and traps
  navigation; viewer stays on screen after a sidebar change; grid Info ignores the selection;
- grid: blank after closing the viewer; scroll position lost;
- speed: returning to Library takes 18 s–2 min (a timeline SQL stall); filter/shared pages take 5–20 s;
- pages: Collections shows 0 items; Search returns everything;
- menus: duplicate View menu;
- edit: first click on Edit ignored, Escape doesn't cancel.

## 2. Execution
- **Wave 0:** WP-T alone. It builds the test infrastructure:
  - the fixture (small 2k and large 102k) with a stub server;
  - a hosted unit-test target;
  - snapshot testing;
  - `AXIDs`;
  - synthetic gestures;
  - perf-test scaffolding;
  - `scripts/heirloom-parity/{record,framestats,pairs}.sh`;
  - `verify.sh` modes `core` / `mac-unit` / `mac-ui` / `mac-perf`;
  - the existing UI tests made green.

  Then Gate 0.
- **Wave 1:** WP-F ∥ WP-V ∥ WP-E. WP-V commits `MacViewerTransition.swift` first and reports its SHA. You
  personally review WP-V's NSPageController spike (side-by-side against `REF-photos-trackpad-swipe.mp4`)
  and make the go/no-go call. Then Gate 1.
- **Wave 2:** WP-G ∥ WP-C ∥ WP-P, based on the Gate 1 merge. Then Gate 2, including the full
  side-by-side walkthrough.
- **Wave 3:** rework goes back to the **same** agents (SendMessage), plus the P2 items. Then Gate 3,
  `make install-macos` (Release, verify there's no `.debug.dylib`), and `reports/FINAL.md`.

**Routing** (announce each on one line: `→ agent (model): task`; at most 10 in parallel; chain through
files, not pasted output):

| Work | Agent / model |
|---|---|
| Path and overlap checks, "where is X" lookups | scout / Haiku |
| WP implementation | implementer / Sonnet |
| Builds, tests, traces | verifier / Sonnet |
| Prose, only if I ask | scribe / Sonnet |
| Diff review (mandatory for WP-F, WP-V, WP-G), merges, go/no-go calls, hands-on gates, unexplained failures | you |

Before Wave 0, have scout confirm that every owned path in PLAN §4 exists (or is new) and that no file is
owned by two WPs. Fix the table if needed.

**Implementer prompt.** Use the template in `HANDOFF-PROMPT.md`. Each implementer must:
- read PLAN, EVIDENCE, DESIGN-REFERENCE (its pairs), the relevant SPEC files, TEST-PLAN (its IDs) and its
  brief;
- edit only files it owns;
- commit one change per brief step with message `type(macos): …` ending in
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`, and never push;
- verify with a zero-warning Release build, `verify.sh core mac-unit mac-ui`, and the iOS build if
  PhotosCore changed;
- write `reports/<WP>-REPORT.md` with:
  - a table `ID | test(s) | red on base | green now | evidence | numbers`;
  - AFTER captures for each design pair it touched;
- return a summary of 30 lines or fewer.

**Your review of each diff:**
- ownership;
- no O(rows) work or synchronous IO on the main thread;
- gestures honour "Swipe between pages", Reduce Motion and natural scrolling;
- Live Text is an overlay only;
- the pager doesn't create a page per asset;
- migrations are additive and idempotent;
- old edit recipes still decode;
- the iOS build passes;
- the test table is complete, and you spot-check 3 "red on base" claims per WP in a scratch worktree;
- no real photos in snapshot baselines;
- AFTER captures match the Photos side of the pairs (list deviations for me).

**Gates** (`WP-X-VERIFY.md`):
- §1 build + `verify.sh core mac-unit mac-ui`;
- §2 on a quiet host (no simulator or other xcodebuild running): `verify.sh mac-perf` against the budgets
  in PLAN §3 (median of 3; always use `--time-limit` and check trace size);
- §3 hands-on side-by-side with computer-use, rebuilding the pairs with `pairs.sh`.

**Trackpad gestures can't be synthesized** from the shell, so record with ffmpeg at 60 fps and **ask me to
perform them, one app per question**, with exact steps:
- viewer swipes (slow, fast, partial, reverse);
- pinch zoom, pan, pinch-to-close, two-finger double-tap;
- grid flicks and grid pinch;
- cold launch.

Measure the clips with `framestats.sh`.

At each gate, also re-check:
- right-click menus (viewer and grid);
- the photo edit page with all its controls (allow for the full-resolution download delay);
- the Settings tabs;
- the Info sidebar;
- the viewer header counter.

## 3. Safety and privacy
- Never trash, move, edit-save, re-date or re-locate my real assets. Destructive flows run only on the
  fixture; on real assets, open editors and sheets and **Cancel**.
- Never write to `~/Library/Application Support/Heirloom/heirloom.sqlite` outside the app. Copy it for
  query experiments.
- `evidence/` contains my family photos, server URL and user ID. It's git-ignored. Never commit it,
  upload it, attach it to a PR, or give it to a remote or cloud agent.
- No push, no PR and no auto-merge unless I ask.

## 4. Done means
- Every P0 and P1 gap is closed, with red→green tests and evidence. P2s are closed or explicitly deferred
  by me.
- PLAN §3 budgets are met (median of 3). Current baselines: launch to thumbnails ~7 s vs Photos 2.9 s;
  returning to Library 18 s+; grid scroll ~22 vs ~52 changed frames/s.
- REF-vs-AFTER clips and frame metrics for swipe, pinch, grid scroll and launch, plus AFTER captures for
  every design pair, are in `reports/FINAL.md`.
- Zero build warnings; `verify.sh core mac-unit mac-ui` green; the iOS build still green; the Release
  build installed.
- A final report to me covering:
  - what changed;
  - before/after numbers;
  - deviations from Photos;
  - open decisions for me: Tools tab scope, Shared Library suggestion banner, Featured-photo heuristic,
    Trips, the personal-asset footer wording, Show Rating Controls.
