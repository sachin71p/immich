# Shared Libraries Fork — Execution Guide (start here)

Goal: fork Immich so that (a) server + web implement shared libraries, shared external libraries, shared
favorites, per-container disk layout with physical moves, full metadata + extended search; and (b) native
Swift iOS and macOS apps (Apple Photos-like) run on top of the forked server. Requirements R1–R17 and all
rules: `DECISIONS.md`. Verified code facts: `CODEMAP.md`.

## Files
| File | Who reads it | Purpose |
|---|---|---|
| `README.md` | orchestrator | This guide: loop, prompts, rules |
| `STATUS.md` | orchestrator | Phase checklist + commits. The only file the orchestrator updates each phase |
| `DECISIONS.md` | all agents (only sections named in the phase) | What to build, rules, invariants |
| `CODEMAP.md` | implementers (only sections named in the phase) | Where things are |
| `phases/S*.md` | one implementer per phase | Server/web phase brief |
| `phases/A*.md` | one implementer per phase | Apple (iOS + macOS) phase brief |
| `handoff/<phase>.md` | written by implementer, read by orchestrator + next phase | ≤40-line summary |
| `handoff/<phase>-verify.md` | written by verifier | pass/fail summary |

## Roles (map to your agent tooling)
| Role | Claude Code agent | Model | Does |
|---|---|---|---|
| orchestrator | main session | Opus | picks phase, dispatches, reviews, commits, updates STATUS |
| implementer | `implementer` | Sonnet | executes one phase file end-to-end, writes handoff |
| verifier | `verifier` | Sonnet | runs the phase's verify commands, writes verify handoff |
| scout | `scout` | Haiku | answers a narrow "where is X" question if a phase hits an unknown |
Other tools: any agent that can read files, edit code and run shell commands can play any role; keep the
same file protocol.

## Orchestrator loop
1. Read `STATUS.md`. Pick the next phase whose dependencies are ✅. Phases marked "parallel-safe with X"
   may be dispatched together (they touch disjoint files).
2. Branch: all work happens on `feat/shared-libraries` (created in S0). One commit per phase.
3. Dispatch implementer with the prompt template below (never paste plan content — pass paths).
4. When it returns: read `handoff/<phase>.md` only. If it says `BLOCKED:`, resolve the decision yourself
   (update `DECISIONS.md` if a rule changes), then re-dispatch.
5. Dispatch verifier with the template below. If it fails, send the failure summary path back to the
   implementer (same agent via SendMessage when possible) — max 2 fix rounds, then take over or re-scope.
6. Review: `git diff --stat` and, for **high-risk phases (S2, S3, S4, S5, S6)**, read the diff of the files
   listed under "Review focus" in the phase file. Check against the invariants in `DECISIONS.md §3`.
7. Commit: `git add -A && git commit -m "feat(shared-libraries): <phase id> <title>"` with the
   `Co-Authored-By` trailer required by your environment. Append the upstream files touched to `FORK.md`'s
   patch list (the implementer drafts this in its handoff).
8. Update `STATUS.md` (status, commit sha, notes ≤1 line). Go to 1.

## Implementer prompt template
```
You are implementing phase <ID> of the Immich fork "shared libraries".
Repo: <abs path to repo>. Branch: feat/shared-libraries (already checked out).
Read, in this order and nothing else up front:
  1. .claude/plans/shared-libraries/phases/<ID>-*.md   (your brief — scope, tasks, tests, done criteria)
  2. the DECISIONS.md and CODEMAP.md sections your brief lists
  3. .claude/plans/shared-libraries/handoff/<dependency>.md for each dependency listed in your brief
Rules:
  - Stay inside the brief's scope. Open only files you need; locate symbols with narrow greps
    (single directory, specific identifier). Never dump whole large files or run repo-wide greps without a path.
  - Follow existing code patterns in neighbouring files. Keep upstream-file edits minimal and additive; put new
    logic in new files. Mark each upstream hook with a `// fork: shared-libraries` comment.
  - Write the tests the brief lists. Run the brief's "self-check" commands before finishing; do not run e2e
    unless the brief says so.
  - If CODEMAP is wrong, note `CODEMAP-FIX:` and continue. If a DECISIONS rule is ambiguous or impossible,
    stop and write `BLOCKED: <question>`.
  - Do not commit. Finish by writing .claude/plans/shared-libraries/handoff/<ID>.md (≤40 lines):
    summary · files changed (new vs upstream-modified) · FORK.md patch-list lines · deviations · open issues.
Reply with only: DONE or BLOCKED, plus the handoff path.
```

## Verifier prompt template
```
Verify phase <ID> of the Immich fork. Repo: <abs path>. Run exactly the commands under "Verify" in
.claude/plans/shared-libraries/phases/<ID>-*.md (in order; stop at the first failing step unless the brief
says continue). Write .claude/plans/shared-libraries/handoff/<ID>-verify.md (≤30 lines): each command →
PASS/FAIL, and for failures the failing test names + the first relevant error lines (≤10 lines each).
Pre-existing failures recorded in handoff/S0-verify.md are not regressions — mark them KNOWN.
Reply with only: PASS or FAIL, plus the path.
```

## Token rules (all agents)
- Pass paths, not content. Handoffs ≤40 lines. Verify reports ≤30 lines.
- A phase reads at most: its brief, named DECISIONS/CODEMAP sections, dependency handoffs, and the code it edits.
- Regenerate OpenAPI/SDK/SQL docs only at the end of phases that change the API or queries (listed in brief).
- Long outputs (test runs, builds, codegen) stay inside the verifier/implementer; report summaries only.
- Never re-scout what CODEMAP already states; if unsure, check the one file named there.

## Phase graph
```
S0 → S1 ─┬→ S2 ─┐
         └→ S3 ─┴→ S4 → S5 → S6 → S7 → S8a → S8b → S8c → S10
                                   └──────────────→ (S9 optional, after S6)
Apple: A0 (can start after S0; mocks API) → A1 needs S6 → A2 … A9 (see phases/A0-apple-overview.md)
```
