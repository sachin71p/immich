import { Kysely } from 'kysely';
import { AssetFileType, MemoryType, SharedSpaceRole } from 'src/enum.js';
import { AccessRepository } from 'src/repositories/access.repository.js';
import { LoggingRepository } from 'src/repositories/logging.repository.js';
import { MemoryRepository } from 'src/repositories/memory.repository.js';
import { DB } from 'src/schema/index.js';
import { BaseService } from 'src/services/base.service.js';
import { newMediumService } from 'test/medium.factory.js';
import { newUuid } from 'test/small.factory.js';
import { getKyselyDB } from 'test/utils.js';

let defaultDatabase: Kysely<DB>;

const setup = (db = defaultDatabase) => {
  const { ctx } = newMediumService(BaseService, { database: db, real: [], mock: [LoggingRepository] });
  return { access: ctx.get(AccessRepository), ctx, memory: ctx.get(MemoryRepository) };
};

const newSpace = async (ctx: ReturnType<typeof setup>['ctx'], ownerId: string, memberId: string) => {
  const space = await ctx.database
    .insertInto('shared_space')
    .values({ id: newUuid(), name: 'Access test space', storageLabel: newUuid() })
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

const newLibrary = async (ctx: ReturnType<typeof setup>['ctx'], ownerId: string, memberId: string) => {
  const library = await ctx.database
    .insertInto('library')
    .values({ id: newUuid(), name: 'Access test library', ownerId, importPaths: [], exclusionPatterns: [] })
    .returningAll()
    .executeTakeFirstOrThrow();
  await ctx.database.insertInto('library_member').values({ libraryId: library.id, userId: memberId }).execute();
  return library;
};

beforeAll(async () => {
  defaultDatabase = await getKyselyDB();
});

describe(AccessRepository.name, () => {
  it('PERM-11 denies a removed contributor direct asset, asset-file, and memory access', async () => {
    const { access, ctx, memory } = setup();
    const { user: containerOwner } = await ctx.newUser();
    const { user: contributor } = await ctx.newUser();
    const space = await newSpace(ctx, containerOwner.id, contributor.id);
    const library = await newLibrary(ctx, containerOwner.id, contributor.id);
    const { asset: spaceAsset } = await ctx.newAsset({ ownerId: contributor.id, spaceId: space.id });
    const { asset: libraryAsset } = await ctx.newAsset({ ownerId: contributor.id, libraryId: library.id });
    const spaceFileId = newUuid();
    const libraryFileId = newUuid();
    await Promise.all([
      ctx.newAssetFile({
        id: spaceFileId,
        assetId: spaceAsset.id,
        type: AssetFileType.Preview,
        path: '/space/preview.jpg',
      }),
      ctx.newAssetFile({
        id: libraryFileId,
        assetId: libraryAsset.id,
        type: AssetFileType.Preview,
        path: '/library/preview.jpg',
      }),
    ]);
    const { memory: userMemory } = await ctx.newMemory({ ownerId: contributor.id, type: MemoryType.OnThisDay });
    await Promise.all([
      ctx.newMemoryAsset({ memoryId: userMemory.id, assetId: spaceAsset.id }),
      ctx.newMemoryAsset({ memoryId: userMemory.id, assetId: libraryAsset.id }),
    ]);

    await expect(
      access.asset.checkOwnerAccess(contributor.id, new Set([spaceAsset.id, libraryAsset.id]), false),
    ).resolves.toEqual(new Set([spaceAsset.id, libraryAsset.id]));
    await expect(
      access.assetFile.checkOwnerAccess(contributor.id, new Set([spaceFileId, libraryFileId]), false),
    ).resolves.toEqual(new Set([spaceFileId, libraryFileId]));
    await expect(memory.get(userMemory.id)).resolves.toEqual(
      expect.objectContaining({
        assets: expect.arrayContaining([
          expect.objectContaining({ id: spaceAsset.id }),
          expect.objectContaining({ id: libraryAsset.id }),
        ]),
      }),
    );

    await ctx.database
      .deleteFrom('shared_space_member')
      .where('spaceId', '=', space.id)
      .where('userId', '=', contributor.id)
      .execute();
    await ctx.database
      .deleteFrom('library_member')
      .where('libraryId', '=', library.id)
      .where('userId', '=', contributor.id)
      .execute();

    await expect(
      access.asset.checkOwnerAccess(contributor.id, new Set([spaceAsset.id, libraryAsset.id]), false),
    ).resolves.toEqual(new Set());
    await expect(
      access.assetFile.checkOwnerAccess(contributor.id, new Set([spaceFileId, libraryFileId]), false),
    ).resolves.toEqual(new Set());
    await expect(memory.get(userMemory.id)).resolves.toEqual(expect.objectContaining({ assets: [] }));
    await expect(memory.search(contributor.id, {})).resolves.toEqual([
      expect.objectContaining({ id: userMemory.id, assets: [] }),
    ]);
  });

  it('PERM-11 denies a removed contributor person and face access', async () => {
    const { access, ctx } = setup();
    const { user: containerOwner } = await ctx.newUser();
    const { user: contributor } = await ctx.newUser();
    const space = await newSpace(ctx, containerOwner.id, contributor.id);
    const { asset: spaceAsset } = await ctx.newAsset({ ownerId: contributor.id, spaceId: space.id });
    const { person: spacePerson } = await ctx.newPerson({ ownerId: contributor.id, spaceId: space.id });
    const { person: personalPerson } = await ctx.newPerson({ ownerId: contributor.id });
    const { assetFace } = await ctx.newAssetFace({
      assetId: spaceAsset.id,
      personGroupId: spacePerson.personGroupId,
    });

    // While a member, the contributor reaches their space person and its faces,
    // and so does the space owner through the S9 member branch.
    await expect(access.person.checkOwnerAccess(contributor.id, new Set([spacePerson.personGroupId]))).resolves.toEqual(
      new Set([spacePerson.personGroupId]),
    );
    await expect(
      access.person.checkOwnerAccess(containerOwner.id, new Set([spacePerson.personGroupId])),
    ).resolves.toEqual(new Set([spacePerson.personGroupId]));
    await expect(access.person.checkFaceOwnerAccess(contributor.id, new Set([assetFace.id]))).resolves.toEqual(
      new Set([assetFace.id]),
    );

    await ctx.database
      .deleteFrom('shared_space_member')
      .where('spaceId', '=', space.id)
      .where('userId', '=', contributor.id)
      .execute();

    // After removal the contributor keeps only their own personal person.
    await expect(access.person.checkOwnerAccess(contributor.id, new Set([spacePerson.personGroupId]))).resolves.toEqual(
      new Set(),
    );
    await expect(access.person.checkFaceOwnerAccess(contributor.id, new Set([assetFace.id]))).resolves.toEqual(
      new Set(),
    );
    await expect(
      access.person.checkOwnerAccess(contributor.id, new Set([personalPerson.personGroupId])),
    ).resolves.toEqual(new Set([personalPerson.personGroupId]));
    // The remaining member still reaches the space person.
    await expect(
      access.person.checkOwnerAccess(containerOwner.id, new Set([spacePerson.personGroupId])),
    ).resolves.toEqual(new Set([spacePerson.personGroupId]));
  });

  it('PERM-11 denies a removed library member face access to owned library assets', async () => {
    const { access, ctx } = setup();
    const { user: libOwner } = await ctx.newUser();
    const { user: contributor } = await ctx.newUser();
    const { user: member } = await ctx.newUser();
    const library = await newLibrary(ctx, libOwner.id, contributor.id);
    await ctx.database.insertInto('library_member').values({ libraryId: library.id, userId: member.id }).execute();
    const { asset: libraryAsset } = await ctx.newAsset({ ownerId: contributor.id, libraryId: library.id });
    const { person: personalPerson } = await ctx.newPerson({ ownerId: contributor.id });
    const { assetFace } = await ctx.newAssetFace({
      assetId: libraryAsset.id,
      personGroupId: personalPerson.personGroupId,
    });

    // While a member, the contributor reaches faces on their owned library asset
    // and keeps their personal person; a current non-owner member gains nothing
    // (the refused library-membership face grant, DECISIONS §4).
    await expect(access.person.checkFaceOwnerAccess(contributor.id, new Set([assetFace.id]))).resolves.toEqual(
      new Set([assetFace.id]),
    );
    await expect(
      access.person.checkOwnerAccess(contributor.id, new Set([personalPerson.personGroupId])),
    ).resolves.toEqual(new Set([personalPerson.personGroupId]));
    await expect(access.person.checkFaceOwnerAccess(member.id, new Set([assetFace.id]))).resolves.toEqual(new Set());
    await expect(access.person.checkOwnerAccess(member.id, new Set([personalPerson.personGroupId]))).resolves.toEqual(
      new Set(),
    );

    await ctx.database
      .deleteFrom('library_member')
      .where('libraryId', '=', library.id)
      .where('userId', '=', contributor.id)
      .execute();

    // After removal the contributor loses face access to the owned library asset
    // (the gate) but keeps their own personal person (no over-deny).
    await expect(access.person.checkFaceOwnerAccess(contributor.id, new Set([assetFace.id]))).resolves.toEqual(
      new Set(),
    );
    await expect(
      access.person.checkOwnerAccess(contributor.id, new Set([personalPerson.personGroupId])),
    ).resolves.toEqual(new Set([personalPerson.personGroupId]));
  });

  it('PERM-01-nonmember denies partner access to space and library assets', async () => {
    const { access, ctx } = setup();
    const { user: containerOwner } = await ctx.newUser();
    const { user: assetOwner } = await ctx.newUser();
    const { user: partner } = await ctx.newUser();
    await ctx.newPartner({ sharedById: assetOwner.id, sharedWithId: partner.id });
    const space = await newSpace(ctx, containerOwner.id, assetOwner.id);
    const library = await newLibrary(ctx, containerOwner.id, assetOwner.id);
    const { asset: personalAsset } = await ctx.newAsset({ ownerId: assetOwner.id });
    const { asset: spaceAsset } = await ctx.newAsset({ ownerId: assetOwner.id, spaceId: space.id });
    const { asset: libraryAsset } = await ctx.newAsset({ ownerId: assetOwner.id, libraryId: library.id });

    await expect(
      access.asset.checkPartnerAccess(partner.id, new Set([personalAsset.id, spaceAsset.id, libraryAsset.id])),
    ).resolves.toEqual(new Set([personalAsset.id]));
  });
});
