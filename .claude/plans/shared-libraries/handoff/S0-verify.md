# S0 verify — baseline results (2026-09-14)

## Environment note (required before any verify run)
`mise` is not installed in this environment. `packages/plugin-sdk` and `packages/sdk`
ship no `dist/`/`build/` — must bootstrap first, from repo root:
  pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter @immich/plugin-core install --frozen-lockfile
  pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter @immich/plugin-core build
`@immich/plugin-core`'s `build:wasm` step fails (`extism-js: command not found` — native
toolchain not installed); this is KNOWN/pre-existing and does not block server/web checks,
since only `@immich/sdk` (outputs to `build/`) and `@immich/plugin-sdk` (outputs to `dist/`)
are consumed by server/web TS builds.

## Results
1. `pnpm install --frozen-lockfile` (server) → PASS (prior run, not repeated)
2. `cd server && pnpm run check` → PASS
3. `cd server && pnpm run lint` → PASS
4. `cd server && pnpm run test` → PASS — 105 files, 2272 passed, 1 expected fail (2273 total)
5. `docker info` → PASS — DOCKER_OK (medium/e2e tests can run)
6. `cd web && pnpm install --frozen-lockfile && pnpm run check:typescript` → PASS

## KNOWN pre-existing issues
- `@immich/plugin-core` wasm build requires `extism-js` binary, not present in this
  environment. Not exercised by server/web TS checks; future phases needing plugin-core's
  wasm artifact must install extism-js separately.
