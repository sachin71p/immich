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
|---|---|---|---|
| `server/src/{database,enum}.ts` | registers shared-library database schema and enums | shared schema support | S1 |
| `server/src/dtos/asset-response.dto.ts` | exposes shared container fields in asset responses | shared schema support | S1 |
| `server/src/schema/{index,enums,functions}.ts` | registers shared-library schema and audit hooks | shared schema support | S1 |
| `server/src/schema/tables/{asset,library}.table.ts` | adds container fields and invariants | shared schema support | S1 |
| `server/src/schema/migrations/ORDER` | registers shared-library migration | shared schema support | S1 |
| `server/src/{repositories/sync.repository,services/sync.service}.ts` | prunes new audit tables | shared schema support | S1 |
| `server/src/services/asset-media.service.spec.ts` | adapts fixture for asset container fields | shared schema support | S1 |
| `server/test/{factories/asset.factory,small.factory}.ts` | adapts asset fixtures for container fields | shared schema support | S1 |
| `server/src/{enum.ts,utils/access.ts,repositories/access.repository.ts}` | grants container-aware asset and shared-space access | shared access control | S2 |
| `server/src/services/{asset.service.ts,album.service.ts}` | protects shared favorites, roles, and Locked visibility | shared access control | S2 |
| `server/src/cores/storage.core.ts` | namespaces generated files by shared-space storage key | shared storage relocation | S3 |
| `server/src/services/asset-relocation.service.ts` | resumes and performs crash-safe asset file relocations | shared storage relocation | S3 |
| `server/src/{repositories/asset.repository.ts,services/library.service.ts}` | guards external scans/watchers while moves are pending | shared storage relocation | S3 |
| `server/src/utils/container-scope.ts` | resolves visibility scope and emits container SQL predicates | visibility scope | S5 |
| `server/src/repositories/{asset,search,map,trash}.repository.ts` | applies container-scoped listing and mutation queries | visibility scope | S5 |
| `server/src/services/{timeline,search,map,asset,trash,user,memory}.service.ts` | resolves and applies request visibility scopes | visibility scope | S5 |
| `server/src/{controllers,dtos}/shared-space.*` (new), `server/src/{repositories,services}/shared-space.*` (new) | shared-space CRUD, members, ownership transfer API | spaces & library-member API | S4 |
| `server/src/controllers/library.controller.ts`, `server/src/dtos/library.dto.ts`, `server/src/services/library.service.ts` | external-library member endpoints, `uploadPath`, `GET /libraries/shared` | spaces & library-member API | S4 |
| `server/src/{controllers/asset.controller.ts,dtos/asset.dto.ts,services/asset.service.ts,repositories/asset.repository.ts}` | `POST /assets/move` (live-pair/stack expansion, target rules, crash-safe relocation) | move API | S4 |
| `server/src/{dtos/asset-media.dto.ts,services/asset-media.service.ts}` | upload target resolution (explicit spaceId → preference → personal) | upload target | S4 |
| `server/src/{dtos/user-preferences.dto.ts,types.ts,utils/preferences.ts}` | `sharedLibraries` preference block (default upload target, timeline toggles) | preferences | S4 |
| `server/src/services/user.service.ts` | user-deletion pre-step: transfer/delete owned spaces, reassign ownerId, inline relocation, re-queue face detection | lifecycle §8 | S4 |
| `server/src/database.ts` | adds `uploadPath` to `Library` type | bugfix (type gap from S1) | S4 |
| `server/src/{services,sync.repository}.ts` | shared-space/library sync streams, membership backfill, audit removals | sync I5, favorites §4 | S6 |
| `server/src/{enum,dtos/sync,database}.ts` | additive sync types and `spaceId` asset DTO field | sync I5 | S6 |
| `server/src/controllers/asset.controller.ts` | full EXIF endpoint | R12 | S7 |
| `server/src/repositories/metadata.repository.ts` | group-aware full exiftool reader | R12 | S7 |
| `server/src/{dtos/search.dto.ts,utils/database.ts,repositories/search.repository.ts,services/search.service.ts}` | scoped rich metadata filters and extension suggestions | R13 | S7 |
