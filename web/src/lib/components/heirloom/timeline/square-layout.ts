// Heirloom Web V2 — square-grid geometry (WP5).
//
// Pure, framework-free layout math for the V2 square virtualized timeline.
// The native macOS grid (WP1 §4) uses square cells (`itemSize = zoom`),
// 2px inter-item/line spacing, 8px section inset, default tile 120px, and
// zoom range 64–300. Grouping follows WP1 decision D1: visible year + month
// headers for Years/Months, flat (headerless) for All.
//
// This module never touches the justified layout — that stays the default
// everywhere (PLAN §12). The V2 component (`V2SquareTimeline.svelte`) is the
// only consumer; it opts in explicitly.

import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
import { DateTime } from 'luxon';

export const V2_SQUARE_DEFAULT_TILE = 120;
export const V2_SQUARE_MIN_TILE = 64;
export const V2_SQUARE_MAX_TILE = 300;
export const V2_SQUARE_GAP = 2;
export const V2_SQUARE_INSET = 8;
export const V2_SQUARE_YEAR_HEADER_HEIGHT = 40;
export const V2_SQUARE_MONTH_HEADER_HEIGHT = 36;
/** Extra rows rendered above/below the viewport so fast scrolling never shows gaps. */
export const V2_SQUARE_OVERSCAN_PX = 600;

export type V2SquareGroup = 'years' | 'months' | 'all';

/** Clamp to an integer tile size in [64, 300]; anything else falls back to 120. */
export const normalizeSquareZoom = (value: string | number | null | undefined): number => {
  if (value === null || value === undefined || value === '') {
    return V2_SQUARE_DEFAULT_TILE;
  }
  const parsed = typeof value === 'number' ? value : Number.parseInt(String(value), 10);
  if (!Number.isInteger(parsed) || parsed < V2_SQUARE_MIN_TILE || parsed > V2_SQUARE_MAX_TILE) {
    return V2_SQUARE_DEFAULT_TILE;
  }
  return parsed;
};

/** Number of square columns that fit in `containerWidth` at the given tile size. */
export const squareColumns = (
  containerWidth: number,
  tile: number,
  gap: number = V2_SQUARE_GAP,
  inset: number = V2_SQUARE_INSET,
): number => Math.max(1, Math.floor((containerWidth - inset * 2 + gap) / (tile + gap)));

/** Whole tile rows needed for `count` assets in `columns` columns. */
export const squareRowCount = (count: number, columns: number): number =>
  count === 0 ? 0 : Math.ceil(count / Math.max(1, columns));

/** Deterministic `MMMM yyyy` month title (mirrors the native `en_US_POSIX` bucket format). */
export const squareMonthTitle = (year: number, month: number): string =>
  DateTime.fromObject({ year, month, day: 1 }, { locale: 'en-US' }).toFormat('MMMM yyyy');

/**
 * WP11 A2: per-tile accessible name. `TimelineAsset` carries no filename, so
 * the label is built from what it does carry — position (`n of total`),
 * capture date, and place when known. Keeps the previous "Photo" prefix so
 * existing AT phrasing stays familiar.
 */
export const describeV2TileLabel = (asset: TimelineAsset, position: number, total: number): string => {
  const { year, month, day } = asset.localDateTime;
  const pad = (value: number): string => String(value).padStart(2, '0');
  const place = [asset.city, asset.country].filter((part) => !!part).join(', ');
  const when = `${year}-${pad(month)}-${pad(day)}`;
  return place ? `Photo ${position} of ${total}, ${when}, ${place}` : `Photo ${position} of ${total}, ${when}`;
};

export interface SquareSection {
  /** Stable key: `yyyy-MM` month bucket, or `'all'` for the flat group. */
  id: string;
  year: number;
  /** Null only for the flat (`all`) group. */
  month: number | null;
  /** Month header text, or null when the group is flat. */
  title: string | null;
  /** Year header text, set on the first section of each year in `years` mode only. */
  yearTitle: string | null;
  assets: TimelineAsset[];
}

/**
 * Bucket assets into sections per D1: one section per calendar month
 * (newest-first, input order preserved) with visible headers for
 * `years`/`months`, and a single headerless section for `all`.
 */
export const buildSquareSections = (assets: TimelineAsset[], group: V2SquareGroup): SquareSection[] => {
  if (group === 'all') {
    return [{ id: 'all', year: -1, month: null, title: null, yearTitle: null, assets: [...assets] }];
  }
  const sections: SquareSection[] = [];
  const byBucket = new Map<string, SquareSection>();
  for (const asset of assets) {
    const { year, month } = asset.localDateTime;
    const id = `${year}-${String(month).padStart(2, '0')}`;
    let section = byBucket.get(id);
    if (!section) {
      section = { id, year, month, title: squareMonthTitle(year, month), yearTitle: null, assets: [] };
      byBucket.set(id, section);
      sections.push(section);
    }
    section.assets.push(asset);
  }
  if (group === 'years') {
    const seenYears = new Set<number>();
    for (const section of sections) {
      if (!seenYears.has(section.year)) {
        seenYears.add(section.year);
        section.yearTitle = String(section.year);
      }
    }
  }
  return sections;
};

export interface SquareLayoutOptions {
  containerWidth: number;
  tile: number;
  gap?: number;
  inset?: number;
  yearHeaderHeight?: number;
  monthHeaderHeight?: number;
}

export type SquareRow =
  | { kind: 'year'; sectionId: string; title: string; top: number; height: number }
  | { kind: 'month'; sectionId: string; title: string; top: number; height: number }
  | {
      kind: 'tiles';
      sectionId: string;
      /** Offset into the section's asset array for the first tile of this row. */
      assetOffset: number;
      count: number;
      top: number;
      height: number;
    };

export interface SquareLayout {
  rows: SquareRow[];
  totalHeight: number;
  columns: number;
  tile: number;
}

/**
 * Lay out sections as absolutely-positionable rows. Tile rows are square
 * (`height === tile`); header rows carry their configured heights. Callers
 * render only the rows intersecting the viewport (see `visibleSquareRows`).
 */
export const layoutSquareGrid = (sections: SquareSection[], options: SquareLayoutOptions): SquareLayout => {
  const {
    containerWidth,
    tile,
    gap = V2_SQUARE_GAP,
    inset = V2_SQUARE_INSET,
    yearHeaderHeight = V2_SQUARE_YEAR_HEADER_HEIGHT,
    monthHeaderHeight = V2_SQUARE_MONTH_HEADER_HEIGHT,
  } = options;
  const columns = squareColumns(containerWidth, tile, gap, inset);
  const rows: SquareRow[] = [];
  let top = inset;
  for (const section of sections) {
    if (section.yearTitle !== null) {
      rows.push({ kind: 'year', sectionId: section.id, title: section.yearTitle, top, height: yearHeaderHeight });
      top += yearHeaderHeight + gap;
    }
    if (section.title !== null) {
      rows.push({ kind: 'month', sectionId: section.id, title: section.title, top, height: monthHeaderHeight });
      top += monthHeaderHeight + gap;
    }
    const rowCount = squareRowCount(section.assets.length, columns);
    for (let row = 0; row < rowCount; row += 1) {
      const assetOffset = row * columns;
      rows.push({
        kind: 'tiles',
        sectionId: section.id,
        assetOffset,
        count: Math.min(columns, section.assets.length - assetOffset),
        top,
        height: tile,
      });
      top += tile + gap;
    }
  }
  // Drop the trailing inter-row gap, then close with the bottom inset.
  const totalHeight = rows.length === 0 ? inset * 2 : top - gap + inset;
  return { rows, totalHeight, columns, tile };
};

/** Row range intersecting `[scrollTop - overscan, scrollTop + viewportHeight + overscan]`. */
export const visibleSquareRows = (
  layout: SquareLayout,
  scrollTop: number,
  viewportHeight: number,
  overscan: number = V2_SQUARE_OVERSCAN_PX,
): SquareRow[] => {
  const windowTop = scrollTop - overscan;
  const windowBottom = scrollTop + viewportHeight + overscan;
  return layout.rows.filter((row) => row.top < windowBottom && row.top + row.height > windowTop);
};

/** Number of tiles actually rendered for the visible rows (virtualization gate). */
export const countVisibleTiles = (rows: SquareRow[]): number => {
  let total = 0;
  for (const row of rows) {
    if (row.kind === 'tiles') {
      total += row.count;
    }
  }
  return total;
};

/**
 * Scroll-anchor helpers: preserve the user's approximate position across
 * zoom/regroup. The component anchors to the first visible tile's asset id
 * and falls back to the proportional ratio when that asset is gone.
 */
export const scrollRatio = (scrollTop: number, totalHeight: number, viewportHeight: number): number => {
  const maxScroll = Math.max(0, totalHeight - viewportHeight);
  if (maxScroll === 0) {
    return 0;
  }
  return Math.min(1, Math.max(0, scrollTop / maxScroll));
};

export const scrollTopForRatio = (ratio: number, totalHeight: number, viewportHeight: number): number => {
  const maxScroll = Math.max(0, totalHeight - viewportHeight);
  return Math.min(maxScroll, Math.max(0, ratio * maxScroll));
};

export interface SquareAnchor {
  sectionId: string;
  assetId: string;
  /** Pixels the tile's top sits below the scroll position (restored after relayout). */
  offset: number;
  ratio: number;
}

/** Capture the first visible tile as the scroll anchor. */
export const captureSquareAnchor = (
  layout: SquareLayout,
  sections: SquareSection[],
  scrollTop: number,
  viewportHeight: number,
): SquareAnchor | null => {
  const byId = new Map(sections.map((section) => [section.id, section]));
  for (const row of layout.rows) {
    if (row.kind !== 'tiles') {
      continue;
    }
    if (row.top + row.height <= scrollTop) {
      continue;
    }
    const section = byId.get(row.sectionId);
    const asset = section?.assets[row.assetOffset];
    if (!asset) {
      continue;
    }
    return {
      sectionId: row.sectionId,
      assetId: asset.id,
      offset: row.top - scrollTop,
      ratio: scrollRatio(scrollTop, layout.totalHeight, viewportHeight),
    };
  }
  return null;
};

/** Restore a scroll position for a relaid-out grid, preferring the anchored asset. */
export const restoreSquareAnchor = (
  layout: SquareLayout,
  sections: SquareSection[],
  anchor: SquareAnchor | null,
  viewportHeight: number,
): number => {
  if (anchor) {
    const section = sections.find((s) => s.id === anchor.sectionId);
    if (section) {
      const index = section.assets.findIndex((asset) => asset.id === anchor.assetId);
      if (index >= 0) {
        const rowIndex = Math.floor(index / Math.max(1, layout.columns));
        let seen = 0;
        for (const row of layout.rows) {
          if (row.kind === 'tiles' && row.sectionId === anchor.sectionId) {
            if (seen === rowIndex) {
              return Math.max(0, row.top - anchor.offset);
            }
            seen += 1;
          }
        }
      }
    }
    return scrollTopForRatio(anchor.ratio, layout.totalHeight, viewportHeight);
  }
  return 0;
}
