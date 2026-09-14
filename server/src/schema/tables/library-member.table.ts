import {
  AfterDeleteTrigger,
  Column,
  CreateDateColumn,
  ForeignKeyColumn,
  type Generated,
  Table,
  Timestamp,
  UpdateDateColumn,
} from '@immich/sql-tools';
import { CreateIdColumn, UpdateIdColumn, UpdatedAtTrigger } from 'src/decorators.js';
import { library_member_delete_audit } from 'src/schema/functions.js';
import { LibraryTable } from 'src/schema/tables/library.table.js';
import { UserTable } from 'src/schema/tables/user.table.js';

// fork: shared-libraries
@Table({ name: 'library_member' })
@UpdatedAtTrigger('library_member_updatedAt')
@AfterDeleteTrigger({
  scope: 'statement',
  function: library_member_delete_audit,
  referencingOldTableAs: 'old',
})
export class LibraryMemberTable {
  @ForeignKeyColumn(() => LibraryTable, {
    onDelete: 'CASCADE',
    onUpdate: 'CASCADE',
    nullable: false,
    primary: true,
  })
  libraryId!: string;

  @ForeignKeyColumn(() => UserTable, {
    onDelete: 'CASCADE',
    onUpdate: 'CASCADE',
    nullable: false,
    primary: true,
  })
  userId!: string;

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
