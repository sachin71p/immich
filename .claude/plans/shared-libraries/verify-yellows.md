# Verify-yellows plan (16-Sep host session, unsandboxed, Docker up)

Goal: verify each 🟨 row's outstanding blockers in STATUS.md; orchestrator updates the file for resolved items. No commits from agents. No `--build` (server image already carries R4-01 fixes). Never touch native-apple app sources (user editing concurrently) or `e2e/test-assets/temp`.

## Wave 1 (parallel, no e2e-stack switching)
- **T1-backfill**: for each of R13-04, W-01, W-02, W-09 — grep `[ID]` tags across `server/src`, `server/test`, `e2e/src/specs`, `web/src`, `native-apple`; report FOUND (file:line) or MISSING. Run related no-docker suites only (server unit via `cd server && CI=true pnpm exec vitest --run --config test/vitest.config.mjs <spec>`). Do NOT run e2e, medium, web-e2e, or switch compose stacks. Done: per-ID table + any test outcome observed.
- **S10-upgrade**: check SQL regen currency for the fork audit method/job enums (repo's own regen/check commands only), run `scripts/fork-test/openapi-diff.sh`, run `scripts/fork-test/upgrade.sh` (uses its own isolated compose project — never touch the e2e stack volumes). Done: per-item PASS/FAIL/NOT-RUN with command output compressed.
- **Web-unit**: `cd web && pnpm run test --run` (report tally); probe e2e-web readiness only (`pnpm exec playwright --version`, browsers installed?) — do NOT run e2e-web (needs fork stack, wave 3). Done: unit tally + readiness verdict.

## Wave 2 (default stack, exclusive window; runs after wave 1)
- **S2-T0-upstream**: `docker compose -f e2e/docker-compose.yml down` (fork stack; peer shares it — keep downtime minimal), then up DEFAULT stack (`docker compose -f e2e/docker-compose.yml up -d --build` + ping wait on 127.0.0.1:2285), run `album.e2e-spec.ts` fully (S2's 5 known failures: viewer add/remove allowed, owner denied, role-change message — compare), run `integrity.e2e-spec.ts` fully (T0), attempt `audio-video` + workflow plugin suites bounded (report even if partial). Restore afterwards: default `down`, fork up (`docker compose -f e2e/docker-compose.yml -f e2e/docker-compose.fork.yml up -d`, NO rebuild) + ping check. Done: per-spec tallies + failing test names, fork stack confirmed back.

## Wave 3 (fork stack, after wave 2 restore)
- **Web-e2e**: `cd e2e && pnpm test:web -- src/specs/web/fork` on the restored fork stack. Done: tally per file.

All agents: read-only except running the named suites; report compressed findings (tallies, failing names, first error lines), never raw logs.
