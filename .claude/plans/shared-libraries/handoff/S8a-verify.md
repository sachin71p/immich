# S8a verification (fresh run)

- `check:typescript` — PASS (exit 0)
- `check:svelte` — CRASH, but exit 0 (host toolchain, not S8a)
  - TS 6.0.3 crash reproduces: `Debug Failure. No error for last overload signature`
    in `resolveCall` (typescript.js:81300).
  - Still completes: `423 FILES 0 ERRORS 0 WARNINGS`, exit 0. Confirms prior report.
- `lint` — FAIL (exit 1) — real S8a defects, 5 errors:
  - `SharedSpaceCreateModal.svelte:24` — `unicorn/catch-error-name`: catch param
    `cause` should be `error_`
  - `.../shared-libraries/[spaceId=id]/.../+page.svelte:27-28` —
    `unicorn/prefer-early-return` (x2) + `unicorn/no-await-expression-member`
  - same file:2 — unused import `invalidate`
  - `admin/library-management/[id]/+layout.svelte:57` — `curly`: missing `{` after `if`
  - plus 3 tailwind class-order/deprecated-class warnings on shared-libraries/+page.svelte
- `test --run` — FAIL (exit 1), not an S8a defect:
  - 40/60 suites fail at setup: `TypeError: Cannot read properties of undefined
    (reading 'getItem')` — `localStorage.getItem` unavailable (Node run without
    `--localstorage-file`). Reproduces on unrelated pre-existing specs
    (`utils.spec.ts`, `Image.spec.ts`, `StarRating.spec.ts`), so it's environmental.
  - All 337 executed tests pass; `SharedSpaceCreateModal.spec.ts` hits the same
    setup crash before assertions run (uncounted, not a content failure).

## Summary
Real S8a defect: lint only (5 errors/3 warnings, all fixable). check:svelte crash
and test setup crash are pre-existing host/toolchain issues, unrelated to S8a code.
