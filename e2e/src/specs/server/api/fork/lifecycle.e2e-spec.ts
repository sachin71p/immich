// Fork lifecycle: space deletion, user deletion, trash emptying (shared-libraries, T1).
// Covers TESTING.md §5: LC-01..04.
// Needs the fork compose stack (scripts/fork-test/run.sh e2e-api).

import {
  create as createSharedSpace,
  addMembers2 as addSpaceMembers,
  deleteSharedSpacesById,
  deleteUserAdmin,
  emptyTrash,
  getAssetInfo as getAssetInfoSdk,
  getMembers2 as getSpaceMembers,
  getMyUser,
  getSharedSpacesById,
  type AssetResponseDto,
} from '@immich/sdk';
import { existsSync } from 'node:fs';
import { basename, join } from 'node:path';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { app, utils } from 'src/utils.js';
import { expectedUploadPath, findUnder, forkDataDir, storageKey, toHostPath } from './disk.js';
import { settle } from './jobs.js';
import { buildWorld, uploadFixture, type World } from './world.js';

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

describe.each([{ template: 'on' }, { template: 'off' }] as const)(
  'fork lifecycle ($template)',
  ({ template }) => {
    let world: World;
    let adminToken: string;

    const token = (user: keyof World['users']) => world.users[user].login.accessToken;
    const userId = (user: keyof World['users']) => world.users[user].login.userId;
    const getAs = (user: keyof World['users'], id: string): Promise<AssetResponseDto> =>
      getAssetInfoSdk({ id }, { headers: auth(token(user)) });

    /** Wait until a deleted user's token stops working (user-delete job done). */
    const waitForUserGone = async (user: keyof World['users']): Promise<void> => {
      const headers = auth(token(user));
      for (let attempt = 0; attempt < 60; attempt++) {
        try {
          await getMyUser({ headers });
        } catch {
          return;
        }
        await sleep(2000);
      }
      throw new Error(`user ${user} was not deleted in time`);
    };

    beforeAll(async () => {
      utils.initSdk();
      world = await buildWorld({ storageTemplate: template });
      adminToken = token('admin');
    }, 600_000);

    afterAll(() => {
      utils.resetTempFolder();
    });

    it('[LC-04] emptying trash only empties manageable containers', async () => {
      // Dedicated contribution so the permanent delete cannot affect later cases.
      const shared = await uploadFixture(token('bob'), 'fork-18', { spaceId: world.spaces.family.id });
      const personal = world.assets.find((a) => a.manifestId === 'fork-06')!;
      for (const [user, id] of [['bob', shared.id], ['alice', personal.id]] as const) {
        const { status } = await request(app)
          .delete('/assets')
          .send({ ids: [id] })
          .set('Authorization', `Bearer ${token(user)}`);
        expect(status).toBe(204);
      }
      await emptyTrash({ headers: auth(token('bob')) });
      await settle(adminToken);
      await expect(getAs('bob', shared.id)).rejects.toMatchObject({ status: 400 });
      await expect(getAs('alice', personal.id)).resolves.toMatchObject({ isTrashed: true });
    }, 300_000);

    it('[LC-01] deleting a space returns assets to personal paths, albums intact', async () => {
      const members = ['fork-02', 'fork-08', 'fork-12'].map((manifestId) => world.assets.find((a) => a.manifestId === manifestId)!);
      const before = new Map<string, string>();
      for (const entry of members) {
        const info = await getAs('alice', entry.id);
        before.set(entry.id, info.originalPath);
      }
      await deleteSharedSpacesById({ id: world.spaces.family.id }, { headers: auth(token('alice')) });
      await settle(adminToken);
      for (const entry of members) {
        const after = await getAs('alice', entry.id);
        expect(after.spaceId).toBeNull();
        expect(existsSync(toHostPath(before.get(entry.id) as string) as string)).toBe(false);
        if (template === 'off') {
          expect(existsSync(expectedUploadPath(storageKey(after), basename(after.originalPath)))).toBe(true);
        } else {
          const found = findUnder(forkDataDir, after.originalFileName);
          expect(found.length).toBeGreaterThan(0);
          expect(found.every((path) => !path.includes('shared'))).toBe(true);
        }
      }
      // Albums are untouched: Trip still holds the former space asset.
      const { assets } = await utils.searchAssets(token('alice'), { albumIds: [world.albumTrip.id], size: 100 });
      expect(assets.items.map((asset: AssetResponseDto) => asset.id)).toContain(members[0].id);
    }, 300_000);

    it('[LC-03] deleting a space owner transfers to the earliest contributor', async () => {
      const space = await createSharedSpace(
        { sharedSpaceCreateDto: { name: 'Dave Space' } },
        { headers: auth(token('dave')) },
      );
      await addSpaceMembers(
        { id: space.id, sharedSpaceMembersDto: { userIds: [userId('alice')] } },
        { headers: auth(token('dave')) },
      );
      await deleteUserAdmin({ id: userId('dave'), userAdminDeleteDto: {} }, { headers: auth(adminToken) });
      await waitForUserGone('dave');
      await settle(adminToken);
      await expect(getSharedSpacesById({ id: space.id }, { headers: auth(token('alice')) })).resolves.toMatchObject({
        id: space.id,
      });
      const members = await getSpaceMembers({ id: space.id }, { headers: auth(token('alice')) });
      expect(members.find((member) => member.userId === userId('alice'))?.role).toBe('owner');
    }, 300_000);

    it('[LC-02] deleting a user preserves shared contributions under the space owner', async () => {
      const cameraIds = ['fork-03', 'fork-16', 'fork-19', 'fork-09b'].map(
        (manifestId) => world.assets.find((a) => a.manifestId === manifestId)!.id,
      );
      const bobPersonal = world.assets.find((a) => a.manifestId === 'fork-15')!;
      await deleteUserAdmin({ id: userId('bob'), userAdminDeleteDto: {} }, { headers: auth(adminToken) });
      await waitForUserGone('bob');
      await settle(adminToken);
      // Contributions survive in the space, re-owned by the space owner (alice).
      for (const id of cameraIds) {
        await expect(getAs('alice', id)).resolves.toMatchObject({ ownerId: userId('alice'), spaceId: world.spaces.camera.id });
      }
      // Bob personal assets are gone …
      await expect(getAs('admin', bobPersonal.id)).rejects.toMatchObject({ status: 400 });
      // … and no derived files remain under his folders.
      expect(existsSync(join(forkDataDir, 'thumbs', userId('bob')))).toBe(false);
      expect(existsSync(join(forkDataDir, 'encoded-video', userId('bob')))).toBe(false);
    }, 300_000);
  },
);
