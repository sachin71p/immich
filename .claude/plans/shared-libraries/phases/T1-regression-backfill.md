# T1 — Regression backfill for completed server phases (S1–S5)

Depends on: T0 · Reads: TESTING.md §3–§5 (rows with Phase = T1), §8 · DECISIONS §3–§10 as referenced by each row ·
handoffs S1–S5 (open issues only).

## Goal
Every TESTING §5 row with Phase `T1` has a passing test on a host with Docker, catching any bug that slipped
through S1–S5 (those phases were marked ✅ with medium/full suites not run).

## Tasks
1. E specs in `e2e/src/specs/server/api/fork/`, one file per group: `spaces.e2e-spec.ts` (R1–R3, R6, R7),
   `timeline-scope.e2e-spec.ts` (R8, R13-03 prep), `external-libraries.e2e-spec.ts` (R9, R10-01..03),
   `moves.e2e-spec.ts` (R4, R5, R7-02, R10-04..07, MV-01), `albums-favorites.e2e-spec.ts` (R11, R16-01..03),
   `lifecycle.e2e-spec.ts` (LC-01..04), `disk.e2e-spec.ts` (R17-01..03, runs last). Each file builds the world
   in `beforeAll` (template mode per describe block) and uses fork helpers only.
2. M specs in `server/test/medium/specs/fork/`: MV-02, MV-03, INV-01, plus guard tests for library watcher/scan
   races if not already present from S3.
3. U additions where a row says U and no unit test exists yet (check S2–S5 specs first; add, don't duplicate).
4. Run on host (TESTING §8). For each failing case: if the test is wrong, fix the test; if the product is wrong,
   write `BUG:` entries in the handoff (case id, observed vs expected, suspected file) — do NOT fix product code in
   this phase. The orchestrator dispatches fixes as `T1-fix-<n>` mini-phases.

## Verify (host)
`scripts/fork-test/run.sh unit medium e2e-api coverage --template both`

## Done when
All T1 rows pass (or have an open `BUG:` with an orchestrator-approved fix phase), coverage check green for S1–S5.
