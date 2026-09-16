// Heirloom Web V2 — centralized route builder (PLAN §7 target routes, §11 sidebar IA).
//
// Every V2 destination is constructed here so sidebar, toolbar, and future
// feature code share one path contract. Labels/order follow PLAN §11 with the
// WP1 §2 ellipsis deltas (`New…`, `New Album…`).

export const V2_ROOT = '/v2' as const;

// Static destinations (PLAN §7).
export const V2_LIBRARY = '/v2/library' as const;
export const V2_COLLECTIONS = '/v2/collections' as const;
export const V2_SEARCH = '/v2/search' as const;
export const V2_FAVORITES = '/v2/favorites' as const;
export const V2_RECENTLY_SAVED = '/v2/recently-saved' as const;
export const V2_MAP = '/v2/map' as const;
export const V2_PEOPLE = '/v2/people' as const;
export const V2_MEMORIES = '/v2/memories' as const;
export const V2_MEDIA_PHOTOS = '/v2/media/photos' as const;
export const V2_MEDIA_VIDEOS = '/v2/media/videos' as const;
export const V2_MEDIA_SCREENSHOTS = '/v2/media/screenshots' as const;
export const V2_IMPORTS = '/v2/imports' as const;
export const V2_TRASH = '/v2/trash' as const;
export const V2_HIDDEN = '/v2/hidden' as const;
export const V2_ARCHIVE = '/v2/archive' as const;
export const V2_LOCKED = '/v2/locked' as const;
export const V2_SETTINGS = '/v2/settings' as const;

/** Asset deep links keep the classic `[[assetId=id]]` convention (lead decision D3). */
export const v2LibraryAsset = (assetId: string): string => `${V2_LIBRARY}/${assetId}`;
export const v2SearchAsset = (assetId: string): string => `${V2_SEARCH}/${assetId}`;

/** Container destinations (PLAN §7). */
export const v2Space = (spaceId: string): string => `/v2/spaces/${spaceId}`;
export const v2ExternalLibrary = (libraryId: string): string => `/v2/libraries/${libraryId}`;
export const v2Album = (albumId: string): string => `/v2/albums/${albumId}`;

/** True for the V2 root and every path beneath it. */
export const isV2Path = (pathname: string): boolean =>
  pathname === V2_ROOT || pathname.startsWith(`${V2_ROOT}/`);

export type V2SidebarMatch = 'exact' | 'prefix';

export interface V2SidebarItem {
  /** Stable identifier used for selection state and tests. */
  id: string;
  /** Native sidebar label (PLAN §11 + WP1 §2 deltas). */
  label: string;
  href: string;
  match: V2SidebarMatch;
  /** Management-sheet actions (WP7) render disabled until their sheets land. */
  unavailable?: boolean;
}

export interface V2SidebarSection {
  id: string;
  title: string | undefined;
  items: V2SidebarItem[];
  /** Dynamic sections are populated from live data by V2Sidebar (WP2 matrix rows). */
  dynamic?: 'spaces' | 'libraries' | 'albums';
}

/**
 * Static sidebar contract in native order (PLAN §11). Dynamic sections carry
 * their creation action here; member items are appended by V2Sidebar from the
 * `sharedSpaces` store (spaces/libraries) and the album service (albums).
 */
export const V2_SIDEBAR_SECTIONS: readonly V2SidebarSection[] = [
  {
    id: 'library',
    title: undefined,
    items: [
      { id: 'library', label: 'Library', href: V2_LIBRARY, match: 'prefix' },
      { id: 'collections', label: 'Collections', href: V2_COLLECTIONS, match: 'exact' },
      { id: 'search', label: 'Search', href: V2_SEARCH, match: 'prefix' },
    ],
  },
  {
    id: 'pinned',
    title: 'Pinned',
    items: [
      { id: 'favorites', label: 'Favorites', href: V2_FAVORITES, match: 'exact' },
      { id: 'recently-saved', label: 'Recently Saved', href: V2_RECENTLY_SAVED, match: 'exact' },
      { id: 'map', label: 'Map', href: V2_MAP, match: 'exact' },
      { id: 'people', label: 'People', href: V2_PEOPLE, match: 'exact' },
      { id: 'memories', label: 'Memories', href: V2_MEMORIES, match: 'exact' },
    ],
  },
  {
    id: 'media-types',
    title: 'Media Types',
    items: [
      { id: 'photos', label: 'Photos', href: V2_MEDIA_PHOTOS, match: 'exact' },
      { id: 'videos', label: 'Videos', href: V2_MEDIA_VIDEOS, match: 'exact' },
      { id: 'screenshots', label: 'Screenshots', href: V2_MEDIA_SCREENSHOTS, match: 'exact' },
    ],
  },
  {
    id: 'shared-libraries',
    title: 'Shared Libraries',
    dynamic: 'spaces',
    items: [{ id: 'new-space', label: 'New…', href: V2_SETTINGS, match: 'exact', unavailable: true }],
  },
  {
    id: 'external-libraries',
    title: 'Shared External Libraries',
    dynamic: 'libraries',
    items: [],
  },
  {
    id: 'albums',
    title: 'Albums',
    dynamic: 'albums',
    items: [{ id: 'new-album', label: 'New Album…', href: V2_SETTINGS, match: 'exact', unavailable: true }],
  },
  {
    id: 'utilities',
    title: 'Utilities',
    items: [
      { id: 'imports', label: 'Imports', href: V2_IMPORTS, match: 'exact' },
      { id: 'recently-deleted', label: 'Recently Deleted', href: V2_TRASH, match: 'exact' },
      { id: 'hidden', label: 'Hidden', href: V2_HIDDEN, match: 'exact' },
      { id: 'archive', label: 'Archive', href: V2_ARCHIVE, match: 'exact' },
      { id: 'locked', label: 'Locked', href: V2_LOCKED, match: 'exact' },
    ],
  },
];

/**
 * Resolve the sidebar item id selected for a pathname. Dynamic container paths
 * (`/v2/spaces/<id>` etc.) resolve to their member href so the live sidebar row
 * highlights. Returns `undefined` when nothing matches (e.g. `/v2/settings`).
 */
export const v2ActiveItemHrefForPath = (pathname: string): string | undefined => {
  if (!isV2Path(pathname)) {
    return undefined;
  }
  const spaceMatch = pathname.match(/^\/v2\/spaces\/([^/]+)/);
  if (spaceMatch) {
    return v2Space(spaceMatch[1]);
  }
  const libraryMatch = pathname.match(/^\/v2\/libraries\/([^/]+)/);
  if (libraryMatch) {
    return v2ExternalLibrary(libraryMatch[1]);
  }
  const albumMatch = pathname.match(/^\/v2\/albums\/([^/]+)/);
  if (albumMatch) {
    return v2Album(albumMatch[1]);
  }
  if (pathname === V2_SETTINGS) {
    return V2_SETTINGS;
  }
  // Longest static href wins so `/v2/media/photos` beats the `/v2` root.
  let best: string | undefined;
  for (const section of V2_SIDEBAR_SECTIONS) {
    for (const item of section.items) {
      if (item.unavailable) {
        continue;
      }
      const matches = item.match === 'exact' ? pathname === item.href : pathname.startsWith(item.href);
      if (matches && (best === undefined || item.href.length > best.length)) {
        best = item.href;
      }
    }
  }
  return best;
};
