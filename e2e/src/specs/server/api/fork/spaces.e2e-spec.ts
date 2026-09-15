// Fork spaces, preferences, contributor rights (shared-libraries, T1).
// Covers TESTING.md §5: R1-01, R1-02, R2-01..04, R3-01..03, R6-01..07, R7-01.
// Needs the fork compose stack (scripts/fork-test/run.sh e2e-api).

import {
  SyncRequestType,
  Type5,
  addAssetsToAlbum as addAssetsToAlbumSdk,
  addMembers2 as addSpaceMembers,
  create as createSharedSpace,
  createAlbum as createAlbumSdk,
  deleteSharedSpacesById,
  getAssetInfo as getAssetInfoSdk,
  getMembers2 as getSpaceMembers,
  getSharedSpacesById,
  removeMember2 as removeSpaceMember,
  transferOwner,
  update as updateSharedSpace,
  updateAssets,
  type AssetResponseDto,
} from '@immich/sdk';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { app, utils } from 'src/utils.js';
import { moveAssetsAs } from './as.js';
import { expectedUploadPath, findUnder, forkDataDir, sharedLibraryPrefix, storageKey, toHostPath } from './disk.js';
import { settle } from './jobs.js';
import { ackAll, readSync } from './sync.js';
import { buildWorld, uploadFixture, type World } from './world.js';

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

describe.each([{ template: 'on' }, { template: 'off' }] as const)(
  'fork spaces ($template)',
  ({ template }) => {
    let world: World;
    let adminToken: string;

    const token = (user: keyof World['users']) => world.users[user].login.accessToken;
    const userId = (user: keyof World['users']) => world.users[user].login.userId;
    const familyAsset = () => world.assets.find((a) => a.manifestId === 'fork-02')!;
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

    it('[R1-01] alice uploads to her personal library', async () => {
      const uploaded = await uploadFixture(token('alice'), 'fork-05');
      await settle(adminToken);
      const asset = await getAs('alice', uploaded.id);
      expect(asset.spaceId).toBeNull();
      expect(asset.libraryId).toBeNull();
      if (template === 'off') {
        const { existsSync } = await import('node:fs');
        expect(existsSync(expectedUploadPath(storageKey(asset), asset.originalFileName))).toBe(true);
      } else {
        // Personal tree, outside the shared tree.
        const found = findUnder(forkDataDir, asset.originalFileName);
        expect(found.length).toBeGreaterThan(0);
        expect(found.every((path) => !path.includes('shared'))).toBe(true);
      }
    }, 300_000);

    it('[R1-02] outsiders get 403 for a personal asset', async () => {
      const target = world.assets.find((a) => a.manifestId === 'fork-01')!;
      for (const outsider of ['bob', 'carol'] as const) {
        const headers = { Authorization: `Bearer ${token(outsider)}` };
        for (const path of [`/assets/${target.id}`, `/assets/${target.id}/original`, `/assets/${target.id}/thumbnail`]) {
          const { status } = await request(app).get(path).set(headers);
          expect(status, `${outsider} ${path}`).toBe(403);
        }
      }
      // Sanity: the owner reads fine.
      await expect(getAs('alice', target.id)).resolves.toMatchObject({ id: target.id });
    });

    it('[R2-01] any user creates a space as owner; duplicate names de-duplicate labels', async () => {
      const first = await createSharedSpace(
        { sharedSpaceCreateDto: { name: 'Family' } },
        { headers: auth(token('alice')) },
      );
      const second = await createSharedSpace(
        { sharedSpaceCreateDto: { name: 'Family' } },
        { headers: auth(token('alice')) },
      );
      expect(first.role).toBe('owner');
      expect(second.role).toBe('owner');
      // Labels are not in the API; with the template on they show up as
      // library/shared/<label>/ directories once an asset lands in each space.
      const a = await uploadFixture(token('alice'), 'fork-25', { spaceId: first.id });
      const b = await uploadFixture(token('alice'), 'fork-26', { spaceId: second.id });
      await settle(adminToken);
      const infoA = await getAs('alice', a.id);
      const infoB = await getAs('alice', b.id);
      if (template === 'on') {
        const [pathA] = findUnder(sharedLibraryPrefix(), infoA.originalFileName);
        const [pathB] = findUnder(sharedLibraryPrefix(), infoB.originalFileName);
        expect(pathA).toMatch(/[/\\]family[/\\]/);
        expect(pathB).toMatch(/[/\\]family-2[/\\]/);
      } else {
        expect(infoA.spaceId).toBe(first.id);
        expect(infoB.spaceId).toBe(second.id);
      }
      await deleteSharedSpacesById({ id: first.id }, { headers: auth(token('alice')) });
      await deleteSharedSpacesById({ id: second.id }, { headers: auth(token('alice')) });
    }, 300_000);

    it('[R2-02] owner and contributor add members; outsider 403; duplicate 400', async () => {
      // Contributor bob adds carol to Family Mobile.
      await addSpaceMembers(
        { id: world.spaces.family.id, sharedSpaceMembersDto: { userIds: [userId('carol')] } },
        { headers: auth(token('bob')) },
      );
      let members = await getSpaceMembers(
        { id: world.spaces.family.id },
        { headers: auth(token('alice')) },
      );
      expect(members.map((m) => m.userId)).toContain(userId('carol'));
      // Outsider dave cannot add members.
      await expect(
        addSpaceMembers(
          { id: world.spaces.family.id, sharedSpaceMembersDto: { userIds: [userId('dave')] } },
          { headers: auth(token('dave')) },
        ),
      ).rejects.toMatchObject({ status: 403 });
      // Duplicate member is a 400.
      await expect(
        addSpaceMembers(
          { id: world.spaces.family.id, sharedSpaceMembersDto: { userIds: [userId('carol')] } },
          { headers: auth(token('alice')) },
        ),
      ).rejects.toMatchObject({ status: 400 });
      // Cleanup: carol leaves again so later cases see the canonical world.
      await removeSpaceMember(
        { id: world.spaces.family.id, userId: userId('carol') },
        { headers: auth(token('alice')) },
      );
      members = await getSpaceMembers({ id: world.spaces.family.id }, { headers: auth(token('alice')) });
      expect(members.map((m) => m.userId)).not.toContain(userId('carol'));
    });

    it('[R2-03] contributor cannot delete or transfer; owner cannot leave; contributor can', async () => {
      await expect(
        deleteSharedSpacesById({ id: world.spaces.family.id }, { headers: auth(token('bob')) }),
      ).rejects.toMatchObject({ status: 403 });
      await expect(
        transferOwner(
          { id: world.spaces.family.id, sharedSpaceOwnerDto: { userId: userId('bob') } },
          { headers: auth(token('bob')) },
        ),
      ).rejects.toMatchObject({ status: 403 });
      await expect(
        removeSpaceMember(
          { id: world.spaces.family.id, userId: userId('alice') },
          { headers: auth(token('alice')) },
        ),
      ).rejects.toThrow();
      // Contributor bob leaves and is re-added for later cases.
      await removeSpaceMember(
        { id: world.spaces.family.id, userId: userId('bob') },
        { headers: auth(token('bob')) },
      );
      let members = await getSpaceMembers({ id: world.spaces.family.id }, { headers: auth(token('alice')) });
      expect(members.map((m) => m.userId)).not.toContain(userId('bob'));
      await addSpaceMembers(
        { id: world.spaces.family.id, sharedSpaceMembersDto: { userIds: [userId('bob')] } },
        { headers: auth(token('alice')) },
      );
      members = await getSpaceMembers({ id: world.spaces.family.id }, { headers: auth(token('alice')) });
      expect(members.map((m) => m.userId)).toContain(userId('bob'));
    });

    it('[R2-04] ownership transfer swaps roles atomically', async () => {
      await transferOwner(
        { id: world.spaces.family.id, sharedSpaceOwnerDto: { userId: userId('bob') } },
        { headers: auth(token('alice')) },
      );
      const members = await getSpaceMembers({ id: world.spaces.family.id }, { headers: auth(token('bob')) });
      const roles = new Map(members.map((m) => [m.userId, m.role]));
      expect(roles.get(userId('bob'))).toBe('owner');
      expect(roles.get(userId('alice'))).toBe('contributor');
      // Old owner can no longer delete; transfer back to restore the world.
      await expect(
        deleteSharedSpacesById({ id: world.spaces.family.id }, { headers: auth(token('alice')) }),
      ).rejects.toMatchObject({ status: 403 });
      await transferOwner(
        { id: world.spaces.family.id, sharedSpaceOwnerDto: { userId: userId('alice') } },
        { headers: auth(token('bob')) },
      );
    });

    it('[R3-01] default upload target routes bob into Family Mobile', async () => {
      const uploaded = await uploadFixture(token('bob'), 'fork-18');
      await settle(adminToken);
      const asset = await getAs('bob', uploaded.id);
      expect(asset.spaceId).toBe(world.spaces.family.id);
      if (template === 'on') {
        const [path] = findUnder(sharedLibraryPrefix(), asset.originalFileName);
        expect(path).toMatch(/family-mobile/);
      }
    }, 300_000);

    it('[R3-02] explicit spaceId overrides the preference; non-member spaceId is 403', async () => {
      const uploaded = await uploadFixture(token('bob'), 'fork-22', { spaceId: world.spaces.camera.id });
      const placed = await getAs('bob', uploaded.id);
      expect(placed.spaceId).toBe(world.spaces.camera.id);
      await expect(uploadFixture(token('bob'), 'fork-28', { spaceId: world.spaces.carolSolo.id })).rejects.toMatchObject(
        { status: 403 },
      );
    }, 300_000);

    it('[R3-03] removed member uploads fall back to personal', async () => {
      await removeSpaceMember(
        { id: world.spaces.family.id, userId: userId('bob') },
        { headers: auth(token('alice')) },
      );
      const uploaded = await uploadFixture(token('bob'), 'fork-30');
      const asset = await getAs('bob', uploaded.id);
      expect(asset.spaceId).toBeNull();
      expect(asset.libraryId).toBeNull();
      await addSpaceMembers(
        { id: world.spaces.family.id, sharedSpaceMembersDto: { userIds: [userId('bob')] } },
        { headers: auth(token('alice')) },
      );
    }, 300_000);

    it('[R6-01] contributor edits metadata of a space asset', async () => {
      const target = familyAsset();
      await updateAssets(
        {
          assetBulkUpdateDto: {
            ids: [target.id],
            description: 'edited by bob',
            latitude: 48.85,
            longitude: 2.35,
          },
        },
        { headers: auth(token('bob')) },
      );
      await expect(getAs('alice', target.id)).resolves.toMatchObject({
        description: 'edited by bob',
        latitude: 48.85,
        longitude: 2.35,
      });
    });

    it('[R6-02] contributor favorite is visible to the owner (API + sync)', async () => {
      const target = familyAsset();
      await ackAll(token('alice'));
      await updateAssets({ assetBulkUpdateDto: { ids: [target.id], isFavorite: true } }, { headers: auth(token('bob')) });
      await expect(getAs('alice', target.id)).resolves.toMatchObject({ isFavorite: true });
      // The generated SDK predates the S6 sync types; the server accepts the raw value.
      const events = await readSync(token('alice'), ['SharedSpaceAssetsV1' as SyncRequestType]);
      const relevant = events.filter((event) => JSON.stringify(event.data ?? {}).includes(target.id));
      expect(relevant.length).toBeGreaterThan(0);
      expect(relevant.some((event) => JSON.stringify(event).includes('"isFavorite":true'))).toBe(true);
      await updateAssets(
        { assetBulkUpdateDto: { ids: [target.id], isFavorite: false } },
        { headers: auth(token('bob')) },
      );
    }, 300_000);

    it('[R6-03] contributor archive is global', async () => {
      const target = familyAsset();
      await utils.archiveAssets(token('bob'), [target.id]);
      await expect(getAs('alice', target.id)).resolves.toMatchObject({ isArchived: true });
    });

    it('[R6-04] contributor trash/restore/delete flows through the owner trash', async () => {
      const uploaded = await uploadFixture(token('alice'), 'fork-29', { spaceId: world.spaces.family.id });
      await settle(adminToken);
      const before = await getAs('alice', uploaded.id);
      const hostOriginal = toHostPath(before.originalPath);
      expect(hostOriginal).not.toBeNull();

      const trash = async () => {
        const { status } = await request(app)
          .delete('/assets')
          .send({ ids: [uploaded.id] })
          .set('Authorization', `Bearer ${token('bob')}`);
        expect(status).toBe(204);
      };
      await trash();
      await expect(getAs('alice', uploaded.id)).resolves.toMatchObject({ isTrashed: true });
      const { status: restoreStatus } = await request(app)
        .post('/trash/restore/assets')
        .send({ ids: [uploaded.id] })
        .set('Authorization', `Bearer ${token('bob')}`);
      expect(restoreStatus).toBe(200);
      await expect(getAs('alice', uploaded.id)).resolves.toMatchObject({ isTrashed: false });

      await trash();
      const { status: deleteStatus } = await request(app)
        .delete('/assets')
        .send({ ids: [uploaded.id], force: true })
        .set('Authorization', `Bearer ${token('bob')}`);
      expect(deleteStatus).toBe(204);
      await settle(adminToken);
      await expect(getAs('alice', uploaded.id)).rejects.toMatchObject({ status: 400 });
      const { existsSync } = await import('node:fs');
      expect(existsSync(hostOriginal as string)).toBe(false);
    }, 300_000);

    it('[R6-05] contributor adds a space asset to his own album', async () => {
      const target = familyAsset();
      const album = await createAlbumSdk(
        { createAlbumDto: { albumName: 'Bob picks' } },
        { headers: auth(token('bob')) },
      );
      await addAssetsToAlbumSdk(
        { id: album.id, bulkIdsDto: { ids: [target.id] } },
        { headers: auth(token('bob')) },
      );
      const { status, body } = await request(app).get(`/albums/${album.id}`).set('Authorization', `Bearer ${token('bob')}`);
      expect(status).toBe(200);
      expect((body.assetCount as number) >= 1).toBe(true);
    });

    it('[R6-06] outsider gets 403/error for every space-asset op', async () => {
      const target = familyAsset();
      const headers = { Authorization: `Bearer ${token('carol')}` };
      for (const path of [`/assets/${target.id}`, `/assets/${target.id}/original`, `/assets/${target.id}/thumbnail`]) {
        const { status } = await request(app).get(path).set(headers);
        expect(status, path).toBe(403);
      }
      await expect(
        updateAssets({ assetBulkUpdateDto: { ids: [target.id], description: 'nope' } }, { headers }),
      ).rejects.toMatchObject({ status: 403 });
      const move = await moveAssetsAs(world.users.carol, {
        assetIds: [target.id],
        target: { type: Type5.Personal },
      });
      expect(move.results).toEqual([{ id: target.id, status: 'error' }]);
      // Upstream bulk delete reports no-access as 400, not 403.
      const { status: trashStatus } = await request(app)
        .delete('/assets')
        .send({ ids: [target.id] })
        .set(headers);
      expect(trashStatus).toBe(400);
    });

    it('[R6-07] removed member loses access to a contribution left in the space', async () => {
      const uploaded = await uploadFixture(token('bob'), 'fork-05', { spaceId: world.spaces.family.id });
      await removeSpaceMember(
        { id: world.spaces.family.id, userId: userId('bob') },
        { headers: auth(token('alice')) },
      );
      const { status } = await request(app)
        .get(`/assets/${uploaded.id}`)
        .set('Authorization', `Bearer ${token('bob')}`);
      expect(status).toBe(403);
      await addSpaceMembers(
        { id: world.spaces.family.id, sharedSpaceMembersDto: { userIds: [userId('bob')] } },
        { headers: auth(token('alice')) },
      );
      await expect(getAs('bob', uploaded.id)).resolves.toMatchObject({ id: uploaded.id });
    }, 300_000);

    it('[R7-01] space list carries role and counts; rename does not move files', async () => {
      const { status, body } = await request(app).get('/shared-spaces').set('Authorization', `Bearer ${token('bob')}`);
      expect(status).toBe(200);
      const family = (body as { id: string; role: string; memberCount: number; assetCount: number }[]).find(
        (space) => space.id === world.spaces.family.id,
      );
      expect(family).toMatchObject({ role: 'contributor' });
      expect(family!.memberCount).toBeGreaterThanOrEqual(2);
      expect(family!.assetCount).toBeGreaterThan(0);

      const target = familyAsset();
      const before = await getAs('alice', target.id);
      const renamed = await updateSharedSpace(
        { id: world.spaces.family.id, sharedSpaceUpdateDto: { name: 'Family Mobile Renamed' } },
        { headers: auth(token('alice')) },
      );
      expect(renamed.name).toBe('Family Mobile Renamed');
      await expect(getSharedSpacesById({ id: world.spaces.family.id }, { headers: auth(token('alice')) })).resolves.toMatchObject(
        { name: 'Family Mobile Renamed' },
      );
      await expect(getAs('alice', target.id)).resolves.toMatchObject({ originalPath: before.originalPath });
      await updateSharedSpace(
        { id: world.spaces.family.id, sharedSpaceUpdateDto: { name: 'Family Mobile' } },
        { headers: auth(token('alice')) },
      );
    });
  },
);
