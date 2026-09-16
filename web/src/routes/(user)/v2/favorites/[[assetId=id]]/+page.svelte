<!-- Heirloom Web V2 — Favorites (WP9 slice 1).
  Live square timeline over the classic favorites composition verbatim
  (`isFavorite` + stacked). Group/zoom come from the shared V2 URL state;
  the source filter is fixed by the WP2 row (favorites are source-scoped by
  definition). Tiles deep-link to the V2 asset URL; close restores the
  collection state. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import { buildV2FavoritesOptions, v2CollectionPath } from '$lib/heirloom/route-options';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import type { AssetResponseDto } from '@immich/sdk';
  import { onDestroy } from 'svelte';

  const timelineManager = new TimelineManager();
  onDestroy(() => timelineManager.destroy());

  const viewState = $derived(v2ViewState.current);
  const options = $derived(buildV2FavoritesOptions());
  const assetId = $derived(page.params.assetId);
  const backHref = $derived(`${v2CollectionPath(page.url.pathname)}${page.url.search}`);
  const assetHref = (id: string) => `/v2/favorites/${id}`;

  const openAsset = (asset: TimelineAsset) => {
    void goto(`${assetHref(asset.id)}${page.url.search}`);
  };

  // Minimum-affected refresh (PLAN §13): upsert the server-confirmed asset.
  const refreshAsset = (asset: AssetResponseDto) => {
    timelineManager.upsertAssets([toTimelineAsset(asset)]);
  };
</script>

<section aria-label="Favorites" data-testid="v2-favorites">
  <V2SquareTimeline
    {timelineManager}
    {options}
    group={viewState.group}
    zoom={viewState.zoom}
    onAssetClick={openAsset}
    emptyTitle="No favorites"
    emptyBody="Favorite an asset and it will appear here."
  />
</section>

{#if assetId}
  <V2ViewerSlot assetId={assetId} {backHref} {assetHref} onAssetChange={refreshAsset} />
{/if}
