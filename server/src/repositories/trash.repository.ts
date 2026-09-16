import { InjectKysely } from 'nestjs-kysely';
import type { Kysely } from 'kysely';
import type { ContainerScope } from 'src/utils/container-scope.js';
import { DummyValue, GenerateSql } from 'src/decorators.js';
import { AssetStatus } from 'src/enum.js';
import { DB } from 'src/schema/index.js';
import { withContainerScope } from 'src/utils/container-scope.js';

export class TrashRepository {
  constructor(@InjectKysely() private db: Kysely<DB>) {}

  getDeletedIds(): AsyncIterableIterator<{ id: string }> {
    return this.db.selectFrom('asset').select(['id']).where('status', '=', AssetStatus.Deleted).stream();
  }

  @GenerateSql({ params: [DummyValue.UUID] })
  async restore(userId: string, scope?: ContainerScope): Promise<number> {
    const { numUpdatedRows } = await this.db
      .updateTable('asset')
      // fork: shared-libraries
      .$if(!!scope, (qb) => qb.where((eb) => withContainerScope(eb, scope!)))
      .$if(!scope, (qb) => qb.where('ownerId', '=', userId))
      .where('status', '=', AssetStatus.Trashed)
      .set({ status: AssetStatus.Active, deletedAt: null })
      .executeTakeFirst();

    return Number(numUpdatedRows);
  }

  @GenerateSql({ params: [DummyValue.UUID] })
  async empty(userId: string, scope?: ContainerScope): Promise<number> {
    const { numUpdatedRows } = await this.db
      .updateTable('asset')
      // fork: shared-libraries
      .$if(!!scope, (qb) => qb.where((eb) => withContainerScope(eb, scope!)))
      .$if(!scope, (qb) => qb.where('ownerId', '=', userId))
      .where('status', '=', AssetStatus.Trashed)
      .set({ status: AssetStatus.Deleted })
      .executeTakeFirst();

    return Number(numUpdatedRows);
  }

  @GenerateSql({ params: [[DummyValue.UUID]] })
  async restoreAll(ids: string[], scope?: ContainerScope): Promise<number> {
    if (ids.length === 0) {
      return 0;
    }

    const { numUpdatedRows } = await this.db
      .updateTable('asset')
      .where('status', '=', AssetStatus.Trashed)
      .where('id', 'in', ids)
      // fork: shared-libraries
      .$if(!!scope, (qb) => qb.where((eb) => withContainerScope(eb, scope!)))
      .set({ status: AssetStatus.Active, deletedAt: null })
      .executeTakeFirst();

    return Number(numUpdatedRows);
  }
}
