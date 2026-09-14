import { Kysely } from 'kysely';
import { AssetRepository } from 'src/repositories/asset.repository.js';
import { LibraryRepository } from 'src/repositories/library.repository.js';
import { LoggingRepository } from 'src/repositories/logging.repository.js';
import { DB } from 'src/schema/index.js';
import { BaseService } from 'src/services/base.service.js';
import { newMediumService } from 'test/medium.factory.js';
import { newUuid } from 'test/small.factory.js';
import { getKyselyDB } from 'test/utils.js';

// fork: shared-libraries
// Schema-only coverage for the S1 migration: no SharedSpaceRepository/service exists yet, so
// this exercises the DB constraints/triggers directly through Kysely.

let defaultDatabase: Kysely<DB>;

const setup = (db?: Kysely<DB>) => {
  const { ctx } = newMediumService(BaseService, {
    database: db || defaultDatabase,
    real: [AssetRepository, LibraryRepository],
    mock: [LoggingRepository],
  });
  return { ctx, sut: ctx.get(AssetRepository) };
};

const newSharedSpace = (db: Kysely<DB>) =>
  db
    .insertInto('shared_space')
    .values({ id: newUuid(), name: 'Space', storageLabel: newUuid() })
    .returningAll()
    .executeTakeFirstOrThrow();

beforeAll(async () => {
  defaultDatabase = await getKyselyDB();
});

describe('shared-libraries schema (S1)', () => {
  describe('asset_space_library_exclusive check', () => {
    it('rejects an asset with both spaceId and libraryId set', async () => {
      const { ctx } = setup();
      const { user } = await ctx.newUser();
      const space = await newSharedSpace(ctx.database);
      const library = await ctx.get(LibraryRepository).create({
        ownerId: user.id,
        name: 'Library',
        importPaths: [],
        exclusionPatterns: [],
      });

      await expect(ctx.newAsset({ ownerId: user.id, spaceId: space.id, libraryId: library.id })).rejects.toThrow();
    });

    it('allows an asset with only spaceId set', async () => {
      const { ctx } = setup();
      const { user } = await ctx.newUser();
      const space = await newSharedSpace(ctx.database);

      await expect(ctx.newAsset({ ownerId: user.id, spaceId: space.id })).resolves.toBeDefined();
    });
  });

  describe('shared_space_asset_audit trigger', () => {
    it('inserts a row when a space asset is moved out of the space', async () => {
      const { ctx } = setup();
      const { user } = await ctx.newUser();
      const space = await newSharedSpace(ctx.database);
      const { asset } = await ctx.newAsset({ ownerId: user.id, spaceId: space.id });

      await ctx.database.updateTable('asset').set({ spaceId: null }).where('id', '=', asset.id).execute();

      const rows = await ctx.database
        .selectFrom('shared_space_asset_audit')
        .selectAll()
        .where('assetId', '=', asset.id)
        .execute();

      expect(rows).toEqual([expect.objectContaining({ spaceId: space.id, assetId: asset.id })]);
    });

    it('inserts a row when a space asset is deleted', async () => {
      const { ctx } = setup();
      const { user } = await ctx.newUser();
      const space = await newSharedSpace(ctx.database);
      const { asset } = await ctx.newAsset({ ownerId: user.id, spaceId: space.id });

      await ctx.database.deleteFrom('asset').where('id', '=', asset.id).execute();

      const rows = await ctx.database
        .selectFrom('shared_space_asset_audit')
        .selectAll()
        .where('assetId', '=', asset.id)
        .execute();

      expect(rows).toEqual([expect.objectContaining({ spaceId: space.id, assetId: asset.id })]);
    });

    it('does not insert a row for updates unrelated to spaceId', async () => {
      const { ctx } = setup();
      const { user } = await ctx.newUser();
      const space = await newSharedSpace(ctx.database);
      const { asset } = await ctx.newAsset({ ownerId: user.id, spaceId: space.id });

      await ctx.database.updateTable('asset').set({ isFavorite: true }).where('id', '=', asset.id).execute();

      const rows = await ctx.database
        .selectFrom('shared_space_asset_audit')
        .selectAll()
        .where('assetId', '=', asset.id)
        .execute();

      expect(rows).toEqual([]);
    });
  });
});
