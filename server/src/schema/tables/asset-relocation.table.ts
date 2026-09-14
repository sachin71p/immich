import { Column, ForeignKeyColumn, type Generated, Table, type Timestamp } from '@immich/sql-tools';
import { AssetTable } from 'src/schema/tables/asset.table.js';

// fork: shared-libraries
@Table({ name: 'asset_relocation' })
export class AssetRelocationTable {
  @ForeignKeyColumn(() => AssetTable, {
    onDelete: 'CASCADE',
    onUpdate: 'CASCADE',
    nullable: false,
    primary: true,
  })
  assetId!: string;

  @Column({ type: 'timestamp with time zone', default: () => 'now()' })
  requestedAt!: Generated<Timestamp>;

  @Column({ type: 'uuid', nullable: true })
  requestedById!: string | null;

  @Column({ type: 'integer', default: 0 })
  attempts!: Generated<number>;

  @Column({ type: 'text', nullable: true })
  lastError!: string | null;
}
