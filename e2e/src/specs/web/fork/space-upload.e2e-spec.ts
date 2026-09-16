import { create as createSharedSpace, type AssetResponseDto } from '@immich/sdk';
import { expect, test } from '@playwright/test';
import { copyFileSync } from 'node:fs';
import { join } from 'node:path';
import { testAssetDir, utils } from 'src/utils.js';

// Covers TESTING.md §5 [W-06]: uploading from a space page lands in that
// space. Needs the fork compose stack (scripts/fork-test/run.sh e2e-web).
test.describe('[W-06] upload from a space page', () => {
  let adminToken: string;
  let aliceToken: string;
  let spaceId: string;

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
  });

  test('[W-06] upload from a space page lands in that space', async ({ context, page }) => {
    // Stage outside the repo: e2e/test-assets/temp is off-limits.
    const staged = '/tmp/w-06-upload.jpg';
    copyFileSync(join(testAssetDir, '..', 'fork-assets', 'generated', 'fork-05.jpg'), staged);

    await utils.setAuthCookies(context, aliceToken);
    await page.goto(`/shared-libraries/${spaceId}`);

    // Desktop and mobile navbars each render an Upload button.
    const uploads = page.getByRole('button', { name: 'Upload' });
    await expect(uploads.first()).toBeVisible();
    // Match the upload POST exactly: the dedup pre-check also POSTs under
    // /assets (/assets/bulk-upload-check) and would resolve the wait early.
    const upload = page.waitForResponse(
      (response) => response.url().endsWith('/api/assets') && response.request().method() === 'POST',
    );
    const chooser = page.waitForEvent('filechooser');
    await uploads.first().click();
    const files = await chooser;
    await files.setFiles(staged);
    const response = await upload;
    expect(response.ok()).toBe(true);

    const { assets } = await utils.searchAssets(aliceToken, { spaceId, size: 100 });
    const landed = assets.items.find((asset: AssetResponseDto) => asset.originalFileName === 'w-06-upload.jpg');
    expect(landed?.id).toBeTruthy();
    const info = await utils.getAssetInfo(aliceToken, landed!.id);
    expect(info.spaceId).toBe(spaceId);
    await expect(page.locator(`[data-asset="${landed!.id}"]`)).toBeVisible();
  });
});
