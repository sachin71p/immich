# S3 verify — 2026-09-14 (round 2)

1. `cd server && pnpm run check` → PASS
2. `pnpm run lint` → PASS
3. `pnpm run test` → FAIL

First reported failures include:
```text
src/controllers/memory.controller.spec.ts (10 tests | 10 failed)
src/controllers/asset-media.controller.spec.ts (9 tests | 9 failed)
src/controllers/timeline.controller.spec.ts (4 tests | 3 failed)
src/controllers/duplicate.controller.spec.ts (1 test | 1 failed)
```

The prior verification already failed controller validations (including map, album,
and notification); those still fail. This run additionally reports broad controller
suite failures. No S3-specific test or error trace was emitted before the command
output limit, so this does not isolate an S3 regression. It is not a documented
sandbox/container limitation; treat it as an unresolved test-suite failure.

Stopped at the first failing Verify step; `pnpm run test:medium` was not run.
