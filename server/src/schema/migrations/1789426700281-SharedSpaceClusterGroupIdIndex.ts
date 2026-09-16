import { Kysely, sql } from 'kysely';

// fork: shared-libraries - 1789426700280-SpacePeople.ts added shared_space.clusterGroupId and its
// FK but, unlike person.spaceId in that same migration, never created the matching index.
export async function up(db: Kysely<any>): Promise<void> {
  await sql`CREATE INDEX "shared_space_clusterGroupId_idx" ON "shared_space" ("clusterGroupId");`.execute(db);
}

export async function down(db: Kysely<any>): Promise<void> {
  await sql`DROP INDEX "shared_space_clusterGroupId_idx";`.execute(db);
}
