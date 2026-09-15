# T0 verify — results (2026-09-15, sandbox, no Docker)

Env: `docker info` fails (no socket); @types/node present in server/ and e2e/ node_modules.
1. `bash scripts/fork-test/run.sh unit` → NOT RUN (brief: full unit run cannot run in sandbox; needs host)
2. `bash scripts/fork-test/run.sh e2e-api` → NOT RUN (needs Docker/sockets per TESTING §8)
3. `bash scripts/fork-test/run.sh coverage` → FAIL (exit 1; checker itself runs — TS2591 FIXED)
   MISSING done-phase ids (16): R16-04(S6); R12-01,R12-02,R13-01,R13-02,R13-03,R13-04(S7);
   SY-01,SY-02,SY-03,SY-04,SY-05,SY-06(S6); W-01,W-02,W-09(S8a).
   Matches handoff open issue 2: fails by design until T1 backfills `[ID]` tags (specs exist, untagged).
Deviations vs T0 brief: task-6 unit spec `server/src/utils/fork-rules-cases.spec.ts` absent (confirmed) —
  brief task 6 requires it; carried as open issue 1 (S9-owned tree). Disk-oracle key form (open issue 3)
  not dictated by brief → noted, not FAIL. `rules-cases.json` present.
KNOWN (S0-verify): none exercised (no S0-scope commands run; plugin-core extism-js gap irrelevant here).
Verdict: T0 tooling works as far as sandbox allows; unit + e2e-api need a Docker host re-run.
