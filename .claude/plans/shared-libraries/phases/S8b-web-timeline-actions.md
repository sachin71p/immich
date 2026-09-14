# S8b — Web: library switcher, move action, favorites & album UI, upload target

Depends on: S8a · Parallel-safe with S8c · Reads: DECISIONS §4, §6, §9 · CODEMAP §H · handoff S8a.

## Tasks
1. Library switcher on `/photos` (Apple-style segmented/dropdown in the timeline header): "All (my timeline sources)",
   "Personal", each space, each shared library → sets TimelineManager options `{}` / `{ personalOnly: true }` /
   `{ spaceId }` / `{ libraryId }`; remember last choice in local storage.
2. Container badge on thumbnails and in the viewer for assets with `spaceId`/`libraryId` (small icon + tooltip with
   container name from the S8a store).
3. "Move to…" action: `web/src/lib/components/timeline/actions/MoveToLibraryAction.svelte` + viewer action; modal lists
   allowed targets (Personal only if every selected asset is mine; my spaces; libraries with upload path); calls
   `POST /assets/move`; toast summary moved/noop/errors (with reasons); refresh timeline buckets.
4. Permission-aware UI: compute `canEdit` / `canFavorite` from asset.ownerId, asset.spaceId (my spaces), asset.libraryId
   (my libraries) and album context; enable favorite/edit/delete/archive buttons accordingly (search for existing
   `isOwner` gates in actions and the viewer nav bar and extend them).
5. Albums: remove Editor-only gating for add/remove in album UI; album members of any role can add/remove.
6. Upload: when uploading from a space page, pass `spaceId`; elsewhere omit (server applies preference).
   `file-uploader.ts` builds the request (~L203).

## Tests
Unit tests for the permission helper and the move-target computation; component test for the move modal.

## Self-check / Verify
`cd web && pnpm run check:typescript && pnpm run check:svelte && pnpm run lint && pnpm run test --run`
