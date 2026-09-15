// Fork shared albums and global favorites (shared-libraries, T1).
// Covers TESTING.md §5: R11-01, R11-02, R16-01..03.
// Needs the fork compose stack (scripts/fork-test/run.sh e2e-api).

import {
  AlbumUserRole,
  addAssetsToAlbum as addAssetsToAlbumSdk,
  removeAssetFromAlbum as removeAssetFromAlbumSdk,
  updateAssets,
  type AssetResponseDto,
} from '@immich/sdk';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { utils } from 'src/utils.js';
import { buildWorld, type World } from './world.js';

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

describe('fork albums and favorites', () => {
  let world: World;

  const token = (user: keyof World['users']) => world.users[user].login.accessToken;
  const userId = (user: keyof World['users']) => world.users[user].login.userId;
  const albumAssets = async (user: keyof World['users']): Promise<string[]> => {
    const { assets } = await utils.searchAssets(token(user), { albumIds: [world.albumTrip.id], size: 100 });
    return assets.items.map((asset: AssetResponseDto) => asset.id);
  };

  beforeAll(async () => {
    utils.initSdk();
    world = await buildWorld({ storageTemplate: 'on' });
  }, 600_000);

  afterAll(() => {
    utils.resetTempFolder();
  });

  it('[R11-01] album viewer adds and removes any album asset', async () => {
    const mine = world.assets.find((a) => a.manifestId === 'fork-15')!;
    const hers = world.assets.find((a) => a.manifestId === 'fork-01')!;
    await addAssetsToAlbumSdk(
      { id: world.albumTrip.id, bulkIdsDto: { ids: [mine.id] } },
      { headers: auth(token('bob')) },
    );
    await expect(albumAssets('bob')).resolves.toContain(mine.id);
    await removeAssetFromAlbumSdk(
      { id: world.albumTrip.id, bulkIdsDto: { ids: [hers.id] } },
      { headers: auth(token('bob')) },
    );
    await expect(albumAssets('alice')).resolves.not.toContain(hers.id);
  }, 300_000);

  it('[R11-02] album roles are safeguarded', async () => {
    // Nobody can change their own role …
    await expect(
      utils.updateAlbumUser(token('bob'), {
        id: world.albumTrip.id,
        userId: userId('bob'),
        updateAlbumUserDto: { role: AlbumUserRole.Editor },
      }),
    ).rejects.toMatchObject({ status: 400 });
    // … and nobody can grant owner.
    await expect(
      utils.updateAlbumUser(token('alice'), {
        id: world.albumTrip.id,
        userId: userId('bob'),
        updateAlbumUserDto: { role: 'owner' as AlbumUserRole },
      }),
    ).rejects.toMatchObject({ status: 400 });
  });

  it('[R16-01] album viewer favorite shows up in the owner favorites', async () => {
    const target = world.assets.find((a) => a.manifestId === 'fork-01')!;
    await updateAssets(
      { assetBulkUpdateDto: { ids: [target.id], isFavorite: true } },
      { headers: auth(token('bob')) },
    );
    const { assets } = await utils.searchAssets(token('alice'), { isFavorite: true, size: 100 });
    expect(assets.items.map((asset: AssetResponseDto) => asset.id)).toContain(target.id);
  });

  it('[R16-02] favorite-only bulk update passes, mixed update is 403', async () => {
    const target = world.assets.find((a) => a.manifestId === 'fork-01')!;
    await updateAssets(
      { assetBulkUpdateDto: { ids: [target.id], isFavorite: true } },
      { headers: auth(token('bob')) },
    );
    await expect(
      updateAssets(
        { assetBulkUpdateDto: { ids: [target.id], isFavorite: true, description: 'hijack' } },
        { headers: auth(token('bob')) },
      ),
    ).rejects.toMatchObject({ status: 403 });
  });

  it('[R16-03] partner cannot favorite', async () => {
    const target = world.assets.find((a) => a.manifestId === 'fork-01')!;
    await expect(
      updateAssets(
        { assetBulkUpdateDto: { ids: [target.id], isFavorite: true } },
        { headers: auth(token('dave')) },
      ),
    ).rejects.toMatchObject({ status: 403 });
  });
});
