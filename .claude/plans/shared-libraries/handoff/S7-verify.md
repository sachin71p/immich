# S7 verification

- `cd server && pnpm run check` — PASS.
- `cd server && pnpm run lint` — PASS.
- `cd server && pnpm exec vitest src/services/search src/services/asset` — FAIL;
  stopped the prescribed sequence at the first failure.
- The bare command does not load the repository Vitest config. All four suites
  fail before tests run because `src/...` imports cannot resolve:
  `asset-media.service.spec.ts`, `asset-relocation.service.spec.ts`,
  `asset.service.spec.ts`, and `search.service.spec.ts`.
- Separate configured equivalent — `pnpm exec vitest --config test/vitest.config.mjs
  src/services/search src/services/asset --run` — PASS (4 files, 241 tests).
- This is a verification-command/config constraint, not evidence of an S7
  source defect. `pnpm run test` and `pnpm run test:medium` were not run after
  the prescribed first failure.
