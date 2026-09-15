import { Kysely } from 'kysely';
import { SharedSpaceRole, SyncEntityType, SyncRequestType } from 'src/enum.js';
import { DB } from 'src/schema/index.js';
import { SyncTestContext } from 'test/medium.factory.js';
import { newUuid } from 'test/small.factory.js';
import { getKyselyDB } from 'test/utils.js';

let defaultDatabase: Kysely<DB>;

const setup = async () => {
  const ctx = new SyncTestContext(defaultDatabase);
  const { auth, user } = await ctx.newSyncAuthUser();
  return { auth, user, ctx };
};

const newSpace = async (ctx: SyncTestContext, ownerId: string, memberId?: string) => {
  const space = await ctx.database
    .insertInto('shared_space')
    .values({ id: newUuid(), name: 'Space', storageLabel: newUuid() })
    .returningAll()
    .executeTakeFirstOrThrow();
  await ctx.database
    .insertInto('shared_space_member')
    .values({ spaceId: space.id, userId: ownerId, role: SharedSpaceRole.Owner })
    .execute();
  if (memberId) {
    await ctx.database
      .insertInto('shared_space_member')
      .values({ spaceId: space.id, userId: memberId, role: SharedSpaceRole.Contributor })
      .execute();
  }
  return space;
};

const newLibrary = async (ctx: SyncTestContext, ownerId: string, memberId?: string) => {
  const library = await ctx.database
    .insertInto('library')
    .values({ id: newUuid(), name: 'Library', ownerId, importPaths: [], exclusionPatterns: [] })
    .returningAll()
    .executeTakeFirstOrThrow();
  if (memberId) {
    await ctx.database.insertInto('library_member').values({ libraryId: library.id, userId: memberId }).execute();
  }
  return library;
};

beforeAll(async () => {
  defaultDatabase = await getKyselyDB();
});

describe('shared container asset sync (S6)', () => {
  it('[SY-01] [SY-02] [R16-04] syncs space create/update favorite, move-out removal, and excludes own contributions', async () => {
    const { auth, user, ctx } = await setup();
    const { user: contributor } = await ctx.newUser();
    const space = await newSpace(ctx, contributor.id, user.id);
    const { asset } = await ctx.newAsset({ ownerId: contributor.id, spaceId: space.id, isFavorite: true });
    const { asset: ownAsset } = await ctx.newAsset({ ownerId: user.id, spaceId: space.id });

    const first = await ctx.syncStream(auth, [SyncRequestType.AssetsV2, SyncRequestType.SharedSpaceAssetsV1]);
    expect(first).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: SyncEntityType.AssetV2,
          data: expect.objectContaining({ id: ownAsset.id, spaceId: space.id }),
        }),
        expect.objectContaining({
          type: SyncEntityType.SharedSpaceAssetCreateV1,
          data: expect.objectContaining({ id: asset.id, spaceId: space.id, isFavorite: true }),
        }),
      ]),
    );
    expect(first).not.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ type: SyncEntityType.SharedSpaceAssetCreateV1, data: { id: ownAsset.id } }),
      ]),
    );
    await ctx.syncAckAll(auth, first);

    await ctx.database.updateTable('asset').set({ isFavorite: false }).where('id', '=', asset.id).execute();
    const favoriteUpdate = await ctx.syncStream(auth, [SyncRequestType.SharedSpaceAssetsV1]);
    expect(favoriteUpdate).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: SyncEntityType.SharedSpaceAssetUpdateV1,
          data: expect.objectContaining({ id: asset.id, isFavorite: false }),
        }),
      ]),
    );
    await ctx.syncAckAll(auth, favoriteUpdate);

    await ctx.database.updateTable('asset').set({ spaceId: null }).where('id', '=', asset.id).execute();
    await expect(ctx.syncStream(auth, [SyncRequestType.SharedSpaceAssetsV1])).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ type: SyncEntityType.SharedSpaceAssetRemoveV1, data: { assetId: asset.id } }),
      ]),
    );
  });

  it('[SY-03] [SY-04] backfills a newly joined space and emits a container delete on leave', async () => {
    const { auth, user, ctx } = await setup();
    const { user: owner } = await ctx.newUser();
    const space = await newSpace(ctx, owner.id);
    const { asset } = await ctx.newAsset({ ownerId: owner.id, spaceId: space.id });

    const initial = await ctx.syncStream(auth, [SyncRequestType.SharedSpaceAssetsV1, SyncRequestType.SharedSpacesV1]);
    await ctx.syncAckAll(auth, initial);
    await ctx.database
      .insertInto('shared_space_member')
      .values({ spaceId: space.id, userId: user.id, role: SharedSpaceRole.Contributor })
      .execute();
    const joined = await ctx.syncStream(auth, [SyncRequestType.SharedSpaceAssetsV1]);
    expect(joined).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: SyncEntityType.SharedSpaceAssetBackfillV1,
          data: expect.objectContaining({ id: asset.id }),
        }),
        expect.objectContaining({
          ack: expect.stringContaining(SyncEntityType.SharedSpaceAssetBackfillV1),
          type: SyncEntityType.SyncAckV1,
        }),
      ]),
    );
    await ctx.syncAckAll(auth, joined);

    await ctx.database
      .deleteFrom('shared_space_member')
      .where('spaceId', '=', space.id)
      .where('userId', '=', user.id)
      .execute();
    await expect(ctx.syncStream(auth, [SyncRequestType.SharedSpacesV1])).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ type: SyncEntityType.SharedSpaceDeleteV1, data: { spaceId: space.id } }),
      ]),
    );
  });

  it('[SY-05] [R16-04] syncs external-library assets and emits removal/deletion for membership loss', async () => {
    const { auth, user, ctx } = await setup();
    const { user: owner } = await ctx.newUser();
    const library = await newLibrary(ctx, owner.id, user.id);
    const { asset } = await ctx.newAsset({ ownerId: owner.id, libraryId: library.id, isFavorite: true });

    const first = await ctx.syncStream(auth, [
      SyncRequestType.SharedLibraryAssetsV1,
      SyncRequestType.SharedLibrariesV1,
    ]);
    expect(first).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: SyncEntityType.SharedLibraryAssetCreateV1,
          data: expect.objectContaining({ id: asset.id, libraryId: library.id, isFavorite: true }),
        }),
      ]),
    );
    await ctx.syncAckAll(auth, first);

    await ctx.database.updateTable('asset').set({ isFavorite: false }).where('id', '=', asset.id).execute();
    await expect(ctx.syncStream(auth, [SyncRequestType.SharedLibraryAssetsV1])).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: SyncEntityType.SharedLibraryAssetUpdateV1,
          data: expect.objectContaining({ id: asset.id, isFavorite: false }),
        }),
      ]),
    );

    await ctx.database.updateTable('asset').set({ libraryId: null }).where('id', '=', asset.id).execute();
    await expect(ctx.syncStream(auth, [SyncRequestType.SharedLibraryAssetsV1])).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ type: SyncEntityType.SharedLibraryAssetRemoveV1, data: { assetId: asset.id } }),
      ]),
    );

    await ctx.database
      .deleteFrom('library_member')
      .where('libraryId', '=', library.id)
      .where('userId', '=', user.id)
      .execute();
    await expect(ctx.syncStream(auth, [SyncRequestType.SharedLibrariesV1])).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ type: SyncEntityType.SharedLibraryDeleteV1, data: { libraryId: library.id } }),
      ]),
    );
  });
});
