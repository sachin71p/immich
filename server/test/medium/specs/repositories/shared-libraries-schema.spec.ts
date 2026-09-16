import { Kysely } from 'kysely';
import { AssetType } from 'src/enum.js';
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
  describe('live-photo container matching', () => {
    it('[I3] does not match a live-photo half in another shared space', async () => {
      const { ctx, sut } = setup();
      const { user } = await ctx.newUser();
      const sourceSpace = await newSharedSpace(ctx.database);
      const otherSpace = await newSharedSpace(ctx.database);
      const { asset: still } = await ctx.newAsset({ ownerId: user.id, spaceId: sourceSpace.id });
      const { asset: motion } = await ctx.newAsset({
        ownerId: user.id,
        spaceId: otherSpace.id,
        type: AssetType.Video,
      });
      await ctx.newExif({ assetId: motion.id, livePhotoCID: 'shared-cid' });

      await expect(
        sut.findLivePhotoMatch({
          ownerId: user.id,
          otherAssetId: still.id,
          livePhotoCID: 'shared-cid',
          type: AssetType.Video,
          libraryId: null,
          spaceId: sourceSpace.id,
        }),
      ).resolves.toBeUndefined();
    });

    it('[I3] does not match a live-photo half in an external library', async () => {
      const { ctx, sut } = setup();
      const { user } = await ctx.newUser();
      const library = await ctx.get(LibraryRepository).create({
        ownerId: user.id,
        name: 'Library',
        importPaths: [],
        exclusionPatterns: [],
      });
      const { asset: still } = await ctx.newAsset({ ownerId: user.id, libraryId: library.id });
      const { asset: motion } = await ctx.newAsset({ ownerId: user.id, type: AssetType.Video });
      await ctx.newExif({ assetId: motion.id, livePhotoCID: 'library-cid' });

      await expect(
        sut.findLivePhotoMatch({
          ownerId: user.id,
          otherAssetId: still.id,
          livePhotoCID: 'library-cid',
          type: AssetType.Video,
          libraryId: library.id,
          spaceId: null,
        }),
      ).resolves.toBeUndefined();
    });
  });

  describe('asset_space_library_exclusive check', () => {
    it('[INV-01] rejects an asset with both spaceId and libraryId set', async () => {
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
