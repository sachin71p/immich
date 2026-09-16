import { AssetOrderBy, AssetVisibility } from '@immich/sdk';
import { describe, expect, it } from 'vitest';
import {
  buildV2FavoritesOptions,
  buildV2LibraryOptions,
  buildV2RecencyOptions,
  hasV2SearchTerms,
  parseV2SearchTerms,
  v2CollectionPath,
} from './route-options';

describe('buildV2LibraryOptions', () => {
  it('matches the classic photos pattern for the all source', () => {
    expect(buildV2LibraryOptions('all')).toEqual({
      visibility: AssetVisibility.Timeline,
      withStacked: true,
      withPartners: true,
    });
  });

  it('maps personal to personalOnly', () => {
    expect(buildV2LibraryOptions('personal')).toEqual({
      visibility: AssetVisibility.Timeline,
      withStacked: true,
      withPartners: true,
      personalOnly: true,
    });
  });

  it('maps space/library sources to id filters', () => {
    expect(buildV2LibraryOptions('space:space-id')).toMatchObject({ spaceId: 'space-id' });
    expect(buildV2LibraryOptions('library:library-id')).toMatchObject({ libraryId: 'library-id' });
  });
});

describe('buildV2FavoritesOptions', () => {
  it('matches the classic favorites pattern', () => {
    expect(buildV2FavoritesOptions()).toEqual({ isFavorite: true, withStacked: true });
  });
});

describe('buildV2RecencyOptions', () => {
  it('matches the classic recently-added pattern (upload order)', () => {
    expect(buildV2RecencyOptions()).toEqual({
      visibility: AssetVisibility.Timeline,
      withStacked: true,
      withPartners: true,
      orderBy: AssetOrderBy.CreatedAt,
    });
  });
});

describe('parseV2SearchTerms', () => {
  it('returns idle terms for a missing query', () => {
    expect(parseV2SearchTerms(null)).toEqual({});
  });

  it('parses a serialized smart-search DTO', () => {
    expect(parseV2SearchTerms(JSON.stringify({ query: 'beach' }))).toEqual({ query: 'beach' });
  });

  it('normalizes malformed JSON to idle instead of throwing', () => {
    expect(parseV2SearchTerms('{not-json')).toEqual({});
  });

  it('normalizes non-object JSON to idle', () => {
    expect(parseV2SearchTerms('"beach"')).toEqual({});
    expect(parseV2SearchTerms('42')).toEqual({});
  });
});

describe('hasV2SearchTerms', () => {
  it('is false for idle terms and true once a criterion exists', () => {
    expect(hasV2SearchTerms({})).toBe(false);
    expect(hasV2SearchTerms({ query: 'beach' })).toBe(true);
    expect(hasV2SearchTerms({ isFavorite: true })).toBe(true);
  });
});

describe('v2CollectionPath', () => {
  it('strips the asset id back to the collection', () => {
    expect(v2CollectionPath('/v2/library/asset-id')).toBe('/v2/library');
    expect(v2CollectionPath('/v2/search/asset-id')).toBe('/v2/search');
    expect(v2CollectionPath('/v2/favorites/asset-id')).toBe('/v2/favorites');
    expect(v2CollectionPath('/v2/recently-saved/asset-id')).toBe('/v2/recently-saved');
  });
});
