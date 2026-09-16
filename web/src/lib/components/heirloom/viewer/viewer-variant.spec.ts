// V2 viewer-variant logic spec (WP8, D3). Pure functions — no component mocks.
import { describe, expect, it } from 'vitest';
import {
  composeHeirloomToolbar,
  displayRotationStyle,
  HEIRLOOM_VIEWER_TOOLBAR_ORDER,
  isV2ViewerRoute,
  nextDisplayRotation,
  pageViewerCursor,
  pageViewerIndex,
} from './viewer-variant';

describe('isV2ViewerRoute', () => {
  it.each([
    '/(user)/v2/library/[[assetId=id]]',
    '/(user)/v2/search/[[assetId=id]]',
    '/(user)/v2/albums/[albumId]',
    '/(user)/v2',
  ])('treats %s as the V2 variant', (routeId) => {
    expect(isV2ViewerRoute(routeId)).toBe(true);
  });

  it.each([
    '/(user)/photos/[[assetId=id]]',
    '/(user)/albums/[albumId=id]/[[photos]]/[[assetId]]',
    '/(user)/search/[[assetId=id]]',
    null,
    undefined,
    '',
  ])('keeps %s on the classic viewer', (routeId) => {
    expect(isV2ViewerRoute(routeId)).toBe(false);
  });

  it('does not match route segments that merely contain v2', () => {
    expect(isV2ViewerRoute('/(user)/photos-v2/[[assetId=id]]')).toBe(false);
  });
});

describe('pageViewerIndex', () => {
  it('pages forward and backward within bounds', () => {
    expect(pageViewerIndex(1, 1, 5)).toBe(2);
    expect(pageViewerIndex(1, -1, 5)).toBe(0);
  });

  it('wraps around both ends (native viewerContext paging)', () => {
    expect(pageViewerIndex(4, 1, 5)).toBe(0);
    expect(pageViewerIndex(0, -1, 5)).toBe(4);
  });

  it('wraps a single-asset context onto itself', () => {
    expect(pageViewerIndex(0, 1, 1)).toBe(0);
    expect(pageViewerIndex(0, -1, 1)).toBe(0);
  });

  it('returns -1 for an empty context', () => {
    expect(pageViewerIndex(0, 1, 0)).toBe(-1);
  });
});

describe('pageViewerCursor', () => {
  const assets = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];

  it('resolves current/previous/next with wrap-around', () => {
    expect(pageViewerCursor(assets, 'a')).toEqual({
      current: { id: 'a' },
      previous: { id: 'c' },
      next: { id: 'b' },
      index: 0,
    });
    expect(pageViewerCursor(assets, 'c')).toEqual({
      current: { id: 'c' },
      previous: { id: 'b' },
      next: { id: 'a' },
      index: 2,
    });
  });

  it('returns undefined for unknown ids and empty contexts', () => {
    expect(pageViewerCursor(assets, 'zzz')).toBeUndefined();
    expect(pageViewerCursor([], 'a')).toBeUndefined();
  });
});

describe('display rotation state', () => {
  it('cycles 0 → 90 → 180 → 270 → 0', () => {
    expect(nextDisplayRotation(0)).toBe(90);
    expect(nextDisplayRotation(90)).toBe(180);
    expect(nextDisplayRotation(180)).toBe(270);
    expect(nextDisplayRotation(270)).toBe(0);
  });

  it('maps rotation to a CSS transform, empty at 0°', () => {
    expect(displayRotationStyle(0)).toBe('');
    expect(displayRotationStyle(90)).toBe('rotate(90deg)');
    expect(displayRotationStyle(270)).toBe('rotate(270deg)');
  });
});

describe('toolbar composition', () => {
  it('matches the native order (WP1 §5)', () => {
    expect([...HEIRLOOM_VIEWER_TOOLBAR_ORDER]).toEqual([
      'favorite',
      'rotate',
      'delete',
      'move',
      'addToAlbum',
      'edit',
      'info',
      'liveText',
    ]);
  });

  it('renders Edit if and only if canEdit (WP10 Decision A posture)', () => {
    expect(composeHeirloomToolbar(true)).toContain('edit');
    expect(composeHeirloomToolbar(false)).not.toContain('edit');
  });

  it('preserves native order in both compositions', () => {
    for (const canEdit of [true, false]) {
      const composed = composeHeirloomToolbar(canEdit);
      const order = [...HEIRLOOM_VIEWER_TOOLBAR_ORDER].filter((tool) => composed.includes(tool));
      expect(composed).toEqual(order);
    }
  });
});
