<!-- Heirloom Web V2 — Library (WP9 slice 1).
  Live square timeline composed (never forked) from TimelineManager via
  V2SquareTimeline. Bucket options reuse the classic photos pattern verbatim
  (`buildV2LibraryOptions`); source/group/zoom resolve through
  `resolveV2LibraryState` precedence (URL > V2 prefs > native defaults) and
  the shell toolbar mutates the same state, so back/forward restores
  source/group/zoom and the viewer asset. Tiles deep-link to the V2 asset URL;
  closing the viewer restores the collection URL with its query intact. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import { buildV2LibraryOptions, v2CollectionPath } from '$lib/heirloom/route-options';
  import { v2LibraryAsset } from '$lib/heirloom/routes';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import type { AssetResponseDto } from '@immich/sdk';
  import { onDestroy } from 'svelte';

  const timelineManager = new TimelineManager();
  onDestroy(() => timelineManager.destroy());

  const viewState = $derived(v2ViewState.current);
  const options = $derived(buildV2LibraryOptions(viewState.source));
  const assetId = $derived(page.params.assetId);
  const backHref = $derived(`${v2CollectionPath(page.url.pathname)}${page.url.search}`);

  const openAsset = (asset: TimelineAsset) => {
    void goto(`${v2LibraryAsset(asset.id)}${page.url.search}`);
  };

  // Minimum-affected refresh (PLAN §13): upsert the server-confirmed asset.
  // Delete/move-out-of-source staleness clears on Sync; see slice-1 report.
  const refreshAsset = (asset: AssetResponseDto) => {
    timelineManager.upsertAssets([toTimelineAsset(asset)]);
  };
</script>

<section aria-label="Library" data-testid="v2-library">
  <V2SquareTimeline
    {timelineManager}
    {options}
    group={viewState.group}
    zoom={viewState.zoom}
    onAssetClick={openAsset}
    emptyTitle="No photos"
    emptyBody="Assets you add will appear here."
  />
</section>

{#if assetId}
  <V2ViewerSlot assetId={assetId} {backHref} assetHref={v2LibraryAsset} onAssetChange={refreshAsset} />
{/if}
