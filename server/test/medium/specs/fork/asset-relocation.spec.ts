import { Kysely } from 'kysely';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { JobName, JobStatus } from 'src/enum.js';
import { AssetRepository } from 'src/repositories/asset.repository.js';
import { ConfigRepository } from 'src/repositories/config.repository.js';
import { CryptoRepository } from 'src/repositories/crypto.repository.js';
import { JobRepository } from 'src/repositories/job.repository.js';
import { MoveRepository } from 'src/repositories/move.repository.js';
import { PersonRepository } from 'src/repositories/person.repository.js';
import { StorageRepository } from 'src/repositories/storage.repository.js';
import { SystemMetadataRepository } from 'src/repositories/system-metadata.repository.js';
import { DB } from 'src/schema/index.js';
import { AssetRelocationService } from 'src/services/asset-relocation.service.js';
import { MediumTestContext, newMediumService } from 'test/medium.factory.js';
import { newUuid } from 'test/small.factory.js';
import { getKyselyDB } from 'test/utils.js';

let defaultDatabase: Kysely<DB>;

const setup = (db?: Kysely<DB>) => {
  return newMediumService(AssetRelocationService, {
    database: db || defaultDatabase,
    real: [
      AssetRepository,
      ConfigRepository,
      CryptoRepository,
      MoveRepository,
      PersonRepository,
      SystemMetadataRepository,
    ],
    mock: [JobRepository, StorageRepository],
  });
};

const newLibrary = async (ctx: MediumTestContext, ownerId: string, uploadPath: string) => {
  return ctx.database
    .insertInto('library')
    .values({
      id: newUuid(),
      name: 'Library',
      ownerId,
      importPaths: ['/import/unused'],
      exclusionPatterns: [],
      uploadPath,
    })
    .returningAll()
    .executeTakeFirstOrThrow();
};

/** An external-library asset staged outside the import paths, ready to relocate into uploadPath. */
const newStagedExternalAsset = async (ctx: MediumTestContext, ownerId: string, libraryId: string) => {
  const { asset } = await ctx.newAsset({
    ownerId,
    libraryId,
    isExternal: true,
    originalPath: `/staging/${newUuid()}.jpg`,
    originalFileName: 'pic.jpg',
  });
  await ctx.newExif({ assetId: asset.id, fileSizeInByte: 7 });
  return asset;
};

const relocationRow = (ctx: MediumTestContext, assetId: string) =>
  ctx.database.selectFrom('asset_relocation').selectAll().where('assetId', '=', assetId).executeTakeFirst();

beforeAll(async () => {
  defaultDatabase = await getKyselyDB();
});

describe('asset relocation (fork T1)', () => {
  it('[MV-02] a failed relocation keeps its row with attempts=1; retry completes with clean move_history', async () => {
    const { sut, ctx } = setup();
    const storage = ctx.getMock(StorageRepository);
    const { user } = await ctx.newUser();
    const uploadPath = join(tmpdir(), 'fork-reloc', newUuid());
    const library = await newLibrary(ctx, user.id, uploadPath);
    const asset = await newStagedExternalAsset(ctx, user.id, library.id);
    const target = join(uploadPath, 'pic.jpg');
    await ctx.get(AssetRepository).createRelocations([asset.id], user.id);

    storage.checkFileExists.mockImplementation((path) => Promise.resolve(path !== target));
    storage.rename.mockRejectedValueOnce(Object.assign(new Error('cross-device link'), { code: 'EXDEV' }));
    storage.copyFile.mockRejectedValueOnce(Object.assign(new Error('injected EIO'), { code: 'EIO' }));

    await expect(sut.handleRelocate({ id: asset.id })).rejects.toThrow('injected EIO');
    const failed = await relocationRow(ctx, asset.id);
    expect(failed?.attempts).toBe(1);
    expect(await ctx.get(AssetRepository).getPendingRelocationIds()).toContain(asset.id);

    storage.rename.mockResolvedValue(undefined);
    await expect(sut.handleRelocate({ id: asset.id })).resolves.toBe(JobStatus.Success);
    expect(await relocationRow(ctx, asset.id)).toBeUndefined();
    expect(await ctx.get(AssetRepository).getPendingRelocationIds()).not.toContain(asset.id);
    const relocated = await ctx.database
      .selectFrom('asset')
      .select('originalPath')
      .where('id', '=', asset.id)
      .executeTakeFirstOrThrow();
    expect(relocated.originalPath).toBe(target);
    expect(
      await ctx.database.selectFrom('move_history').select('id').where('entityId', '=', asset.id).execute(),
    ).toEqual([]);
  });

  it('[MV-03] bootstrap re-queues pending relocations and the worker finishes them', async () => {
    const { sut, ctx } = setup();
    const jobs = ctx.getMock(JobRepository);
    const storage = ctx.getMock(StorageRepository);
    const { user } = await ctx.newUser();
    const uploadPath = join(tmpdir(), 'fork-reloc', newUuid());
    const library = await newLibrary(ctx, user.id, uploadPath);
    const asset = await newStagedExternalAsset(ctx, user.id, library.id);
    await ctx.get(AssetRepository).createRelocations([asset.id], user.id);

    // A restart boots with the row still pending: bootstrap re-queues the sweep,
    // and the sweep re-queues one job per pending asset.
    await sut.onBootstrap();
    expect(jobs.queue).toHaveBeenCalledWith({ name: JobName.AssetRelocateQueueAll });
    await expect(sut.handleQueueAll()).resolves.toBe(JobStatus.Success);
    expect(jobs.queueAll).toHaveBeenCalledWith([{ name: JobName.AssetRelocate, data: { id: asset.id } }]);

    storage.checkFileExists.mockResolvedValue(false);
    storage.rename.mockResolvedValue(undefined);
    await expect(sut.handleRelocate({ id: asset.id })).resolves.toBe(JobStatus.Success);
    expect(await relocationRow(ctx, asset.id)).toBeUndefined();
  });
});
