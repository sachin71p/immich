// Fork external libraries and moves into/out of them (shared-libraries, T1).
// Covers TESTING.md §5: R9-01, R9-03, R9-04, R10-01..03.
// (R9-02 lives in timeline-scope.e2e-spec.ts.)
// Needs the fork compose stack (scripts/fork-test/run.sh e2e-api).

import {
  Type6,
  Type7,
  addMembers as addLibraryMembers,
  getMembers as getLibraryMembers,
  removeMember as removeLibraryMember,
  type AssetResponseDto,
} from '@immich/sdk';
import { cpSync, existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { testAssetDir, testAssetDirInternal, utils } from 'src/utils.js';
import { moveAssetsAs } from './as.js';
import {
  expectedUploadPath,
  expectFilesAt,
  hostTestAssetDir,
  sharedLibraryPrefix,
  storageKey,
  toHostPath,
} from './disk.js';
import { settle } from './jobs.js';
import { buildWorld, generatedDir, type World } from './world.js';

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

const incomingHostDir = () => join(hostTestAssetDir, 'temp', 'fork', 'archive', 'incoming');

const searchIds = async (token: string, dto: Record<string, unknown> = {}): Promise<string[]> => {
  const { assets } = await utils.searchAssets(token, { size: 100, ...dto });
  return assets.items.map((asset: AssetResponseDto) => asset.id);
};

describe.each([{ template: 'on' }, { template: 'off' }] as const)(
  'fork external libraries ($template)',
  ({ template }) => {
    let world: World;
    let adminToken: string;

    const token = (user: keyof World['users']) => world.users[user].login.accessToken;
    const userId = (user: keyof World['users']) => world.users[user].login.userId;
    const archiveId = () => world.libraries.archive.id;

    beforeAll(async () => {
      utils.initSdk();
      world = await buildWorld({ storageTemplate: template });
      adminToken = token('admin');
    }, 600_000);

    afterAll(() => {
      utils.resetTempFolder();
    });

    it('[R9-01] library membership gates asset visibility', async () => {
      // Bob starts as a member; removal revokes, re-adding restores.
      await removeLibraryMember({ id: archiveId(), userId: userId('bob') }, { headers: auth(adminToken) });
      await expect(utils.searchAssets(token('bob'), { libraryId: archiveId() })).rejects.toMatchObject({ status: 403 });
      await addLibraryMembers(
        { id: archiveId(), libraryMembersDto: { userIds: [userId('bob')] } },
        { headers: auth(adminToken) },
      );
      const members = await getLibraryMembers({ id: archiveId() }, { headers: auth(adminToken) });
      expect(members.map((m) => m.userId)).toContain(userId('bob'));
      const ids = await searchIds(token('bob'), { libraryId: archiveId() });
      expect(ids.length).toBe(3);
      // Outsider carol sees nothing.
      await expect(utils.searchAssets(token('carol'), { libraryId: archiveId() })).rejects.toMatchObject({
        status: 403,
      });
    }, 300_000);

    it('[R9-03] uploadPath validation rejects bad paths and saves a good one', async () => {
      await expect(
        utils.updateLibrary(adminToken, archiveId(), { uploadPath: '/elsewhere/incoming' }),
      ).rejects.toMatchObject({ status: 400 });
      mkdirSync(join(testAssetDir, 'temp', 'fork', 'archive', 'incoming2'), { recursive: true });
      await utils.updateLibrary(adminToken, archiveId(), {
        uploadPath: `${testAssetDirInternal}/temp/fork/archive/incoming2`,
      });
      // Restore the world upload path.
      await utils.updateLibrary(adminToken, archiveId(), {
        uploadPath: `${testAssetDirInternal}/temp/fork/archive/incoming`,
      });
    }, 300_000);

    it('[R9-04] a host-dropped file is scanned and visible to members', async () => {
      const source = join(generatedDir, 'fork-28.jpg');
      const destDir = join(testAssetDir, 'temp', 'fork', 'archive');
      cpSync(source, join(destDir, 'fork-28.jpg'));
      await utils.scan(adminToken, archiveId());
      await settle(adminToken);
      const ids = await searchIds(token('bob'), { libraryId: archiveId() });
      expect(ids.length).toBe(4);
      const { assets } = await utils.searchAssets(token('bob'), { libraryId: archiveId(), size: 100 });
      expect(assets.items.map((asset: AssetResponseDto) => asset.originalFileName)).toContain('fork-28.jpg');
    }, 300_000);

    it('[R10-01] personal asset moves into the upload path without duplication', async () => {
      const target = world.assets.find((a) => a.manifestId === 'fork-01')!;
      const result = await moveAssetsAs(world.users.alice, {
        assetIds: [target.id],
        target: { type: Type7.Library, id: archiveId() },
      });
      expect(result.results).toEqual([{ id: target.id, status: 'moved' }]);
      await settle(adminToken);
      const { assets } = await utils.searchAssets(token('alice'), { libraryId: archiveId(), size: 100 });
      const moved = assets.items.find((asset: AssetResponseDto) => asset.id === target.id);
      expect(moved).toMatchObject({ libraryId: archiveId() });
      const host = toHostPath(moved!.originalPath);
      expect(host?.startsWith(incomingHostDir())).toBe(true);
      expect(existsSync(host as string)).toBe(true);
      // Rescan: no duplicate import, asset stays online.
      await utils.scan(adminToken, archiveId());
      await settle(adminToken);
      const again = await searchIds(token('alice'), { libraryId: archiveId() });
      expect(again.filter((id) => id === target.id)).toHaveLength(1);
      const searched = await utils.searchAssets(token('alice'), { libraryId: archiveId(), size: 100 });
      const info = searched.assets.items.find((asset: AssetResponseDto) => asset.id === target.id)!;
      expect(info.isOffline).toBe(false);
    }, 300_000);

    it('[R10-02] library asset moves to a space and the watcher leaves it alone', async () => {
      const { assets } = await utils.searchAssets(token('alice'), { libraryId: archiveId(), size: 100 });
      const target = assets.items.find((asset: AssetResponseDto) => asset.originalFileName === 'fork-13.webp')!;
      const result = await moveAssetsAs(world.users.bob, {
        assetIds: [target.id],
        target: { type: Type6.Space, id: world.spaces.family.id },
      });
      expect(result.results).toEqual([{ id: target.id, status: 'moved' }]);
      await settle(adminToken);
      const searched = await utils.searchAssets(token('bob'), {
        spaceId: world.spaces.family.id,
        size: 100,
      });
      const info = searched.assets.items.find((asset: AssetResponseDto) => asset.id === target.id)!;
      expect(info.spaceId).toBe(world.spaces.family.id);
      expect(info.originalPath.startsWith('/test-assets/')).toBe(false);
      if (template === 'off') {
        expect(existsSync(expectedUploadPath(storageKey(info), info.originalFileName))).toBe(true);
      } else {
        expectFilesAt(
          {
            id: info.id,
            ownerId: info.ownerId,
            spaceId: info.spaceId,
            originalFileName: info.originalFileName,
            originalPath: info.originalPath,
          },
          { template, hostPrefix: sharedLibraryPrefix() },
        );
      }
      // A library scan must not delete or offline the moved-away asset.
      await utils.scan(adminToken, archiveId());
      await settle(adminToken);
      const rescanned = await utils.searchAssets(token('bob'), {
        spaceId: world.spaces.family.id,
        size: 100,
      });
      const after = rescanned.assets.items.find((asset: AssetResponseDto) => asset.id === target.id)!;
      expect(after.isOffline).toBe(false);
    }, 300_000);

    it('[R10-03] moving into a library without an upload path errors', async () => {
      const target = world.assets.find((a) => a.manifestId === 'fork-06')!;
      const result = await moveAssetsAs(world.users.alice, {
        assetIds: [target.id],
        target: { type: Type7.Library, id: world.libraries.nasro.id },
      });
      expect(result.results).toEqual([{ id: target.id, status: 'error', reason: 'target_access' }]);
    }, 300_000);
  },
);
