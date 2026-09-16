import { Kysely } from 'kysely';
import { SharedSpaceRole } from 'src/enum.js';
import { AccessRepository } from 'src/repositories/access.repository.js';
import { ClusterGroupRepository } from 'src/repositories/cluster-group.repository.js';
import { EventRepository } from 'src/repositories/event.repository.js';
import { LoggingRepository } from 'src/repositories/logging.repository.js';
import { PersonRepository } from 'src/repositories/person.repository.js';
import { SearchRepository } from 'src/repositories/search.repository.js';
import { UserRepository } from 'src/repositories/user.repository.js';
import { DB } from 'src/schema/index.js';
import { ClusterGroupService } from 'src/services/cluster-group.service.js';
import { newMediumService } from 'test/medium.factory.js';
import { factory, newEmbedding, newUuid } from 'test/small.factory.js';
import { getKyselyDB } from 'test/utils.js';

let defaultDatabase: Kysely<DB>;

// fork: shared-libraries (§3c) - how the S9 space-scoped face graphs compose with
// upstream's user-level cluster groups. MEDIUM (host Docker); cannot run in sandbox.
const setup = (db?: Kysely<DB>) => {
  const ctx = newMediumService(ClusterGroupService, {
    database: db || defaultDatabase,
    real: [AccessRepository, ClusterGroupRepository, PersonRepository, UserRepository, SearchRepository],
    mock: [LoggingRepository, EventRepository],
  });

  ctx.ctx.getMock(EventRepository).emit.mockResolvedValue();

  return ctx;
};

const getClusterGroupId = async (ctx: ReturnType<typeof setup>['ctx'], userId: string) => {
  const { clusterGroupId } = await ctx.database
    .selectFrom('user')
    .select('user.clusterGroupId')
    .where('user.id', '=', userId)
    .executeTakeFirstOrThrow();

  return clusterGroupId;
};

beforeAll(async () => {
  defaultDatabase = await getKyselyDB();
});

describe('cluster-group interaction', () => {
  it('composes space membership and cluster-group membership without duplicates or leaks', async () => {
    const { sut, ctx } = setup();
    const person = ctx.get(PersonRepository);
    const search = ctx.get(SearchRepository);
    const { user: host } = await ctx.newUser();
    const { user: guest } = await ctx.newUser();
    const hostGroupId = await getClusterGroupId(ctx, host.id);

    // Guest is a member of the host's space.
    const space = await ctx.database
      .insertInto('shared_space')
      .values({ id: newUuid(), name: 'Interaction space', storageLabel: newUuid() })
      .returningAll()
      .executeTakeFirstOrThrow();
    await ctx.database
      .insertInto('shared_space_member')
      .values([
        { spaceId: space.id, userId: host.id, role: SharedSpaceRole.Owner },
        { spaceId: space.id, userId: guest.id, role: SharedSpaceRole.Contributor },
      ])
      .execute();

    // Personal rows: each user has a named person with a face on their own asset.
    const { asset: hostAsset } = await ctx.newAsset({ ownerId: host.id });
    const { person: hostPersonal } = await ctx.newPerson({ ownerId: host.id, name: 'Host Personal' });
    const { assetFace: hostFace } = await ctx.newAssetFace({
      assetId: hostAsset.id,
      personGroupId: hostPersonal.personGroupId,
    });
    const { asset: guestAsset } = await ctx.newAsset({ ownerId: guest.id });
    const { person: guestPersonal } = await ctx.newPerson({ ownerId: guest.id, name: 'Guest Personal' });
    const { assetFace: guestFace } = await ctx.newAssetFace({
      assetId: guestAsset.id,
      personGroupId: guestPersonal.personGroupId,
    });
    const guestEmbedding = newEmbedding();
    await ctx.database.insertInto('face_search').values({ faceId: guestFace.id, embedding: guestEmbedding }).execute();
    await ctx.database.insertInto('face_search').values({ faceId: hostFace.id, embedding: newEmbedding() }).execute();

    // Space-scoped row in the space's universe with a face on a space asset (S9).
    const spaceGroup = await person.createSpaceGroup(space.id);
    const { asset: spaceAsset } = await ctx.newAsset({ ownerId: guest.id, spaceId: space.id });
    const { person: spacePerson } = await ctx.newPerson({
      ownerId: host.id,
      spaceId: space.id,
      personGroupId: spaceGroup.id,
      name: 'Space Person',
    });
    await ctx.newAssetFace({ assetId: spaceAsset.id, personGroupId: spacePerson.personGroupId });

    const memberships = await person.getMemberSpaceIds(guest.id, true);
    const memberSpaceIds = memberships.map(({ spaceId }) => spaceId);
    expect(memberSpaceIds).toEqual([space.id]);

    // One coherent set: guest's personal rows plus space rows, no duplicates,
    // and none of the host's personal rows.
    const { items } = await person.getAllForUser({ skip: 0, take: 10 }, guest.id, {
      withHidden: false,
      memberSpaceIds,
    });
    const groupIds = items.map(({ personGroupId }) => personGroupId);
    expect(new Set(groupIds).size).toBe(groupIds.length);
    expect(groupIds).toEqual(expect.arrayContaining([guestPersonal.personGroupId, spacePerson.personGroupId]));
    expect(groupIds).not.toContain(hostPersonal.personGroupId);

    // Renaming is per-row: the space row and the personal row are independent.
    await person.update({ ownerId: host.id, personGroupId: spacePerson.personGroupId, name: 'Space Renamed' });
    await expect(
      person.getByGroupId({ ownerId: guest.id, personGroupId: guestPersonal.personGroupId }),
    ).resolves.toEqual(expect.objectContaining({ name: 'Guest Personal' }));
    await person.update({ ownerId: guest.id, personGroupId: guestPersonal.personGroupId, name: 'Guest Renamed' });
    await expect(person.getByGroupId({ ownerId: host.id, personGroupId: spacePerson.personGroupId })).resolves.toEqual(
      expect.objectContaining({ name: 'Space Renamed' }),
    );

    // Before joining the host's cluster group, the guest's assets are outside
    // its face-search scope even though the guest is a space member: S9 does not
    // bypass upstream cluster-group sharing.
    await expect(
      search.searchFaces({ clusterGroupId: hostGroupId, embedding: guestEmbedding, numResults: 10, maxDistance: 0.6 }),
    ).resolves.toEqual(expect.not.arrayContaining([expect.objectContaining({ id: guestFace.id })]));

    // Guest accepts into the host's cluster group via the upstream request flow.
    const { value: request } = await sut.createRequest(factory.auth({ user: host }), hostGroupId, {
      userId: guest.id,
    });
    await sut.acceptRequest(factory.auth({ user: guest }), request.id);

    // The guest's solely-owned person groups move into the host's cluster group
    // while list membership (person.ownerId) is unchanged.
    await expect(getClusterGroupId(ctx, guest.id)).resolves.toBe(hostGroupId);
    const groups = await ctx.database
      .selectFrom('person_group')
      .innerJoin('person', 'person.personGroupId', 'person_group.id')
      .select(['person_group.clusterGroupId', 'person.ownerId'])
      .where('person.ownerId', '=', guest.id)
      .execute();
    expect(groups.length).toBeGreaterThan(0);
    for (const group of groups) {
      expect(group).toEqual(expect.objectContaining({ clusterGroupId: hostGroupId, ownerId: guest.id }));
    }
    const after = await person.getAllForUser({ skip: 0, take: 10 }, guest.id, {
      withHidden: false,
      memberSpaceIds,
    });
    expect(after.items.map(({ personGroupId }) => personGroupId)).toContain(guestPersonal.personGroupId);

    // Now the guest's assets are in scope for the host group's face search.
    await expect(
      search.searchFaces({ clusterGroupId: hostGroupId, embedding: guestEmbedding, numResults: 10, maxDistance: 0.6 }),
    ).resolves.toEqual(expect.arrayContaining([expect.objectContaining({ id: guestFace.id })]));
  });
});
