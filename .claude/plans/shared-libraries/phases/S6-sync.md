# S6 — Sync stream for spaces & shared external libraries

Depends on: S5 · Reads: DECISIONS §3 (I5), §4 (favorites in sync), §10 · CODEMAP §F · handoff S1, S5.

## Goal
Native Apple clients can mirror every asset they can see (own, partner, album, space, shared library) via
`POST /sync/stream`, including removals when an asset leaves a container or the user leaves it.

## Tasks (mirror the AlbumAssets V2 + backfill implementation exactly; copy, rename, adapt)
1. Enums: `SyncRequestType` += `SharedSpacesV1`, `SharedSpaceMembersV1`, `SharedSpaceAssetsV1`,
   `SharedSpaceAssetExifsV1`, `SharedLibrariesV1`, `SharedLibraryAssetsV1`, `SharedLibraryAssetExifsV1`.
   `SyncEntityType` += `SharedSpaceV1`, `SharedSpaceDeleteV1`, `SharedSpaceMemberV1`, `SharedSpaceMemberBackfillV1`,
   `SharedSpaceMemberDeleteV1`, `SharedSpaceAssetCreateV1`, `SharedSpaceAssetUpdateV1`, `SharedSpaceAssetBackfillV1`,
   `SharedSpaceAssetRemoveV1`, `SharedSpaceAssetExifCreateV1`, `SharedSpaceAssetExifUpdateV1`,
   `SharedSpaceAssetExifBackfillV1`, and the same set with `SharedLibrary…` (library entity: `SharedLibraryV1`,
   `SharedLibraryDeleteV1` = membership lost).
2. Semantics:
   - Space/library asset streams exclude assets owned by the requesting user (they arrive via `AssetsV2`, which gains an
     additive `spaceId` field on SyncAssetV1/V2 DTOs).
   - `…AssetRemoveV1` comes from `shared_space_asset_audit` / `library_asset_audit` (asset deleted or moved out).
   - Membership removal → `SharedSpaceDeleteV1` / `SharedLibraryDeleteV1` for that user (from member audit tables);
     clients drop all assets of that container.
   - New membership → backfill using member `createId` like album backfill.
   - `isFavorite` real value in space/library/album streams.
3. Add to `SYNC_TYPES_ORDER` after the album types; register ack handling and reset.
4. Before changing SyncAssetV1/V2 DTOs: confirm the Flutter client tolerates unknown fields (check how
   `mobile/lib` decodes SyncAssetV2 — look for its fromJson/decoder only). If it would break, instead add
   `SyncAssetV3` + `AssetsV3` request type and leave V1/V2 untouched; note the choice in handoff.
5. Regenerate OpenAPI + SDKs + SQL docs.

## Tests (medium, copy the album-asset sync spec structure)
- Space asset created by B appears for A as SharedSpaceAssetCreateV1; update (favorite) → UpdateV1 with real isFavorite.
- Move out of space → RemoveV1 for A; B receives AssetV2 update with spaceId null.
- A joins space later → backfill of existing assets, then `complete` ack prevents resend.
- A removed from space → SharedSpaceDeleteV1; no further space events.
- Library member equivalents. Own contributions never appear in space streams.
- Upstream sync specs still pass unchanged.

## Self-check
`cd server && pnpm run check && pnpm run lint && pnpm exec vitest src/services/sync`

## Verify
1. `cd server && pnpm run check` 2. `pnpm run lint` 3. `pnpm run test` 4. (Docker) `pnpm run test:medium -- test/medium/specs/sync`

## Review focus (orchestrator)
Checkpoint/ack correctness for the new types; audit-trigger-driven removals; DTO compatibility decision.
