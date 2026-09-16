import { create as createSharedSpace } from '@immich/sdk';
import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { testAssetDir, utils } from 'src/utils.js';

// Covers TESTING.md §5 [W-03]: the /photos library switcher filters the grid
// and the visible counts match the API world. Needs the fork compose stack
// (scripts/fork-test/run.sh e2e-web).
test.describe('[W-03] library switcher', () => {
  let adminToken: string;
  let aliceToken: string;
  let spaceId: string;
  let personalId: string;
  let spaceAssetId: string;

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
    ({ id: spaceId } = await createSharedSpace(
      { sharedSpaceCreateDto: { name: 'Family Mobile' } },
      { headers: { Authorization: `Bearer ${aliceToken}` } },
    ));
    const generated = join(testAssetDir, '..', 'fork-assets', 'generated');
    ({ id: personalId } = await utils.createAsset(aliceToken, {
      assetData: { bytes: readFileSync(join(generated, 'fork-05.jpg')), filename: 'w-03-personal.jpg' },
    }));
    ({ id: spaceAssetId } = await utils.createAsset(aliceToken, {
      assetData: { bytes: readFileSync(join(generated, 'fork-07.jpg')), filename: 'w-03-space.jpg' },
      spaceId,
    }));
    // Queue status is an admin endpoint: alice's token gets a 403 here.
    await utils.waitForQueueFinish(adminToken, 'metadataExtraction');
  });

  test('[W-03] library switcher filters the grid (counts match world)', async ({ context, page }) => {
    // The world both selections must agree with: all, personal-only, space.
    const { assets: all } = await utils.searchAssets(aliceToken, { size: 100 });
    expect(all.items.map((item) => item.id)).toEqual(expect.arrayContaining([personalId, spaceAssetId]));
    const { assets: personal } = await utils.searchAssets(aliceToken, { personalOnly: true, size: 100 });
    expect(personal.items.map((item) => item.id)).toEqual([personalId]);
    const { assets: inSpace } = await utils.searchAssets(aliceToken, { spaceId, size: 100 });
    expect(inSpace.items.map((item) => item.id)).toEqual([spaceAssetId]);

    await utils.setAuthCookies(context, aliceToken);
    await page.goto('/photos');

    const thumbs = page.locator('[data-asset]');
    // The bits-ui Select trigger is a plain button with a static "Libraries"
    // aria-label; the selected value is only its text content. (The search
    // bar owns the page's single combobox role; the sidebar "Family Mobile"
    // entry is a span, never a button.)
    const switcher = page.getByRole('button', { name: 'Libraries' });
    await expect(switcher).toHaveCount(1);
    await expect(switcher).toBeVisible();
    // Default source is "all": both assets render.
    await expect(thumbs).toHaveCount(2);

    // Personal shows only the personal asset.
    await switcher.click();
    await page.getByRole('option', { name: 'Personal', exact: true }).click();
    await expect(thumbs).toHaveCount(1);
    await expect(page.locator(`[data-asset="${personalId}"]`)).toBeVisible();
    await expect(page.locator(`[data-asset="${spaceAssetId}"]`)).toHaveCount(0);

    // The space shows only the space asset.
    await switcher.click();
    await page.getByRole('option', { name: 'Family Mobile' }).click();
    await expect(thumbs).toHaveCount(1);
    await expect(page.locator(`[data-asset="${spaceAssetId}"]`)).toBeVisible();
    await expect(page.locator(`[data-asset="${personalId}"]`)).toHaveCount(0);
  });
});
