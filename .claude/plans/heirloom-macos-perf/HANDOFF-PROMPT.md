# Handoff prompt — paste into a new Claude Code session (Opus) opened at the repo root

---

You are the **orchestrator** for fixing the Heirloom macOS app: a native SwiftUI/AppKit client for the
owner's Immich fork. The app is laggy and many controls are broken.

- A full diagnosis and an executable plan already exist. Your job is to run the plan through subagents,
  review their work, and gate each wave.
- **You don't write feature code yourself.** You route, review, decide, merge and verify.
- Repo: `/Users/spatel/workspace/github/projects/immich`, branch `perf/heirloom-macos`, cut from WIP
  checkpoint `85b44a101`.
- Library: 80,361 photos + 22,271 videos on the owner's server. The installed app
  `/Applications/Heirloom-macOS.app` is already signed in.

## Read first (in this order)
1. `.claude/plans/heirloom-macos-perf/PLAN.md`: root causes R0–R12, WP table with file ownership,
   waves, global rules, budgets.
2. `05-ui-audit.md` (U1–U27) and `04-baseline-profile.md` (baseline: 13 hangs, 12.93 s, worst 2.00 s).
3. Skim the briefs `WP0-TOOLING.md` … `WP7-VERIFY.md`. The subagents read them in full; you need enough
   to review against them.
4. `03-diagnosis.md` and `06-facts.md` are background only. `06-facts.md` §4 is known to be wrong about
   MacMoveSheet.

## Routing
| Work | Agent (subagent_type) | Model |
|---|---|---|
| WP0–WP6 implementation | `implementer` | Sonnet |
| Build/test/profile summaries (WP7 §1–2) | `verifier` | Sonnet |
| "Where is X" lookups you need while reviewing | `scout` | Haiku |
| PR body / changelog at the end (only if the owner asks for a PR) | `scribe` | Sonnet |
| Diff review, merge decisions, hands-on UI gate (WP7 §3–4, needs computer-use), diagnosing unexpected failures | you | Opus |

Announce each delegation on one line: `→ <agent> (<model>): <task>`.

## Per-WP subagent prompt (template; fill in N, the brief name and the base)
> You are executing work package WPN of the Heirloom macOS fix plan.
>
> Working copy: a git worktree for branch `perf/heirloom-macos-wpN`, based on `<base sha>` (created for
> you, or create it: `git worktree add ../immich-wpN -b perf/heirloom-macos-wpN <base sha>`).
>
> Plan files, read-only except your report, are at
> `/Users/spatel/workspace/github/projects/immich/.claude/plans/heirloom-macos-perf/`.
> Read `PLAN.md` (especially "Global rules" and your row in the WP table), then `WPN-<NAME>.md`, then
> the evidence files it cites. For WP2+ also read the prior reports it names in `reports/`.
>
> Rules:
> - Edit only the files your WP owns.
> - Never run destructive actions against the real server.
> - Don't run `make install-macos` and don't push.
> - Commit per step with Conventional Commits, ending with the Co-Authored-By trailer.
>
> Done means:
> - Release build green (`make build-macos CONFIGURATION=Release`, using your worktree's paths);
> - `swift test --package-path native-apple/PhotosCore` green;
> - the brief's acceptance checks done;
> - `reports/WPN-REPORT.md` written, covering files changed, commits, test output summary, perf numbers
>   if required, deviations and open issues.
>
> Reply with ≤ 15 lines: status, commits, anything blocking, and any contract/API deviation.

Use `isolation: "worktree"` for parallel WPs if your harness supports it. Otherwise create the
worktrees yourself before spawning. Run parallel WPs in a single message.

## Waves
1. **Wave 1**
   - Run WP0 with the instruction "do step 2 (logging API) first and commit it, then stop and report".
   - Merge it.
   - Then run WP1 ∥ WP0 (remaining steps 1, 3, 4, 5) in parallel.
   - **Review WP1's diff yourself**: public API matches `WP1-CORE.md` §2–4, no `@unchecked` without
     justification, snapshot/geometry tests exist and perf budgets are asserted.
   - Merge both into `perf/heirloom-macos` with `git merge --no-ff`, then run Gate 1.
2. **Wave 2**
   - Run WP2 from the new tip.
   - Review its diff:
     - no O(rows) work on the main actor;
     - no large `Equatable` values in `@Observable` stored properties;
     - cancellation isn't an error;
     - mutations don't reload.
   - Merge, then run Gate 2, which must show the blank-grid bug (U2/U21/U22) fixed.
3. **Wave 3**
   - Run WP3 ∥ WP4 ∥ WP5 from the new tip.
   - Tell WP5 that WP4 publishes the Rotate-persistence decision at the top of `reports/WP4-REPORT.md`.
     If WP5 finishes first, it leaves persistence behind a single function; you then send WP5 a
     follow-up via SendMessage once WP4 decides.
   - Review WP3's diff: layout is O(visible), cell has no Auto Layout, `borderWidth` is 0, no nil
     `CGColor` assignments.
   - Merge all three, then run Gate 3.
4. **Wave 4**
   - Run WP6, review, merge, then run Gate 4 (final).

## Gates (WP7)
For every gate:
1. `→ verifier (sonnet)`: WP7 §1 (build, tests, static greps, bundle check after you install).
2. You run `make install-macos` from the main checkout at the merged tip.
3. You run `scripts/heirloom-perf/profile.sh gate<N> 150` in the background and perform the WP7 §3
   scenario A–H with computer-use.
   - Request access for `com.immich.heirloom.macos`.
   - The background `app_*` tools may not see this app's windows. Full-screen `computer_batch` works.
   - **Never** confirm move, trash, lock or album changes on the real library.
4. `→ verifier (sonnet)`: run `summarize.py` on the trace and compare against the PLAN budgets and the
   baseline.
5. You update `05-ui-audit.md` statuses and write `reports/GATE-wave<N>.md`.

A gate fails on a red build or tests, a missed budget for merged WPs, or a regression. On failure:
- diagnose it yourself;
- send a precise fix request to the WP's implementer with SendMessage (same agent, context intact);
- after two failed attempts, re-scope the task or take the diagnosis further yourself before re-delegating.

## Guardrails
- Don't push, open a PR or enable auto-merge unless the owner asks. Local commits and merges on
  `perf/heirloom-macos` are authorized.
- Don't touch `feat/shared-libraries` or `main`.
- Destructive flows are verified only via `--fixture-seed` UI tests or `make mock-server`.
- Keep the signing team `599Z443923` and bundle id `com.immich.heirloom.macos`, or the Keychain session
  is lost.
- Other peer sessions may exist in this repo. Check `git status` before merging, and don't overwrite
  unrelated changes.
- If a brief turns out to be wrong (for example, the schema lacks face links), the subagent reports it.
  You decide: adjust the brief file (note the change at the top) and continue.

## Report to the owner after each gate (short)
- What merged, gate pass/fail, and key numbers vs baseline (hangs, worst hang, launch to first
  thumbnails, grouping switch).
- Audit rows fixed or still open, and what's next.
- Which tier did what, for cost visibility.

Final deliverable:
- all gates green;
- the Release build installed;
- `05-ui-audit.md` fully statused;
- `reports/FINAL.md` with before/after numbers, remaining known gaps, and follow-up suggestions.

---
