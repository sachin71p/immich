<!-- Heirloom Web V2 — Hidden (WP9 slice 3).
  Buckets `{ visibility: Hidden }`: the same server enum value the archive and
  locked pages compose — only the V2 route is new (no classic hidden page
  exists). Viewer stays URL-backed through the `view` param. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import { buildV2VisibilityOptions, getV2ViewerId, setV2ViewerId } from '$lib/heirloom/slice3-options';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import { AssetVisibility, type AssetResponseDto } from '@immich/sdk';
  import { onDestroy } from 'svelte';

  const timelineManager = new TimelineManager();
  onDestroy(() => timelineManager.destroy());

  const viewState = $derived(v2ViewState.current);
  const options = $derived(buildV2VisibilityOptions(AssetVisibility.Hidden));
  const viewerId = $derived(getV2ViewerId(page.url.search));
  const collectionHref = $derived(`${page.url.pathname}${setV2ViewerId(page.url.search, null)}`);
  const assetHref = (id: string) => `${page.url.pathname}${setV2ViewerId(page.url.search, id)}`;

  const openAsset = (asset: TimelineAsset) => {
    void goto(assetHref(asset.id));
  };

  const refreshAsset = (asset: AssetResponseDto) => {
    timelineManager.upsertAssets([toTimelineAsset(asset)]);
  };
</script>

<section aria-label="Hidden" data-testid="v2-hidden">
  <V2SquareTimeline
    {timelineManager}
    {options}
    group={viewState.group}
    zoom={viewState.zoom}
    onAssetClick={openAsset}
    emptyTitle="No hidden assets"
    emptyBody="Hidden assets stay out of the timeline but remain in your library."
  />
</section>

{#if viewerId}
  <V2ViewerSlot
    assetId={viewerId}
    backHref={collectionHref}
    {assetHref}
    onAssetChange={refreshAsset}
  />
{/if}
