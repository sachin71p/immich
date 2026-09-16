// Heirloom Web V2 — map selection composition (WP9 slice 2).
//
// Pure builders behind `/v2/map`. Data is composed (never forked):
// - markers come from `getMapMarkers` (same SDK call `Map.svelte` owns);
// - the selection grid is a buckets timeline over `{ withCoordinates }`
//   narrowed by the cluster bbox + asset filter (the classic
//   `MapTimelinePanel` composition, rendered through `V2SquareTimeline`);
// - the count headline mirrors `MacMapPlacesView` verbatim:
//   "N located photos" idle, "N selected" with a selection.

import type { MapMarkerResponseDto } from '@immich/sdk';
import type { SelectionBBox } from '$lib/components/shared-components/map/types';
import type { TimelineManagerOptions } from '$lib/managers/timeline-manager/types';

/** Grid options for the selection side: located-assets timeline, cluster-narrowed. */
export const buildV2MapOptions = (bbox?: string, selectedIds?: Set<string>): TimelineManagerOptions => ({
  withCoordinates: true,
  withStacked: true,
  ...(bbox ? { bbox, assetFilter: selectedIds ?? new Set<string>() } : {}),
});

/** Headline copy: mirrors `MacMapPlacesView` ("N located photos" / "N selected"). */
export const v2MapHeadline = (totalLocated: number, selectedCount: number): string =>
  selectedCount > 0 ? `${selectedCount} selected` : `${totalLocated} located photos`;

/** Serialize a cluster bbox to the buckets `bbox` param ("west,south,east,north"). */
export const v2MapBboxParam = (bbox: SelectionBBox): string =>
  `${bbox.west},${bbox.south},${bbox.east},${bbox.north}`;

/**
 * Marker→selection mapping: keep only ids that still exist in the marker
 * set, so a stale cluster tap (markers reloaded underneath) can never
 * select phantom assets. Order follows the cluster tap order.
 */
export const v2ClusterSelection = (
  markers: Pick<MapMarkerResponseDto, 'id'>[],
  tappedIds: string[],
): Set<string> => {
  const known = new Set(markers.map((marker) => marker.id));
  return new Set(tappedIds.filter((id) => known.has(id)));
};
