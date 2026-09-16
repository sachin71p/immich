# Fix batches — fork-test 20260915-144745 triage (2026-09-15)

Repo /Users/spatel/workspace/github/projects/immich, branch feat/shared-libraries.
Full failure log: /tmp/kickoff-pasted-log.txt. Triage memory: project MEMORY.md ("Triage 20260915-144745").

## Decided contracts (orchestrator judgment — do not relitigate)
- Bulk-move error results INTENTIONALLY carry `reason` (`source_access`/`target_access`/`duplicate`).
  Proof: server/src/services/asset.service.ts:114,126 + server/src/services/asset.service.spec.ts:158.
  E2e asserts that use exact `toEqual` without `reason` are STALE — update the specs, not the service.
- R6-02 300s timeouts are downstream of R16-01 (viewer favorite 400 → no update → sync wait starves).
  Fixing viewer-favorite access is expected to clear the timeouts; if not, say so explicitly.

## Batches (parallel-safe scopes)
- B1 S2-access (server/src space/album/asset access + member services). Read handoff/S2.md + S2-e2e-fix.md first.
  403 (not 400) for unauthorized space/album ops; removeSpaceMember works; owner transfer + re-own on
  lifecycle; viewer add/favorite allowed, partner favorite 403.
- B2 S3-paths (storage keys / move engine). Read phases/S3-relocation.md + e2e disk oracle (e2e/src/specs/server/api/fork/disk.ts).
  Derived thumbs/encoded-video folders + sidecars land correctly after moves; personal-path returns; no /test-assets residue.
- B3 S4-move-API + spec updates. REAL: R10-06 duplicate must error (not `moved`). TEST: add `reason` to exact-match
  asserts in e2e/src/specs/server/api/fork/moves.e2e-spec.ts:166 and external-libraries.e2e-spec.ts:174.
- B4 T1-factory (TEST only, server/test/medium.factory.ts + fork medium specs). Add MoveRepository to
  newRealRepository switch (~line 549); provide logger for factory-constructed services (BaseService ctor
  setContext crash). Mirror existing factory patterns; do not change product code.
- B5 integrity diagnosis (READ-ONLY, no edits). Why do all integrity jobs/summaries come back empty in e2e?
  Prime suspect: S3 storage-layout interplay. Return cause + owner file + proposed fix; do not implement.

## Global constraints
- NEVER commit, push, or run anything needing Docker/CoreSimulator/brew/mise (sandbox-blocked; host verifies).
- One concern per agent; stay inside your listed files. If your fix needs a file outside scope, STOP and report.
- Verify with the repo's own typecheck + lint scoped to touched files (see server/package.json scripts).
  DB-backed suites (medium/e2e) cannot run here — say so, do not fake it.
- Return: files changed, what/why per file (max 5 lines each), typecheck/lint output, anything unresolved.
