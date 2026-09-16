import { create as createSharedSpace, type AssetResponseDto } from '@immich/sdk';
import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { testAssetDir, utils } from 'src/utils.js';

// Covers TESTING.md §5 [W-08]: exposure/file filters plus the library
// selector return the expected assets, and the URL round-trips. Fixture ISOs:
// fork-01 100 (jpg, personal), fork-03 3200 (png, personal), fork-02 800
// (jpg, space). Needs the fork compose stack (scripts/fork-test/run.sh
// e2e-web).

// Each search starts from a clean /search load (fresh filter state).
const openFilters = async (page: Page) => {
  await page.goto('/search');
  await page.getByRole('search').getByRole('combobox').click();
  await page.getByRole('button', { name: 'Advanced filters' }).click();
  await expect(page.locator('#exposure-selection')).toBeVisible();
};

// The search bar carries its own "Search"-named button, so scope the submit
// to the open filters panel.
const filtersPanel = (page: Page) =>
  page.locator('div[role="listbox"]', { has: page.getByRole('button', { name: 'Advanced filters' }) });

const submitSearch = async (page: Page) => {
  const search = filtersPanel(page).getByRole('button', { name: 'Search', exact: true });
  await expect(search).toHaveCount(1);
  // The panel can extend past the viewport in a way Playwright cannot scroll
  // into view; the button is visible and enabled, so dispatch the click.
  await search.dispatchEvent('click');
  await expect(page).toHaveURL(/query=/);
};

const gridIds = (page: Page) => page.locator('[data-asset]');

test.describe('[W-08] search filters', () => {
  let adminToken: string;
  let aliceToken: string;
  let spaceId: string;
  let iso100Id: string;
  let iso3200Id: string;
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
    ({ id: iso100Id } = await utils.createAsset(aliceToken, {
      assetData: { bytes: readFileSync(join(generated, 'fork-01.jpg')), filename: 'w-08-iso100.jpg' },
    }));
    ({ id: iso3200Id } = await utils.createAsset(aliceToken, {
      assetData: { bytes: readFileSync(join(generated, 'fork-03.png')), filename: 'w-08-iso3200.png' },
    }));
    ({ id: spaceAssetId } = await utils.createAsset(aliceToken, {
      assetData: { bytes: readFileSync(join(generated, 'fork-02.jpg')), filename: 'w-08-space.jpg' },
      spaceId,
    }));
    // Queue status is an admin endpoint: alice's token gets a 403 here.
    await utils.waitForQueueFinish(adminToken, 'metadataExtraction');
  });

  test('[W-08] exposure filter returns expected assets', async ({ context, page }) => {
    await utils.setAuthCookies(context, aliceToken);
    await openFilters(page);

    // ISO lives in the first min/max pair of the exposure section.
    const exposure = page.locator('#exposure-selection');
    await exposure.getByRole('spinbutton', { name: 'Min' }).first().fill('50');
    await exposure.getByRole('spinbutton', { name: 'Max' }).first().fill('200');
    await submitSearch(page);

    expect(decodeURIComponent(page.url())).toContain('"isoMin":50');
    await expect(gridIds(page)).toHaveCount(1);
    await expect(page.locator(`[data-asset="${iso100Id}"]`)).toBeVisible();
    await expect(page.locator(`[data-asset="${iso3200Id}"]`)).toHaveCount(0);
    await expect(page.locator(`[data-asset="${spaceAssetId}"]`)).toHaveCount(0);
  });

  test('[W-08] file filter returns expected assets', async ({ context, page }) => {
    await utils.setAuthCookies(context, aliceToken);
    await openFilters(page);

    await page.locator('#file-selection').getByPlaceholder('jpg, png').fill('png');
    await submitSearch(page);

    expect(decodeURIComponent(page.url())).toContain('"fileExtensions":["png"]');
    await expect(gridIds(page)).toHaveCount(1);
    await expect(page.locator(`[data-asset="${iso3200Id}"]`)).toBeVisible();
  });

  test('[W-08] library selector returns expected assets; URL round-trips', async ({ context, page }) => {
    await utils.setAuthCookies(context, aliceToken);
    await openFilters(page);

    // The section title shares its name with the activating button, so open
    // the section via the button role and scope the rest to the section.
    await page.getByRole('button', { name: 'Library', exact: true }).click();
    const library = page.locator('#library-selection');
    const combo = library.getByRole('combobox', { name: 'Shared libraries' });
    await combo.click();
    // Options portal outside the section: match page-wide by exact name.
    await page.getByRole('option', { name: 'Family Mobile' }).click();
    await expect(combo).toHaveValue('Family Mobile');
    await submitSearch(page);

    expect(decodeURIComponent(page.url())).toContain(`"spaceId":"${spaceId}"`);
    await expect(gridIds(page)).toHaveCount(1);
    await expect(page.locator(`[data-asset="${spaceAssetId}"]`)).toBeVisible();
    await expect(page.locator(`[data-asset="${iso100Id}"]`)).toHaveCount(0);

    // Reload: the URL restores both the filter UI and the results.
    await page.reload();
    await expect(page.locator(`[data-asset="${spaceAssetId}"]`)).toBeVisible();
    await expect(gridIds(page)).toHaveCount(1);
    const { assets } = await utils.searchAssets(aliceToken, { spaceId, size: 100 });
    expect(assets.items.map((asset: AssetResponseDto) => asset.id)).toEqual([spaceAssetId]);
  });
});
