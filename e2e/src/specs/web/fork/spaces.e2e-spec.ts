import { getMembers2 as getSpaceMembers } from '@immich/sdk';
import { expect, test } from '@playwright/test';
import { utils } from 'src/utils.js';

// Covers TESTING.md §5 [W-01]: create space, add member, rename, leave/delete
// flows with confirm dialogs. Needs the fork compose stack
// (scripts/fork-test/run.sh e2e-web).
test.describe('[W-01] shared libraries', () => {
  let aliceToken: string;
  let bobToken: string;
  let bobUserId: string;

  test.beforeAll(async () => {
    utils.initSdk();
    await utils.resetDatabase();
    const admin = await utils.adminSetup();
    ({ accessToken: aliceToken } = await utils.userSetup(admin.accessToken, {
      email: 'alice@example.com',
      password: 'Password123',
      name: 'alice',
    }));
    const bob = await utils.userSetup(admin.accessToken, {
      email: 'bob@example.com',
      password: 'Password123',
      name: 'bob',
    });
    bobToken = bob.accessToken;
    bobUserId = bob.userId;
  });

  test('[W-01] create a space with a confirm-free create dialog', async ({ context, page }) => {
    await utils.setAuthCookies(context, aliceToken);
    await page.goto('/shared-libraries');
    await page.getByRole('button', { name: 'New shared library' }).click();
    await page.getByRole('textbox', { name: 'Name' }).fill('Family Mobile');
    await page.getByRole('button', { name: 'Create' }).click();
    await expect(page.getByText('Shared library created')).toBeVisible();
    await expect(page.getByText('Family Mobile').first()).toBeVisible();
  });

  test('[W-01] add a member, rename, then leave and delete with confirms', async ({ context, page }) => {
    await utils.setAuthCookies(context, aliceToken);
    await page.goto('/shared-libraries');
    await page.getByText('Family Mobile').first().click();
    await expect(page).toHaveURL(/\/shared-libraries\/.+/);

    // Add bob as a member.
    await page.getByRole('button', { name: 'Members' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByPlaceholder('Search').fill('bob');
    await dialog.getByText('bob@example.com').click();
    await dialog.getByRole('button', { name: 'Add', exact: true }).click();
    // Reopening no longer offers bob: he is now a member. The admin remains a
    // candidate, so anchor on the populated list (admin visible, bob absent)
    // rather than the empty-list text.
    await page.getByRole('button', { name: 'Members' }).click();
    const membersDialog = page.getByRole('dialog');
    await expect(membersDialog.getByText('admin@immich.cloud')).toBeVisible();
    await expect(membersDialog.getByText('bob@example.com')).not.toBeVisible();
    await page.keyboard.press('Escape');
    const spaceId = page.url().split('/').pop() as string;
    const members = await getSpaceMembers(
      { id: spaceId },
      { headers: { Authorization: `Bearer ${aliceToken}` } },
    );
    expect(members.map((member) => member.userId)).toContain(bobUserId);

    // Rename via the menu.
    await page.getByRole('button', { name: 'Menu' }).click();
    await page.getByText('Edit').click();
    await page.getByRole('textbox', { name: 'Name' }).fill('Family Mobile Renamed');
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('heading', { name: 'Family Mobile Renamed' })).toBeVisible();

    // Bob leaves through the confirm dialog.
    await utils.setAuthCookies(context, bobToken);
    await page.goto('/shared-libraries');
    await page.getByText('Family Mobile Renamed').first().click();
    await page.getByRole('button', { name: 'Menu' }).click();
    await page.getByText('Leave shared library').click();
    await page.getByRole('button', { name: 'Confirm' }).click();
    await expect(page).toHaveURL('/shared-libraries');
    await expect(page.getByText('Family Mobile Renamed')).not.toBeVisible();

    // Alice deletes through the confirm dialog.
    await utils.setAuthCookies(context, aliceToken);
    await page.goto('/shared-libraries');
    await page.getByText('Family Mobile Renamed').first().click();
    await page.getByRole('button', { name: 'Menu' }).click();
    await page.getByText('Delete shared library').click();
    await page.getByRole('button', { name: 'Confirm' }).click();
    await expect(page).toHaveURL('/shared-libraries');
    await expect(page.getByText('Family Mobile Renamed')).not.toBeVisible();
  });
});
