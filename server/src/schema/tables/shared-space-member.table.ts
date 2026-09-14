import {
  AfterDeleteTrigger,
  Column,
  CreateDateColumn,
  ForeignKeyColumn,
  type Generated,
  Index,
  Table,
  Timestamp,
  UpdateDateColumn,
} from '@immich/sql-tools';
import { CreateIdColumn, UpdateIdColumn, UpdatedAtTrigger } from 'src/decorators.js';
import { SharedSpaceRole } from 'src/enum.js';
import { shared_space_role_enum } from 'src/schema/enums.js';
import { shared_space_member_delete_audit } from 'src/schema/functions.js';
import { SharedSpaceTable } from 'src/schema/tables/shared-space.table.js';
import { UserTable } from 'src/schema/tables/user.table.js';

// fork: shared-libraries
@Table({ name: 'shared_space_member' })
@Index({
  name: 'shared_space_member_unique_owner',
  columns: ['spaceId'],
  unique: true,
  where: `role = 'owner'`,
})
@UpdatedAtTrigger('shared_space_member_updatedAt')
@AfterDeleteTrigger({
  scope: 'statement',
  function: shared_space_member_delete_audit,
  referencingOldTableAs: 'old',
  when: 'pg_trigger_depth() <= 1',
})
export class SharedSpaceMemberTable {
  @ForeignKeyColumn(() => SharedSpaceTable, {
    onDelete: 'CASCADE',
    onUpdate: 'CASCADE',
    nullable: false,
    primary: true,
  })
  spaceId!: string;

  @ForeignKeyColumn(() => UserTable, {
    onDelete: 'CASCADE',
    onUpdate: 'CASCADE',
    nullable: false,
    primary: true,
  })
  userId!: string;

  @Column({ enum: shared_space_role_enum, default: SharedSpaceRole.Contributor })
  role!: Generated<SharedSpaceRole>;

  @Column({ type: 'boolean', default: true })
  showInTimeline!: Generated<boolean>;

  @CreateIdColumn({ index: true })
  createId!: Generated<string>;

  @CreateDateColumn()
  createdAt!: Generated<Timestamp>;

  @UpdateIdColumn({ index: true })
  updateId!: Generated<string>;

  @UpdateDateColumn()
  updatedAt!: Generated<Timestamp>;
}
