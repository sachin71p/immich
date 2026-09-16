import { Kysely } from 'kysely';
import { AssetOrder, AssetVisibility } from 'src/enum.js';
import { AssetRepository } from 'src/repositories/asset.repository.js';
import { LoggingRepository } from 'src/repositories/logging.repository.js';
import { DB } from 'src/schema/index.js';
import { BaseService } from 'src/services/base.service.js';
import { newMediumService } from 'test/medium.factory.js';
import { factory, newUuid } from 'test/small.factory.js';
import { getKyselyDB } from 'test/utils.js';

let defaultDatabase: Kysely<DB>;

const setup = (db?: Kysely<DB>) => {
  const { ctx } = newMediumService(BaseService, {
    database: db || defaultDatabase,
    real: [],
    mock: [LoggingRepository],
  });
  return { ctx, sut: ctx.get(AssetRepository) };
};

beforeAll(async () => {
  defaultDatabase = await getKyselyDB();
});

// R16/PERM-16: favorites are global per asset — space, library, and album
// viewers see the same flag. The time-bucket projection used to force
// isFavorite=false for every non-owned asset outside a space, hiding library
// members' favorites.
describe('shared container favorites (R16)', () => {
  it('[R16] shows the real favorite flag to library members in time buckets', async () => {
    const { ctx, sut } = setup();
    const { user: owner } = await ctx.newUser();
    const { user: member } = await ctx.newUser();
    const memberAuth = factory.auth({ user: { id: member.id } });

    const library = await ctx.database
      .insertInto('library')
      .values({ id: newUuid(), name: 'Library', ownerId: owner.id, importPaths: [], exclusionPatterns: [] })
      .returningAll()
      .executeTakeFirstOrThrow();
    await ctx.database.insertInto('library_member').values({ libraryId: library.id, userId: member.id }).execute();

    const { asset } = await ctx.newAsset({
      ownerId: owner.id,
      libraryId: library.id,
      isFavorite: true,
      fileCreatedAt: new Date('2026-03-08T23:30:00.000Z'),
      localDateTime: new Date('2026-03-09T01:30:00.000Z'),
    });
    await ctx.newExif({ assetId: asset.id, timeZone: 'UTC+2' });

    const bucket = await sut.getTimeBucket(
      '2026-03-01',
      {
        order: AssetOrder.Desc,
        visibility: AssetVisibility.Timeline,
        scope: { personalUserIds: [], spaceIds: [], libraryIds: [library.id] },
      },
      memberAuth,
    );

    expect(JSON.parse(bucket.assets)).toEqual(expect.objectContaining({ id: [asset.id], isFavorite: [true] }));
  });
});
