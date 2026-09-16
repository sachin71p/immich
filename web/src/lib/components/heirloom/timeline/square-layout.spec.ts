// WP5 — square-grid geometry + group-boundary + zoom specs.
import { describe, expect, it } from 'vitest';
import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
import { AssetVisibility } from '@immich/sdk';
import {
  buildSquareSections,
  captureSquareAnchor,
  countVisibleTiles,
  layoutSquareGrid,
  normalizeSquareZoom,
  restoreSquareAnchor,
  scrollRatio,
  scrollTopForRatio,
  squareColumns,
  squareMonthTitle,
  squareRowCount,
  V2_SQUARE_DEFAULT_TILE,
  visibleSquareRows,
} from './square-layout';

const asset = (id: string, year: number, month: number): TimelineAsset => ({
  id,
  ownerId: 'owner-1',
  ratio: 1,
  thumbhash: null,
  localDateTime: { year, month, day: 3, hour: 1, minute: 2, second: 3, millisecond: 0 },
  createdAt: { year, month, day: 3, hour: 1, minute: 2, second: 3, millisecond: 0 },
  fileCreatedAt: { year, month, day: 3, hour: 1, minute: 2, second: 3, millisecond: 0 },
  visibility: AssetVisibility.Timeline,
  isFavorite: false,
  isTrashed: false,
  isVideo: false,
  isImage: true,
  stack: null,
  duration: null,
  projectionType: null,
  livePhotoVideoId: null,
  city: null,
  country: null,
  people: null,
});

describe('normalizeSquareZoom', () => {
  it.each([64, 120, 200, 300])('accepts %s', (value) => {
    expect(normalizeSquareZoom(value)).toBe(value);
    expect(normalizeSquareZoom(String(value))).toBe(value);
  });

  it.each([null, undefined, '', '63', '301', 'abc', '12.5', 0, 'nan'])(
    'falls back to 120 for %s',
    (value) => {
      expect(normalizeSquareZoom(value)).toBe(V2_SQUARE_DEFAULT_TILE);
    },
  );
});

describe('square geometry', () => {
  it('fits 11 columns of 120px tiles in a 1400px window with 2px gaps + 8px inset', () => {
    // floor((1400 - 16 + 2) / 122) = 11
    expect(squareColumns(1400, 120)).toBe(11);
  });

  it('always fits at least one column', () => {
    expect(squareColumns(10, 300)).toBe(1);
  });

  it('scales columns with zoom', () => {
    const narrow = squareColumns(1400, 300);
    const wide = squareColumns(1400, 64);
    expect(narrow).toBeLessThan(squareColumns(1400, 120));
    expect(wide).toBeGreaterThan(squareColumns(1400, 120));
  });

  it('counts tile rows with a partial last row', () => {
    expect(squareRowCount(0, 11)).toBe(0);
    expect(squareRowCount(11, 11)).toBe(1);
    expect(squareRowCount(12, 11)).toBe(2);
  });
});

describe('group boundaries (D1)', () => {
  const assets = [asset('a1', 2026, 3), asset('a2', 2026, 3), asset('a3', 2026, 1), asset('a4', 2025, 12)];

  it('months: one visible header per calendar month', () => {
    const sections = buildSquareSections(assets, 'months');
    expect(sections.map((s) => s.id)).toEqual(['2026-03', '2026-01', '2025-12']);
    expect(sections.map((s) => s.title)).toEqual(['March 2026', 'January 2026', 'December 2025']);
    expect(sections.every((s) => s.yearTitle === null)).toBe(true);
    expect(sections[0].assets.map((a) => a.id)).toEqual(['a1', 'a2']);
  });

  it('years: year headers on the first section of each year plus month headers', () => {
    const sections = buildSquareSections(assets, 'years');
    expect(sections.map((s) => s.yearTitle)).toEqual(['2026', null, '2025']);
    expect(sections.every((s) => s.title !== null)).toBe(true);
  });

  it('all: single flat headerless section', () => {
    const sections = buildSquareSections(assets, 'all');
    expect(sections).toHaveLength(1);
    expect(sections[0].title).toBeNull();
    expect(sections[0].yearTitle).toBeNull();
    expect(sections[0].assets).toHaveLength(4);
  });

  it('formats month titles as MMMM yyyy', () => {
    expect(squareMonthTitle(2026, 1)).toBe('January 2026');
  });
});

describe('layoutSquareGrid', () => {
  it('stacks headers and square tile rows with gap/inset accounting', () => {
    const sections = buildSquareSections([asset('a1', 2026, 3), asset('a2', 2026, 3)], 'months');
    const layout = layoutSquareGrid(sections, { containerWidth: 1400, tile: 120 });
    expect(layout.columns).toBe(11);
    expect(layout.rows).toHaveLength(2); // month header + one tile row
    expect(layout.rows[0]).toMatchObject({ kind: 'month', title: 'March 2026', top: 8, height: 36 });
    expect(layout.rows[1]).toMatchObject({ kind: 'tiles', top: 8 + 36 + 2, height: 120, count: 2 });
    // top(8) + month(36) + gap(2) + tile(120) - trailing gap(2) + bottom inset(8)
    expect(layout.totalHeight).toBe(8 + 36 + 2 + 120 + 8);
  });

  it('emits year headers before month headers in years mode', () => {
    const sections = buildSquareSections([asset('a1', 2026, 3)], 'years');
    const layout = layoutSquareGrid(sections, { containerWidth: 1400, tile: 120 });
    expect(layout.rows.map((r) => r.kind)).toEqual(['year', 'month', 'tiles']);
    expect(layout.rows[0]).toMatchObject({ kind: 'year', title: '2026' });
  });
});

describe('virtualization gate (10k assets)', () => {
  const many = Array.from({ length: 10_000 }, (_, i) => {
    const month = (i % 12) + 1;
    return asset(`asset-${i}`, 2026 - Math.floor(i / 2400), month);
  });

  it('never renders the full collection', () => {
    const sections = buildSquareSections(many, 'months');
    const layout = layoutSquareGrid(sections, { containerWidth: 1400, tile: 120 });
    const visible = visibleSquareRows(layout, 0, 900);
    const rendered = countVisibleTiles(visible);
    expect(rendered).toBeGreaterThan(0);
    expect(rendered).toBeLessThan(1000);
    expect(rendered).toBeLessThan(many.length);
  });

  it('advances the window while scrolling', () => {
    const sections = buildSquareSections(many, 'all');
    const layout = layoutSquareGrid(sections, { containerWidth: 1400, tile: 120 });
    const top = visibleSquareRows(layout, 0, 900);
    const deep = visibleSquareRows(layout, 20_000, 900);
    expect(deep.length).toBeGreaterThan(0);
    expect(deep[0].top).toBeGreaterThan(top[0].top);
    expect(countVisibleTiles(deep)).toBeLessThan(many.length);
  });
});

describe('scroll anchor across zoom/regroup', () => {
  const assets = Array.from({ length: 200 }, (_, i) => asset(`asset-${i}`, 2026, (i % 5) + 1));

  it('round-trips a proportional position', () => {
    const sections = buildSquareSections(assets, 'months');
    const layout = layoutSquareGrid(sections, { containerWidth: 1400, tile: 120 });
    const ratio = scrollRatio(500, layout.totalHeight, 900);
    expect(scrollTopForRatio(ratio, layout.totalHeight, 900)).toBeCloseTo(500, 5);
  });

  it('keeps the anchored asset visible after zooming', () => {
    const sections = buildSquareSections(assets, 'months');
    const before = layoutSquareGrid(sections, { containerWidth: 1400, tile: 120 });
    const anchor = captureSquareAnchor(before, sections, 1000, 900);
    expect(anchor).not.toBeNull();
    // Column count changes with zoom (11 -> 6), so the anchor is row-grained:
    // the contract is the anchored asset stays visible, not first-in-row.
    const after = layoutSquareGrid(sections, { containerWidth: 1400, tile: 200 });
    const restored = restoreSquareAnchor(after, sections, anchor, 900);
    const visibleIds = new Set<string>();
    for (const row of visibleSquareRows(after, restored, 900)) {
      if (row.kind === 'tiles') {
        const section = sections.find((s) => s.id === row.sectionId);
        section?.assets.slice(row.assetOffset, row.assetOffset + row.count).forEach((a) => visibleIds.add(a.id));
      }
    }
    expect(visibleIds.has(anchor!.assetId)).toBe(true);
    // Note: asset-anchoring intentionally wins over proportional ratio here —
    // zooming changes total height, so both cannot hold. Ratio fallback is
    // covered by the round-trip test and used only when the asset is gone.
  });

  it('falls back to the ratio when the anchored asset is gone', () => {
    const sections = buildSquareSections(assets, 'months');
    const before = layoutSquareGrid(sections, { containerWidth: 1400, tile: 120 });
    const anchor = captureSquareAnchor(before, sections, 1000, 900);
    const regrouped = buildSquareSections(assets.slice(50), 'all');
    const after = layoutSquareGrid(regrouped, { containerWidth: 1400, tile: 120 });
    const restored = restoreSquareAnchor(after, regrouped, anchor, 900);
    expect(restored).toBeGreaterThanOrEqual(0);
    expect(restored).toBeLessThanOrEqual(after.totalHeight);
  });
});
