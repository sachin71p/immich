# S8c verify (2026-09-15, fresh run)

1. `cd web && pnpm run check:typescript` → PASS (exit 0, no output)
2. `cd web && pnpm run check:svelte` → KNOWN (exit 0; TS 6.0.3
   `Debug Failure. No error for last overload signature` crash as in
   S8a-verify; `svelte-check found 0 errors and 0 warnings`)
3. `cd web && pnpm run lint` → PASS (exit 0; S8b's 2 pre-existing
   lint errors appear fixed in tree)
4. `cd web && pnpm run test --run` → KNOWN (exit 1; 42/65 suites fail
   at setup with `TypeError: Cannot read properties of undefined
   (reading 'getItem')` via ThemeManager/PersistedLocalStorage —
   same env gap as S8a-verify; hits pre-existing specs too.
   All 356 executed tests pass, 0 content failures. Both new S8c
   specs (`SearchExposureSection`, `search-bar-utils`) crash at
   setup before assertions — no tests run.)
5. `scripts/fork-test/run.sh coverage` → FAIL (harness, not S8c:
   `coverage.ts` has 5 TS2591 errors — missing @types/node for
   `node:fs`/`node:path`/`process`; T0 harness still being built.
   Missing case ids undeterminable.)
6. Tiers medium/e2e/upgrade → NOT RUN (need Docker/sockets; TESTING.md §8)

Verdict: S8c code clean (ts/lint pass, no test-content failures);
test execution blocked by known env gaps; coverage harness broken.
