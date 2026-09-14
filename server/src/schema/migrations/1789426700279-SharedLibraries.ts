import { Kysely, sql } from 'kysely';

// fork: shared-libraries
const reservedStorageLabelQuery = sql<{ id: string }>`SELECT "id" FROM "user" WHERE "storageLabel" = 'shared' LIMIT 1`;

export async function up(db: Kysely<any>): Promise<void> {
  // fork: shared-libraries
  const { rows } = await reservedStorageLabelQuery.execute(db);
  if (rows.length > 0) {
    throw new Error(
      'User storage label "shared" is reserved by the shared-libraries fork; rename it before upgrading',
    );
  }

  await sql`CREATE OR REPLACE FUNCTION shared_space_member_delete_audit()
  RETURNS TRIGGER
  LANGUAGE PLPGSQL
  AS $$
    BEGIN
      INSERT INTO shared_space_audit ("spaceId", "userId")
      SELECT "spaceId", "userId"
      FROM OLD;

      IF pg_trigger_depth() = 1 THEN
        INSERT INTO shared_space_member_audit ("spaceId", "userId")
        SELECT "spaceId", "userId"
        FROM OLD;
      END IF;

      RETURN NULL;
    END
  $$;`.execute(db);
  await sql`CREATE OR REPLACE FUNCTION shared_space_asset_delete_audit()
  RETURNS TRIGGER
  LANGUAGE PLPGSQL
  AS $$
    BEGIN
      INSERT INTO shared_space_asset_audit ("spaceId", "assetId")
      SELECT "spaceId", "id"
      FROM OLD
      WHERE "spaceId" IS NOT NULL;
      RETURN NULL;
    END
  $$;`.execute(db);
  await sql`CREATE OR REPLACE FUNCTION shared_space_asset_update_audit()
  RETURNS TRIGGER
  LANGUAGE PLPGSQL
  AS $$
    BEGIN
      IF OLD."spaceId" IS NOT NULL AND OLD."spaceId" IS DISTINCT FROM NEW."spaceId" THEN
        INSERT INTO shared_space_asset_audit ("spaceId", "assetId")
        VALUES (OLD."spaceId", OLD."id");
      END IF;
      RETURN NULL;
    END
  $$;`.execute(db);
  await sql`CREATE OR REPLACE FUNCTION library_member_delete_audit()
  RETURNS TRIGGER
  LANGUAGE PLPGSQL
  AS $$
    BEGIN
      INSERT INTO library_member_audit ("libraryId", "userId")
      SELECT "libraryId", "userId"
      FROM OLD;
      RETURN NULL;
    END
  $$;`.execute(db);
  await sql`CREATE OR REPLACE FUNCTION library_asset_delete_audit()
  RETURNS TRIGGER
  LANGUAGE PLPGSQL
  AS $$
    BEGIN
      INSERT INTO library_asset_audit ("libraryId", "assetId")
      SELECT "libraryId", "id"
      FROM OLD
      WHERE "libraryId" IS NOT NULL;
      RETURN NULL;
    END
  $$;`.execute(db);
  await sql`CREATE OR REPLACE FUNCTION library_asset_update_audit()
  RETURNS TRIGGER
  LANGUAGE PLPGSQL
  AS $$
    BEGIN
      IF OLD."libraryId" IS NOT NULL AND OLD."libraryId" IS DISTINCT FROM NEW."libraryId" THEN
        INSERT INTO library_asset_audit ("libraryId", "assetId")
        VALUES (OLD."libraryId", OLD."id");
      END IF;
      RETURN NULL;
    END
  $$;`.execute(db);
  await sql`CREATE TYPE "shared_space_role" AS ENUM ('owner','contributor');`.execute(db);
  await sql`ALTER TABLE "library" ADD "uploadPath" text;`.execute(db);
  await sql`ALTER TABLE "asset" ADD "spaceId" uuid;`.execute(db);
  await sql`CREATE INDEX "asset_spaceId_localDateTime_idx" ON "asset" ("spaceId", "localDateTime");`.execute(db);
  await sql`CREATE INDEX "asset_spaceId_idx" ON "asset" ("spaceId");`.execute(db);
  await sql`CREATE TABLE "shared_space" (
  "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
  "name" character varying NOT NULL,
  "description" text NOT NULL DEFAULT '',
  "storageLabel" character varying NOT NULL,
  "createdById" uuid,
  "thumbnailAssetId" uuid,
  "createdAt" timestamp with time zone NOT NULL DEFAULT now(),
  "updatedAt" timestamp with time zone NOT NULL DEFAULT now(),
  "updateId" uuid NOT NULL DEFAULT immich_uuid_v7(),
  CONSTRAINT "shared_space_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "user" ("id") ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "shared_space_storageLabel_uq" UNIQUE ("storageLabel"),
  CONSTRAINT "shared_space_pkey" PRIMARY KEY ("id")
);`.execute(db);
  await sql`COMMENT ON COLUMN "shared_space"."thumbnailAssetId" IS 'Asset ID to be used as thumbnail';`.execute(db);
  await sql`ALTER TABLE "asset" ADD CONSTRAINT "asset_spaceId_fkey" FOREIGN KEY ("spaceId") REFERENCES "shared_space" ("id") ON UPDATE CASCADE ON DELETE SET NULL;`.execute(db);
  await sql`ALTER TABLE "asset" ADD CONSTRAINT "asset_space_library_exclusive" CHECK ("spaceId" IS NULL OR "libraryId" IS NULL);`.execute(db);
  await sql`CREATE OR REPLACE TRIGGER "library_asset_update_audit"
  AFTER UPDATE ON "asset"
  FOR EACH ROW
  EXECUTE FUNCTION library_asset_update_audit();`.execute(db);
  await sql`CREATE OR REPLACE TRIGGER "library_asset_delete_audit"
  AFTER DELETE ON "asset"
  REFERENCING OLD TABLE AS "old"
  FOR EACH STATEMENT
  EXECUTE FUNCTION library_asset_delete_audit();`.execute(db);
  await sql`CREATE OR REPLACE TRIGGER "shared_space_asset_update_audit"
  AFTER UPDATE ON "asset"
  FOR EACH ROW
  EXECUTE FUNCTION shared_space_asset_update_audit();`.execute(db);
  await sql`CREATE OR REPLACE TRIGGER "shared_space_asset_delete_audit"
  AFTER DELETE ON "asset"
  REFERENCING OLD TABLE AS "old"
  FOR EACH STATEMENT
  EXECUTE FUNCTION shared_space_asset_delete_audit();`.execute(db);
  await sql`CREATE INDEX "shared_space_createdById_idx" ON "shared_space" ("createdById");`.execute(db);
  await sql`CREATE INDEX "shared_space_thumbnailAssetId_idx" ON "shared_space" ("thumbnailAssetId");`.execute(db);
  await sql`CREATE INDEX "shared_space_updateId_idx" ON "shared_space" ("updateId");`.execute(db);
  await sql`CREATE OR REPLACE TRIGGER "shared_space_updatedAt"
  BEFORE UPDATE ON "shared_space"
  FOR EACH ROW
  EXECUTE FUNCTION updated_at();`.execute(db);
  await sql`ALTER TABLE "shared_space" ADD CONSTRAINT "shared_space_thumbnailAssetId_fkey" FOREIGN KEY ("thumbnailAssetId") REFERENCES "asset" ("id") ON UPDATE CASCADE ON DELETE SET NULL;`.execute(db);
  await sql`CREATE TABLE "asset_relocation" (
  "assetId" uuid NOT NULL,
  "requestedAt" timestamp with time zone NOT NULL DEFAULT now(),
  "requestedById" uuid,
  "attempts" integer NOT NULL DEFAULT 0,
  "lastError" text,
  CONSTRAINT "asset_relocation_assetId_fkey" FOREIGN KEY ("assetId") REFERENCES "asset" ("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "asset_relocation_pkey" PRIMARY KEY ("assetId")
);`.execute(db);
  await sql`CREATE TABLE "library_asset_audit" (
  "id" uuid NOT NULL DEFAULT immich_uuid_v7(),
  "libraryId" uuid NOT NULL,
  "assetId" uuid NOT NULL,
  "deletedAt" timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "library_asset_audit_pkey" PRIMARY KEY ("id")
);`.execute(db);
  await sql`CREATE INDEX "library_asset_audit_libraryId_idx" ON "library_asset_audit" ("libraryId");`.execute(db);
  await sql`CREATE INDEX "library_asset_audit_assetId_idx" ON "library_asset_audit" ("assetId");`.execute(db);
  await sql`CREATE INDEX "library_asset_audit_deletedAt_idx" ON "library_asset_audit" ("deletedAt");`.execute(db);
  await sql`CREATE TABLE "library_member_audit" (
  "id" uuid NOT NULL DEFAULT immich_uuid_v7(),
  "libraryId" uuid NOT NULL,
  "userId" uuid NOT NULL,
  "deletedAt" timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "library_member_audit_pkey" PRIMARY KEY ("id")
);`.execute(db);
  await sql`CREATE INDEX "library_member_audit_libraryId_idx" ON "library_member_audit" ("libraryId");`.execute(db);
  await sql`CREATE INDEX "library_member_audit_userId_idx" ON "library_member_audit" ("userId");`.execute(db);
  await sql`CREATE INDEX "library_member_audit_deletedAt_idx" ON "library_member_audit" ("deletedAt");`.execute(db);
  await sql`CREATE TABLE "library_member" (
  "libraryId" uuid NOT NULL,
  "userId" uuid NOT NULL,
  "showInTimeline" boolean NOT NULL DEFAULT true,
  "createId" uuid NOT NULL DEFAULT immich_uuid_v7(),
  "createdAt" timestamp with time zone NOT NULL DEFAULT now(),
  "updateId" uuid NOT NULL DEFAULT immich_uuid_v7(),
  "updatedAt" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "library_member_libraryId_fkey" FOREIGN KEY ("libraryId") REFERENCES "library" ("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "library_member_userId_fkey" FOREIGN KEY ("userId") REFERENCES "user" ("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "library_member_pkey" PRIMARY KEY ("libraryId", "userId")
);`.execute(db);
  await sql`CREATE INDEX "library_member_libraryId_idx" ON "library_member" ("libraryId");`.execute(db);
  await sql`CREATE INDEX "library_member_userId_idx" ON "library_member" ("userId");`.execute(db);
  await sql`CREATE INDEX "library_member_createId_idx" ON "library_member" ("createId");`.execute(db);
  await sql`CREATE INDEX "library_member_updateId_idx" ON "library_member" ("updateId");`.execute(db);
  await sql`CREATE OR REPLACE TRIGGER "library_member_delete_audit"
  AFTER DELETE ON "library_member"
  REFERENCING OLD TABLE AS "old"
  FOR EACH STATEMENT
  EXECUTE FUNCTION library_member_delete_audit();`.execute(db);
  await sql`CREATE OR REPLACE TRIGGER "library_member_updatedAt"
  BEFORE UPDATE ON "library_member"
  FOR EACH ROW
  EXECUTE FUNCTION updated_at();`.execute(db);
  await sql`CREATE TABLE "shared_space_asset_audit" (
  "id" uuid NOT NULL DEFAULT immich_uuid_v7(),
  "spaceId" uuid NOT NULL,
  "assetId" uuid NOT NULL,
  "deletedAt" timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "shared_space_asset_audit_pkey" PRIMARY KEY ("id")
);`.execute(db);
  await sql`CREATE INDEX "shared_space_asset_audit_spaceId_idx" ON "shared_space_asset_audit" ("spaceId");`.execute(db);
  await sql`CREATE INDEX "shared_space_asset_audit_assetId_idx" ON "shared_space_asset_audit" ("assetId");`.execute(db);
  await sql`CREATE INDEX "shared_space_asset_audit_deletedAt_idx" ON "shared_space_asset_audit" ("deletedAt");`.execute(db);
  await sql`CREATE TABLE "shared_space_audit" (
  "id" uuid NOT NULL DEFAULT immich_uuid_v7(),
  "spaceId" uuid NOT NULL,
  "userId" uuid NOT NULL,
  "deletedAt" timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "shared_space_audit_pkey" PRIMARY KEY ("id")
);`.execute(db);
  await sql`CREATE INDEX "shared_space_audit_spaceId_idx" ON "shared_space_audit" ("spaceId");`.execute(db);
  await sql`CREATE INDEX "shared_space_audit_userId_idx" ON "shared_space_audit" ("userId");`.execute(db);
  await sql`CREATE INDEX "shared_space_audit_deletedAt_idx" ON "shared_space_audit" ("deletedAt");`.execute(db);
  await sql`CREATE TABLE "shared_space_member_audit" (
  "id" uuid NOT NULL DEFAULT immich_uuid_v7(),
  "spaceId" uuid NOT NULL,
  "userId" uuid NOT NULL,
  "deletedAt" timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "shared_space_member_audit_pkey" PRIMARY KEY ("id")
);`.execute(db);
  await sql`CREATE INDEX "shared_space_member_audit_spaceId_idx" ON "shared_space_member_audit" ("spaceId");`.execute(db);
  await sql`CREATE INDEX "shared_space_member_audit_userId_idx" ON "shared_space_member_audit" ("userId");`.execute(db);
  await sql`CREATE INDEX "shared_space_member_audit_deletedAt_idx" ON "shared_space_member_audit" ("deletedAt");`.execute(db);
  await sql`CREATE TABLE "shared_space_member" (
  "spaceId" uuid NOT NULL,
  "userId" uuid NOT NULL,
  "role" shared_space_role NOT NULL DEFAULT 'contributor',
  "showInTimeline" boolean NOT NULL DEFAULT true,
  "createId" uuid NOT NULL DEFAULT immich_uuid_v7(),
  "createdAt" timestamp with time zone NOT NULL DEFAULT now(),
  "updateId" uuid NOT NULL DEFAULT immich_uuid_v7(),
  "updatedAt" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "shared_space_member_spaceId_fkey" FOREIGN KEY ("spaceId") REFERENCES "shared_space" ("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "shared_space_member_userId_fkey" FOREIGN KEY ("userId") REFERENCES "user" ("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "shared_space_member_pkey" PRIMARY KEY ("spaceId", "userId")
);`.execute(db);
  await sql`CREATE UNIQUE INDEX "shared_space_member_unique_owner" ON "shared_space_member" ("spaceId") WHERE (role = 'owner');`.execute(db);
  await sql`CREATE INDEX "shared_space_member_spaceId_idx" ON "shared_space_member" ("spaceId");`.execute(db);
  await sql`CREATE INDEX "shared_space_member_userId_idx" ON "shared_space_member" ("userId");`.execute(db);
  await sql`CREATE INDEX "shared_space_member_createId_idx" ON "shared_space_member" ("createId");`.execute(db);
  await sql`CREATE INDEX "shared_space_member_updateId_idx" ON "shared_space_member" ("updateId");`.execute(db);
  await sql`CREATE OR REPLACE TRIGGER "shared_space_member_delete_audit"
  AFTER DELETE ON "shared_space_member"
  REFERENCING OLD TABLE AS "old"
  FOR EACH STATEMENT
  WHEN (pg_trigger_depth() <= 1)
  EXECUTE FUNCTION shared_space_member_delete_audit();`.execute(db);
  await sql`CREATE OR REPLACE TRIGGER "shared_space_member_updatedAt"
  BEFORE UPDATE ON "shared_space_member"
  FOR EACH ROW
  EXECUTE FUNCTION updated_at();`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('function_shared_space_member_delete_audit', '{"type":"function","name":"shared_space_member_delete_audit","sql":"CREATE OR REPLACE FUNCTION shared_space_member_delete_audit()\\n  RETURNS TRIGGER\\n  LANGUAGE PLPGSQL\\n  AS $$\\n    BEGIN\\n      INSERT INTO shared_space_audit (\\"spaceId\\", \\"userId\\")\\n      SELECT \\"spaceId\\", \\"userId\\"\\n      FROM OLD;\\n\\n      IF pg_trigger_depth() = 1 THEN\\n        INSERT INTO shared_space_member_audit (\\"spaceId\\", \\"userId\\")\\n        SELECT \\"spaceId\\", \\"userId\\"\\n        FROM OLD;\\n      END IF;\\n\\n      RETURN NULL;\\n    END\\n  $$;"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('function_shared_space_asset_delete_audit', '{"type":"function","name":"shared_space_asset_delete_audit","sql":"CREATE OR REPLACE FUNCTION shared_space_asset_delete_audit()\\n  RETURNS TRIGGER\\n  LANGUAGE PLPGSQL\\n  AS $$\\n    BEGIN\\n      INSERT INTO shared_space_asset_audit (\\"spaceId\\", \\"assetId\\")\\n      SELECT \\"spaceId\\", \\"id\\"\\n      FROM OLD\\n      WHERE \\"spaceId\\" IS NOT NULL;\\n      RETURN NULL;\\n    END\\n  $$;"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('function_shared_space_asset_update_audit', '{"type":"function","name":"shared_space_asset_update_audit","sql":"CREATE OR REPLACE FUNCTION shared_space_asset_update_audit()\\n  RETURNS TRIGGER\\n  LANGUAGE PLPGSQL\\n  AS $$\\n    BEGIN\\n      IF OLD.\\"spaceId\\" IS NOT NULL AND OLD.\\"spaceId\\" IS DISTINCT FROM NEW.\\"spaceId\\" THEN\\n        INSERT INTO shared_space_asset_audit (\\"spaceId\\", \\"assetId\\")\\n        VALUES (OLD.\\"spaceId\\", OLD.\\"id\\");\\n      END IF;\\n      RETURN NULL;\\n    END\\n  $$;"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('function_library_member_delete_audit', '{"type":"function","name":"library_member_delete_audit","sql":"CREATE OR REPLACE FUNCTION library_member_delete_audit()\\n  RETURNS TRIGGER\\n  LANGUAGE PLPGSQL\\n  AS $$\\n    BEGIN\\n      INSERT INTO library_member_audit (\\"libraryId\\", \\"userId\\")\\n      SELECT \\"libraryId\\", \\"userId\\"\\n      FROM OLD;\\n      RETURN NULL;\\n    END\\n  $$;"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('function_library_asset_delete_audit', '{"type":"function","name":"library_asset_delete_audit","sql":"CREATE OR REPLACE FUNCTION library_asset_delete_audit()\\n  RETURNS TRIGGER\\n  LANGUAGE PLPGSQL\\n  AS $$\\n    BEGIN\\n      INSERT INTO library_asset_audit (\\"libraryId\\", \\"assetId\\")\\n      SELECT \\"libraryId\\", \\"id\\"\\n      FROM OLD\\n      WHERE \\"libraryId\\" IS NOT NULL;\\n      RETURN NULL;\\n    END\\n  $$;"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('function_library_asset_update_audit', '{"type":"function","name":"library_asset_update_audit","sql":"CREATE OR REPLACE FUNCTION library_asset_update_audit()\\n  RETURNS TRIGGER\\n  LANGUAGE PLPGSQL\\n  AS $$\\n    BEGIN\\n      IF OLD.\\"libraryId\\" IS NOT NULL AND OLD.\\"libraryId\\" IS DISTINCT FROM NEW.\\"libraryId\\" THEN\\n        INSERT INTO library_asset_audit (\\"libraryId\\", \\"assetId\\")\\n        VALUES (OLD.\\"libraryId\\", OLD.\\"id\\");\\n      END IF;\\n      RETURN NULL;\\n    END\\n  $$;"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('trigger_shared_space_updatedAt', '{"type":"trigger","name":"shared_space_updatedAt","sql":"CREATE OR REPLACE TRIGGER \\"shared_space_updatedAt\\"\\n  BEFORE UPDATE ON \\"shared_space\\"\\n  FOR EACH ROW\\n  EXECUTE FUNCTION updated_at();"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('trigger_library_asset_update_audit', '{"type":"trigger","name":"library_asset_update_audit","sql":"CREATE OR REPLACE TRIGGER \\"library_asset_update_audit\\"\\n  AFTER UPDATE ON \\"asset\\"\\n  FOR EACH ROW\\n  EXECUTE FUNCTION library_asset_update_audit();"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('trigger_library_asset_delete_audit', '{"type":"trigger","name":"library_asset_delete_audit","sql":"CREATE OR REPLACE TRIGGER \\"library_asset_delete_audit\\"\\n  AFTER DELETE ON \\"asset\\"\\n  REFERENCING OLD TABLE AS \\"old\\"\\n  FOR EACH STATEMENT\\n  EXECUTE FUNCTION library_asset_delete_audit();"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('trigger_shared_space_asset_update_audit', '{"type":"trigger","name":"shared_space_asset_update_audit","sql":"CREATE OR REPLACE TRIGGER \\"shared_space_asset_update_audit\\"\\n  AFTER UPDATE ON \\"asset\\"\\n  FOR EACH ROW\\n  EXECUTE FUNCTION shared_space_asset_update_audit();"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('trigger_shared_space_asset_delete_audit', '{"type":"trigger","name":"shared_space_asset_delete_audit","sql":"CREATE OR REPLACE TRIGGER \\"shared_space_asset_delete_audit\\"\\n  AFTER DELETE ON \\"asset\\"\\n  REFERENCING OLD TABLE AS \\"old\\"\\n  FOR EACH STATEMENT\\n  EXECUTE FUNCTION shared_space_asset_delete_audit();"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('trigger_library_member_delete_audit', '{"type":"trigger","name":"library_member_delete_audit","sql":"CREATE OR REPLACE TRIGGER \\"library_member_delete_audit\\"\\n  AFTER DELETE ON \\"library_member\\"\\n  REFERENCING OLD TABLE AS \\"old\\"\\n  FOR EACH STATEMENT\\n  EXECUTE FUNCTION library_member_delete_audit();"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('trigger_library_member_updatedAt', '{"type":"trigger","name":"library_member_updatedAt","sql":"CREATE OR REPLACE TRIGGER \\"library_member_updatedAt\\"\\n  BEFORE UPDATE ON \\"library_member\\"\\n  FOR EACH ROW\\n  EXECUTE FUNCTION updated_at();"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('trigger_shared_space_member_delete_audit', '{"type":"trigger","name":"shared_space_member_delete_audit","sql":"CREATE OR REPLACE TRIGGER \\"shared_space_member_delete_audit\\"\\n  AFTER DELETE ON \\"shared_space_member\\"\\n  REFERENCING OLD TABLE AS \\"old\\"\\n  FOR EACH STATEMENT\\n  WHEN (pg_trigger_depth() <= 1)\\n  EXECUTE FUNCTION shared_space_member_delete_audit();"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('trigger_shared_space_member_updatedAt', '{"type":"trigger","name":"shared_space_member_updatedAt","sql":"CREATE OR REPLACE TRIGGER \\"shared_space_member_updatedAt\\"\\n  BEFORE UPDATE ON \\"shared_space_member\\"\\n  FOR EACH ROW\\n  EXECUTE FUNCTION updated_at();"}'::jsonb);`.execute(db);
  await sql`INSERT INTO "migration_overrides" ("name", "value") VALUES ('index_shared_space_member_unique_owner', '{"type":"index","name":"shared_space_member_unique_owner","sql":"CREATE UNIQUE INDEX \\"shared_space_member_unique_owner\\" ON \\"shared_space_member\\" (\\"spaceId\\") WHERE (role = ''owner'');"}'::jsonb);`.execute(db);
}

export async function down(db: Kysely<any>): Promise<void> {
  await sql`DROP TRIGGER "shared_space_member_delete_audit" ON "shared_space_member";`.execute(db);
  await sql`DROP FUNCTION shared_space_member_delete_audit;`.execute(db);
  await sql`DROP TRIGGER "shared_space_asset_delete_audit" ON "asset";`.execute(db);
  await sql`DROP FUNCTION shared_space_asset_delete_audit;`.execute(db);
  await sql`DROP TRIGGER "shared_space_asset_update_audit" ON "asset";`.execute(db);
  await sql`DROP FUNCTION shared_space_asset_update_audit;`.execute(db);
  await sql`DROP TRIGGER "library_member_delete_audit" ON "library_member";`.execute(db);
  await sql`DROP FUNCTION library_member_delete_audit;`.execute(db);
  await sql`DROP TRIGGER "library_asset_delete_audit" ON "asset";`.execute(db);
  await sql`DROP FUNCTION library_asset_delete_audit;`.execute(db);
  await sql`DROP TRIGGER "library_asset_update_audit" ON "asset";`.execute(db);
  await sql`DROP FUNCTION library_asset_update_audit;`.execute(db);
  await sql`ALTER TABLE "asset" DROP CONSTRAINT "asset_spaceId_fkey";`.execute(db);
  await sql`ALTER TABLE "shared_space" DROP CONSTRAINT "shared_space_thumbnailAssetId_fkey";`.execute(db);
  await sql`DROP TABLE "shared_space_member";`.execute(db);
  await sql`DROP TYPE "shared_space_role";`.execute(db);
  await sql`ALTER TABLE "library" DROP COLUMN "uploadPath";`.execute(db);
  await sql`ALTER TABLE "asset" DROP CONSTRAINT "asset_space_library_exclusive";`.execute(db);
  await sql`ALTER TABLE "asset" DROP COLUMN "spaceId";`.execute(db);
  await sql`DROP TABLE "shared_space";`.execute(db);
  await sql`DROP TABLE "asset_relocation";`.execute(db);
  await sql`DROP TABLE "library_asset_audit";`.execute(db);
  await sql`DROP TABLE "library_member_audit";`.execute(db);
  await sql`DROP TABLE "library_member";`.execute(db);
  await sql`DROP TABLE "shared_space_asset_audit";`.execute(db);
  await sql`DROP TABLE "shared_space_audit";`.execute(db);
  await sql`DROP TABLE "shared_space_member_audit";`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'function_shared_space_member_delete_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'function_shared_space_asset_delete_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'function_shared_space_asset_update_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'function_library_member_delete_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'function_library_asset_delete_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'function_library_asset_update_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'trigger_shared_space_updatedAt';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'trigger_library_asset_update_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'trigger_library_asset_delete_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'trigger_shared_space_asset_update_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'trigger_shared_space_asset_delete_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'trigger_library_member_delete_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'trigger_library_member_updatedAt';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'trigger_shared_space_member_delete_audit';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'trigger_shared_space_member_updatedAt';`.execute(db);
  await sql`DELETE FROM "migration_overrides" WHERE "name" = 'index_shared_space_member_unique_owner';`.execute(db);
}
