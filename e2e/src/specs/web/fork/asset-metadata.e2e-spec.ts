import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { testAssetDir, utils } from 'src/utils.js';

// Covers TESTING.md §5 [W-07]: the detail panel "All metadata" section shows
// manifest values and its search box filters keys. fork-01 carries
// make "Canon" / model "Canon EOS R5" in the fixture manifest. Needs the fork
// compose stack (scripts/fork-test/run.sh e2e-web).
test.describe('[W-07] full metadata panel', () => {
  let adminToken: string;
  let aliceToken: string;
  let assetId: string;

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
    ({ id: assetId } = await utils.createAsset(aliceToken, {
      assetData: {
        bytes: readFileSync(join(testAssetDir, '..', 'fork-assets', 'generated', 'fork-01.jpg')),
        filename: 'w-07.jpg',
      },
    }));
    // Queue status is an admin endpoint: alice's token gets a 403 here.
    await utils.waitForQueueFinish(adminToken, 'metadataExtraction');
  });

  test('[W-07] All metadata shows manifest values, search box filters keys', async ({ context, page }) => {
    await utils.setAuthCookies(context, aliceToken);
    await page.goto(`/photos/${assetId}`);
    await page.waitForSelector('#immich-asset-viewer');

    // The detail panel starts closed for a fresh profile.
    const toggle = page.getByRole('button', { name: 'All metadata' });
    if (!(await toggle.isVisible())) {
      await page.getByTestId('asset-viewer-navbar-actions').getByRole('button', { name: 'Info' }).click();
    }
    await expect(toggle).toBeVisible();
    await toggle.click();

    const search = page.getByPlaceholder('Search metadata keys');
    await expect(search).toBeVisible();
    const panel = search.locator('xpath=ancestor::section[1]');
    // Groups render as collapsed <details>: open each before asserting values.
    const summaries = panel.locator('summary');
    const groups = await summaries.count();
    for (let index = 0; index < groups; index++) {
      await summaries.nth(index).click();
    }
    await expect(panel.getByText('Canon', { exact: true })).toBeVisible();
    await expect(panel.getByText('Canon EOS R5')).toBeVisible();

    await search.fill('model');
    await expect(panel.getByText('Canon EOS R5')).toBeVisible();
    await expect(panel.getByText('Make', { exact: true })).toHaveCount(0);
  });
});
