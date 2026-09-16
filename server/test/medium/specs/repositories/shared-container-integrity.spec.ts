import { Kysely } from 'kysely';
import { AssetVisibility } from 'src/enum.js';
import { AssetRepository } from 'src/repositories/asset.repository.js';
import { LoggingRepository } from 'src/repositories/logging.repository.js';
import { DB } from 'src/schema/index.js';
import { BaseService } from 'src/services/base.service.js';
import { newMediumService } from 'test/medium.factory.js';
import { newUuid } from 'test/small.factory.js';
import { getKyselyDB } from 'test/utils.js';

let defaultDatabase: Kysely<DB>;

const setup = (db?: Kysely<DB>) => {
  const { ctx } = newMediumService(BaseService, {
    database: db || defaultDatabase,
    real: [AssetRepository],
    mock: [LoggingRepository],
  });
  return { ctx };
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

describe('shared container integrity (C5)', () => {
  it('[I6] rejects a direct space delete that would clear asset spaceId without relocation rows', async () => {
    const { ctx } = setup();
    const { user } = await ctx.newUser();
    const space = await newSharedSpace(ctx.database);
    const { asset } = await ctx.newAsset({ ownerId: user.id, spaceId: space.id });

    await expect(ctx.database.deleteFrom('shared_space').where('id', '=', space.id).execute()).rejects.toThrow();

    await expect(
      ctx.database.selectFrom('asset').select('spaceId').where('id', '=', asset.id).executeTakeFirstOrThrow(),
    ).resolves.toMatchObject({ spaceId: space.id });
  });

  it('[I7] rejects Locked visibility for an asset in a shared space', async () => {
    const { ctx } = setup();
    const { user } = await ctx.newUser();
    const space = await newSharedSpace(ctx.database);

    await expect(
      ctx.newAsset({ ownerId: user.id, spaceId: space.id, visibility: AssetVisibility.Locked }),
    ).rejects.toThrow();
  });
});
