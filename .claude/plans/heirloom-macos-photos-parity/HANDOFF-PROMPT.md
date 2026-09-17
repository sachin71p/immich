> Shortest path: paste `START-PROMPT.md` instead; it supersedes the summary below, and this file remains the source of the implementer template.

# Handoff prompt — paste into a new Claude Code session (Opus) opened at the repo root

---

You are the **orchestrator** for the Heirloom macOS **Apple Photos parity** program.

Heirloom is the owner's native macOS client for their Immich fork. The goal is for it to look, feel and
perform like Apple Photos on macOS 27: same chrome, same interactive trackpad swipe and pinch in the
viewer, same edit mode, and Photos-level launch and scroll performance.

- A hands-on audit (2026-09-17) with screenshots, screen recordings and measurements is done, and a plan
  exists.
- **You don't write feature code.** You route work to subagents, review their diffs, merge, and run the
  gates, including hands-on verification with computer-use.

- **Repo:** `/Users/spatel/workspace/github/projects/immich`.
- **Base:** `feat/shared-libraries` @ `9b9bb7f2e`.
- **Integration branch:** create `feat/heirloom-macos-photos-parity` from the base.
- **Installed app:** `/Applications/Heirloom-macOS.app`. It is signed in to the owner's server
  (80,358 photos + 22,271 videos).
- **Other sessions are active** in worktrees `../immich-ios-wp2`…`wp5` (iOS work that touches PhotosCore).
  Don't touch those worktrees. Check PhotosCore overlap before every merge (PLAN §0.5).

## Read first, in order
1. `.claude/plans/heirloom-macos-photos-parity/PLAN.md`: rules, gap inventory (V/G/C/E/P/F IDs),
   architecture decisions, budgets, WP ownership, waves.
2. `DESIGN-REFERENCE.md`: open the side-by-side images in `evidence/design/pairs/` (Photos target on the
   left, Heirloom current on the right). You'll judge the AFTER captures against these at every gate.
3. `TEST-PLAN.md`: required regression tests per gap ID, and the red-first rule. You enforce it.
   - Also read `SPEC-TOOLBAR-SETTINGS.md`: the owner-reviewed toolbar spec and Settings decisions. These
     are binding, and not yours to renegotiate.
   - Owner exception: the scope capsule shows the icon plus the full library name.
   - Owner decision: **never** offer "Download Originals"; the library lives on the owner's ZFS server.
   - Also read `SPEC-INFO-PANEL.md` (binding Info spec: Photos content and styling, but an **in-window sidebar**, and keep all Heirloom fields).
   - Settings must show the user **name together with** the user ID.
4. `EVIDENCE.md`: what Photos does, what Heirloom does, and the measurements. Look at
   `evidence/frames/*.png`; extract frames from `evidence/video/REF-*.mp4` and `CUR-*.mp4` with ffmpeg.
   The evidence folder contains the owner's personal photos and is git-ignored. Never commit it, upload it,
   or pass it to a remote/cloud agent.
5. Skim `WP-T-TESTINFRA.md`, `WP-F-PERF.md`, `WP-V-VIEWER.md`, `WP-E-EDIT.md`, `WP-G-GRID.md`, `WP-C-CHROME.md`,
   `WP-P-PAGES.md` and `WP-X-VERIFY.md`. Subagents read their own brief in full.
6. Background only: `.claude/plans/heirloom-macos-perf/PLAN.md` and `reports/FINAL.md` (the previous perf
   program). Its green gates missed today's P0s, so require hands-on proof.

## Routing
| Work | subagent_type | Model |
|---|---|---|
| Confirm owned paths exist and don't overlap across WPs; any "where is X" lookup | `scout` | Haiku |
| WP-T, WP-F, WP-V, WP-E, WP-G, WP-C, WP-P implementation | `implementer` | Sonnet |
| WP-X §1–2 builds, tests, traces | `verifier` | Sonnet |
| Report and changelog prose (only if asked) | `scribe` | Sonnet |
| Diff review (mandatory for WP-F, WP-V, WP-G), merges, the NSPageController go/no-go review, WP-X §3 hands-on side-by-side, diagnosing unexplained failures | you | Opus |

Announce every delegation on one line: `→ <agent> (<model>): <task>`. Run independent WPs in parallel in a
single message, at most 10 at a time. Chain agents through files, not pasted output.

## Sequence
0. `→ scout (haiku)`: verify every path in PLAN §4 exists (or is new), and find any file claimed by two WPs.
   Fix the PLAN table if needed. Create the integration branch and the worktrees:
   `git worktree add ../immich-mac-<wp> -b feat/heirloom-macos-parity-<wp> feat/heirloom-macos-photos-parity`.
1. **Wave 0:** WP-T (`WP-T-TESTINFRA.md`) alone: fixture, test targets, AX identifiers, synthetic
   gestures, perf scaffolding, parity scripts. Merge it, then run WP-X → **Gate 0**. Feature WPs branch
   from the Gate 0 merge.
2. **Wave 1:** WP-F ∥ WP-V ∥ WP-E.
   - When WP-V reports the `MacViewerTransition.swift` SHA, note it.
   - When WP-V finishes its step-2 spike, **review the side-by-side video yourself** before letting it
     continue: the NSPageController go/no-go is yours.
   - Merge each WP after reviewing its diff, then run WP-X → **Gate 1**.
3. **Wave 2:** WP-G ∥ WP-C ∥ WP-P, from the Gate 1 merge. Merge, then WP-X → **Gate 2**, including the full
   side-by-side walkthrough.
4. **Wave 3:** send rework back to the **same** agents (SendMessage to their ids), plus the P2 items.
   Then WP-X → **Gate 3**, run `make install-macos` (Release), and write `reports/FINAL.md` with the
   REF-vs-AFTER tables and clips.
5. Report to the owner:
   - what changed;
   - measured before/after;
   - open owner decisions (Tools tab scope, the Shared Library banner, Featured-photo heuristic, Trips).

   No push, no PR unless the owner asks.

## Implementer prompt template (fill in `<WP>`, `<brief>`, `<base>`, `<worktree>`)
> You are executing work package `<WP>` of the Heirloom macOS Apple-Photos-parity plan.
>
> - **Working copy:** `<worktree>` on branch `feat/heirloom-macos-parity-<wp>`, based on `<base>`.
>   Work only there.
> - **Read in full:**
>   - `/Users/spatel/workspace/github/projects/immich/.claude/plans/heirloom-macos-photos-parity/PLAN.md`
>     (§0 rules are mandatory);
>   - `EVIDENCE.md`;
>   - `DESIGN-REFERENCE.md`: open every `evidence/design/pairs/*.png` listed for your gap IDs and match
>     the left (Apple Photos) side;
>   - `SPEC-TOOLBAR-SETTINGS.md` if you are WP-C (binding) or WP-V (the viewer toolbar, §2);
>   - `SPEC-INFO-PANEL.md` if you are WP-V (binding);
>   - `TEST-PLAN.md`: implement every test listed for your gap IDs, red first on base `9b9bb7f2e`, then
>     green;
>   - your brief, `<brief>`.
>   - Evidence media is in the plan's `evidence/` folder (read-only; never copy it into the repo tree
>     that's committed).
> - **Scope:** you may edit only the files your WP owns (PLAN §4). If you need a change elsewhere, stop
>   and report exactly what and why.
> - **Commits:** one per brief step, message `type(macos): …`, ending with
>   `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. No push.
> - **Verify each step:**
>   - `xcodebuild -project native-apple/Heirloom.xcodeproj -scheme Heirloom-macOS -configuration Release
>     -destination 'platform=macOS' build` (zero new warnings);
>   - `swift test --package-path native-apple/PhotosCore` if you touched PhotosCore;
>   - your WP's UI tests.
>   - For performance claims, use Release plus signposts on the owner's library.
>   - For UI claims, screenshots or recordings of the running app. Unit tests alone don't count.
> - **Safety:** never trash, move or edit-save real assets. Use the fixture library (`FixtureSeed.swift`)
>   for destructive flows. Never write to `~/Library/Application Support/Heirloom/heirloom.sqlite`
>   outside the app; copy it for query experiments.
> - **Done means:** every step in your brief is complete, with its proof in
>   `.claude/plans/heirloom-macos-photos-parity/reports/<WP>-REPORT.md`.
>   - The report has a table: gap ID | status | evidence path | numbers.
>   - List anything you couldn't do and why.
>   - Return a ≤ 30-line summary: commits (SHA + subject), build/test results, budgets met or missed,
>     open questions. Don't return file dumps.

## Review checklist (you, per diff)
- **Ownership:** only owned files changed (`git diff --stat <base>..HEAD`).
- **Performance:** no O(rows) work on the main thread; no synchronous IO in view updates; nothing
  allocated per cell configure.
- **Gestures:** they honour "Swipe between pages", Reduce Motion and natural scrolling.
- **Viewer:** Live Text is an overlay, never a replacement view (V1). The pager doesn't instantiate a page
  per asset.
- **Data safety:** migrations are additive and idempotent; old edit recipes still decode.
- **PhotosCore:** API changes are source-compatible with iOS (the iOS build passes).
- **Tests:** every closed gap ID has its TEST-PLAN tests. The report's `ID | test | red on base | green`
  table is complete. Spot-check 3 red-on-base claims per WP. Snapshot baselines use synthetic fixture
  images only; reject any baseline containing real photos.
- **Design:** the AFTER captures match the Photos side of each touched pair in `evidence/design/pairs/`.
  List deviations for the owner.
- **Proof:** evidence exists and is believable. Re-run anything suspicious yourself before you accept it.

## Owner-hands steps
Synthetic trackpad gestures can't be generated from this shell, and Photos ignores wheel events for paging.
For every gesture check:
1. Start a 60 fps ffmpeg screen recording in the background:
   `ffmpeg -f avfoundation -framerate 60 -capture_cursor 1 -i "3:none" -vf scale=1728:-2 -c:v h264_videotoolbox -b:v 14M <out>.mp4`
   (stop it with `pkill -INT -f <out>`).
2. Put the target app in the right state.
3. Ask the owner (AskUserQuestion) for the exact gestures, **one app per question**. The owner prefers
   being prompted per app.
4. Analyse the clip with the PLAN §3 frame recipe.

The owner also asked, and these must be re-checked at each gate:
- right-click behaviour in both apps;
- trackpad pinch and two-finger double-tap in the viewer;
- cold-launch videos for both apps;
- the photo (not video) edit page with all its controls, allowing for the full-resolution download delay.
