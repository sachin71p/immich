# S5 — Visibility scope across queries

Depends on: S4 · Reads: DECISIONS §9, §10, §11 · CODEMAP §D, §G · handoff S4.

## Goal
Every listing/search/aggregation includes exactly the containers DECISIONS §10 says, and supports the explicit
container filter. Upstream behaviour for a user with no spaces/libraries/prefs must be unchanged (except the
documented partner/external change).

## Tasks
1. Types: `ContainerScope { personalUserIds: string[]; spaceIds: string[]; libraryIds: string[] }` in a new
   `server/src/utils/container-scope.ts`, plus Kysely helper `withContainerScope(eb, scope)` implementing the §10
   expression (handle empty arrays → false branches, not SQL errors).
2. `ContainerScopeService` (new, or methods on shared-space service): `resolve(auth, { purpose: 'timeline'|'manage'|'locked',
   withPartners?: boolean, filter?: { spaceId?, libraryId?, personalOnly? } })`. Explicit filter → requireAccess and
   return that single container. Reuse `getMyPartnerIds` for partners.
3. Replace owner scoping at every site in CODEMAP §D except People/Albums/Tags. Pattern: keep the repository
   parameter list upstream-compatible where practical (add an optional `scope` param; if present it replaces the
   `ownerId = any(userIds)` predicate). Sites: timeline buckets/bucket; search legacy + V3 builders; suggestions
   (`getExifField`); assets-by-city; map markers; memories + getByDayOfYear; statistics; calendar heatmap; explore
   (city ids, recently created); trash restore/empty/restoreAll (purpose `manage`); archive & favorites views (they
   are timeline requests with visibility/isFavorite: purpose `manage` for archive, `timeline` for favorites).
   Locked visibility → purpose `locked`.
4. DTOs: add optional `spaceId`, `libraryId`, `personalOnly` to `TimeBucketDto` and the search DTOs (legacy + V3),
   map markers, and statistics DTOs; validate mutual exclusion (400). Upstream `userId` (partner timeline) keeps
   upstream meaning and ignores prefs.
5. `AssetResponseDto`: add optional `spaceId` (additive; I5). Sync `isFavorite` fix for album-asset queries
   (DECISIONS §4 last bullet) — update `sync.repository.ts` album asset selects; leave partner selects.
6. Regenerate SQL docs + OpenAPI + SDKs.

## Tests
- Scope resolution unit tests for each purpose and filter (incl. empty memberships, stale filter → 403).
- Medium (Docker): seed users A, B; space S (A owner, B contributor); library L shared to B; assets in each container:
  B's timeline shows personal(B)+S+L; toggling showInTimeline hides S; `spaceId=S` shows only S;
  search/suggestions/map/statistics respect the same; trash for B lists trashed S assets; empty-trash by B removes
  trashed S assets but not A's personal trash; favorites view for B shows A's favorited asset in S;
  a user with no spaces sees exactly upstream results (snapshot vs. upstream query on same seed).

## Self-check
`cd server && pnpm run check && pnpm run lint && pnpm exec vitest src/utils/container-scope src/services/timeline src/services/search src/services/map src/services/trash src/services/memory`

## Verify
1. `cd server && pnpm run check` 2. `pnpm run lint` 3. `pnpm run test` 4. (Docker) `pnpm run test:medium`

## Review focus (orchestrator)
`withContainerScope` SQL; every replaced predicate (use `git diff server/src/repositories server/src/database.ts`);
trash empty semantics; performance: EXPLAIN a timeline bucket query on seeded data should use the spaceId index.
