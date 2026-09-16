# Flip the verdict — work plan (HEAD 464f9122b)

Conjunction required (HOST-VERIFICATION-BRIEF §3): canary green (fresh) + no
failing fork case + INV-02/INV-03 green + S9 three suites green. Owed alongside:
true upstream-e2e on /data, S10 regen, live email render (2f), C7 exercise (2g),
f6bd80b62 split (§0, at push-prep), coverage-matrix decision (2d).

## Tracks (disjoint file scopes — parallel-safe in one checkout)

1. **runner-fix** — `scripts/fork-test/` only. Fix `run.sh:128` `keep[@]`
   unbound-variable crash under bash 3.2. Verify: `bash -n` + crash path gone
   under macOS `/bin/bash`. No other edits.
2. **r4-01** — server relocation/metadata code + fork `moves.e2e-spec.ts` +
   server unit specs. Fix personal-move identity failure. Verify: unit specs,
   tsc, eslint. No e2e-stack runs (gate owns e2e).
3. **r17-03** — e2e world/disk harness files only. Fix auditDisk orphans
   plant/assert mismatch. Server/src and spec assertions off-limits (report
   staleness instead). Verify: e2e tsc/eslint.
4. **unit-web** — web test config/setup only; app-source edits FORBIDDEN
   (report file:line + proposal). Triage localStorage import failure env vs
   regression. Verify: failing files import clean.
5. **apple** — `native-apple/` only. Fix Editing keyNotFound, UploadQueue SHA1,
   SearchTests location/size. Verify: affected suites via xcodebuild/verify.sh.
6. **s10** — OpenAPI/SQL artifacts + timeline rename (3 clients + server,
   atomic) + coverage matrix. Add INV-02/INV-03/UP-01 coverage; R13-04/W-01/
   W-02/W-09 are T1-owned, do NOT touch. Decide invisible tags
   ([C3]/[R16]/[I6]/[I7]/PERM-11): matrix gains them. Verify: tsc/eslint,
   INV-02 diff if runnable without full gate.
7. **c7** — no source edits (/tmp scratch only). Two-filesystem exercise or
   honest NOT-POSSIBLE with `df` evidence.

## Gate (after all tracks complete)

Fresh canary (5 album specs, default stack) → STOP on regression; else
`run.sh all upgrade --template both` under mise toolchain; S9/S3/S4/S6
re-runs; grep e2e-api log for `require is not defined`/`ERR_MODULE_NOT_FOUND`
+ NotifyAlbumInvite outcome (2f live evidence); standalone retry of e2e-web
album map-view on failure (flake check).

## Finish (parent)

Findings update → flip verdict iff conjunction met → f6bd80b62 split
(no upstream: rebase locally safe) → report.

Global constraints: host execution, Docker OK, sandbox off. mise, never bare
pnpm. No `brew install`. Never edit media goldens. No AUDIT-FINDINGS.md edits
from tracks, no history rewrites, no pushes. Never stage/commit from tracks —
orchestrator commits.

## Phase 2 (after phase-1 tracks + orchestrator commits)

Final gate on the committed tree: fresh canary → `run.sh all upgrade
--template both` → true upstream-e2e on the DEFAULT stack (verify
media root is `/data`, not `/fork-data`, before running) → S9 trio only
if not already evidenced → findings update → flip iff conjunction met.

## §0 decision (owner)

`origin/feat/shared-libraries` exists → the f6bd80b62 split is SUPERSEDED.
No rebase, no follow-up shuffle: history stands as-is, recorded in findings.
