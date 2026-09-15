// Fork job helpers (shared-libraries, T0). See TESTING.md §4.
//
// settle() waits for every queue the world build touches (storage template /
// relocation, thumbnails, metadata, library). pauseRelocation() /
// resumeRelocation() freeze the relocation queue so MV-01 style cases can
// assert the API state mid-move.

import { QueueCommand, QueueName, type QueuesResponseLegacyDto } from '@immich/sdk';
import { utils } from 'src/utils.js';

type LegacyQueue = keyof QueuesResponseLegacyDto;

const settleQueues: LegacyQueue[] = [
  'thumbnailGeneration',
  'metadataExtraction',
  'sidecar',
  'library',
  'storageTemplateMigration',
];

/** Wait until all fork-relevant queues (and any extra ones) are empty. */
export const settle = async (adminToken: string, extraQueues: LegacyQueue[] = []): Promise<void> => {
  for (const queue of [...settleQueues, ...extraQueues]) {
    try {
      await utils.waitForQueueFinish(adminToken, queue, 120_000);
    } catch (error) {
      // Unknown queue keys (e.g. before a phase registers them) must not fail
      // the harness: only the known queues are required.
      if (!settleQueues.includes(queue)) {
        continue;
      }
      throw error;
    }
  }
};

/** Pause the relocation queue (storageTemplateMigration workers pick up relocation rows). */
export const pauseRelocation = (adminToken: string) =>
  utils.queueCommand(adminToken, QueueName.StorageTemplateMigration, { command: QueueCommand.Pause });

/** Resume the relocation queue. */
export const resumeRelocation = (adminToken: string) =>
  utils.queueCommand(adminToken, QueueName.StorageTemplateMigration, { command: QueueCommand.Resume });
