# T0 e2e oracle — fork path-mapping fix
## Root causes
- (a1) world.ts never sent sidecar bytes: server writes `<orig>.xmp` only from sidecarData → template-on failed at first sidecar asset.
- (a2) disk.ts `expectedUploadPath` appended filename twice (`…/f/f`) and nested by client `originalFileName`, but template-off originals nest by stored uuid basename → now `basename(originalPath)`, single append.
- (a3) auditDisk 400s = getAsset 400 ('Asset not found', asset.service.ts:205) cascading from a silent bad upload id; `requireAssetId` now fails loudly at the true site.
- (b) integrity.e2e-spec `docker exec`s files into `/data/upload/…`, but the fork stack serves `/fork-data` → all detections read zero. Fixed in docs: upstream specs run on default compose only.
## Files changed
- `e2e/.../fork/world.ts`: sidecarData upload in `uploadFixture`, `requireAssetId` guard (incl. live-photo uploads).
- `e2e/.../fork/disk.ts`: `containerMediaRoot`/`containerTestAssetRoot` constants, fixed `expectedUploadPath`, `toHostPath` on constants.
- `TESTING.md` §§3,4,6,8: media-root mapping, basename rule, upstream-tier default-stack constraint.
## Self-check
- tsc: world.ts/disk.ts clean (21 errors pre-existing in T1-owned specs, SDK type drift). eslint: world.ts clean; disk.ts 4 pre-existing auditDisk violations (verified at baseline).
- e2e: NOT RUN (no Docker in sandbox).
## Host verification needed
- Fork stack `run.sh e2e-api`: world.e2e-spec (the 4 failures); report which tracked id 400s if (a3) persists.
- Default stack `upstream` tier (NO fork override): integrity.e2e-spec (the 13 failures).
- T1: 6 `expectedUploadPath(…, originalFileName)` call sites (moves, spaces, external-libs, lifecycle) must pass `basename(originalPath)`.
## BUG:
- None confirmed in product code (storageKey/sidecar-migration/duplicate handling all match upstream semantics).
