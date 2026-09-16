<!-- Heirloom Web V2 — Map/Places (WP9 slice 2).
  Native horizontal split (`MacMapPlacesView`): clustered map (min 300) +
  selection grid (min 220/ideal 320) with a headline count
  ("N located photos" idle, "N selected" with a selection).

  Data is composed (never forked): markers come from `getMapMarkers` (the
  same SDK call `Map.svelte` owns) and are passed in, so the map never
  fetches twice; the selection side is a buckets timeline over
  `{ withCoordinates }` narrowed by the cluster bbox + asset filter (the
  classic `MapTimelinePanel` composition through `V2SquareTimeline`).
  Tiles deep-link to the V2 asset URL; close restores the collection.

  Map tiles are external nondeterministic content: the map pane sits on a
  neutral placeholder and carries a stable test id, so visual gating can
  mask the tile region (WP3 manifest) without touching structure. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import {
    buildV2MapOptions,
    v2ClusterSelection,
    v2MapBboxParam,
    v2MapHeadline,
  } from '$lib/components/heirloom/map/map-selection';
  import type { SelectionBBox } from '$lib/components/shared-components/map/types';
  import { v2CollectionPath } from '$lib/heirloom/route-options';
  import { featureFlagsManager } from '$lib/managers/feature-flags-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { handlePromiseError } from '$lib/utils';
  import { getMapMarkers, type MapMarkerResponseDto } from '@immich/sdk';
  import { LoadingSpinner } from '@immich/ui';
  import { mdiRefresh } from '@mdi/js';
  import { Icon } from '@immich/ui';
  import { onDestroy, onMount } from 'svelte';

  const timelineManager = new TimelineManager();
  onDestroy(() => timelineManager.destroy());

  let mapMarkers = $state<MapMarkerResponseDto[] | undefined>(undefined);
  let loadError = $state(false);
  let selectedIds = $state(new Set<string>());
  let selectedBbox = $state<string | undefined>(undefined);

  const mapEnabled = $derived(featureFlagsManager.value.map);
  const headline = $derived(v2MapHeadline(mapMarkers?.length ?? 0, selectedIds.size));
  const options = $derived(buildV2MapOptions(selectedBbox, selectedIds));
  const assetId = $derived(page.params.assetId);
  const backHref = $derived(`${v2CollectionPath(page.url.pathname)}${page.url.search}`);
  const assetHref = (id: string) => `/v2/map/${id}`;

  const reloadMarkers = async () => {
    loadError = false;
    try {
      // Same SDK call `Map.svelte` owns; passing markers in avoids a
      // second fetch (Map skips its own load when markers are provided).
      mapMarkers = await getMapMarkers({});
    } catch {
      loadError = true;
    }
  };

  onMount(() => {
    void reloadMarkers();
  });

  const openAsset = (asset: TimelineAsset) => {
    void goto(`${assetHref(asset.id)}${page.url.search}`);
  };

  const onClusterSelect = (tappedIds: string[], bbox: SelectionBBox) => {
    selectedIds = v2ClusterSelection(mapMarkers ?? [], tappedIds);
    selectedBbox = v2MapBboxParam(bbox);
  };

  const closeSelection = () => {
    selectedIds = new Set();
    selectedBbox = undefined;
  };
</script>

<section aria-label="Map" data-testid="v2-map" class="flex size-full min-h-0 flex-col">
  {#if !mapEnabled}
    <div class="flex flex-1 flex-col items-center justify-center gap-2 p-8 text-center" data-testid="v2-map-unavailable">
      <p class="text-lg font-medium">Map is unavailable</p>
      <p class="text-sm opacity-70">The map feature is disabled on this server.</p>
      <p><a href="/v2/library" class="underline">Back to Library</a></p>
    </div>
  {:else if loadError}
    <div class="flex flex-1 flex-col items-center justify-center gap-3 p-8 text-center" role="alert" data-testid="v2-map-error">
      <p class="text-lg font-medium">Couldn't load map markers.</p>
      <button
        type="button"
        class="inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm underline"
        onclick={() => handlePromiseError(reloadMarkers())}
      >
        <Icon icon={mdiRefresh} size="16" /> Retry
      </button>
    </div>
  {:else if mapMarkers === undefined}
    <div class="flex flex-1 items-center justify-center" aria-busy="true" data-testid="v2-map-loading">
      <LoadingSpinner />
    </div>
  {:else}
    <div class="flex min-h-0 flex-1 flex-col sm:flex-row">
      <div
        class="min-h-0 min-w-0 flex-1 bg-gray-300/40 sm:min-w-[300px] dark:bg-gray-700/40"
        data-testid="v2-map-tiles"
        role="region"
        aria-label="Clustered photo map"
      >
        {#await import('$lib/components/shared-components/map/Map.svelte') then { default: Map }}
          <Map
            bind:mapMarkers
            onSelect={(ids) => {
              if (ids[0]) {
                void goto(`${assetHref(ids[0])}${page.url.search}`);
              }
            }}
            {onClusterSelect}
            onViewportClose={closeSelection}
            viewportGridActive={selectedIds.size > 0}
          />
        {/await}
      </div>
      <div class="flex min-h-0 flex-col border-t border-gray-200 sm:w-[320px] sm:min-w-[220px] sm:border-s sm:border-t-0 dark:border-gray-700">
        <div class="flex items-center justify-between px-4 py-2">
          <h2 class="text-base font-semibold" data-testid="v2-map-count">{headline}</h2>
          <!-- WP11 A6: visually-hidden live twin — the heading stays visual-only. -->
          <p class="v2-visually-hidden" role="status" data-testid="v2-map-count-status">{headline}</p>
          {#if selectedIds.size > 0}
            <button type="button" class="text-sm underline" onclick={closeSelection}>Clear selection</button>
          {/if}
        </div>
        <div class="min-h-0 flex-1">
          <V2SquareTimeline
            {timelineManager}
            {options}
            group="all"
            zoom={96}
            {selectedIds}
            onAssetClick={openAsset}
            emptyTitle={selectedIds.size > 0 ? 'No selected photos here' : 'No located photos'}
            emptyBody={selectedIds.size > 0
              ? 'The selection changed — pick another cluster.'
              : 'Photos with location data will appear on the map.'}
          />
        </div>
      </div>
    </div>
  {/if}
</section>

{#if assetId && mapMarkers !== undefined && !loadError}
  <V2ViewerSlot assetId={assetId} {backHref} {assetHref} />
{/if}
