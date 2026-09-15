import { expect, test } from '@playwright/test';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { testAssetDir, testAssetDirInternal, utils } from 'src/utils.js';

// Covers TESTING.md §5 [W-09]: admin adds a library member and saves the
// upload path, with server validation errors displayed. Needs the fork compose
// stack (scripts/fork-test/run.sh e2e-web).
test.describe('[W-09] external library members and upload path', () => {
  let adminToken: string;
  let libraryId: string;
  let uploadDir: string;

  test.beforeAll(async () => {
    utils.initSdk();
    await utils.resetDatabase();
    const admin = await utils.adminSetup();
    adminToken = admin.accessToken;
    await utils.userSetup(adminToken, {
      email: 'bob@example.com',
      password: 'Password123',
      name: 'bob',
    });
    mkdirSync(join(testAssetDir, 'temp', 'fork-web', 'incoming'), { recursive: true });
    ({ id: libraryId } = await utils.createLibrary(adminToken, {
      name: 'Archive',
      ownerId: admin.userId,
      importPaths: [`${testAssetDirInternal}/temp/fork-web`],
    }));
    uploadDir = `${testAssetDirInternal}/temp/fork-web/incoming`;
  });

  test('[W-09] add a member and validate the upload path', async ({ context, page }) => {
    await utils.setAuthCookies(context, adminToken);
    await page.goto(`/admin/library-management/${libraryId}`);

    // Add bob through the members modal.
    await page.getByRole('button', { name: 'Add', exact: true }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByPlaceholder('Search').fill('bob');
    await dialog.getByText('bob@example.com').click();
    await dialog.getByRole('button', { name: 'Add', exact: true }).click();
    // Reopening lists bob as a member with a Remove action.
    await page.getByRole('button', { name: 'Add', exact: true }).click();
    await expect(page.getByRole('dialog').getByText('bob', { exact: true })).toBeVisible();
    await expect(page.getByRole('dialog').getByRole('button', { name: 'Remove' })).toBeVisible();
    await page.keyboard.press('Escape');

    // A path outside the import paths shows the server validation error.
    await page.getByPlaceholder('/library/import/upload').fill('/elsewhere/incoming');
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByText(/Immich Server Error/)).toBeVisible();

    // A writable path inside the import paths saves (the toast only fires on success).
    await page.getByPlaceholder('/library/import/upload').fill(uploadDir);
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByText('Updated library')).toBeVisible();
  });
});
