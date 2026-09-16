import { describe, expect, it } from 'vitest';
import {
  buildV2MapOptions,
  v2ClusterSelection,
  v2MapBboxParam,
  v2MapHeadline,
} from './map-selection';

describe('buildV2MapOptions', () => {
  it('requests the located-assets timeline when nothing is selected', () => {
    expect(buildV2MapOptions()).toEqual({ withCoordinates: true, withStacked: true });
  });

  it('narrows to the cluster bbox + asset filter on selection', () => {
    const selectedIds = new Set(['a', 'b']);
    expect(buildV2MapOptions('1,2,3,4', selectedIds)).toEqual({
      withCoordinates: true,
      withStacked: true,
      bbox: '1,2,3,4',
      assetFilter: selectedIds,
    });
  });
});

describe('v2MapHeadline', () => {
  it('shows the located count when nothing is selected', () => {
    expect(v2MapHeadline(42, 0)).toBe('42 located photos');
  });

  it('shows the selection count once a cluster is tapped', () => {
    expect(v2MapHeadline(42, 7)).toBe('7 selected');
  });

  it('shows zero located photos for an empty library', () => {
    expect(v2MapHeadline(0, 0)).toBe('0 located photos');
  });
});

describe('v2MapBboxParam', () => {
  it('serializes west,south,east,north', () => {
    expect(v2MapBboxParam({ west: 1, south: 2, east: 3, north: 4 })).toBe('1,2,3,4');
  });
});

describe('v2ClusterSelection', () => {
  const markers = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];

  it('maps a cluster tap to marker ids in tap order', () => {
    expect(v2ClusterSelection(markers, ['c', 'a'])).toEqual(new Set(['c', 'a']));
  });

  it('drops stale ids the marker set no longer contains', () => {
    expect(v2ClusterSelection(markers, ['a', 'gone', 'b'])).toEqual(new Set(['a', 'b']));
  });

  it('is empty when nothing tapped matches', () => {
    expect(v2ClusterSelection(markers, ['gone'])).toEqual(new Set());
  });
});
