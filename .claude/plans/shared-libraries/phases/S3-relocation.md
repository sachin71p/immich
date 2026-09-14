# S3 — Storage keys & relocation engine

Depends on: S1 · Parallel-safe with S2 · Reads: DECISIONS §3 (I3, I4, I6), §7 · CODEMAP §C, §E, §G.

## Goal
Given any asset, compute where every one of its files should live for its current container (§7) and move them
crash-safely. Guard external-library scanning against in-flight moves. No API yet (S4 calls this).

## Tasks
1. Storage key (StorageCore): add `getStorageKey(asset: { ownerId: string; spaceId?: string | null })` →
   `shared/${spaceId}` or `ownerId`. Use it instead of raw ownerId in `getImagePath`, `getEncodedVideoPath`,
   `getAndroidMotionPath` (and any other asset-file builder). Make sure every caller's asset object includes
   `spaceId` (add `spaceId` to the relevant repository selects). Personal paths must be byte-identical to upstream.
2. Storage template root hook (`storage-template.service.ts` ~L276): if asset.spaceId → root
   `library/shared/<space.storageLabel>`; else upstream. Load space storageLabel in the template migration query.
   Expose the per-asset template move as a public method (`moveAssetToTemplatePath(assetId)` or reuse existing name)
   so the relocation engine can call it. Confirm upstream template skips external (libraryId) assets; keep that.
3. New `server/src/services/asset-relocation.service.ts` (+ repository methods in a new
   `asset-relocation.repository.ts` if needed):
   - Job `AssetRelocate { id }` on `QueueName.StorageTemplateMigration` (reuse queue; no new admin UI).
     Algorithm (idempotent):
     a. Load asset (+ files, livePhotoVideoId, spaceId, libraryId, owner storageLabel, space storageLabel,
        library uploadPath, template config).
     b. Original + sidecar:
        - external (libraryId set): if originalPath is not inside any importPath → target
          `<uploadPath>/<rendered template or originalFileName>` with de-dup suffix; move original then sidecar.
        - personal/space, template ON → call the template per-asset move (task 2).
        - personal/space, template OFF → if not already under `upload/<K>/` → `upload/<K>/xx/yy/<basename>` via
          `StorageCore.getNestedPath`.
     c. Derived files: for every `asset_file` row (Thumbnail, Preview, FullSize incl. edited, EncodedVideo) compute
        the builder path with the storage key; if different → `StorageCore.moveFile` with pathType = file type; update row.
     d. If asset has a live motion asset: relocate it too (same job, recursion depth 1).
     e. On success delete the `asset_relocation` row. On error: increment attempts, store lastError, rethrow.
   - Job `AssetRelocateQueueAll`: queue `AssetRelocate` for every `asset_relocation` row. Trigger it on server
     bootstrap (after migrations) and nightly (reuse the nightly jobs hook).
   - Public helper `requestRelocation(assetIds, requestedById, trx?)`: upsert `asset_relocation` rows (in the
     caller's transaction) and queue jobs after commit.
4. External-library guards (`library.service.ts`, `asset.repository.ts`):
   - `LibraryRemoveAsset` (unlink): skip if the path equals `move_history.oldPath` or belongs to an asset with a pending
     `asset_relocation` row.
   - `LibrarySyncFiles` / `filterNewExternalAssetPaths`: skip paths that equal any `move_history.newPath` or the
     originalPath of an asset with a pending relocation.
   - `detectOfflineExternalAssets`: exclude assets with a pending relocation (`NOT EXISTS asset_relocation`).
5. Library `uploadPath` validation helper (used by S4): absolute, inside one importPath, exists, writable
   (`fs.access W_OK`), not an Immich media folder.
6. Reserved storage label: user DTO/service rejects `shared` (case-insensitive) with 400.

## Tests (unit, with repository mocks like existing storage-template specs)
- Path matrix: {personal, space, external} × {template ON, OFF} for original, sidecar, thumbnail, preview, fullsize,
  encoded video → expected paths per DECISIONS §7; personal == upstream.
- Relocation idempotent (second run moves nothing); partial failure leaves the relocation row with attempts=1.
- Live motion asset relocated with its still.
- Guards: unlink of a path in move_history does not delete the asset; new-file scan ignores a pending move target;
  offline detection ignores pending relocations.
- Reserved label rejected.

## Self-check
`cd server && pnpm run check && pnpm run lint && pnpm exec vitest src/services/asset-relocation src/services/storage-template src/services/library src/cores`
Then `mise //server:sql`.

## Verify
1. `cd server && pnpm run check` 2. `pnpm run lint` 3. `pnpm run test` 4. (Docker) `pnpm run test:medium`

## Review focus (orchestrator)
Order of DB update vs file move; guard conditions; that personal paths are unchanged; recursion on motion asset.
