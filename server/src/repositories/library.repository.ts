import { Injectable } from '@nestjs/common';
import { type Insertable, type Kysely, type Updateable, sql } from 'kysely';
import { InjectKysely } from 'nestjs-kysely';
import { DummyValue, GenerateSql } from 'src/decorators.js';
import { LibraryStatsResponseDto } from 'src/dtos/library.dto.js';
import { AssetType, AssetVisibility } from 'src/enum.js';
import { DB } from 'src/schema/index.js';
import { LibraryTable } from 'src/schema/tables/library.table.js';

export enum AssetSyncResult {
  DO_NOTHING,
  UPDATE,
  OFFLINE,
  CHECK_OFFLINE,
}

@Injectable()
export class LibraryRepository {
  constructor(@InjectKysely() private db: Kysely<DB>) {}

  @GenerateSql({ params: [DummyValue.UUID] })
  get(id: string, withDeleted = false) {
    return this.db
      .selectFrom('library')
      .selectAll('library')
      .where('library.id', '=', id)
      .$if(!withDeleted, (qb) => qb.where('library.deletedAt', 'is', null))
      .executeTakeFirst();
  }

  @GenerateSql({ params: [] })
  getAll(withDeleted = false) {
    return this.db
      .selectFrom('library')
      .selectAll('library')
      .orderBy('createdAt', 'asc')
      .$if(!withDeleted, (qb) => qb.where('library.deletedAt', 'is', null))
      .execute();
  }

  @GenerateSql()
  getAllDeleted() {
    return this.db
      .selectFrom('library')
      .selectAll('library')
      .where('library.deletedAt', 'is not', null)
      .orderBy('createdAt', 'asc')
      .execute();
  }

  create(library: Insertable<LibraryTable>) {
    return this.db.insertInto('library').values(library).returningAll().executeTakeFirstOrThrow();
  }

  async delete(id: string) {
    await this.db.transaction().execute(async (trx) => {
      // fork: shared-libraries (C3: member rows cascade on library delete, which skips
      // the member-delete audit trigger. Leave user-keyed tombstones first so every
      // member still receives SharedLibraryDeleteV1.)
      await trx
        .insertInto('library_member_audit')
        .columns(['libraryId', 'userId'])
        .expression((eb) => eb.selectFrom('library_member').select(['libraryId', 'userId']).where('libraryId', '=', id))
        .execute();
      await trx.deleteFrom('library').where('library.id', '=', id).execute();
    });
  }

  async softDelete(id: string) {
    await this.db.updateTable('library').set({ deletedAt: new Date() }).where('library.id', '=', id).execute();
  }

  update(id: string, library: Updateable<LibraryTable>) {
    return this.db
      .updateTable('library')
      .set(library)
      .where('library.id', '=', id)
      .returningAll()
      .executeTakeFirstOrThrow();
  }

  // fork: shared-libraries
  getMembers(libraryId: string) {
    return this.db
      .selectFrom('library_member')
      .select(['userId', 'showInTimeline', 'createdAt'])
      .where('libraryId', '=', libraryId)
      .orderBy('createdAt', 'asc')
      .execute();
  }

  // fork: shared-libraries
  async addMembers(libraryId: string, userIds: string[]) {
    const users = await this.db
      .selectFrom('user')
      .select('id')
      .where('id', 'in', userIds)
      .where('deletedAt', 'is', null)
      .execute();
    if (users.length !== userIds.length) return false;
    const existing = await this.db
      .selectFrom('library_member')
      .select('userId')
      .where('libraryId', '=', libraryId)
      .where('userId', 'in', userIds)
      .execute();
    if (existing.length > 0) return false;
    await this.db
      .insertInto('library_member')
      .values(userIds.map((userId) => ({ libraryId, userId })))
      .execute();
    return true;
  }

  // fork: shared-libraries
  removeMember(libraryId: string, userId: string) {
    return this.db
      .deleteFrom('library_member')
      .where('libraryId', '=', libraryId)
      .where('userId', '=', userId)
      .execute();
  }

  // fork: shared-libraries
  updateMember(libraryId: string, userId: string, showInTimeline: boolean) {
    return this.db
      .updateTable('library_member')
      .set({ showInTimeline })
      .where('libraryId', '=', libraryId)
      .where('userId', '=', userId)
      .execute();
  }

  // fork: shared-libraries
  getShared(userId: string) {
    return this.db
      .selectFrom('library')
      .leftJoin('library_member', (join) =>
        join.onRef('library_member.libraryId', '=', 'library.id').on('library_member.userId', '=', userId),
      )
      .select(['library.id', 'library.name', 'library.ownerId', 'library.uploadPath', 'library_member.showInTimeline'])
      .select((eb) =>
        eb
          .selectFrom('asset')
          .select((eb) => eb.fn.countAll<number>().as('count'))
          .whereRef('asset.libraryId', '=', 'library.id')
          .where('asset.deletedAt', 'is', null)
          .as('assetCount'),
      )
      .where('library.deletedAt', 'is', null)
      .where((eb) => eb.or([eb('library.ownerId', '=', userId), eb('library_member.userId', '=', userId)]))
      .execute();
  }

  @GenerateSql({ params: [DummyValue.UUID] })
  async getStatistics(id: string): Promise<LibraryStatsResponseDto | undefined> {
    const stats = await this.db
      .selectFrom('library')
      .innerJoin('asset', 'asset.libraryId', 'library.id')
      .leftJoin('asset_exif', 'asset_exif.assetId', 'asset.id')
      .select((eb) =>
        eb.fn
          .countAll<number>()
          .filterWhere((eb) =>
            eb.and([eb('asset.type', '=', AssetType.Image), eb('asset.visibility', '!=', AssetVisibility.Hidden)]),
          )
          .as('photos'),
      )
      .select((eb) =>
        eb.fn
          .countAll<number>()
          .filterWhere((eb) =>
            eb.and([eb('asset.type', '=', AssetType.Video), eb('asset.visibility', '!=', AssetVisibility.Hidden)]),
          )
          .as('videos'),
      )
      .select((eb) => eb.fn.coalesce((eb) => eb.fn.sum('asset_exif.fileSizeInByte'), eb.val(0)).as('usage'))
      .where('asset.deletedAt', 'is', null)
      .groupBy('library.id')
      .where('library.id', '=', id)
      .executeTakeFirst();

    // possibly a new library with 0 assets
    if (!stats) {
      const zero = sql<number>`0::int`;
      return this.db
        .selectFrom('library')
        .select(zero.as('photos'))
        .select(zero.as('videos'))
        .select(zero.as('usage'))
        .select(zero.as('total'))
        .where('library.id', '=', id)
        .executeTakeFirst();
    }

    return {
      photos: stats.photos,
      videos: stats.videos,
      usage: stats.usage,
      total: stats.photos + stats.videos,
    };
  }

  streamAssetIds(libraryId: string) {
    return this.db.selectFrom('asset').select(['id']).where('libraryId', '=', libraryId).stream();
  }
}
