# T0 — Test harness, fixtures, world, runner

Depends on: S0 · Parallel-safe with S6/S7 (touches only e2e/, scripts/, server/test/fork-fixtures/, .gitignore) ·
Reads: TESTING.md §1–§4, §6, §8 · CODEMAP §G.

Known e2e facts (scouted): `e2e/docker-compose.yml` (server :2285, Postgres :5435, `./test-assets` → `/test-assets`);
helpers in `e2e/src/utils.ts` (`resetDatabase`, `adminSetup`, `userSetup`, `createAsset`, `createLibrary`, `scan`,
`waitForQueueFinish`, `waitForWebsocketEvent`, `createImageFile`); external-library spec
`e2e/src/specs/server/api/library.e2e-spec.ts` uses `testAssetDir` (host) ↔ `testAssetDirInternal` (container);
`e2e/test-assets` is a git submodule (immich-app/test-assets) — not checked out yet; CI runs e2e with
`VITEST_DISABLE_DOCKER_SETUP=true` after `docker compose up -d --build`; medium tests always start Postgres via
testcontainers (`server/test/medium/globalSetup.ts`).

## Tasks
1. `git submodule update --init e2e/test-assets`; inventory formats (HEIC, DNG, MP4/MOV, motion photos) and pick
   upstream fixtures for manifest (kind `upstream`). Do not modify the submodule.
2. Fixture generator `server/test/fork-fixtures/generate.ts` (+ `pnpm exec tsx` or node invocation documented in
   the script header) → writes `e2e/fork-assets/generated/*` and verifies against `e2e/fork-assets/manifest.json`
   (TESTING §2.1 coverage list). Commit the generated files and the manifest.
3. Personal slot: `e2e/fork-assets/personal/` + `.gitignore` entries (`e2e/fork-assets/personal/`, `e2e/.fork-data/`,
   `e2e/.fork-report/`); `scripts/fork-test/index-personal.ts` builds `manifest.local.json`; README in the folder
   listing expected file names (TESTING §2.3).
4. `e2e/docker-compose.fork.yml` override: bind-mount the server media root (the location upstream compose uses for
   uploads/library/thumbs) to `./.fork-data`, keep `/test-assets` read-write, set any env needed for storage-template
   on/off toggling via API (prefer toggling through the system-config API inside tests instead of env).
5. Helpers in `e2e/src/specs/server/api/fork/`: `world.ts` (TESTING §3), `disk.ts` (independent `expectedPaths`,
   `expectFilesAt`, `auditDisk`), `jobs.ts` (`settle`, pause/resume relocation via jobs API), `sync.ts`, `as.ts`,
   `record-sync.ts`. Reuse `e2e/src/utils.ts`; do not edit it (add wrappers in fork files instead).
6. `e2e/fork-assets/rules-cases.json` (schema + ~40 rows derived from DECISIONS §4/§6/§10) and a server unit spec
   `server/src/utils/fork-rules-cases.spec.ts` that runs every row against the real access/move/scope functions.
7. Runner `scripts/fork-test/run.sh` + coverage checker `scripts/fork-test/coverage.ts` per TESTING §6.
8. Smoke spec `e2e/src/specs/server/api/fork/world.e2e-spec.ts`: `[R17-01]` build world (template on and off),
   `settle()`, assert all expected paths; `[R17-03]` `auditDisk()` clean.
9. FORK.md: add the regression gate from TESTING §7 to the merge procedure. Add `.github/workflows/fork-tests.yml`.

## Self-check (sandbox-safe)
`cd server && pnpm run check && pnpm exec vitest src/utils/fork-rules-cases.spec.ts`;
`cd e2e && pnpm exec tsc --noEmit` (or the e2e package's typecheck script); `bash -n scripts/fork-test/run.sh`.

## Verify (host with Docker; else NOT RUN per TESTING §8)
1. `scripts/fork-test/run.sh unit` 2. `scripts/fork-test/run.sh e2e-api` (runs world smoke) 3. `scripts/fork-test/run.sh coverage`

## Done when
World builds in both template modes with a clean disk audit; runner + coverage work; fixtures committed;
personal fixtures optional and skipped cleanly.
