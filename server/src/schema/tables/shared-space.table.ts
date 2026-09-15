import {
  Column,
  CreateDateColumn,
  ForeignKeyColumn,
  type Generated,
  PrimaryGeneratedColumn,
  Table,
  Timestamp,
  UpdateDateColumn,
} from '@immich/sql-tools';
import { UpdateIdColumn, UpdatedAtTrigger } from 'src/decorators.js';
import { AssetTable } from 'src/schema/tables/asset.table.js';
import { ClusterGroupTable } from 'src/schema/tables/cluster-group.table.js';
import { UserTable } from 'src/schema/tables/user.table.js';

// fork: shared-libraries
@Table({ name: 'shared_space' })
@UpdatedAtTrigger('shared_space_updatedAt')
export class SharedSpaceTable {
  @PrimaryGeneratedColumn()
  id!: Generated<string>;

  @Column()
  name!: string;

  @Column({ type: 'text', default: '' })
  description!: Generated<string>;

  @Column({ unique: true })
  storageLabel!: string;

  @ForeignKeyColumn(() => UserTable, { nullable: true, onDelete: 'SET NULL', onUpdate: 'CASCADE' })
  createdById!: string | null;

  @ForeignKeyColumn(() => AssetTable, {
    nullable: true,
    onDelete: 'SET NULL',
    onUpdate: 'CASCADE',
    comment: 'Asset ID to be used as thumbnail',
  })
  thumbnailAssetId!: string | null;

  // fork: shared-libraries - facial-recognition universe for space-scoped people (S9), assigned lazily.
  @ForeignKeyColumn(() => ClusterGroupTable, { nullable: true, onDelete: 'SET NULL', onUpdate: 'CASCADE' })
  clusterGroupId!: string | null;

  @CreateDateColumn()
  createdAt!: Generated<Timestamp>;

  @UpdateDateColumn()
  updatedAt!: Generated<Timestamp>;

  @UpdateIdColumn({ index: true })
  updateId!: Generated<string>;
}
