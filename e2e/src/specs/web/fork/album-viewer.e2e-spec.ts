import { AlbumUserRole, type AssetResponseDto } from '@immich/sdk';
import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { testAssetDir, utils } from 'src/utils.js';

// Covers TESTING.md §5 [W-05]: bob (album viewer) favorites in Trip so alice
// sees the heart, and the viewer can add/remove album assets. Needs the fork
// compose stack (scripts/fork-test/run.sh e2e-web).
test.describe('[W-05] album viewer favorites and edits', () => {
  let adminToken: string;
  let aliceToken: string;
  let bobToken: string;
  let albumId: string;
  let tripAssetId: string;
  let bobAssetId: string;

  const albumAssets = async (token: string): Promise<string[]> => {
    const { assets } = await utils.searchAssets(token, { albumIds: [albumId], size: 100 });
    return assets.items.map((asset: AssetResponseDto) => asset.id);
  };

  test.beforeAll(async () => {
    utils.initSdk();
    await utils.resetDatabase();
    const admin = await utils.adminSetup();
    adminToken = admin.accessToken;
    ({ accessToken: aliceToken } = await utils.userSetup(adminToken, {
      email: 'alice@example.com',
      password: 'Password123',
      name: 'alice',
    }));
    const bob = await utils.userSetup(adminToken, {
      email: 'bob@example.com',
      password: 'Password123',
      name: 'bob',
    });
    bobToken = bob.accessToken;
    const generated = join(testAssetDir, '..', 'fork-assets', 'generated');
    ({ id: tripAssetId } = await utils.createAsset(aliceToken, {
      assetData: { bytes: readFileSync(join(generated, 'fork-01.jpg')), filename: 'w-05-trip.jpg' },
    }));
    ({ id: bobAssetId } = await utils.createAsset(bobToken, {
      assetData: { bytes: readFileSync(join(generated, 'fork-11.jpg')), filename: 'w-05-bob.jpg' },
    }));
    ({ id: albumId } = await utils.createAlbum(aliceToken, {
      albumName: 'Trip',
      assetIds: [tripAssetId],
      albumUsers: [{ userId: bob.userId, role: AlbumUserRole.Viewer }],
    }));
    // Queue status is an admin endpoint: alice's token gets a 403 here.
    await utils.waitForQueueFinish(adminToken, 'metadataExtraction');
  });

  test('[W-05] viewer favorite shows a heart to the owner', async ({ context, page }) => {
    await utils.setAuthCookies(context, bobToken);
    await page.goto(`/albums/${albumId}`);
    await page.locator(`[data-asset="${tripAssetId}"]`).click();
    await page.waitForSelector('#immich-asset-viewer');

    const actions = page.getByTestId('asset-viewer-navbar-actions');
    await actions.getByRole('button', { name: 'Favorite' }).click();
    // The viewer action toasts the singular string (no count).
    await expect(page.getByText('Added to favorites', { exact: true })).toBeVisible();

    const { assets } = await utils.searchAssets(aliceToken, { isFavorite: true, size: 100 });
    expect(assets.items.map((asset: AssetResponseDto) => asset.id)).toContain(tripAssetId);

    // Alice sees the heart on the grid thumbnail.
    await utils.setAuthCookies(context, aliceToken);
    await page.goto(`/albums/${albumId}`);
    await expect(page.locator(`[data-asset="${tripAssetId}"]`).locator('[data-icon-favorite]')).toBeVisible();
  });

  test('[W-05] viewer can add and remove album assets', async ({ context, page }) => {
    await utils.setAuthCookies(context, bobToken);
    await page.goto(`/albums/${albumId}`);

    // Add one of bob's own assets through the picker.
    await page.getByRole('button', { name: 'Add photos' }).click();
    await expect(page.getByText('Add to album')).toBeVisible();
    await page.locator(`[data-asset="${bobAssetId}"]`).click();
    await page.getByRole('button', { name: 'Add assets' }).click();
    await expect(page.locator(`[data-asset="${bobAssetId}"]`)).toBeVisible();
    await expect(await albumAssets(bobToken)).toContain(bobAssetId);

    // Remove it again through the selection menu.
    const thumb = page.locator(`[data-asset="${bobAssetId}"]`);
    await thumb.hover();
    const checkbox = thumb.getByRole('checkbox');
    await expect(checkbox).toHaveCount(1);
    await checkbox.click();
    const menu = page.getByRole('button', { name: 'Menu' });
    await expect(menu).toHaveCount(1);
    await menu.click();
    await page.getByRole('menuitem', { name: 'Remove from album' }).click();
    // Removal asks for confirmation first.
    await page.getByRole('button', { name: 'Confirm' }).click();
    await expect(page.getByText('Removed 1 asset')).toBeVisible();
    await expect(thumb).toHaveCount(0);
    await expect(await albumAssets(aliceToken)).not.toContain(bobAssetId);
  });
});
