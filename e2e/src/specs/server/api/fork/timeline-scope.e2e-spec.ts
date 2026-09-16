// Fork timeline scope and smart-search scope (shared-libraries, T1).
// Covers TESTING.md §5: R8-01..05, R13-04 (smart search, ML-gated).
// Needs the fork compose stack (scripts/fork-test/run.sh e2e-api).

import {
  getMapMarkers,
  getTimeBuckets,
  searchAssetStatistics,
  searchSmart,
  updateMyPreferences,
  updateMyTimeline2,
  type AssetResponseDto,
} from '@immich/sdk';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { utils } from 'src/utils.js';
import { buildWorld, type World } from './world.js';

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

const bucketTotal = async (token: string, params: Record<string, unknown> = {}): Promise<number> => {
  const buckets = (await getTimeBuckets(params as never, { headers: auth(token) })) as unknown as {
    count: number;
  }[];
  return buckets.reduce((sum, bucket) => sum + bucket.count, 0);
};

const searchIds = async (token: string, dto: Record<string, unknown> = {}): Promise<string[]> => {
  // Match the unstacked timeline bucket contract used throughout this suite.
  // Search otherwise returns only the stack primary, while the expected world
  // deliberately contains both members of Bob's two-item stack.
  const { assets } = await utils.searchAssets(token, { size: 100, withStacked: false, ...dto });
  return assets.items.map((asset: AssetResponseDto) => asset.id);
};

describe('fork timeline scope', () => {
  let world: World;

  const token = (user: keyof World['users']) => world.users[user].login.accessToken;
  // World assets visible to bob by default: his personal (6), Family Mobile
  // (3), Camera (4), Archive (3). Carol Solo, alice personal, NAS-RO excluded.
  const expectedBobIds = () => [
    ...world.assets
      .filter((a) => ['fork-15', 'fork-23', 'fork-24', 'fork-20', 'fork-21', 'fork-09a'].includes(a.manifestId))
      .map((a) => a.id),
    ...world.assets
      .filter((a) =>
        ['fork-02', 'fork-08', 'fork-12', 'fork-03', 'fork-16', 'fork-19', 'fork-09b'].includes(a.manifestId),
      )
      .map((a) => a.id),
  ];
  const cameraIds = () =>
    world.assets.filter((a) => ['fork-03', 'fork-16', 'fork-19', 'fork-09b'].includes(a.manifestId)).map((a) => a.id);

  beforeAll(async () => {
    utils.initSdk();
    world = await buildWorld({ storageTemplate: 'on' });
  }, 600_000);

  afterAll(() => {
    utils.resetTempFolder();
  });

  it('[R8-01] default timeline matches the visible world', async () => {
    const expected = new Set(expectedBobIds());
    expect(expected.size).toBe(6 + 3 + 4);
    const ids = await searchIds(token('bob'));
    expect(new Set(ids)).toEqual(expected);
    // Buckets (unstacked) agree with search.
    await expect(bucketTotal(token('bob'), { withStacked: false })).resolves.toBe(expected.size);
  }, 300_000);

  it('[R8-02] hidden containers leave every surface but stay directly filterable', async () => {
    const beforeBuckets = await bucketTotal(token('bob'), { withStacked: false });
    const beforeMarkers = await getMapMarkers({}, { headers: auth(token('bob')) });
    const beforeStats = await searchAssetStatistics({ statisticsSearchDto: {} }, { headers: auth(token('bob')) });
    expect(beforeBuckets).toBeGreaterThan(0);

    await updateMyTimeline2(
      { id: world.spaces.camera.id, sharedSpaceTimelineDto: { showInTimeline: false } },
      { headers: auth(token('bob')) },
    );

    const hidden = new Set(cameraIds());
    const ids = await searchIds(token('bob'));
    expect(ids.some((id) => hidden.has(id))).toBe(false);
    await expect(bucketTotal(token('bob'), { withStacked: false })).resolves.toBe(beforeBuckets - hidden.size);
    const markers = await getMapMarkers({}, { headers: auth(token('bob')) });
    const markerIds = new Set((markers as unknown as { id: string }[]).map((marker) => marker.id));
    expect([...hidden].some((id) => markerIds.has(id))).toBe(false);
    expect(markers.length).toBeLessThan(beforeMarkers.length);
    const stats = await searchAssetStatistics({ statisticsSearchDto: {} }, { headers: auth(token('bob')) });
    expect(stats.total).toBe(beforeStats.total - hidden.size);

    // Explicit spaceId still shows the hidden container.
    const direct = await searchIds(token('bob'), { spaceId: world.spaces.camera.id });
    expect(new Set(direct)).toEqual(hidden);
    await expect(bucketTotal(token('bob'), { spaceId: world.spaces.camera.id, withStacked: false })).resolves.toBe(
      hidden.size,
    );

    await updateMyTimeline2(
      { id: world.spaces.camera.id, sharedSpaceTimelineDto: { showInTimeline: true } },
      { headers: auth(token('bob')) },
    );
  }, 300_000);

  it('[R8-03] hiding personal leaves only shared containers', async () => {
    await updateMyPreferences(
      { userPreferencesUpdateDto: { sharedLibraries: { showPersonalInTimeline: false } } },
      { headers: auth(token('bob')) },
    );
    const ids = await searchIds(token('bob'));
    const personal = new Set(
      world.assets.filter((a) => ['fork-15', 'fork-23', 'fork-24', 'fork-20', 'fork-21', 'fork-09a'].includes(a.manifestId)).map((a) => a.id),
    );
    expect(ids.some((id) => personal.has(id))).toBe(false);
    expect(ids.length).toBe(3 + 4 + 3);
    await updateMyPreferences(
      { userPreferencesUpdateDto: { sharedLibraries: { showPersonalInTimeline: true } } },
      { headers: auth(token('bob')) },
    );
  }, 300_000);

  it('[R8-04] explicit filters are exclusive and access-checked', async () => {
    // Two filters at once is a 400.
    await expect(
      utils.searchAssets(token('bob'), {
        spaceId: world.spaces.family.id,
        libraryId: world.libraries.archive.id,
      }),
    ).rejects.toMatchObject({ status: 400 });
    // A space bob cannot see is a 403.
    await expect(utils.searchAssets(token('bob'), { spaceId: world.spaces.carolSolo.id })).rejects.toMatchObject({
      status: 403,
    });
    // personalOnly returns exactly the personal slice.
    const personal = await searchIds(token('bob'), { personalOnly: true });
    expect(personal.length).toBe(6);
  });

  it('[R8-05] partner sees alice personal, not her shared containers', async () => {
    // Dave owns nothing: without partners his timeline is empty.
    await expect(bucketTotal(token('dave'), { withPartners: false })).resolves.toBe(0);
    const withPartners = await bucketTotal(token('dave'), { withPartners: true });
    // Alice personal timeline assets: fork-01/06/07 + live still (+motion).
    // Locked (fork-10) never appears on a timeline.
    expect(withPartners).toBeGreaterThanOrEqual(3);
    // Dave cannot reach the shared containers directly either.
    await expect(utils.searchAssets(token('dave'), { spaceId: world.spaces.family.id })).rejects.toMatchObject({
      status: 403,
    });
    await expect(
      utils.searchAssets(token('dave'), { libraryId: world.libraries.archive.id }),
    ).rejects.toMatchObject({ status: 403 });
  }, 300_000);

  it('[R9-02] hiding an owned library removes it from the timeline but not its filter', async () => {
    const before = await bucketTotal(token('alice'), { withStacked: false });
    await updateMyPreferences(
      {
        userPreferencesUpdateDto: { sharedLibraries: { hiddenOwnedLibraryIds: [world.libraries.archive.id] } },
      },
      { headers: auth(token('alice')) },
    );
    const after = await bucketTotal(token('alice'), { withStacked: false });
    expect(after).toBe(before - 3);
    const direct = await searchIds(token('alice'), { libraryId: world.libraries.archive.id });
    expect(direct.length).toBe(3);
    await updateMyPreferences(
      { userPreferencesUpdateDto: { sharedLibraries: { hiddenOwnedLibraryIds: [] } } },
      { headers: auth(token('alice')) },
    );
  }, 300_000);

  it.runIf(process.env.FORK_E2E_ML === '1')('[R13-04] smart search respects scope', async () => {
    const results = (await searchSmart(
      { smartSearchDto: { query: 'a photo' } },
      { headers: auth(token('bob')) },
    )) as unknown as { assets: { items: { id: string }[] } };
    const ids = results.assets.items.map((asset) => asset.id);
    expect(ids.length).toBeGreaterThan(0);
    const carolIds = new Set(
      world.assets.filter((a) => ['fork-04', 'fork-17', 'fork-27'].includes(a.manifestId)).map((a) => a.id),
    );
    expect(ids.some((id) => carolIds.has(id))).toBe(false);
  }, 300_000);
});
