// Heirloom Web V2 — URL/preference state contract (PLAN §9, lead-owned).
//
// Shareable library-view state lives in the URL. Resolution precedence per field:
//   1. valid URL param (highest)
//   2. V2-specific saved preference (fallback; V2 keys must never overwrite classic keys)
//   3. native default (final fallback)
//
// Invalid values normalize to the next precedence level. These are pure functions
// with no navigation side effects, so applying them cannot produce a reload loop.
// Source parsing reuses the classic parser verbatim (WP2 §0); only validity is new.

import { parseLibrarySource } from '$lib/utils/library-source';

export const V2_DEFAULT_SOURCE = 'all';
export const V2_DEFAULT_GROUP = 'months' as const;
export const V2_DEFAULT_ZOOM = 120;
export const V2_MIN_ZOOM = 64;
export const V2_MAX_ZOOM = 300;

export const V2_GROUPS = ['years', 'months', 'all'] as const;
export type V2Group = (typeof V2_GROUPS)[number];

/** V2-only preference keys. Distinct from classic keys (e.g. `timeline-library-source`). */
export const V2_PREF_SOURCE_KEY = 'heirloom-v2-library-source';
export const V2_PREF_GROUP_KEY = 'heirloom-v2-library-source-group';
export const V2_PREF_ZOOM_KEY = 'heirloom-v2-library-source-zoom';

export interface V2LibraryState {
  source: string;
  group: V2Group;
  zoom: number;
}

export interface V2StoredPreferences {
  source?: string;
  group?: string;
  zoom?: string | number;
}

const isNonEmptyId = (id: string): boolean => id.length > 0;

/** A source string is valid when the classic parser maps it to a known filter shape. */
export const isValidV2Source = (value: string): boolean => {
  if (value === 'all' || value === 'personal') {
    return true;
  }
  const filter = parseLibrarySource(value);
  return (
    (filter.spaceId !== undefined && isNonEmptyId(filter.spaceId)) ||
    (filter.libraryId !== undefined && isNonEmptyId(filter.libraryId))
  );
};

export const normalizeV2Source = (value: string | null | undefined): string =>
  value && isValidV2Source(value) ? value : V2_DEFAULT_SOURCE;

export const normalizeV2Group = (value: string | null | undefined): V2Group =>
  value === 'years' || value === 'months' || value === 'all' ? value : V2_DEFAULT_GROUP;

const parseZoom = (value: string | number | null | undefined): number | undefined => {
  if (value === null || value === undefined || value === '') {
    return undefined;
  }
  const parsed = typeof value === 'number' ? value : Number.parseInt(String(value), 10);
  if (!Number.isInteger(parsed) || parsed < V2_MIN_ZOOM || parsed > V2_MAX_ZOOM) {
    return undefined;
  }
  return parsed;
};

export const normalizeV2Zoom = (value: string | number | null | undefined): number =>
  parseZoom(value) ?? V2_DEFAULT_ZOOM;

/**
 * Resolve effective state. Each field is independent: a valid URL field always wins
 * for that field, otherwise the stored preference is normalized, otherwise the default.
 */
export const resolveV2LibraryState = (
  params: URLSearchParams,
  preferences: V2StoredPreferences = {},
): V2LibraryState => {
  const urlSource = params.get('source');
  const urlGroup = params.get('group');
  const urlZoom = params.get('zoom');

  return {
    source:
      urlSource && isValidV2Source(urlSource)
        ? urlSource
        : normalizeV2Source(preferences.source),
    group:
      urlGroup && (V2_GROUPS as readonly string[]).includes(urlGroup)
        ? (urlGroup as V2Group)
        : normalizeV2Group(preferences.group),
    zoom: parseZoom(urlZoom) ?? normalizeV2Zoom(preferences.zoom),
  };
};

/** Serialize resolved state back to URL params (round-trips through resolveV2LibraryState). */
export const toV2SearchParams = (state: V2LibraryState): URLSearchParams => {
  const params = new URLSearchParams();
  params.set('source', state.source);
  params.set('group', state.group);
  params.set('zoom', String(state.zoom));
  return params;
};
