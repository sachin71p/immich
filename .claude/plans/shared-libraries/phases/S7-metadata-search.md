# S7 — Full metadata endpoint & extended search filters

Depends on: S5 · Reads: DECISIONS §2 (R12, R13), §10 · CODEMAP §D (search rows), §F (SyncAssetExifV1 field list = exif columns) · handoff S5.

## Goal
R12: any viewer of an asset can read its complete metadata. R13: search/filter by rich metadata within the scope.

## Tasks
1. `GET /assets/:id/exif/full` (permission AssetRead; name chosen to avoid upstream `/assets/:id/metadata` KV API):
   read original (and sidecar if present) with the exiftool wrapper the server already uses for metadata extraction
   (find it in `metadata.repository.ts`/`metadata.service.ts`); return `{ groups: Record<string, Record<string, unknown>> }`
   grouped by exiftool family-1 group (EXIF, XMP, MakerNotes, Composite, File, QuickTime, …). Strip binary blobs
   (replace with `{ binary: true, bytes }`). Offline external asset → 404 with reason.
2. Extended filters on metadata search (legacy DTO + V3 DTO + both builders in `database.ts`) and statistics:
   `isoMin/isoMax`, `fNumberMin/fNumberMax`, `focalLengthMin/focalLengthMax`, `exposureTimeMin/exposureTimeMax`
   (seconds; exif stores text like "1/125" — compare with a SQL expression converting fractions; if impractical, skip
   and note), `fileSizeMin/fileSizeMax` (bytes), `widthMin/heightMin`, `fileExtensions[]`, `mimeTypes[]`,
   `projectionType`, `hasLocation` (bool), `orientation`, `fpsMin/fpsMax`. Reuse existing filters (make, model,
   lensModel, city, country, rating, dates, type, isFavorite, personIds, tagIds) as-is.
3. Suggestions endpoint: add `lensModel` if missing and `fileExtension` suggestions, scoped (S5 helper).
4. Regenerate OpenAPI + SDKs + SQL docs.

## Tests
- Full exif endpoint: access matrix (owner, space member, album member ✓; stranger ✗); binary stripping; sidecar merge.
- Each new filter narrows results correctly on seeded exif rows; combined filters AND together; scope respected.

## Self-check / Verify
1. `cd server && pnpm run check` 2. `pnpm run lint` 3. `pnpm exec vitest src/services/search src/services/asset` 4. `pnpm run test`
5. (Docker) `pnpm run test:medium`
