import { Column, CreateDateColumn, type Generated, Table, Timestamp } from '@immich/sql-tools';
import { PrimaryGeneratedUuidV7Column } from 'src/decorators.js';

@Table('person_audit')
export class PersonAuditTable {
  @PrimaryGeneratedUuidV7Column()
  id!: Generated<string>;

  @Column({ type: 'uuid', index: true })
  personGroupId!: string;

  @Column({ type: 'uuid', index: true })
  ownerId!: string;

  // fork: shared-libraries - space scope of a deleted space person (S9), for member sync deletes.
  @Column({ type: 'uuid', nullable: true, default: null })
  spaceId!: string | null;

  @CreateDateColumn({ default: () => 'clock_timestamp()', index: true })
  deletedAt!: Generated<Timestamp>;
}
