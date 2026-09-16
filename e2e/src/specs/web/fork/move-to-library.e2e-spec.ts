import { create as createSharedSpace } from '@immich/sdk';
import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { testAssetDir, utils } from 'src/utils.js';

// Covers TESTING.md §5 [W-04]: "Move to…" lists only allowed targets, the
// result toast fires, and the grid updates. Needs the fork compose stack
// (scripts/fork-test/run.sh e2e-web).
test.describe('[W-04] move to dialog', () => {
  let adminToken: string;
  let aliceToken: string;
  let carolToken: string;
  let familyId: string;
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
    ({ accessToken: carolToken } = await utils.userSetup(adminToken, {
      email: 'carol@example.com',
      password: 'Password123',
      name: 'carol',
    }));
    ({ id: familyId } = await createSharedSpace(
      { sharedSpaceCreateDto: { name: 'Family Mobile' } },
      { headers: { Authorization: `Bearer ${aliceToken}` } },
    ));
    // A space alice is NOT a member of: never a legal move target for her.
    await createSharedSpace(
      { sharedSpaceCreateDto: { name: 'Elsewhere' } },
      { headers: { Authorization: `Bearer ${carolToken}` } },
    );
    ({ id: assetId } = await utils.createAsset(aliceToken, {
      assetData: {
        bytes: readFileSync(join(testAssetDir, '..', 'fork-assets', 'generated', 'fork-05.jpg')),
        filename: 'w-04.jpg',
      },
    }));
    // Queue status is an admin endpoint: alice's token gets a 403 here.
    await utils.waitForQueueFinish(adminToken, 'metadataExtraction');
  });

  test('[W-04] Move to lists only allowed targets; result toast; grid updates', async ({ context, page }) => {
    await utils.setAuthCookies(context, aliceToken);
    await page.goto('/photos');
    const thumb = page.locator(`[data-asset="${assetId}"]`);
    await expect(thumb).toBeVisible();

    // Select the asset: the checkbox only renders on hover.
    await thumb.hover();
    const checkbox = thumb.getByRole('checkbox');
    await expect(checkbox).toHaveCount(1);
    await checkbox.click();

    // The selection bar renders a single Menu button.
    const menu = page.getByRole('button', { name: 'Menu' });
    await expect(menu).toHaveCount(1);
    await menu.click();
    await page.getByRole('menuitem', { name: 'Move to…' }).click();

    const dialog = page.getByRole('dialog');
    await expect(dialog.getByText('Personal', { exact: true })).toBeVisible();
    await expect(dialog.getByText('Family Mobile')).toBeVisible();
    await expect(dialog.getByText('Elsewhere')).toHaveCount(0);

    await dialog.getByText('Family Mobile').click();
    await expect(page.getByText(/1 moved/)).toBeVisible();
    // The moved asset no longer matches the timeline it left.
    await expect(thumb).toHaveCount(0);

    const info = await utils.getAssetInfo(aliceToken, assetId);
    expect(info.spaceId).toBe(familyId);
  });
});
