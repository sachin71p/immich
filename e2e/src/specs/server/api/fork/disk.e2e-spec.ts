// Fork disk layout gate (shared-libraries, T1).
// Covers TESTING.md §5: R17-01 (post-move placement), R17-02 (reserved
// label), R17-03 (audit clean after mutation). Runs last per the T1 brief.
// Needs the fork compose stack (scripts/fork-test/run.sh e2e-api).

import { Type6 } from '@immich/sdk';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { app, utils } from 'src/utils.js';
import { moveAssetsAs } from './as.js';
import {
  auditDisk,
  expectFilesAt,
  personalLibraryPrefix,
  sharedLibraryPrefix,
  type DiskAsset,
} from './disk.js';
import { settle } from './jobs.js';
import { buildWorld, getAsset, type World } from './world.js';

const withSidecar = new Set(['fork-06', 'fork-07', 'fork-08', 'fork-10']);

const tokenFor = (world: World, owner: string): string => {
  const user = (world.users as Record<string, { login: { accessToken: string } }>)[owner];
  if (!user) {
    throw new Error(`unknown world owner ${owner}`);
  }
  return user.login.accessToken;
};

const toDiskAsset = async (world: World, entry: { id: string; manifestId: string; owner: string }): Promise<DiskAsset> => {
  const asset = await getAsset(tokenFor(world, entry.owner), entry.id);
  return {
    id: asset.id,
    ownerId: asset.ownerId,
    spaceId: asset.spaceId,
    libraryId: asset.libraryId,
    originalFileName: asset.originalFileName,
    originalPath: asset.originalPath,
    sidecarPath: withSidecar.has(entry.manifestId) ? `${asset.originalPath}.xmp` : null,
  };
};

describe.sequential.each([{ template: 'on' }, { template: 'off' }] as const)(
  '[R17-01] fork disk gate ($template)',
  ({ template }) => {
    let world: World;
    let adminToken: string;

    beforeAll(async () => {
      utils.initSdk();
      world = await buildWorld({ storageTemplate: template });
      adminToken = world.users.admin.login.accessToken;
    }, 600_000);

    afterAll(() => {
      utils.resetTempFolder();
    });

    it('[R17-02] the shared storage label is rejected', async () => {
      const aliceId = world.users.alice.login.userId;
      const { status } = await request(app)
        .put(`/admin/users/${aliceId}`)
        .send({ storageLabel: 'shared' })
        .set('Authorization', `Bearer ${adminToken}`);
      expect(status).toBe(400);
      const { status: okStatus } = await request(app)
        .put(`/admin/users/${aliceId}`)
        .send({ storageLabel: 'alice-personal' })
        .set('Authorization', `Bearer ${adminToken}`);
      expect(okStatus).toBe(200);
    });

    it('[R17-01] every asset lands at its expected paths after a move', async () => {
      const target = world.assets.find((a) => a.manifestId === 'fork-15')!;
      const result = await moveAssetsAs(world.users.bob, {
        assetIds: [target.id],
        target: { type: Type6.Space, id: world.spaces.family.id },
      });
      expect(result.results).toEqual([{ id: target.id, status: 'moved' }]);
      await settle(adminToken);
      for (const entry of world.assets) {
        const disk = await toDiskAsset(world, entry);
        const hostPrefix = disk.spaceId
          ? sharedLibraryPrefix()
          : disk.libraryId
            ? undefined
            : personalLibraryPrefix(disk.ownerId);
        expectFilesAt(disk, { template, hostPrefix });
      }
    }, 300_000);

    it('[R17-03] auditDisk() is clean after the move', async () => {
      const { orphans, missing } = await auditDisk(async () =>
        Promise.all(world.assets.map((entry) => toDiskAsset(world, entry))),
      );
      expect(missing, `missing files: ${missing.join(', ')}`).toEqual([]);
      expect(orphans, `orphan files: ${orphans.join(', ')}`).toEqual([]);
    }, 300_000);
  },
);
