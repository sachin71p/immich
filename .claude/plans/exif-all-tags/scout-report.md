# Scout Report: EXIF Raw Tags Persistence

## 1. Metadata Extraction Flow & Insertion Point

**File:** `/Users/spatel/workspace/github/projects/immich/server/src/services/metadata.service.ts`

### `handleQueueMetadataExtraction` (lines 216-227)
- **What it does:** Queues individual asset extraction jobs for the metadata queue
- **Key method:** `assetJobRepository.streamForMetadataExtraction(force)`
- **force parameter behavior:**
  - `force: false` (default): Filters assets where `asset_job_status.metadataExtractedAt IS NULL` — only "Missing" assets
  - `force: true`: No filter — processes "All" assets (used in admin UI "All" button)
- **Source query:** Lines 374-379 in `asset-job.repository.ts`

### `handleMetadataExtraction` (lines 229-427)
**Exact flow for readTags and upsertExif:**

1. **Line 242:** `this.getExifTags(asset)` called — returns `{ tags, audio, video, packets, format }`
2. **Lines 584-640:** Inside `getExifTags()`:
   - Line 588: `this.metadataRepository.readTags(asset.originalPath)` — reads main file tags
   - Line 589: `sidecarFile ? this.metadataRepository.readTags(sidecarFile.path) : null` — reads sidecar tags
   - Line 634: Merged result: `{ ...mediaTags, ...videoResult?.tags, ...sidecarTags }`
3. **Lines 278-324:** `exifData` object built (Insertable<AssetExifTable>) with all extracted fields
4. **Lines 393-399:** `this.assetRepository.upsertExif({...})` called with:
   - `exif: exifData`
   - `audio: audioData`
   - `video: videoData`
   - `keyframes: keyframeData`
   - `lockedPropertiesBehavior: 'skip'`

**Variables in scope at upsertExif point:**
- `asset.id` — asset UUID
- `asset.originalPath` — original file path
- `registeredSidecar.path` — sidecar path (if present)
- `asset.type` — AssetType.Image | AssetType.Video
- `exifResult` object containing all tag data
- `stats` — file stats (size, mtime, etc.)
- `isSidecarInTransit` — boolean flag for sidecar availability

**Best insertion point for raw tags read:**
After line 634 in `getExifTags()` or before the upsertExif call (line 393). The raw tags should be read in parallel with `readTags`:
```typescript
// In getExifTags, add in parallel:
const [mediaTags, sidecarTags, videoResult, rawMediaTags, rawSidecarTags] = await Promise.all([
  this.metadataRepository.readTags(asset.originalPath),
  sidecarFile ? this.metadataRepository.readTags(sidecarFile.path) : null,
  shouldProbe ? this.getVideoTags(asset.originalPath) : null,
  this.metadataRepository.readFullTags(asset.originalPath),  // <-- NEW
  sidecarFile ? this.metadataRepository.readFullTags(sidecarFile.path) : null,  // <-- NEW
]);
```

Then pass the raw tags to upsertExif and handle insertion of a new `asset_exif_raw` table row.

---

## 2. Table Registration & Schema Pattern

**File:** `/Users/spatel/workspace/github/projects/immich/server/src/schema/index.ts`

### How a new table gets registered:
1. Create table class in `server/src/schema/tables/asset-exif-raw.table.ts` (new file)
2. Import the class in `schema/index.ts` (line 49 example: `AssetExifTable`)
3. Add to `ImmichDatabase.tables` array (line 148 example)
4. Add to `DB` interface (line 276 example: `asset_exif: AssetExifTable`)

### Example decorators from `asset-exif.table.ts` (lines 15-121):
```typescript
@Table('asset_exif')
@Index({
  name: 'IDX_asset_exif_gist_earthcoord',
  using: 'gist',
  expression: 'll_to_earth_public(latitude, longitude)',
})
@UpdatedAtTrigger('asset_exif_updatedAt')
export class AssetExifTable {
  @ForeignKeyColumn(() => AssetTable, { onDelete: 'CASCADE', primary: true })
  assetId!: string;
  
  @Column({ type: 'character varying', array: true, nullable: true })
  tags!: string[] | null;
  
  @UpdateDateColumn({ default: () => 'clock_timestamp()' })
  updatedAt!: Generated<Timestamp>;

  @UpdateIdColumn({ index: true })
  updateId!: Generated<string>;
}
```

### Example JSONB column pattern from `asset-metadata.table.ts` (lines 24-45):
```typescript
@UpdatedAtTrigger('asset_metadata_updated_at')
@Table('asset_metadata')
@AfterDeleteTrigger({...})
export class AssetMetadataTable {
  @ForeignKeyColumn(() => AssetTable, {
    onUpdate: 'CASCADE',
    onDelete: 'CASCADE',
    primary: true,
    index: false,
  })
  assetId!: string;

  @PrimaryColumn({ type: 'character varying' })
  key!: AssetMetadataKey | string;

  @Column({ type: 'jsonb' })
  value!: Record<string, unknown>;

  @UpdateIdColumn({ index: true })
  updateId!: Generated<string>;

  @UpdateDateColumn({ index: true })
  updatedAt!: Generated<Timestamp>;
}
```

**For asset_exif_raw table with JSONB:**
- Use `@ForeignKeyColumn(() => AssetTable, { onDelete: 'CASCADE', primary: true })` for assetId
- Use `@Column({ type: 'jsonb', nullable: true })` for rawTags column
- Include `@UpdatedAtTrigger` and `@UpdateIdColumn` for sync tracking
- No need for @UpdateDateColumn — asset_exif_updatedAt trigger will cover it (same asset row)

---

## 3. Migrations: Structure & Recent Fork Examples

**File:** `/Users/spatel/workspace/github/projects/immich/server/src/schema/migrations/ORDER` (tail shows order)

Last 4 migration files:
1. `1789426700279-SharedLibraries.ts` (24490 bytes)
2. `1789426700280-SpacePeople.ts` (2938 bytes)
3. `1789426700281-SharedSpaceClusterGroupIdIndex.ts` (537 bytes)
4. Plus 96 prior migrations

**ORDER file format (tail, lines 97-99):**
```
1789426700279-SharedLibraries
1789426700280-SpacePeople
1789426700281-SharedSpaceClusterGroupIdIndex
```
(Just migration name without timestamp or .ts extension; runs in listed order)

### Most recent fork migration template: `1789426700281-SharedSpaceClusterGroupIdIndex.ts`
```typescript
import { Kysely, sql } from 'kysely';

// fork: shared-libraries - 1789426700280-SpacePeople.ts added shared_space.clusterGroupId and its
// FK but, unlike person.spaceId in that same migration, never created the matching index.
export async function up(db: Kysely<any>): Promise<void> {
  await sql`CREATE INDEX "shared_space_clusterGroupId_idx" ON "shared_space" ("clusterGroupId");`.execute(db);
}

export async function down(db: Kysely<any>): Promise<void> {
  await sql`DROP INDEX "shared_space_clusterGroupId_idx";`.execute(db);
}
```

### First 40 lines of `1789426700280-SpacePeople.ts` (template for complex migration):
```typescript
import { Kysely, sql } from 'kysely';

// fork: shared-libraries - space-scoped people (S9).
export async function up(db: Kysely<any>): Promise<void> {
  await sql`ALTER TABLE "person" ADD "spaceId" uuid;`.execute(db);
  await sql`ALTER TABLE "person" ADD CONSTRAINT "person_spaceId_fkey" FOREIGN KEY ("spaceId") REFERENCES "shared_space" ("id") ON UPDATE CASCADE ON DELETE CASCADE;`.execute(db);
  await sql`CREATE INDEX "person_spaceId_idx" ON "person" ("spaceId");`.execute(db);
  await sql`ALTER TABLE "shared_space" ADD "clusterGroupId" uuid;`.execute(db);
  await sql`ALTER TABLE "shared_space" ADD CONSTRAINT "shared_space_clusterGroupId_fkey" FOREIGN KEY ("clusterGroupId") REFERENCES "cluster_group" ("id") ON UPDATE CASCADE ON DELETE SET NULL;`.execute(db);
  await sql`ALTER TABLE "person_audit" ADD "spaceId" uuid;`.execute(db);
  await sql`CREATE OR REPLACE FUNCTION person_delete_audit()
  RETURNS TRIGGER
  LANGUAGE PLPGSQL
  AS $$
    BEGIN
      INSERT INTO person_audit ("personGroupId", "ownerId", "spaceId")
      SELECT "personGroupId", "ownerId", "spaceId"
      FROM OLD;
      RETURN NULL;
    END
  $$;`.execute(db);
  await sql`UPDATE "migration_overrides" SET "value" = '{"type":"function","name":"person_delete_audit","sql":"CREATE OR REPLACE FUNCTION person_delete_audit()\\n  RETURNS TRIGGER\\n  LANGUAGE PLPGSQL\\n  AS $$\\n    BEGIN\\n      INSERT INTO person_audit (\\"personGroupId\\", \\"ownerId\\", \\"spaceId\\")\\n      SELECT \\"personGroupId\\", \\"ownerId\\", \\"spaceId\\"\\n      FROM OLD;\\n      RETURN NULL;\\n    END\\n  $$;"}'::jsonb WHERE "name" = 'function_person_delete_audit';`.execute(db);
}

export async function down(db: Kysely<any>): Promise<void> {
  await sql`CREATE OR REPLACE FUNCTION person_delete_audit()
  RETURNS TRIGGER
  LANGUAGE PLPGSQL
  AS $$
    BEGIN
      INSERT INTO person_audit ("personGroupId", "ownerId")
      SELECT "personGroupId", "ownerId"
      FROM OLD;
      RETURN NULL;
    END
  $$;`.execute(db);
```

**For asset_exif_raw migration:**
```typescript
import { Kysely, sql } from 'kysely';

export async function up(db: Kysely<any>): Promise<void> {
  await sql`CREATE TABLE "asset_exif_raw" (
    "assetId" uuid PRIMARY KEY NOT NULL,
    "rawTags" jsonb,
    "updatedAt" timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
    "updateId" uuid NOT NULL,
    CONSTRAINT "asset_exif_raw_assetId_fkey" FOREIGN KEY ("assetId") REFERENCES "asset" ("id") ON UPDATE CASCADE ON DELETE CASCADE
  );`.execute(db);
  
  await sql`CREATE INDEX "asset_exif_raw_updateId_idx" ON "asset_exif_raw" ("updateId");`.execute(db);
}

export async function down(db: Kysely<any>): Promise<void> {
  await sql`DROP TABLE "asset_exif_raw";`.execute(db);
}
```

---

## 4. Repository: upsertExif Definition & SQL Generation

**File:** `/Users/spatel/workspace/github/projects/immich/server/src/repositories/asset.repository.ts`

### upsertExif method (lines 194-320, simplified view):
```typescript
@GenerateSql({
  params: [
    {
      exif: { dateTimeOriginal: DummyValue.DATE, lockedProperties: ['dateTimeOriginal'] },
      lockedPropertiesBehavior: 'append',
    },
  ],
})
async upsertExif({ exif, audio, video, keyframes, lockedPropertiesBehavior }: UpsertExifOptions): Promise<void> {
  let query = this.db;
  if (audio) {
    (query as any) = this.db.with('audio', (qb) =>
      qb.insertInto('asset_audio')...
    );
  }
  if (video) {
    (query as any) = query.with('video', (qb) =>
      qb.insertInto('asset_video')...
    );
  }
  if (keyframes) {
    (query as any) = query.with('keyframe', (qb) =>
      qb.insertInto('asset_keyframe')...
    );
  }
  
  await query
    .insertInto('asset_exif')
    .values(exif)
    .onConflict((oc) =>
      oc.column('assetId').doUpdateSet((eb) => {
        const updateLocked = <T extends keyof AssetExifTable>(col: T) => eb.ref(`excluded.${col}`);
        const skipLocked = <T extends keyof AssetExifTable>(col: T) =>
          eb.case()
            .when(sql`${col}`, '=', eb.fn.any('asset_exif.lockedProperties'))
            .then(eb.ref(`asset_exif.${col}`))
            .else(eb.ref(`excluded.${col}`))
            .end();
        const ref = lockedPropertiesBehavior === 'skip' ? skipLocked : updateLocked;
        return { /* 40+ column updates */ };
      }),
    )
    .execute();
}
```

The `@GenerateSql` decorator is used to generate SQL files during the build process.

### Generated SQL production:
**Location:** `/Users/spatel/workspace/github/projects/immich/server/src/queries/asset.repository.sql` (lines 3-17)

The generated upsertExif SQL is very basic (only shows dateTimeOriginal) because the actual complex logic is built at runtime via Kysely's QueryBuilder. The @GenerateSql decorator helps track which queries are critical for code generation testing.

**Generated SQL refresh:**
- Script: `pnpm --filter immich migrations:generate` (NOT for upsertExif — migrations only)
- SQL script: `mise //:sql` (runs during CI; root-level mise.toml task)
- Location: `.github/workflows/test.yml` line 832
- **Failure mode:** CI fails with `sql-schema-up-to-date` check if generated SQL files are stale (lines 836-851)
- These are checked into git; if you modify a @GenerateSql decorated method, you must run `mise //:sql` and commit the updated files
- Tests will fail if generated SQL doesn't match the source code

---

## 5. All asset_exif References in Fork Code (Cascade Handling)

All references to `asset_exif` in fork-specific relocation/move/delete/copy code:

| File | Line | Description |
|------|------|-------------|
| `asset-job.repository.ts` | 388 | SELECT for storageTemplateAssetQuery joins asset_exif to get file size and timezone |
| `library.repository.ts` | 160 | leftJoin asset_exif in library query |
| `library.repository.ts` | 177 | SUM(asset_exif.fileSizeInByte) for library usage calculation |
| `stack.repository.ts` | 24-27 | SELECT asset_exif as exifInfo subquery (reads exif data for stack items) |
| `duplicate.repository.ts` | 50, 126 | SELECT asset_exif.* and toJson(asset_exif) for duplicate candidates |
| `asset.repository.ts` | 177-188 | withBoundingBox helper: queries asset_exif.latitude/longitude ranges |
| `asset-exif.table.ts` | 23 | **ForeignKeyColumn onDelete: CASCADE** — asset_exif rows auto-deleted when asset deleted |

**Key finding:** The `asset_exif` table already has `onDelete: 'CASCADE'` on the asset FK (line 23 of asset-exif.table.ts), so deletion is automatic. **The new `asset_exif_raw` table MUST also have CASCADE on delete from asset** to avoid orphaned rows.

**No explicit copy/move handling needed** for asset_exif itself — when assets are duplicated/copied between spaces or libraries (e.g., via asset.duplicate), a fresh metadata extraction runs on the copy, which repopulates exif. The raw table would also be repopulated by the same extraction.

---

## 6. Tests: Mock Patterns & Medium Tests

**File:** `/Users/spatel/workspace/github/projects/immich/server/test/repositories/metadata.repository.mock.ts`

### Metadata repository mock (lines 5-14):
```typescript
export const newMetadataRepositoryMock = (): Mocked<RepositoryInterface<MetadataRepository>> => {
  return {
    setMaxConcurrency: vitest.fn(),
    teardown: vitest.fn(),
    readTags: vitest.fn(),
    readFullTags: vitest.fn(),  // <-- Already exists!
    writeTags: vitest.fn(),
    extractBinaryTag: vitest.fn(),
  };
};
```

**Note:** `readFullTags` is already in the mock! It was added in the fork (line 133 comment in metadata.repository.ts: "fork: shared-libraries - -G1 preserves exiftool's family-1 group").

### Test setup: `metadata.service.spec.ts` (lines 75-93)

```typescript
describe(MetadataService.name, () => {
  let sut: MetadataService;
  let mocks: ServiceMocks;

  const mockReadTags = (exifData?: Partial<ImmichTags>, sidecarData?: Partial<ImmichTags>) => {
    mocks.metadata.readTags.mockReset();
    mocks.metadata.readTags.mockResolvedValueOnce(exifData ?? {});
    mocks.metadata.readTags.mockResolvedValueOnce(sidecarData ?? {});
  };

  beforeEach(() => {
    ({ sut, mocks } = newTestService(MetadataService));
    mockReadTags();
    mocks.config.getWorker.mockReturnValue(ImmichWorker.Microservices);
    delete process.env.TZ;
  });
});
```

### How to add readFullTags mock:
```typescript
const mockReadFullTags = (mediaRaw?: Record<string, unknown>, sidecarRaw?: Record<string, unknown>) => {
  mocks.metadata.readFullTags.mockReset();
  mocks.metadata.readFullTags.mockResolvedValueOnce(mediaRaw ?? {});
  mocks.metadata.readFullTags.mockResolvedValueOnce(sidecarRaw ?? {});
};
```

Then in test beforeEach:
```typescript
mockReadTags();
mockReadFullTags();
// or for specific tests:
mockReadFullTags({ 'EXIF:ISO': 400, 'EXIF:Make': 'Canon' }, {});
```

### Medium tests helper
- Located in: `server/test/medium/` directory
- Use `vitest --config test/vitest.config.medium.mjs` to run
- No specific exif/asset creation helper found, but AssetFactory exists in `test/factories/asset.factory.ts`
- Tests typically call repository/service methods directly with test doubles

---

## 7. Database Typing & Kysely DB Generation

**File:** `/Users/spatel/workspace/github/projects/immich/server/src/schema/index.ts` (lines 258-371)

### DB interface (exported at line 258):
```typescript
export interface DB {
  kysely_migrations: { timestamp: string; name: string };
  
  asset: AssetTable;
  asset_exif: AssetExifTable;
  asset_file: AssetFileTable;
  // ... all other tables
}
```

This is **manually defined** (NOT generated from decorators). When you add a new table:

1. **Import the table class** (line 49): `import { AssetExifRawTable } from 'src/schema/tables/asset-exif-raw.table.js';`
2. **Add to tables array** (line 148): `AssetExifRawTable,`
3. **Add to DB interface** (after line 276): `asset_exif_raw: AssetExifRawTable;`

The DB interface is used by all Kysely queries for **full type inference**:
```typescript
@InjectKysely() private db: Kysely<DB>
```

When you add `asset_exif_raw: AssetExifRawTable` to DB, all downstream code gets autocomplete:
```typescript
this.db.insertInto('asset_exif_raw')  // <-- type-safe table name
  .values(rawExifData)                // <-- type-safe column names & types
```

**No generation needed** — this is just a TypeScript interface you maintain manually. The @immich/sql-tools package reads the decorators on table classes and generates migrations & SQL, but the DB interface is the contract layer you keep in sync.

---

## Summary for Implementation

**To persist all raw EXIF tags:**

1. ✅ `readFullTags` already exists in `metadataRepository` (lines 134-141 of metadata.repository.ts)
2. ✅ Mock for it already exists (line 10 of metadata.repository.mock.ts)
3. Call both `readTags` + `readFullTags` in parallel in `getExifTags()`
4. Create new `AssetExifRawTable` with JSONB column + CASCADE FK to asset
5. Register it: import, add to tables[], add to DB interface
6. Create migration: ALTER TABLE asset_exif_raw (CREATE + FK + indices)
7. Extend upsertExif or create new method to insert raw tags row in parallel
8. Update generated SQL via `mise //:sql`
9. Add tests: mock `readFullTags`, verify raw data persists

**Critical:** The new raw table MUST have `onDelete: 'CASCADE'` on assetId FK, matching asset-exif.table.ts line 23.
