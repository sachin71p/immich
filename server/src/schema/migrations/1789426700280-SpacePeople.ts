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
  await sql`UPDATE "migration_overrides" SET "value" = '{"type":"function","name":"person_delete_audit","sql":"CREATE OR REPLACE FUNCTION person_delete_audit()\\n  RETURNS TRIGGER\\n  LANGUAGE PLPGSQL\\n  AS $$\\n    BEGIN\\n      INSERT INTO person_audit (\\"personGroupId\\", \\"ownerId\\")\\n      SELECT \\"personGroupId\\", \\"ownerId\\"\\n      FROM OLD;\\n      RETURN NULL;\\n    END\\n  $$;"}'::jsonb WHERE "name" = 'function_person_delete_audit';`.execute(db);
  await sql`ALTER TABLE "person_audit" DROP COLUMN "spaceId";`.execute(db);
  await sql`ALTER TABLE "shared_space" DROP CONSTRAINT "shared_space_clusterGroupId_fkey";`.execute(db);
  await sql`ALTER TABLE "shared_space" DROP COLUMN "clusterGroupId";`.execute(db);
  await sql`DROP INDEX "person_spaceId_idx";`.execute(db);
  await sql`ALTER TABLE "person" DROP CONSTRAINT "person_spaceId_fkey";`.execute(db);
  await sql`ALTER TABLE "person" DROP COLUMN "spaceId";`.execute(db);
}
