# S4 — Spaces & library-member API, move API, upload target, lifecycle

Depends on: S2, S3 · Reads: DECISIONS §4, §5, §6, §8, §9 · CODEMAP §A, §E, §G · handoff S2, S3.

## Goal
Everything a client needs to manage shared libraries and move assets, plus lifecycle hooks. Visibility in
listings comes in S5 (so tests here assert DB state + access, not timeline contents).

## Tasks
1. New `shared-space.controller.ts`, `shared-space.service.ts`, `shared-space.repository.ts`, `dtos/shared-space.dto.ts`
   (template: activity/album files). Endpoints (all `@Authenticated({ permission })` with §5 permissions):
   - `POST /shared-spaces` {name, description?} → create space + owner member; storageLabel = unique slug of name.
   - `GET /shared-spaces` → spaces I belong to: id, name, description, role, memberCount, assetCount,
     showInTimeline, thumbnailAssetId, createdAt, updatedAt.
   - `GET /shared-spaces/:id`, `PATCH /shared-spaces/:id` {name?, description?, thumbnailAssetId?} (member).
   - `DELETE /shared-spaces/:id` (owner) → lifecycle §8 (single transaction: spaceId=NULL for its assets +
     `requestRelocation`; then delete space).
   - `GET /shared-spaces/:id/members`; `POST /shared-spaces/:id/members` {userIds[]} (member; users must exist, not
     already members); `DELETE /shared-spaces/:id/members/:userId` (member removing a contributor, or self = leave;
     owner cannot be removed/leave); `PUT /shared-spaces/:id/owner` {userId} (owner → transfer);
     `PATCH /shared-spaces/:id/members/me` {showInTimeline}.
2. External library members (extend library controller/service; admin-only like upstream except `/me` routes):
   - `GET /libraries/:id/members`, `POST /libraries/:id/members` {userIds[]}, `DELETE /libraries/:id/members/:userId` (admin).
   - `PATCH /libraries/:id` accepts `uploadPath` (admin; validated with S3 helper; null clears).
   - `GET /libraries/shared` (any user) → libraries I own or am a member of: id, name, ownerId, isOwner,
     showInTimeline, assetCount, hasUploadPath.
   - `PATCH /libraries/:id/members/me` {showInTimeline} (member) — for owners store in user pref
     `sharedLibraries.hiddenOwnedLibraryIds`.
3. User preferences (find `UserPreferences` DTO/defaults in server/src): add `sharedLibraries: { defaultUploadTarget,
   showPersonalInTimeline, hiddenOwnedLibraryIds }` with defaults per §9; validation (spaceId must be a membership).
4. Move API: `POST /assets/move` {assetIds[] (max 1000), target: {type: 'personal'|'space'|'library', id?}}
   → `{ results: [{ id, status: 'moved'|'noop'|'error', reason? }] }`. Implement §6 exactly:
   require `AssetMove` on sources; expand live pairs + stacks; pre-check target rules, Locked, duplicate checksum
   (look at asset table unique indexes); in one transaction set spaceId/libraryId/isExternal, call
   `requestRelocation`; after commit emit the upstream asset-update event(s) so websockets/sync notice.
5. Upload target: `AssetMediaCreateDto` gets optional `spaceId`. In the upload service: resolve target (explicit →
   preference → personal); require membership; set `spaceId` on insert; after insert call `requestRelocation`
   (idempotent; files are moved once the template/metadata flow finishes — ensure relocation runs after
   `AssetMetadataExtracted` for space assets, e.g. queue from the same event handler as template single-migration).
   Duplicate upload (same owner checksum) keeps upstream response.
6. Lifecycle hooks:
   - User delete job (`user.service.ts` UserDelete): pre-step per §8 (transfer/delete owned spaces, reassign
     ownerId for space + foreign-library assets, inline relocation, re-queue face detection for reassigned assets;
     throw on failure before any upstream deletion).
   - Library deletion: upstream behaviour; also delete `library_member` rows (FK cascade covers it).
7. Regenerate OpenAPI + TS SDK + Dart (`mise //server:sync-open-api && mise :open-api-typescript && mise :open-api-dart`)
   and SQL docs.

## Tests
Unit (service specs with mocks) + medium where Docker exists:
- CRUD + role matrix from §4 (contributor cannot delete space / transfer; owner cannot leave).
- Delete space → assets have spaceId NULL, relocation rows exist.
- Move matrix: personal→space ✓; space→personal own ✓ / other's ✗; space→space needs both memberships;
  →library needs uploadPath; live pair and stack expansion; Locked ✗; noop; duplicate ✗.
- Upload with spaceId (member ✓, non-member 403), preference fallback, stale preference → personal.
- User deletion pre-step: contributions survive with new ownerId; owned space transferred; relocation failure aborts.

## Self-check
`cd server && pnpm run check && pnpm run lint && pnpm exec vitest src/services/shared-space src/services/asset src/services/user src/services/library src/services/asset-media`

## Verify
1. `cd server && pnpm run check` 2. `pnpm run lint` 3. `pnpm run test` 4. (Docker) `pnpm run test:medium`
5. `git diff --stat -- open-api packages/sdk mobile/openapi` shows regenerated clients.

## Review focus (orchestrator)
Move transaction + expansion; user-deletion pre-step ordering; upload target resolution.
