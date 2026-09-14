# S1 — Schema & migrations

Depends on: S0 · Reads: DECISIONS §1, §3, §4, §7, §9 · CODEMAP §C (tables), §F (audit/updateId), §G.

## Goal
All new tables/columns/constraints/triggers in place, migration generated and reviewed. No behaviour yet.

## Tasks
Copy conventions from the closest existing table (album ≈ space, album_user ≈ member, album_asset_audit ≈ asset audit).
1. `server/src/schema/tables/shared-space.table.ts` → `shared_space`:
   id (uuid pk, same default as album), name text not null, description text not null default '',
   storageLabel text not null unique, createdById uuid FK user ON DELETE SET NULL nullable,
   thumbnailAssetId uuid FK asset ON DELETE SET NULL nullable, createdAt, updatedAt, updateId (uuid v7 +
   updated-at trigger exactly like album).
2. `shared-space-member.table.ts` → `shared_space_member`: spaceId FK CASCADE, userId FK user CASCADE,
   role enum `shared_space_role` ('owner','contributor'), showInTimeline bool not null default true,
   createdAt, updatedAt, updateId, createId (like album_user; used for sync backfill). PK (spaceId,userId).
   Partial unique index: one `owner` per spaceId.
3. `library-member.table.ts` → `library_member`: libraryId FK library CASCADE, userId FK user CASCADE,
   showInTimeline bool default true, createdAt, updatedAt, updateId, createId. PK (libraryId,userId).
4. `library` table: add `uploadPath text null`.
5. `asset` table: add `spaceId uuid null` FK shared_space ON DELETE SET NULL; index on spaceId (and a
   composite mirroring whatever index upstream has on (ownerId, <timeline date col>), with spaceId);
   CHECK constraint `asset_space_library_exclusive`: `"spaceId" IS NULL OR "libraryId" IS NULL` (I1).
6. `asset-relocation.table.ts` → `asset_relocation`: assetId uuid pk FK asset CASCADE, requestedAt timestamptz
   default now(), requestedById uuid null, attempts int not null default 0, lastError text null.
7. Audit tables + triggers (mirror album_* audit designs exactly, including updateId/uuid v7 ids):
   - `shared_space_audit` (spaceId, userId) — on space delete, one row per member (like album_audit).
   - `shared_space_member_audit` (spaceId, userId) — on member delete.
   - `shared_space_asset_audit` (spaceId, assetId) — trigger on asset DELETE where old.spaceId not null, AND on
     asset UPDATE where old.spaceId is not null and old.spaceId is distinct from new.spaceId.
   - `library_member_audit` (libraryId, userId) — on member delete.
   - `library_asset_audit` (libraryId, assetId) — same two triggers keyed on libraryId.
   Register cleanup of these audit tables in the existing audit cleanup job list if it's table-driven.
8. Register all tables/enums/functions/triggers in `server/src/schema/index.ts`.
9. Generate migration: `cd server && pnpm run migrations:generate` → review; hand-edit if the generator missed
   the CHECK, partial index, or triggers. Name it `<ts>-SharedLibraries.ts`.
   Add at the top of `up()`: fail with message `User storage label "shared" is reserved by the shared-libraries fork;
   rename it before upgrading` if any `user.storageLabel = 'shared'`.
10. Regenerate SQL docs `mise //server:sql` only if queries changed (they shouldn't in S1).

## Tests
- Medium test (if Docker available per S0): migration applies on empty DB; CHECK rejects both ids set; asset spaceId
  update inserts a `shared_space_asset_audit` row; deleting asset in a space inserts one.

## Self-check
`cd server && pnpm run check && pnpm run lint`; `pnpm run migrations:generate` a second time produces no new diff.

## Verify
1. `cd server && pnpm run check` 2. `cd server && pnpm run lint` 3. `cd server && pnpm run test`
4. (Docker) `cd server && pnpm run test:medium -- <new schema spec path>`

## Review focus (orchestrator)
Migration file; trigger SQL; CHECK; FK delete behaviours.

## Done when
Migration + tables committed, re-generate produces no drift, tests green (except KNOWN).
