import type { PersonResponseDto } from '@immich/sdk';
import { describe, expect, it } from 'vitest';
import {
  buildV2PersonAssetsOptions,
  countV2VisiblePeople,
  filterV2PersonRows,
  toV2PersonRows,
} from './people-list';

const person = (overrides: Partial<PersonResponseDto> = {}): PersonResponseDto =>
  ({
    id: 'p1',
    name: 'Ada',
    birthDate: null,
    thumbnailPath: '/thumb',
    isHidden: false,
    isFavorite: false,
    updatedAt: '2026-01-01T00:00:00Z',
    ...overrides,
  }) as PersonResponseDto;

describe('toV2PersonRows', () => {
  it('maps names and flags through', () => {
    expect(toV2PersonRows([person({ id: 'a', name: 'Ada', isFavorite: true })])).toEqual([
      { id: 'a', displayName: 'Ada', isUnnamed: false, isHidden: false, isFavorite: true, updatedAt: expect.any(String) },
    ]);
  });

  it('falls back to Unnamed for empty names like native', () => {
    const [row] = toV2PersonRows([person({ name: '' })]);
    expect(row.displayName).toBe('Unnamed');
    expect(row.isUnnamed).toBe(true);
  });
});

describe('countV2VisiblePeople', () => {
  it('excludes hidden people', () => {
    expect(countV2VisiblePeople([person(), person({ isHidden: true }), person()])).toBe(2);
  });
});

describe('filterV2PersonRows', () => {
  const rows = toV2PersonRows([person({ id: 'a', name: 'Ada' }), person({ id: 'b', name: 'Grace' })]);

  it('returns all rows on an empty query', () => {
    expect(filterV2PersonRows(rows, '  ')).toBe(rows);
  });

  it('matches case-insensitively by substring', () => {
    expect(filterV2PersonRows(rows, 'ada').map((row) => row.id)).toEqual(['a']);
    expect(filterV2PersonRows(rows, 'AC').map((row) => row.id)).toEqual(['b']);
  });

  it('matches the Unnamed fallback', () => {
    const unnamed = toV2PersonRows([person({ id: 'u', name: '' })]);
    expect(filterV2PersonRows(unnamed, 'unnamed')).toHaveLength(1);
  });
});

describe('buildV2PersonAssetsOptions', () => {
  it('filters buckets to the person', () => {
    expect(buildV2PersonAssetsOptions('p1')).toEqual({ personId: 'p1', withStacked: true });
  });
});
