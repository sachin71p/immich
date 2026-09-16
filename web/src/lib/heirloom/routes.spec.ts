// V2 route-builder + sidebar-contract spec (PLAN §7, §9, §11; WP4 acceptance).
import { describe, expect, it } from 'vitest';
import {
  isV2Path,
  v2ActiveItemHrefForPath,
  v2Album,
  v2ExternalLibrary,
  v2LibraryAsset,
  v2SearchAsset,
  v2Space,
  V2_ARCHIVE,
  V2_COLLECTIONS,
  V2_FAVORITES,
  V2_HIDDEN,
  V2_IMPORTS,
  V2_LIBRARY,
  V2_LOCKED,
  V2_MAP,
  V2_MEDIA_PHOTOS,
  V2_MEDIA_SCREENSHOTS,
  V2_MEDIA_VIDEOS,
  V2_MEMORIES,
  V2_PEOPLE,
  V2_RECENTLY_SAVED,
  V2_ROOT,
  V2_SEARCH,
  V2_SETTINGS,
  V2_SIDEBAR_SECTIONS,
  V2_TRASH,
} from './routes';

describe('V2 route builders', () => {
  it('builds asset deep links under the [[assetId=id]] convention (D3)', () => {
    expect(v2LibraryAsset('abc')).toBe('/v2/library/abc');
    expect(v2SearchAsset('abc')).toBe('/v2/search/abc');
  });

  it('builds container destinations', () => {
    expect(v2Space('s1')).toBe('/v2/spaces/s1');
    expect(v2ExternalLibrary('l1')).toBe('/v2/libraries/l1');
    expect(v2Album('a1')).toBe('/v2/albums/a1');
  });

  it('exposes every PLAN §7 static destination', () => {
    expect([
      V2_ROOT,
      V2_LIBRARY,
      V2_COLLECTIONS,
      V2_SEARCH,
      V2_FAVORITES,
      V2_RECENTLY_SAVED,
      V2_MAP,
      V2_PEOPLE,
      V2_MEMORIES,
      V2_MEDIA_PHOTOS,
      V2_MEDIA_VIDEOS,
      V2_MEDIA_SCREENSHOTS,
      V2_IMPORTS,
      V2_TRASH,
      V2_HIDDEN,
      V2_ARCHIVE,
      V2_LOCKED,
      V2_SETTINGS,
    ]).toMatchInlineSnapshot(`
      [
        "/v2",
        "/v2/library",
        "/v2/collections",
        "/v2/search",
        "/v2/favorites",
        "/v2/recently-saved",
        "/v2/map",
        "/v2/people",
        "/v2/memories",
        "/v2/media/photos",
        "/v2/media/videos",
        "/v2/media/screenshots",
        "/v2/imports",
        "/v2/trash",
        "/v2/hidden",
        "/v2/archive",
        "/v2/locked",
        "/v2/settings",
      ]
    `);
  });
});

describe('isV2Path', () => {
  it.each(['/v2', '/v2/library', '/v2/spaces/x', '/v2/settings'])('matches %s', (path) => {
    expect(isV2Path(path)).toBe(true);
  });

  it.each(['/photos', '/albums', '/v3/library', '/v2x'])('rejects %s', (path) => {
    expect(isV2Path(path)).toBe(false);
  });
});

describe('V2 sidebar contract (PLAN §11 + WP1 §2 deltas)', () => {
  it('orders sections natively', () => {
    expect(V2_SIDEBAR_SECTIONS.map((section) => section.id)).toEqual([
      'library',
      'pinned',
      'media-types',
      'shared-libraries',
      'external-libraries',
      'albums',
      'utilities',
    ]);
  });

  it('labels library/pinned/media/utilities sections natively', () => {
    const labels = new Map(V2_SIDEBAR_SECTIONS.map((section) => [section.id, section.items.map((item) => item.label)]));
    expect(labels.get('library')).toEqual(['Library', 'Collections', 'Search']);
    expect(labels.get('pinned')).toEqual(['Favorites', 'Recently Saved', 'Map', 'People', 'Memories']);
    expect(labels.get('media-types')).toEqual(['Photos', 'Videos', 'Screenshots']);
    expect(labels.get('utilities')).toEqual(['Imports', 'Recently Deleted', 'Hidden', 'Archive', 'Locked']);
  });

  it('keeps the WP1 ellipsis deltas on creation actions', () => {
    const labels = V2_SIDEBAR_SECTIONS.flatMap((section) => section.items.map((item) => item.label));
    expect(labels).toContain('New…');
    expect(labels).toContain('New Album…');
  });

  it('marks creation actions unavailable until WP7 management sheets land', () => {
    const flagged = V2_SIDEBAR_SECTIONS.flatMap((section) => section.items).filter((item) => item.unavailable);
    expect(flagged.map((item) => item.label).sort()).toEqual(['New Album…', 'New…']);
  });

  it('declares live-data ownership for spaces/libraries/albums sections', () => {
    const dynamic = new Map(
      V2_SIDEBAR_SECTIONS.filter((section) => section.dynamic).map((section) => [section.id, section.dynamic]),
    );
    expect(dynamic.get('shared-libraries')).toBe('spaces');
    expect(dynamic.get('external-libraries')).toBe('libraries');
    expect(dynamic.get('albums')).toBe('albums');
  });
});

describe('v2ActiveItemHrefForPath', () => {
  it.each([
    ['/v2/library', V2_LIBRARY],
    ['/v2/library/123e4567-e89b-12d3-a456-426614174000', V2_LIBRARY],
    ['/v2/collections', V2_COLLECTIONS],
    ['/v2/search', V2_SEARCH],
    ['/v2/media/photos', V2_MEDIA_PHOTOS],
    ['/v2/settings', V2_SETTINGS],
    ['/v2/trash', V2_TRASH],
  ])('resolves %s to %s', (path, expected) => {
    expect(v2ActiveItemHrefForPath(path)).toBe(expected);
  });

  it('resolves container members to their live sidebar href', () => {
    expect(v2ActiveItemHrefForPath('/v2/spaces/s1')).toBe('/v2/spaces/s1');
    expect(v2ActiveItemHrefForPath('/v2/libraries/l1')).toBe('/v2/libraries/l1');
    expect(v2ActiveItemHrefForPath('/v2/albums/a1')).toBe('/v2/albums/a1');
  });

  it.each([['/photos'], ['/v2']])('returns undefined for %s', (path) => {
    expect(v2ActiveItemHrefForPath(path)).toBeUndefined();
  });
});
