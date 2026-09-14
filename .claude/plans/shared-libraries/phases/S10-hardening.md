# S10 — Hardening: e2e, FORK.md, upstream-merge rehearsal

Depends on: S8b, S8c · Reads: DECISIONS §2–§8 · CODEMAP §G · all S handoffs (skim "open issues" only).

## Tasks
1. E2E API specs (e2e/ — find existing API spec folder and copy a spec): golden paths per requirement R2–R13, R16, R17:
   create space, add member, upload with default target, move personal→space→personal, member edits/favorites/deletes,
   album viewer add/remove/favorite, library member sees library, move into library upload path, physical file
   locations on disk after moves (container paths per DECISIONS §7), space deletion returns assets, user deletion
   keeps contributions.
2. E2E web (Playwright) smoke: create space via UI, switch library, move via action, favorite visible to other user.
3. Upgrade test: start from an upstream-only DB (base tag) with data → run fork migrations → all data intact,
   Flutter-compatible endpoints unchanged (compare OpenAPI diff: only additions).
4. FORK.md: complete the patch list from all handoffs; add "conflict hotspots" (files with the most fork hooks).
5. Merge rehearsal: on a throwaway branch merge the latest upstream release tag; record conflicts, time taken, and
   regenerate steps in FORK.md; do not commit the merge to feat/shared-libraries.
6. Admin integrity: a CLI/admin job "Verify container paths" that reports assets whose files are not at their §7 path
   (reuse relocation path computation, report-only).

## Verify
1. Server: check, lint, test, test:medium 2. Web: check:typescript, check:svelte, lint, test --run
3. `mise //e2e:test-web` (Docker) 4. OpenAPI diff vs base tag contains no removals/renames.
