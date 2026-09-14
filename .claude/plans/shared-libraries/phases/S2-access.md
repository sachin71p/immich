# S2 — Access control, favorites, album permissions

Depends on: S1 · Parallel-safe with S3 (disjoint files) · Reads: DECISIONS §3 (I7), §4, §5 · CODEMAP §A, §B.

## Goal
Authorization matches DECISIONS §4 for assets in spaces and shared external libraries, shared favorites (R16),
and album add/remove by any member (R11). No new endpoints yet (S4 adds them).

## Tasks
1. `Permission` enum: add the values in DECISIONS §5 (string values exactly as listed).
2. `access.repository.ts` — new methods (new code block, same style):
   - `asset.checkSpaceAccess(userId, assetIds)` → assets whose `spaceId` is a space where userId is a member.
   - `asset.checkLibraryMemberAccess(userId, assetIds)` → assets whose `libraryId` is a library the user owns or is a
     `library_member` of. (Owner of the library already has owner-access via ownerId for upstream assets; include
     anyway for assets contributed by members.)
   - `asset.checkAlbumMemberAccess(userId, assetIds)` if the existing album check filters by role — any role counts.
   - `space.checkMemberAccess(userId, spaceIds)`, `space.checkOwnerAccess(userId, spaceIds)`.
   - `library.checkMemberAccess(userId, libraryIds)` (owner or member).
   - Narrow `asset.checkOwnerAccess`: add `AND (asset.spaceId IS NULL OR EXISTS member(spaceId, userId))`.
3. `access.ts` branches (keep upstream branches, append ours):
   - AssetRead/View/Download/Share/Update/Delete/Copy/EditCreate/EditDelete/FileRead: + space member, + library member.
   - `AssetFavorite`: owner | space member | library member | album member (any role).
   - `AssetMove`: owner | space member | library member (container access; target rules are checked in S4).
   - AlbumAssetCreate / AlbumAssetDelete: owner | any shared album user (drop Editor-only restriction).
   - `asset.util.ts` album-removal rule (~L81–85): any album member may remove any asset.
   - SharedSpace*: read/update/memberCreate/memberDelete → member; delete → owner. (Member update = self prefs; S4 enforces.)
   - LibraryMember*: admin only (mirror library endpoints).
4. Album role update (`album.service.ts` ~L343 + controller for `user/me` if separate): reject changing own role and
   reject setting role `owner` (400). Leaving an album (removing self) stays allowed.
5. Favorites split: in `asset.service.ts` update + bulk update: if the DTO's only defined field is `isFavorite` →
   `requireAccess(AssetFavorite)`, else upstream `AssetUpdate`. Controller permission decorators stay upstream
   (API keys with `asset.update` keep working); document that `asset.favorite` scope also suffices by adding it
   to the decorator if the decorator supports any-of, otherwise leave.
6. I7: in asset update paths, reject setting `visibility = Locked` for assets with spaceId or libraryId (400).

## Tests (unit, next to existing access/asset/album specs)
- Space member can read/update/delete/favorite an asset owned by another member; non-member cannot.
- Removed contributor loses access to own asset left in the space.
- Library member can read/update; non-member cannot.
- Album viewer can add + remove assets and favorite album assets but cannot update other fields.
- Album user cannot change own role; cannot set owner role.
- Favorite-only bulk update by album member succeeds; mixed update (isFavorite + description) fails.
- Locked visibility rejected for space asset.

## Self-check
`cd server && pnpm run check && pnpm run lint && pnpm exec vitest src/utils/access src/services/asset.service src/services/album.service`
(adjust to actual spec file paths). Regenerate SQL docs `mise //server:sql`. Regenerate OpenAPI (`mise //server:sync-open-api`) since Permission enum changed.

## Verify
1. `cd server && pnpm run check` 2. `pnpm run lint` 3. `pnpm run test` 4. (Docker) `pnpm run test:medium` (access specs)

## Review focus (orchestrator)
`access.ts` diff, `access.repository.ts` new SQL, narrowing of checkOwnerAccess, favorites split logic.
