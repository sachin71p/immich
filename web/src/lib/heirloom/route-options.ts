// Heirloom Web V2 — core-route data composition (WP9 slice 1).
//
// Pure builders behind the five core routes. Every composition reuses the
// WP2 route/data matrix verbatim — this module adds no fetch logic, no new
// filter semantics, only the exact option shapes already shipped by classic
// routes:
//
// - library: photos `[[assetId]]` pattern (visibility Timeline + stacked +
//   partners + parsed source filter)
// - favorites: favorites pattern (`isFavorite` + stacked)
// - recently-saved: recently-added pattern (Timeline + stacked + partners,
//   ordered by CreatedAt) — lead decision D2 maps BOTH recently-saved and
//   imports to this recency composition
// - search: classic `?query=` DTO convention (JSON-serialized metadata/smart
//   search terms) plus the V2 collection-path helper for viewer close targets

import {
  AssetOrderBy,
  AssetVisibility,
  type MetadataSearchDto,
  type SmartSearchDto,
} from '@immich/sdk';
import type { TimelineManagerOptions } from '$lib/managers/timeline-manager/types';
import { parseLibrarySource } from '$lib/utils/library-source';

/** Library grid: exact pattern from `routes/(user)/photos/[[assetId=id]]/+page.svelte`. */
export const buildV2LibraryOptions = (source: string): TimelineManagerOptions => ({
  visibility: AssetVisibility.Timeline,
  withStacked: true,
  withPartners: true,
  ...parseLibrarySource(source),
});

/** Favorites grid: exact pattern from the classic favorites page. */
export const buildV2FavoritesOptions = (): TimelineManagerOptions => ({
  isFavorite: true,
  withStacked: true,
});

/**
 * Recently Saved grid: exact pattern from the classic recently-added page.
 * Upload/creation order (`CreatedAt`); see D2 for the native-label mapping.
 */
export const buildV2RecencyOptions = (): TimelineManagerOptions => ({
  visibility: AssetVisibility.Timeline,
  withStacked: true,
  withPartners: true,
  orderBy: AssetOrderBy.CreatedAt,
});

/** Search terms: classic `MetadataSearchDto & Pick<SmartSearchDto, ...>` convention. */
export type V2SearchTerms = MetadataSearchDto & Pick<SmartSearchDto, 'query' | 'queryAssetId'>;

/**
 * Parse the raw `?query=` param. Classic code assumes valid JSON; V2
 * normalizes malformed input to `{}` (idle state) instead of throwing, so a
 * hand-edited URL can never break the route.
 */
export const parseV2SearchTerms = (raw: string | null): V2SearchTerms => {
  if (!raw) {
    return {};
  }
  try {
    const parsed: unknown = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? (parsed as V2SearchTerms) : {};
  } catch {
    return {};
  }
};

/** True when the terms carry at least one search criterion (results mode, not idle). */
export const hasV2SearchTerms = (terms: V2SearchTerms): boolean => Object.keys(terms).length > 0;

/**
 * Collection path backing a V2 asset URL: strips the trailing `/<assetId>`
 * so viewer close restores the collection, including its query string
 * (source/group/zoom for grids, `?query=` for search). Call only with an
 * asset URL (pages gate on `page.params.assetId`).
 */
export const v2CollectionPath = (assetPathname: string): string =>
  assetPathname.replace(/\/[^/]+$/, '') || '/';
