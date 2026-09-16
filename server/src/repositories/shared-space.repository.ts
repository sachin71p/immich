import { Injectable } from '@nestjs/common';
import { type Kysely, type Updateable } from 'kysely';
import { InjectKysely } from 'nestjs-kysely';
import { SharedSpaceRole } from 'src/enum.js';
import { DB } from 'src/schema/index.js';
import { SharedSpaceTable } from 'src/schema/tables/shared-space.table.js';

export type SharedSpaceWithStats = {
  id: string;
  name: string;
  description: string;
  thumbnailAssetId: string | null;
  createdAt: Date;
  updatedAt: Date;
  role: SharedSpaceRole;
  showInTimeline: boolean;
  memberCount: number;
  assetCount: number;
};

@Injectable()
export class SharedSpaceRepository {
  constructor(@InjectKysely() private db: Kysely<DB>) {}

  private withStats(userId: string) {
    return this.db
      .selectFrom('shared_space')
      .innerJoin('shared_space_member as member', (join) =>
        join.onRef('member.spaceId', '=', 'shared_space.id').on('member.userId', '=', userId),
      )
      .select([
        'shared_space.id',
        'shared_space.name',
        'shared_space.description',
        'shared_space.thumbnailAssetId',
        'shared_space.createdAt',
        'shared_space.updatedAt',
        'member.role',
        'member.showInTimeline',
      ])
      .select((eb) => [
        eb
          .selectFrom('shared_space_member as member_count')
          .select((eb) => eb.fn.countAll<number>().as('count'))
          .whereRef('member_count.spaceId', '=', 'shared_space.id')
          .as('memberCount'),
        eb
          .selectFrom('asset')
          .select((eb) => eb.fn.countAll<number>().as('count'))
          .whereRef('asset.spaceId', '=', 'shared_space.id')
          .where('asset.deletedAt', 'is', null)
          .as('assetCount'),
      ]);
  }

  getAll(userId: string): Promise<SharedSpaceWithStats[]> {
    return this.withStats(userId).orderBy('shared_space.createdAt', 'asc').execute() as Promise<SharedSpaceWithStats[]>;
  }

  get(id: string, userId: string): Promise<SharedSpaceWithStats | undefined> {
    return this.withStats(userId).where('shared_space.id', '=', id).executeTakeFirst() as Promise<
      SharedSpaceWithStats | undefined
    >;
  }

  async create({
    name,
    description,
    createdById,
    storageLabel,
  }: {
    name: string;
    description?: string;
    createdById: string;
    storageLabel: string;
  }) {
    return this.db.transaction().execute(async (trx) => {
      const space = await trx
        .insertInto('shared_space')
        .values({ name, description: description ?? '', createdById, storageLabel, thumbnailAssetId: null })
        .returningAll()
        .executeTakeFirstOrThrow();
      await trx
        .insertInto('shared_space_member')
        .values({ spaceId: space.id, userId: createdById, role: SharedSpaceRole.Owner })
        .execute();
      return space;
    });
  }

  async getStorageLabelCandidates(base: string): Promise<string[]> {
    return this.db
      .selectFrom('shared_space')
      .select('storageLabel')
      .where('storageLabel', 'like', `${base}%`)
      .execute()
      .then((spaces) => spaces.map(({ storageLabel }) => storageLabel));
  }

  update(id: string, dto: Updateable<SharedSpaceTable>) {
    return this.db.updateTable('shared_space').set(dto).where('id', '=', id).returningAll().executeTakeFirstOrThrow();
  }

  getMembers(spaceId: string) {
    return this.db
      .selectFrom('shared_space_member')
      .select(['userId', 'role', 'showInTimeline', 'createdAt'])
      .where('spaceId', '=', spaceId)
      .orderBy('createdAt', 'asc')
      .execute();
  }

  // fork: shared-libraries
  getOwnedSpaces(userId: string) {
    return this.db
      .selectFrom('shared_space_member')
      .select('spaceId')
      .where('userId', '=', userId)
      .where('role', '=', SharedSpaceRole.Owner)
      .execute();
  }

  async addMembers(spaceId: string, userIds: string[]) {
    const existing = await this.db
      .selectFrom('user')
      .select('id')
      .where('id', 'in', userIds)
      .where('deletedAt', 'is', null)
      .execute();
    if (existing.length !== userIds.length) return false;
    const current = await this.db
      .selectFrom('shared_space_member')
      .select('userId')
      .where('spaceId', '=', spaceId)
      .where('userId', 'in', userIds)
      .execute();
    if (current.length > 0) return false;
    await this.db
      .insertInto('shared_space_member')
      .values(userIds.map((userId) => ({ spaceId, userId })))
      .execute();
    return true;
  }

  removeMember(spaceId: string, userId: string) {
    return this.db
      .deleteFrom('shared_space_member')
      .where('spaceId', '=', spaceId)
      .where('userId', '=', userId)
      .executeTakeFirst();
  }

  updateMember(spaceId: string, userId: string, values: { role?: SharedSpaceRole; showInTimeline?: boolean }) {
    return this.db
      .updateTable('shared_space_member')
      .set(values)
      .where('spaceId', '=', spaceId)
      .where('userId', '=', userId)
      .execute();
  }

  async transferOwner(spaceId: string, ownerId: string, nextOwnerId: string) {
    await this.db.transaction().execute(async (trx) => {
      await trx
        .updateTable('shared_space_member')
        .set({ role: SharedSpaceRole.Contributor })
        .where('spaceId', '=', spaceId)
        .where('userId', '=', ownerId)
        .execute();
      await trx
        .updateTable('shared_space_member')
        .set({ role: SharedSpaceRole.Owner })
        .where('spaceId', '=', spaceId)
        .where('userId', '=', nextOwnerId)
        .execute();
    });
  }

  async deleteSpace(id: string, onAssets: (assetIds: string[], trx: Kysely<DB>) => Promise<void>): Promise<void> {
    await this.db.transaction().execute(async (trx) => {
      const assets = await trx
        .updateTable('asset')
        .set({ spaceId: null })
        .where('spaceId', '=', id)
        .returning('id')
        .execute();
      await onAssets(
        assets.map(({ id }) => id),
        trx,
      );
      // fork: shared-libraries (C3: member rows cascade on space delete, which skips
      // the member-delete audit trigger via its depth guard. Leave user-keyed
      // tombstones first so every member still receives SharedSpaceDeleteV1.)
      await trx
        .insertInto('shared_space_audit')
        .columns(['spaceId', 'userId'])
        .expression((eb) =>
          eb.selectFrom('shared_space_member').select(['spaceId', 'userId']).where('spaceId', '=', id),
        )
        .execute();
      await trx.deleteFrom('shared_space').where('id', '=', id).execute();
    });
  }

  async isMember(spaceId: string, userId: string): Promise<boolean> {
    return !!(await this.db
      .selectFrom('shared_space_member')
      .select('spaceId')
      .where('spaceId', '=', spaceId)
      .where('userId', '=', userId)
      .executeTakeFirst());
  }
}
