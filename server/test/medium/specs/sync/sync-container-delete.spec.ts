import { Kysely } from 'kysely';
import { SharedSpaceRole, SyncEntityType, SyncRequestType } from 'src/enum.js';
import { LibraryRepository } from 'src/repositories/library.repository.js';
import { SharedSpaceRepository } from 'src/repositories/shared-space.repository.js';
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

const newSpace = async (ctx: SyncTestContext, ownerId: string, memberId: string) => {
  const space = await ctx.database
    .insertInto('shared_space')
    .values({ id: newUuid(), name: 'Space', storageLabel: newUuid() })
    .returningAll()
    .executeTakeFirstOrThrow();
  await ctx.database
    .insertInto('shared_space_member')
    .values([
      { spaceId: space.id, userId: ownerId, role: SharedSpaceRole.Owner },
      { spaceId: space.id, userId: memberId, role: SharedSpaceRole.Contributor },
    ])
    .execute();
  return space;
};

const newLibrary = async (ctx: SyncTestContext, ownerId: string, memberId: string) => {
  const library = await ctx.database
    .insertInto('library')
    .values({ id: newUuid(), name: 'Library', ownerId, importPaths: [], exclusionPatterns: [] })
    .returningAll()
    .executeTakeFirstOrThrow();
  await ctx.database.insertInto('library_member').values({ libraryId: library.id, userId: memberId }).execute();
  return library;
};

beforeAll(async () => {
  defaultDatabase = await getKyselyDB();
});

// C3: container deletion must leave user-keyed sync tombstones. Member rows
// cascade on container delete, which skips the member-delete audit trigger via
// its depth guard — without an explicit tombstone the members' clients would
// keep showing the deleted container forever (no delete event, no upserts).
// Member *removal* delivery is covered by [SY-03] [SY-04] [SY-05]; the Apple
// client drops containers on these events (membershipLoss fixture test).
describe('shared container deletion sync (C3)', () => {
  it('[LC-01] [C3] space deletion emits SharedSpaceDeleteV1 to members', async () => {
    const { auth, user, ctx } = await setup();
    const { user: owner } = await ctx.newUser();
    const space = await newSpace(ctx, owner.id, user.id);
    await ctx.newAsset({ ownerId: owner.id, spaceId: space.id });

    const initial = await ctx.syncStream(auth, [SyncRequestType.SharedSpacesV1]);
    expect(initial).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: SyncEntityType.SharedSpaceV1,
          data: expect.objectContaining({ id: space.id }),
        }),
      ]),
    );
    await ctx.syncAckAll(auth, initial);

    await new SharedSpaceRepository(ctx.database).deleteSpace(space.id, async () => {});

    await expect(ctx.syncStream(auth, [SyncRequestType.SharedSpacesV1])).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ type: SyncEntityType.SharedSpaceDeleteV1, data: { spaceId: space.id } }),
      ]),
    );
    // The container delete is the channel: no per-member delete is emitted.
    await expect(ctx.syncStream(auth, [SyncRequestType.SharedSpaceMembersV1])).resolves.toEqual(
      expect.not.arrayContaining([expect.objectContaining({ type: SyncEntityType.SharedSpaceMemberDeleteV1 })]),
    );
  });

  it('[C3] library deletion emits SharedLibraryDeleteV1 to members', async () => {
    const { auth, user, ctx } = await setup();
    const { user: owner } = await ctx.newUser();
    const library = await newLibrary(ctx, owner.id, user.id);
    await ctx.newAsset({ ownerId: owner.id, libraryId: library.id });

    const initial = await ctx.syncStream(auth, [SyncRequestType.SharedLibrariesV1]);
    expect(initial).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: SyncEntityType.SharedLibraryV1,
          data: expect.objectContaining({ id: library.id }),
        }),
      ]),
    );
    await ctx.syncAckAll(auth, initial);

    await new LibraryRepository(ctx.database).delete(library.id);

    await expect(ctx.syncStream(auth, [SyncRequestType.SharedLibrariesV1])).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ type: SyncEntityType.SharedLibraryDeleteV1, data: { libraryId: library.id } }),
      ]),
    );
  });
});
