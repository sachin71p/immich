import { create as createSharedSpace } from '@immich/sdk';
import { expect, test } from '@playwright/test';
import { utils } from 'src/utils.js';

// Covers TESTING.md §5 [W-02]: default upload target + timeline source toggles
// persist and affect /photos. Needs the fork compose stack
// (scripts/fork-test/run.sh e2e-web).
test.describe('[W-02] library settings', () => {
  let adminToken: string;
  let aliceToken: string;

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
    // Queue status is an admin endpoint: alice's token gets a 403 here.
    await utils.waitForQueueFinish(adminToken, 'metadataExtraction');

    await page.goto('/user-settings');
    // Library settings live in a collapsed accordion: expand it first.
    await page.getByRole('heading', { name: /^libraries$/i }).click();
    await expect(page.getByText('Default upload target')).toBeVisible();

    // Default target starts personal; switch it to the space and back. The space
    // name also labels its timeline-source switch row, so scope every dropdown
    // interaction: the selected value is the data-button-root Button, options
    // live in the open absolute-positioned menu (selection leaves it open).
    const displayValue = (name: string) => page.locator('button[data-button-root]').filter({ hasText: name });
    const menuOption = (name: string) =>
      page.locator('div.absolute').getByRole('button', { name, exact: true });
    await displayValue('Personal library').click();
    // The save fires async on selection: reloading before it lands aborts the
    // request and the preference silently reverts.
    const firstSave = page.waitForResponse(
      (response) => response.url().includes('preferences') && response.request().method() !== 'GET',
    );
    await menuOption('Family Mobile').click();
    const saveResult = await firstSave;
    expect(saveResult.ok()).toBe(true);
    await page.keyboard.press('Escape');
    await expect(displayValue('Family Mobile')).toBeVisible();
    await page.reload();
    await expect(displayValue('Family Mobile')).toBeVisible();
    await displayValue('Family Mobile').click();
    await menuOption('Personal library').click();
    await page.keyboard.press('Escape');

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
