// Heirloom Web V2 — slice-3 composition specs (WP9 slice 3).
//
// Assert the filter/option contract each route composes: media type filters
// (buckets lack `type`, so these must be search-DTO shapes), the screenshot
// filename predicate, bucket options per container, and the `view`-param
// round-trip that keeps flat pages URL-backed.

import { AssetTypeEnum, AssetVisibility } from '@immich/sdk';
import { describe, expect, it } from 'vitest';
import {
  buildV2AlbumBucketOptions,
  buildV2ExternalLibraryBucketOptions,
  buildV2MediaSearchFilter,
  buildV2SpaceBucketOptions,
  buildV2TrashOptions,
  buildV2VisibilityOptions,
  getV2ViewerId,
  SCREENSHOT_FILENAME_QUERY,
  setV2ViewerId,
  V2_VIEWER_PARAM,
} from './slice3-options';

describe('buildV2MediaSearchFilter', () => {
  it('filters photos to IMAGE type', () => {
    expect(buildV2MediaSearchFilter('photos', 'all')).toMatchObject({ type: AssetTypeEnum.Image });
  });

  it('filters videos to VIDEO type', () => {
    expect(buildV2MediaSearchFilter('videos', 'all')).toMatchObject({ type: AssetTypeEnum.Video });
  });

  it('never emits a buckets-style bare filter without a server type', () => {
    for (const kind of ['photos', 'videos', 'screenshots'] as const) {
      expect(buildV2MediaSearchFilter(kind, 'all').type).toBeDefined();
    }
  });

  it('screenshots combine IMAGE type with the filename predicate', () => {
    const filter = buildV2MediaSearchFilter('screenshots', 'all');
    expect(filter.type).toBe(AssetTypeEnum.Image);
    expect(filter.originalFileName).toBe(SCREENSHOT_FILENAME_QUERY);
  });

  it('does not apply the filename predicate to photos or videos', () => {
    expect(buildV2MediaSearchFilter('photos', 'all').originalFileName).toBeUndefined();
    expect(buildV2MediaSearchFilter('videos', 'all').originalFileName).toBeUndefined();
  });

  it('composes personal scoping', () => {
    expect(buildV2MediaSearchFilter('photos', 'personal')).toMatchObject({
      type: AssetTypeEnum.Image,
      personalOnly: true,
    });
  });

  it('composes space scoping', () => {
    expect(buildV2MediaSearchFilter('videos', 'space:abc')).toMatchObject({
      type: AssetTypeEnum.Video,
      spaceId: 'abc',
    });
  });

  it('composes library scoping', () => {
    expect(buildV2MediaSearchFilter('photos', 'library:xyz')).toMatchObject({
      type: AssetTypeEnum.Image,
      libraryId: 'xyz',
    });
  });
});

describe('bucket option builders', () => {
  it('spaces scope by spaceId with stacked assets', () => {
    expect(buildV2SpaceBucketOptions('space-1')).toEqual({ spaceId: 'space-1', withStacked: true });
  });

  it('external libraries scope by libraryId with stacked assets', () => {
    expect(buildV2ExternalLibraryBucketOptions('lib-1')).toEqual({ libraryId: 'lib-1', withStacked: true });
  });

  it('albums use the timelineAlbumId browse pattern', () => {
    expect(buildV2AlbumBucketOptions('album-1')).toEqual({ timelineAlbumId: 'album-1' });
  });

  it('trash uses the isTrashed pattern', () => {
    expect(buildV2TrashOptions()).toEqual({ isTrashed: true });
  });

  it.each([AssetVisibility.Archive, AssetVisibility.Hidden, AssetVisibility.Locked] as const)(
    'visibility %s composes a stacked visibility filter',
    (visibility) => {
      expect(buildV2VisibilityOptions(visibility)).toEqual({ visibility, withStacked: true });
    },
  );
});

describe('viewer view-param round-trip', () => {
  it('reads the viewer id', () => {
    expect(getV2ViewerId(`?${V2_VIEWER_PARAM}=asset-1`)).toBe('asset-1');
  });

  it('returns null when no viewer is open', () => {
    expect(getV2ViewerId('?source=all&zoom=120')).toBeNull();
  });

  it('sets the viewer id while preserving grid params', () => {
    const next = setV2ViewerId('?source=all&zoom=120', 'asset-1');
    expect(next).toContain(`${V2_VIEWER_PARAM}=asset-1`);
    expect(next).toContain('source=all');
    expect(next).toContain('zoom=120');
  });

  it('clears the viewer id while preserving grid params', () => {
    expect(setV2ViewerId(`?source=all&${V2_VIEWER_PARAM}=asset-1`, null)).toBe('?source=all');
  });

  it('round-trips set then get', () => {
    const next = setV2ViewerId('?source=personal', 'asset-9');
    expect(getV2ViewerId(next)).toBe('asset-9');
  });
});
