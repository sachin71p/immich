# S0 — Fork baseline

Depends on: — · Reads: DECISIONS §1–§2 only.

## Goal
Reproducible starting point: upstream remote, working branch, FORK.md, and a record of pre-existing test
failures so later phases don't chase them.

## Tasks
1. `git remote add upstream https://github.com/immich-app/immich.git` (skip if exists); `git fetch upstream --tags`.
   Record `git describe --tags --abbrev=0` and `git rev-parse HEAD` (base).
2. `git checkout -b feat/shared-libraries` from current `main`.
3. Create `FORK.md` at repo root:
   - Purpose (2 lines, link `.claude/plans/shared-libraries/DECISIONS.md`).
   - Base: upstream tag + sha.
   - Merge procedure: fetch upstream tags → `git merge <tag>` on a branch `merge/<tag>` → resolve conflicts
     using the patch list → regenerate OpenAPI/SDK/SQL (`mise //server:sync-open-api`, `mise :open-api-typescript`,
     `mise :open-api-dart`, `mise //server:sql`) instead of hand-merging generated files → run S10 verify list.
   - Cadence: merge every upstream minor release (≈monthly); apply security releases immediately.
   - Patch list table: `| upstream file | change | reason | phase |` (empty for now).
4. Ensure `.claude/plans/` is committed (it is the spec). Do not add build artifacts.

## Verify (verifier)
1. `cd server && pnpm install --frozen-lockfile`
2. `cd server && pnpm run check`
3. `cd server && pnpm run lint`
4. `cd server && pnpm run test` (continue on failure; record failing test names as KNOWN)
5. `docker info >/dev/null 2>&1 && echo DOCKER_OK || echo NO_DOCKER` (record: medium/e2e tests need Docker)
6. `cd web && pnpm install --frozen-lockfile && pnpm run check:typescript`

## Done when
Branch exists, FORK.md committed, `handoff/S0-verify.md` lists baseline results (KNOWN failures + Docker availability).
