// Heirloom Web V2 — slice-3 route data composition (WP9 slice 3).
//
// Pure builders behind the ten slice-3 route groups. Every composition reuses
// the WP2 route/data matrix verbatim — this module adds no fetch logic and no
// new filter semantics, only the exact option shapes already shipped by
// classic routes:
//
// - media/photos + media/videos: search-backed `type` filter (buckets lack
//   `type`; WP2 §1). `MetadataSearchDto.type` is server-filtered.
// - media/screenshots: `originalFileName` substring predicate. Server-verified:
//   `server/src/utils/database.ts` matches `originalFileName` with case-
//   insensitive `ilike '%value%'`, so `screenshot` matches "Screenshot …",
//   "screenshot-…", etc. No `fileExtensions` narrowing — OS naming varies and
//   over-constraining would silently empty the route.
// - spaces/[spaceId]: buckets `{ spaceId }` (classic shared-libraries space
//   page pattern) + `withStacked`.
// - libraries/[libraryId]: buckets `{ libraryId }` (mirrors the spaceId
//   pattern; the param exists on `getTimeBuckets`).
// - albums/[albumId]: buckets `{ timelineAlbumId }` (classic album page
//   grid pattern when browsing; the `{ albumId, order }` variant is the
//   activity/select-mode path, not the V2 read path).
// - imports: recency composition (lead decision D2 — native `.recents` and
//   `.imports` share one arm; V2 maps both to the classic recently-added
//   upload-order pattern).
// - trash: buckets `{ isTrashed: true }` (classic trash page pattern).
// - hidden / archive / locked: buckets `{ visibility }` (classic archive and
//   locked page patterns; `hidden` is the same API enum value with no classic
//   page — the filter itself is server-backed, not invented).
// - locked: personal-only (WP2 R3). No space/library scoping is composed
//   here — the locked page offers no scope selector by construction.
// - viewer: flat pages stay URL-backed through the `view` query param (no
//   route restructure; slice-1 `[[assetId]]` subdirs are untouched). Group/
//   zoom/source params round-trip untouched so back/forward restores state.

import { AssetTypeEnum, AssetVisibility } from '@immich/sdk';
import type { TimelineManagerOptions } from '$lib/managers/timeline-manager/types';
import { parseLibrarySource } from '$lib/utils/library-source';

export type V2MediaKind = 'photos' | 'videos' | 'screenshots';

/**
 * Case-insensitive filename substring behind the Screenshots route.
 * Matches macOS/iOS "Screenshot …" naming through the server `ilike`
 * predicate; documented here (not on the page) so fixtures can assert it.
 */
export const SCREENSHOT_FILENAME_QUERY = 'screenshot';

/** Space timeline: classic `shared-libraries/[spaceId]` options verbatim. */
export const buildV2SpaceBucketOptions = (spaceId: string): TimelineManagerOptions => ({
  spaceId,
  withStacked: true,
});

/** External-library timeline: mirrors the space pattern via `libraryId`. */
export const buildV2ExternalLibraryBucketOptions = (libraryId: string): TimelineManagerOptions => ({
  libraryId,
  withStacked: true,
});

/** Album timeline: classic album page browse-mode options verbatim. */
export const buildV2AlbumBucketOptions = (albumId: string): TimelineManagerOptions => ({
  timelineAlbumId: albumId,
});

/** Trash timeline: classic trash page options verbatim. */
export const buildV2TrashOptions = (): TimelineManagerOptions => ({
  isTrashed: true,
});

/**
 * Visibility timeline: classic archive/locked page options verbatim.
 * `hidden` uses the same server enum value; only the V2 route is new.
 */
export const buildV2VisibilityOptions = (
  visibility: AssetVisibility.Archive | AssetVisibility.Hidden | AssetVisibility.Locked,
): TimelineManagerOptions => ({
  visibility,
  withStacked: true,
});

/**
 * Media search filter: server-side `MetadataSearchDto` fragment behind the
 * three media routes. Scope (personal/space/library) composes through the
 * shared `parseLibrarySource` vocabulary; screenshots add the filename
 * predicate on top of the IMAGE type.
 */
export const buildV2MediaSearchFilter = (
  kind: V2MediaKind,
  scope: string,
): { type: AssetTypeEnum; originalFileName?: string } & Record<string, string | boolean | undefined> => {
  const type = kind === 'videos' ? AssetTypeEnum.Video : AssetTypeEnum.Image;
  const scopeParams = parseLibrarySource(scope) as Record<string, string | boolean | undefined>;
  if (kind === 'screenshots') {
    return { ...scopeParams, type, originalFileName: SCREENSHOT_FILENAME_QUERY };
  }
  return { ...scopeParams, type };
};

/** Query param carrying the open viewer asset on flat V2 pages. */
export const V2_VIEWER_PARAM = 'view';

/**
 * Minimal query parser (manual split/decode rather than `URLSearchParams`:
 * asset ids and grid params are simple tokens and this keeps the module free
 * of DOM-adjacent globals for the vitest node environment).
 */
const parseV2Query = (search: string): Array<[string, string]> => {
  const query = search.startsWith('?') ? search.slice(1) : search;
  if (!query) {
    return [];
  }
  return query.split('&').flatMap((pair) => {
    if (!pair) {
      return [];
    }
    const separator = pair.indexOf('=');
    const rawName = separator === -1 ? pair : pair.slice(0, separator);
    const rawValue = separator === -1 ? '' : pair.slice(separator + 1);
    try {
      return [[decodeURIComponent(rawName), decodeURIComponent(rawValue)] as [string, string]];
    } catch {
      return [];
    }
  });
};

const serializeV2Query = (pairs: Array<[string, string]>, hadQuestionMark: boolean): string => {
  const serialized = pairs
    .map(([name, value]) => `${encodeURIComponent(name)}=${encodeURIComponent(value)}`)
    .join('&');
  if (!serialized) {
    return '';
  }
  return hadQuestionMark ? `?${serialized}` : serialized;
};

/** Read the viewer asset id from a raw query string (leading `?` tolerated). */
export const getV2ViewerId = (search: string): string | null => {
  for (const [name, value] of parseV2Query(search)) {
    if (name === V2_VIEWER_PARAM) {
      return value;
    }
  }
  return null;
};

/**
 * Return the query string with the viewer param set (open) or removed
 * (close). All other params (source/group/zoom/`query`) pass through
 * untouched; the leading `?` is preserved when present.
 */
export const setV2ViewerId = (search: string, assetId: string | null): string => {
  const hadQuestionMark = search.startsWith('?');
  const kept = parseV2Query(search).filter(([name]) => name !== V2_VIEWER_PARAM);
  if (assetId !== null) {
    kept.push([V2_VIEWER_PARAM, assetId]);
  }
  return serializeV2Query(kept, hadQuestionMark);
};
