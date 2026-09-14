# Fork: Shared Libraries

This is a fork of [immich-app/immich](https://github.com/immich-app/immich) that adds shared
libraries (spaces) and related features. See
[`.claude/plans/shared-libraries/DECISIONS.md`](.claude/plans/shared-libraries/DECISIONS.md)
for the full product/design spec.

## Base

- Upstream tag: `v3.1.0`
- Base sha: `e55ac299a4ec7cb372e35dbf2c6c05ee9ce77f6c`

## Merge procedure

1. `git fetch upstream --tags`.
2. Create a branch `merge/<tag>` and run `git merge <tag>` on it.
3. Resolve conflicts using the patch list below.
4. Regenerate generated files instead of hand-merging them: `mise //server:sync-open-api`,
   `mise :open-api-typescript`, `mise :open-api-dart`, `mise //server:sql`.
5. Run the S10 verify list.

## Cadence

Merge every upstream minor release (approximately monthly); apply security releases
immediately.

## Patch list

| upstream file | change | reason | phase |
| `server/src/{database,enum}.ts` | registers shared-library database schema and enums | shared schema support | S1 |
| `server/src/dtos/asset-response.dto.ts` | exposes shared container fields in asset responses | shared schema support | S1 |
| `server/src/schema/{index,enums,functions}.ts` | registers shared-library schema and audit hooks | shared schema support | S1 |
| `server/src/schema/tables/{asset,library}.table.ts` | adds container fields and invariants | shared schema support | S1 |
| `server/src/schema/migrations/ORDER` | registers shared-library migration | shared schema support | S1 |
| `server/src/{repositories/sync.repository,services/sync.service}.ts` | prunes new audit tables | shared schema support | S1 |
| `server/src/services/asset-media.service.spec.ts` | adapts fixture for asset container fields | shared schema support | S1 |
| `server/test/{factories/asset.factory,small.factory}.ts` | adapts asset fixtures for container fields | shared schema support | S1 |
|---|---|---|---|
