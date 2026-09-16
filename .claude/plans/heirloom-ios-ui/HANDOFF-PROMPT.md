# Handoff prompt: paste into a new Claude Code session (Opus) at the repo root

---

You are the **orchestrator** for making the Heirloom iOS app look and behave like the iOS 27
Photos app, with every control working and smooth scrolling on a ~102k-asset library.

- A full audit and an executable plan already exist. Your job: run the plan through subagents,
  review their diffs, merge, and gate each wave.
- **You don't write feature code yourself.**
- Repo: `/Users/spatel/workspace/github/projects/immich`.
- The main checkout belongs to another session (`perf/heirloom-macos`). Don't work there, and don't
  touch its branches, `main` or `feat/shared-libraries`.

## Read first
1. `.claude/plans/heirloom-ios-ui/PLAN.md`: rules, budgets, WP table, WP0–WP6 specs, device-driving notes.
2. `03-audit.md`: findings and root causes. `02-profile.md`: device traces.
3. Look at the reference screenshots `shots/device-native-*.png` and the current state
   `shots/device-heirloom-*.png`. They contain personal photos: never commit, upload or paste them
   anywhere.
4. `01-controls.md`: the control inventory. It is background, so spot-check its claims.

## Setup
```bash
git -C /Users/spatel/workspace/github/projects/immich branch feat/heirloom-ios-native-ui b38ea8217
```
Create worktrees per WP from the current integration tip:
```bash
git worktree add ../immich-ios-wpN -b feat/heirloom-ios-wpN <tip>
```
Merge with `git merge --no-ff` inside an integration worktree:
```bash
git worktree add ../immich-ios-int feat/heirloom-ios-native-ui
```

## Routing (announce each as `→ agent (model): task`)
| Work | Agent | Model |
|---|---|---|
| WP0–WP5 implementation | `implementer` | Sonnet |
| Builds, tests, trace summaries (WP6 §1, §4) | `verifier` | Sonnet |
| "Where is X" lookups while reviewing | `scout` | Haiku |
| Diff review, merges, device install, Device Hub scenario, screenshot comparison, diagnosing unexpected failures | you | Opus |

## Per-WP subagent prompt (fill in N and NAME)
> Execute WPN (NAME) of the Heirloom iOS native-UI plan.
>
> - Plan: `/Users/spatel/workspace/github/projects/immich/.claude/plans/heirloom-ios-ui/PLAN.md`.
>   Read "Global rules", the WP table and the WPN section.
> - Evidence: `03-audit.md`, `02-profile.md`, and the reference screenshots named in your section
>   (`shots/device-native-*.png`). Read the images; they are the visual spec.
> - For W2 packages, also read `reports/WP1-REPORT.md` and `native-apple/Apps/iOS/Sources/Grid/README.md`.
> - Working copy: worktree `../immich-ios-wpN` on branch `feat/heirloom-ios-wpN` (create it from
>   `<tip>` if it doesn't exist).
>
> Rules:
> - Edit only the files your WP owns.
> - Never perform destructive actions against the real server.
> - Never install to a device.
> - Never commit PNGs from `shots/`.
> - Commit per step (Conventional Commits, with the Co-Authored-By trailer). No push.
>
> Done means:
> - `make build-ios` is green (run `native-apple/scripts/gen-api.sh` first if needed);
> - `swift test --package-path native-apple/PhotosCore` is green;
> - `bash native-apple/scripts/verify.sh ios` is green;
> - your section's acceptance checks are met;
> - `reports/WPN-REPORT.md` is written: files, commits, tests, numbers, root causes found,
>   deviations, open issues.
>
> Reply in ≤ 15 lines: status, commits, blockers, API/contract deviations.

## Waves
1. **W1**
   - Run WP0.
   - Review: the split has no behaviour change; the fixture images render; the tour test exists.
   - Merge WP0, then run WP1 from the new tip.
   - **Review WP1 yourself**:
     - no `.estimated` sizes;
     - no O(rows) work on main or in `body`;
     - the snapshot is a reference type, gated by generation;
     - thumbhash is decoded off-main;
     - `editMode` doesn't reset layout or snapshot;
     - the `AssetGridView` / `ViewerRoute` / `GridSelectionModel` API is documented.
   - Merge WP1 and run **Gate 1**: WP6 steps; the Library part of the scenario must meet its budgets.
2. **W2**
   - Run WP2 ∥ WP3 ∥ WP4 ∥ WP5 in parallel (single message, one worktree each) from the Gate 1 tip.
   - WP4 uses `AccountButtonPlaceholder` until WP5 lands. After merging both, send a one-line
     follow-up to WP4 (via SendMessage) to swap in `AccountButton`.
   - Review each diff against its spec and the reference screenshots.
   - Merge in this order: WP5, then WP2, then WP4, then WP3. Resolve conflicts yourself only when
     they're trivial; otherwise send them back.
   - Run **Gate 2** (full scenario).

**On a gate failure:**
- Diagnose it yourself.
- Send a precise fix request with SendMessage to the same implementer.
- After two failed attempts, re-scope the task.

## Guardrails
- Don't push, open a PR or enable auto-merge unless the owner asks.
- Get the owner's OK once before the first device install.
- Never confirm trash, delete, move, hide, lock or archive on the real library.
- Only type text into the device for search queries, never credentials.
- If the macOS session's UI tests are running (`AutomationModeUI` overlay), don't click on the
  Mac; wait for them to finish.
- Keep team `599Z443923` and bundle id `com.immich.heirloom.ios`.

## Report to the owner after each gate (short)
- What merged, and pass/fail per budget (before → after).
- Audit rows fixed or still open.
- 3–5 side-by-side screenshot pairs (paths).
- Which tier did what.

Final deliverable:
- Gate 2 green;
- `03-audit.md` statused;
- `reports/FINAL.md`;
- the Release build installed on the phone (after the owner's OK).

---
