# S10 — Hardening: e2e, FORK.md, upstream-merge rehearsal

Depends on: S8b, S8c, T1 · Reads: TESTING.md §5 (rows with Phase = S10), §6, §7 · DECISIONS §2–§8 · CODEMAP §G ·
all S/T handoffs (skim "open issues" only).

Per-requirement e2e API/web tests are no longer built here — T1 and each phase own their TESTING.md rows.

## Tasks
1. Confirm `scripts/fork-test/run.sh coverage` is green for every ✅ phase; fill any gaps.
2. `[UP-01]` upgrade test script (`scripts/fork-test/upgrade.sh`): start an upstream-only stack at the base tag,
   seed data with upstream e2e utils, swap to the fork image → migrations run → data intact; reserved-label guard.
3. `[INV-02]` OpenAPI diff script vs the base tag's spec: fails on any removal/rename/type change.
   `[INV-03]` wire `run.sh upstream` (upstream e2e API + web + medium suites unchanged).
4. FORK.md: complete the patch list from all handoffs; add "conflict hotspots" (files with the most fork hooks).
5. Merge rehearsal: on a throwaway branch merge the latest upstream release tag; record conflicts, time taken, and
   regenerate steps in FORK.md; do not commit the merge to feat/shared-libraries.
6. Admin integrity: a CLI/admin job "Verify container paths" that reports assets whose files are not at their §7 path
   (reuse relocation path computation, report-only).

## Verify (host with Docker)
`scripts/fork-test/run.sh all upgrade`
