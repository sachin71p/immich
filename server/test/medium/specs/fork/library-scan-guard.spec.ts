import { Kysely } from 'kysely';
import { JobStatus } from 'src/enum.js';
import { AssetRepository } from 'src/repositories/asset.repository.js';
import { JobRepository } from 'src/repositories/job.repository.js';
import { DB } from 'src/schema/index.js';
import { LibraryService } from 'src/services/library.service.js';
import { MediumTestContext, newMediumService } from 'test/medium.factory.js';
import { newUuid } from 'test/small.factory.js';
import { getKyselyDB } from 'test/utils.js';

let defaultDatabase: Kysely<DB>;

const setup = (db?: Kysely<DB>) => {
  return newMediumService(LibraryService, {
    database: db || defaultDatabase,
    real: [AssetRepository],
    mock: [JobRepository],
  });
};

const newLibrary = async (ctx: MediumTestContext, ownerId: string) => {
  return ctx.database
    .insertInto('library')
    .values({ id: newUuid(), name: 'Library', ownerId, importPaths: ['/import/x'], exclusionPatterns: [] })
    .returningAll()
    .executeTakeFirstOrThrow();
};

const isOffline = async (ctx: MediumTestContext, assetId: string) => {
  const row = await ctx.database
    .selectFrom('asset')
    .select('isOffline')
    .where('id', '=', assetId)
    .executeTakeFirstOrThrow();
  return row.isOffline;
};

const assetExists = async (ctx: MediumTestContext, assetId: string) =>
  !!(await ctx.database.selectFrom('asset').select('id').where('id', '=', assetId).executeTakeFirst());

beforeAll(async () => {
  defaultDatabase = await getKyselyDB();
});

describe('library scan and watcher guards (fork T1)', () => {
  it('[R10-02] a watcher unlink for a path with a pending relocation is ignored, then honored', async () => {
    const { sut, ctx } = setup();
    const { user } = await ctx.newUser();
    const library = await newLibrary(ctx, user.id);
    const { asset } = await ctx.newAsset({
      ownerId: user.id,
      libraryId: library.id,
      isExternal: true,
      originalPath: '/import/x/pic.jpg',
    });
    const job = { libraryId: library.id, paths: ['/import/x/pic.jpg'] };

    await ctx.get(AssetRepository).createRelocations([asset.id], user.id);
    await expect(sut.handleAssetRemoval(job)).resolves.toBe(JobStatus.Success);
    expect(await assetExists(ctx, asset.id)).toBe(true);

    await ctx.get(AssetRepository).completeRelocation(asset.id);
    await expect(sut.handleAssetRemoval(job)).resolves.toBe(JobStatus.Success);
    expect(await assetExists(ctx, asset.id)).toBe(false);
  });

  it('[R10-02] a scan does not offline an asset with a pending relocation', async () => {
    const { ctx } = setup();
    const { user } = await ctx.newUser();
    const library = await newLibrary(ctx, user.id);
    // Staged outside the import paths (as after a move), so the scan would
    // offline it if the relocation guard did not exclude it.
    const { asset } = await ctx.newAsset({
      ownerId: user.id,
      libraryId: library.id,
      isExternal: true,
      originalPath: '/staging/pic.jpg',
    });

    await ctx.get(AssetRepository).createRelocations([asset.id], user.id);
    await ctx.get(AssetRepository).detectOfflineExternalAssets(library.id, ['/import/x'], []);
    expect(await isOffline(ctx, asset.id)).toBe(false);

    await ctx.get(AssetRepository).completeRelocation(asset.id);
    await ctx.get(AssetRepository).detectOfflineExternalAssets(library.id, ['/import/x'], []);
    expect(await isOffline(ctx, asset.id)).toBe(true);
  });
});
