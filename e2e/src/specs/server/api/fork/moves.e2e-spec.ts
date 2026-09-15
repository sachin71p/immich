// Fork container moves (shared-libraries, T1).
// Covers TESTING.md §5: R4-01, R5-01, R5-02, R7-02, R10-04..07, MV-01.
// Needs the fork compose stack (scripts/fork-test/run.sh e2e-api).

import {
  AssetVisibility,
  Type5,
  Type6,
  bulkTagAssets,
  createTag,
  getAssetInfo as getAssetInfoSdk,
  updateAssets,
  type AssetResponseDto,
} from '@immich/sdk';
import { existsSync } from 'node:fs';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { app, utils } from 'src/utils.js';
import { moveAssetsAs } from './as.js';
import {
  expectedUploadPath,
  expectFilesAt,
  findUnder,
  forkDataDir,
  sharedLibraryPrefix,
  storageKey,
  toHostPath,
} from './disk.js';
import { pauseRelocation, resumeRelocation, settle } from './jobs.js';
import { buildWorld, uploadFixture, type World } from './world.js';

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

const personalOriginals = (filename: string): string[] =>
  findUnder(forkDataDir, filename).filter((path) => !path.includes('shared'));

describe.each([{ template: 'on' }, { template: 'off' }] as const)(
  'fork moves ($template)',
  ({ template }) => {
    let world: World;
    let adminToken: string;

    const token = (user: keyof World['users']) => world.users[user].login.accessToken;
    const getAs = (user: keyof World['users'], id: string): Promise<AssetResponseDto> =>
      getAssetInfoSdk({ id }, { headers: auth(token(user)) });

    beforeAll(async () => {
      utils.initSdk();
      world = await buildWorld({ storageTemplate: template });
      adminToken = token('admin');
    }, 600_000);

    afterAll(() => {
      utils.resetTempFolder();
    });

    it('[R4-01] personal assets move to a space with identity intact', async () => {
      const one = world.assets.find((a) => a.manifestId === 'fork-01')!;
      const six = world.assets.find((a) => a.manifestId === 'fork-06')!;
      const beforeOne = await getAs('alice', one.id);
      const beforeSix = await getAs('alice', six.id);
      await updateAssets(
        { assetBulkUpdateDto: { ids: [one.id], isFavorite: true } },
        { headers: auth(token('alice')) },
      );
      const tag = await createTag({ tagCreateDto: { name: 'moved-with-me' } }, { headers: auth(token('alice')) });
      await bulkTagAssets(
        { tagBulkAssetsDto: { tagIds: [tag.id], assetIds: [one.id] } },
        { headers: auth(token('alice')) },
      );

      const result = await moveAssetsAs(world.users.alice, {
        assetIds: [one.id, six.id],
        target: { type: Type6.Space, id: world.spaces.family.id },
      });
      expect(result.results).toEqual([
        { id: one.id, status: 'moved' },
        { id: six.id, status: 'moved' },
      ]);
      await settle(adminToken);

      for (const [entry, before] of [[one, beforeOne], [six, beforeSix]] as const) {
        const after = await getAs('alice', entry.id);
        expect(after.id).toBe(entry.id);
        expect(after.spaceId).toBe(world.spaces.family.id);
        expect(after.ownerId).toBe(before.ownerId);
        // Old paths are gone, new files are in the shared tree.
        const oldHost = toHostPath(before.originalPath) as string;
        expect(existsSync(oldHost)).toBe(false);
        if (template === 'off') {
          expect(existsSync(expectedUploadPath(storageKey(after), after.originalFileName))).toBe(true);
        } else {
          const { dirname } = await import('node:path');
          expectFilesAt(
            {
              id: after.id,
              ownerId: after.ownerId,
              spaceId: after.spaceId,
              originalFileName: after.originalFileName,
              originalPath: after.originalPath,
            },
            { template, hostPrefix: sharedLibraryPrefix(), absentFrom: [dirname(oldHost)] },
          );
        }
      }
      // fork-06 carries an .xmp sidecar: it moves alongside the original.
      const afterSix = await getAs('alice', six.id);
      expect(existsSync(`${toHostPath(beforeSix.originalPath)}.xmp`)).toBe(false);
      expect(existsSync(`${toHostPath(afterSix.originalPath)}.xmp`)).toBe(true);
      // Identity survived: favorite, tag, album membership.
      const afterOne = await getAs('alice', one.id);
      expect(afterOne.isFavorite).toBe(true);
      expect(afterOne.tags?.map((tag) => tag.name)).toContain('moved-with-me');
      const { assets } = await utils.searchAssets(token('alice'), { albumIds: [world.albumTrip.id], size: 100 });
      expect(assets.items.map((asset: AssetResponseDto) => asset.id)).toContain(one.id);
    }, 300_000);

    it('[R5-01] own space asset moves back to personal paths', async () => {
      const target = world.assets.find((a) => a.manifestId === 'fork-02')!;
      const before = await getAs('alice', target.id);
      const result = await moveAssetsAs(world.users.alice, {
        assetIds: [target.id],
        target: { type: Type5.Personal },
      });
      expect(result.results).toEqual([{ id: target.id, status: 'moved' }]);
      await settle(adminToken);
      const after = await getAs('alice', target.id);
      expect(after.spaceId).toBeNull();
      expect(after.libraryId).toBeNull();
      if (template === 'off') {
        expect(existsSync(expectedUploadPath(storageKey(after), after.originalFileName))).toBe(true);
      } else {
        expect(personalOriginals(after.originalFileName).length).toBeGreaterThan(0);
      }
      expect(existsSync(toHostPath(before.originalPath) as string)).toBe(false);
    }, 300_000);

    it('[R5-02] moving another member asset to personal fails', async () => {
      const uploaded = await uploadFixture(token('bob'), 'fork-26', { spaceId: world.spaces.family.id });
      const result = await moveAssetsAs(world.users.alice, {
        assetIds: [uploaded.id],
        target: { type: Type5.Personal },
      });
      expect(result.results).toEqual([{ id: uploaded.id, status: 'error', reason: 'target_access' }]);
      const kept = await getAs('bob', uploaded.id);
      expect(kept.spaceId).toBe(world.spaces.family.id);
    }, 300_000);

    it('[R7-02] space-to-space move needs membership on both sides', async () => {
      const target = world.assets.find((a) => a.manifestId === 'fork-08')!;
      const before = await getAs('alice', target.id);
      const result = await moveAssetsAs(world.users.alice, {
        assetIds: [target.id],
        target: { type: Type6.Space, id: world.spaces.camera.id },
      });
      expect(result.results).toEqual([{ id: target.id, status: 'moved' }]);
      await settle(adminToken);
      const after = await getAs('alice', target.id);
      expect(after.spaceId).toBe(world.spaces.camera.id);
      expect(existsSync(toHostPath(before.originalPath) as string)).toBe(false);
      const other = world.assets.find((a) => a.manifestId === 'fork-12')!;
      const denied = await moveAssetsAs(world.users.carol, {
        assetIds: [other.id],
        target: { type: Type6.Space, id: world.spaces.carolSolo.id },
      });
      expect(denied.results).toEqual([{ id: other.id, status: 'error', reason: 'source_access' }]);
    }, 300_000);

    it('[R10-06] same-container move is noop; target duplicate errors', async () => {
      const own = world.assets.find((a) => a.manifestId === 'fork-07')!;
      await expect(
        moveAssetsAs(world.users.alice, { assetIds: [own.id], target: { type: Type5.Personal } }),
      ).resolves.toEqual({ results: [{ id: own.id, status: 'noop' }] });
      const dup = world.assets.find((a) => a.manifestId === 'fork-09a')!;
      await expect(
        moveAssetsAs(world.users.bob, { assetIds: [dup.id], target: { type: Type6.Space, id: world.spaces.camera.id } }),
      ).resolves.toEqual({ results: [{ id: dup.id, status: 'error', reason: 'duplicate' }] });
    }, 300_000);

    it('[R10-05] moving one stack member moves the whole stack', async () => {
      const member = world.assets.find((a) => a.manifestId === 'fork-20')!;
      const sibling = world.assets.find((a) => a.manifestId === 'fork-21')!;
      const result = await moveAssetsAs(world.users.bob, {
        assetIds: [member.id],
        target: { type: Type6.Space, id: world.spaces.camera.id },
      });
      expect(result.results).toEqual([{ id: member.id, status: 'moved' }]);
      await settle(adminToken);
      const afterMember = await getAs('bob', member.id);
      const afterSibling = await getAs('bob', sibling.id);
      expect(afterMember.spaceId).toBe(world.spaces.camera.id);
      expect(afterSibling.spaceId).toBe(world.spaces.camera.id);
      expect(afterMember.stack?.id).toBeDefined();
      expect(afterSibling.stack?.id).toBe(afterMember.stack?.id);
    }, 300_000);

    it('[R10-04] moving a live still moves its motion part too', async () => {
      const live = world.assets.find((a) => a.manifestId === 'personal-live');
      if (!live) {
        console.warn('[R10-04] no live-photo pair in this world (personal fixtures absent) — nothing to assert');
        return;
      }
      const still = await getAs('alice', live.id);
      const motionId = still.livePhotoVideoId as string;
      const result = await moveAssetsAs(world.users.alice, {
        assetIds: [live.id],
        target: { type: Type6.Space, id: world.spaces.family.id },
      });
      expect(result.results).toEqual([{ id: live.id, status: 'moved' }]);
      await settle(adminToken);
      await expect(getAs('alice', live.id)).resolves.toMatchObject({ spaceId: world.spaces.family.id });
      const motion = await getAs('alice', motionId);
      expect(motion.spaceId).toBe(world.spaces.family.id);
      if (template === 'off') {
        expect(existsSync(expectedUploadPath(storageKey(motion), motion.originalFileName))).toBe(true);
      }
    }, 300_000);

    it('[R10-07] Locked assets cannot move and shared assets cannot lock', async () => {
      const locked = world.assets.find((a) => a.manifestId === 'fork-10')!;
      await expect(
        moveAssetsAs(world.users.alice, { assetIds: [locked.id], target: { type: Type6.Space, id: world.spaces.family.id } }),
      ).resolves.toEqual({ results: [{ id: locked.id, status: 'error', reason: 'locked' }] });
      const shared = world.assets.find((a) => a.manifestId === 'fork-12')!;
      await expect(
        updateAssets(
          { assetBulkUpdateDto: { ids: [shared.id], visibility: AssetVisibility.Locked } },
          { headers: auth(token('alice')) },
        ),
      ).rejects.toMatchObject({ status: 400 });
    }, 300_000);

    it('[MV-01] DB moves first, files follow after resume', async () => {
      const target = world.assets.find((a) => a.manifestId === 'fork-07')!;
      const before = await getAs('alice', target.id);
      const oldHost = toHostPath(before.originalPath) as string;
      expect(existsSync(oldHost)).toBe(true);

      await pauseRelocation(adminToken);
      try {
        const result = await moveAssetsAs(world.users.alice, {
          assetIds: [target.id],
          target: { type: Type6.Space, id: world.spaces.family.id },
        });
        expect(result.results).toEqual([{ id: target.id, status: 'moved' }]);
        // DB is already the new container while the original still downloads.
        await expect(getAs('alice', target.id)).resolves.toMatchObject({ spaceId: world.spaces.family.id });
        const { status: downloadStatus } = await request(app)
          .get(`/assets/${target.id}/original`)
          .set('Authorization', `Bearer ${token('alice')}`);
        expect(downloadStatus).toBe(200);
        expect(existsSync(oldHost)).toBe(true);
      } finally {
        await resumeRelocation(adminToken);
      }
      await settle(adminToken);
      const after = await getAs('alice', target.id);
      expect(existsSync(toHostPath(after.originalPath) as string)).toBe(true);
      expect(existsSync(oldHost)).toBe(false);
    }, 300_000);
  },
);
