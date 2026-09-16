// Fork world smoke (shared-libraries, T0).
// [R17-01] world builds in both template modes, every asset's files at
// expectedPaths; [R17-03] auditDisk() is clean afterwards.
// Needs the fork compose stack (scripts/fork-test/run.sh e2e-api).

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { utils } from 'src/utils.js';
import { auditDisk, expectFilesAt, personalLibraryPrefix, sharedLibraryPrefix, type DiskAsset } from './disk.js';
import { auditToken, buildWorld, getAsset, type World } from './world.js';

const withSidecar = new Set(['fork-06', 'fork-07', 'fork-08', 'fork-10']);

const toDiskAsset = async (token: string, entry: { id: string; manifestId: string }): Promise<DiskAsset> => {
  const asset = await getAsset(token, entry.id);
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

const tokenFor = (world: World, owner: string): Promise<string> =>
  // Placement audits read through the elevated audit sessions (locked assets
  // are unreadable on plain sessions).
  auditToken(world, owner);

describe.sequential.each(
  process.env.FORK_E2E_TEMPLATE === 'on' ? ([{ template: 'on' }] as const) : ([{ template: 'off' }] as const),
)('[R17-01] fork world ($template)', ({ template }) => {
  let world: World;

  beforeAll(async () => {
    utils.initSdk();
    world = await buildWorld({ storageTemplate: template });
  }, 600_000);

  afterAll(() => {
    utils.resetTempFolder();
  });

  it('places every asset at its expected paths', async () => {
    for (const entry of world.assets) {
      const disk = await toDiskAsset(await tokenFor(world, entry.owner), entry);
      const hostPrefix = disk.spaceId
        ? sharedLibraryPrefix()
        : disk.libraryId
          ? undefined
          : personalLibraryPrefix(disk.ownerId);
      expectFilesAt(disk, { template, hostPrefix });
    }
  }, 300_000);

  it('[R17-03] auditDisk() reports zero orphans and zero missing files', async () => {
    const { orphans, missing } = await auditDisk(async () =>
      Promise.all(
        world.assets.map(async (entry) => {
          const disk = await toDiskAsset(await tokenFor(world, entry.owner), entry);
          return { id: disk.id, originalPath: disk.originalPath, sidecarPath: disk.sidecarPath };
        }),
      ),
    );
    expect(missing, `missing files: ${missing.join(', ')}`).toEqual([]);
    expect(orphans, `orphan files: ${orphans.join(', ')}`).toEqual([]);
  }, 300_000);

  it('covers the manifest fixtures used by the world', () => {
    const manifest = JSON.parse(
      readFileSync(join(import.meta.dirname, '..', '..', '..', '..', '..', 'fork-assets', 'manifest.json'), 'utf8'),
    ) as {
      generated: { id: string }[];
    };
    const used = new Set(world.assets.map((a) => a.manifestId));
    for (const id of ['fork-01', 'fork-02', 'fork-03', 'fork-06', 'fork-09a', 'fork-09b', 'fork-10']) {
      expect(used.has(id), `world missing coverage fixture ${id}`).toBe(true);
    }
    expect(manifest.generated.length).toBeGreaterThan(0);
  });
});
