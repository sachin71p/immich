import { create as createSharedSpace } from '@immich/sdk';
import { expect, test } from '@playwright/test';
import { utils } from 'src/utils.js';

// Covers TESTING.md §5 [W-02]: default upload target + timeline source toggles
// persist and affect /photos. Needs the fork compose stack
// (scripts/fork-test/run.sh e2e-web).
test.describe('[W-02] library settings', () => {
  let aliceToken: string;

  test.beforeAll(async () => {
    utils.initSdk();
    await utils.resetDatabase();
    const admin = await utils.adminSetup();
    ({ accessToken: aliceToken } = await utils.userSetup(admin.accessToken, {
      email: 'alice@example.com',
      password: 'Password123',
      name: 'alice',
    }));
    await createSharedSpace(
      { sharedSpaceCreateDto: { name: 'Family Mobile' } },
      { headers: { Authorization: `Bearer ${aliceToken}` } },
    );
  });

  test('[W-02] upload target and timeline toggles persist and scope the timeline', async ({ context, page }) => {
    await utils.setAuthCookies(context, aliceToken);
    // A personal asset to observe timeline scoping with.
    const asset = await utils.createAsset(aliceToken, {
      assetData: { bytes: Buffer.from('w-02', 'utf8'), filename: 'w-02.jpg' },
    });
    await utils.waitForQueueFinish(aliceToken, 'metadataExtraction');

    await page.goto('/user-settings');
    await expect(page.getByText('Default upload target')).toBeVisible();

    // Default target starts personal; switch it to the space and back.
    await page.getByRole('button', { name: 'Personal library' }).click();
    await page.getByRole('button', { name: 'Family Mobile' }).click();
    await expect(page.getByRole('button', { name: 'Family Mobile' })).toBeVisible();
    await page.reload();
    await expect(page.getByRole('button', { name: 'Family Mobile' })).toBeVisible();
    await page.getByRole('button', { name: 'Family Mobile' }).click();
    await page.getByRole('button', { name: 'Personal library' }).click();

    // Hiding personal removes the asset from the default timeline scope that
    // /photos renders, while the explicit personal filter still finds it.
    const personalToggle = page.getByLabel('Personal library');
    await expect(personalToggle).toBeChecked();
    await personalToggle.click();
    await expect(personalToggle).not.toBeChecked();
    await page.reload();
    await expect(page.getByLabel('Personal library')).not.toBeChecked();

    const { assets: scoped } = await utils.searchAssets(aliceToken, { size: 100 });
    expect(scoped.items.map((item) => item.id)).not.toContain(asset.id);
    const { assets: personal } = await utils.searchAssets(aliceToken, { personalOnly: true, size: 100 });
    expect(personal.items.map((item) => item.id)).toContain(asset.id);
  });
});
