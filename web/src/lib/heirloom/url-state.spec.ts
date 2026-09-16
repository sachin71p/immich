// V2 URL-state contract spec (PLAN §9). Vectors mirror web/src/lib/heirloom-test/url-state.ts.
import { describe, expect, it } from 'vitest';
import {
  V2_DEFAULT_GROUP,
  V2_DEFAULT_SOURCE,
  V2_DEFAULT_ZOOM,
  normalizeV2Group,
  normalizeV2Source,
  normalizeV2Zoom,
  resolveV2LibraryState,
  toV2SearchParams,
} from './url-state';

const paramsOf = (query: string): URLSearchParams => new URLSearchParams(query);

describe('normalizeV2Source', () => {
  it.each(['all', 'personal', 'space:123', 'library:abc'])('accepts %s', (value) => {
    expect(normalizeV2Source(value)).toBe(value);
  });

  it.each([null, undefined, '', 'everything', 'space:', 'library:', 'SPACE:x'])(
    'normalizes %s to default',
    (value) => {
      expect(normalizeV2Source(value)).toBe(V2_DEFAULT_SOURCE);
    },
  );
});

describe('normalizeV2Group', () => {
  it.each(['years', 'months', 'all'])('accepts %s', (value) => {
    expect(normalizeV2Group(value)).toBe(value);
  });

  it.each([null, undefined, '', 'weeks', 'MONTHS'])('normalizes %s to months', (value) => {
    expect(normalizeV2Group(value)).toBe(V2_DEFAULT_GROUP);
  });
});

describe('normalizeV2Zoom', () => {
  it.each(['64', '120', '300', 200])('accepts %s', (value) => {
    expect(normalizeV2Zoom(value)).toBe(Number(value));
  });

  it.each([null, undefined, '', '63', '301', 'abc', '12.5', Number.NaN])(
    'normalizes %s to 120',
    (value) => {
      expect(normalizeV2Zoom(value)).toBe(V2_DEFAULT_ZOOM);
    },
  );
});

describe('resolveV2LibraryState precedence', () => {
  it('uses native defaults when URL and preferences are empty', () => {
    expect(resolveV2LibraryState(paramsOf(''), {})).toEqual({
      source: 'all',
      group: 'months',
      zoom: 120,
    });
  });

  it('prefers valid URL fields over preferences per field', () => {
    const state = resolveV2LibraryState(paramsOf('source=personal&group=years&zoom=64'), {
      source: 'space:1',
      group: 'all',
      zoom: '300',
    });
    expect(state).toEqual({ source: 'personal', group: 'years', zoom: 64 });
  });

  it('keeps a valid URL zoom of 120 over a differing preference', () => {
    const state = resolveV2LibraryState(paramsOf('zoom=120'), { zoom: '200' });
    expect(state.zoom).toBe(120);
  });

  it('falls back per field when the URL value is invalid', () => {
    const state = resolveV2LibraryState(paramsOf('source=bogus&group=weeks&zoom=999'), {
      source: 'personal',
      group: 'all',
      zoom: '200',
    });
    expect(state).toEqual({ source: 'personal', group: 'all', zoom: 200 });
  });

  it('falls back to defaults when URL and preferences are both invalid', () => {
    const state = resolveV2LibraryState(paramsOf('source=bogus'), { source: 'bogus' });
    expect(state.source).toBe(V2_DEFAULT_SOURCE);
  });
});

describe('toV2SearchParams', () => {
  it('round-trips through resolveV2LibraryState', () => {
    const params = toV2SearchParams({ source: 'space:9', group: 'years', zoom: 300 });
    expect(resolveV2LibraryState(params, {})).toEqual({
      source: 'space:9',
      group: 'years',
      zoom: 300,
    });
  });
});
