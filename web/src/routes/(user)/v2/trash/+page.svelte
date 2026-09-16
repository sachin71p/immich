<!-- Heirloom Web V2 — Recently Deleted (WP9 slice 3).
  Buckets `{ isTrashed: true }` (classic trash page pattern) through the
  composed V2SquareTimeline. Empty/Restore All reuse `handleEmptyTrash` /
  `handleRestoreTrash` from the existing trash service (built-in confirmation
  + toasts); the grid refetches afterwards so emptied/restored assets leave
  the view immediately. Viewer stays URL-backed through the `view` param. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import { buildV2TrashOptions, getV2ViewerId, setV2ViewerId } from '$lib/heirloom/slice3-options';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { handleEmptyTrash, handleRestoreTrash } from '$lib/services/trash.service';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import type { AssetResponseDto } from '@immich/sdk';
  import { onDestroy } from 'svelte';

  const timelineManager = new TimelineManager();
  onDestroy(() => timelineManager.destroy());

  const viewState = $derived(v2ViewState.current);
  const options = $derived(buildV2TrashOptions());
  const viewerId = $derived(getV2ViewerId(page.url.search));
  const collectionHref = $derived(`${page.url.pathname}${setV2ViewerId(page.url.search, null)}`);
  const assetHref = (id: string) => `${page.url.pathname}${setV2ViewerId(page.url.search, id)}`;

  const openAsset = (asset: TimelineAsset) => {
    void goto(assetHref(asset.id));
  };

  const refreshAsset = (asset: AssetResponseDto) => {
    timelineManager.upsertAssets([toTimelineAsset(asset)]);
  };

  const refreshGrid = () => {
    void timelineManager.updateOptions({ ...options });
  };
</script>

<section aria-label="Recently Deleted" data-testid="v2-trash">
  <header>
    <div>
      <button
        type="button"
        data-testid="v2-trash-restore-all"
        onclick={() => void handleRestoreTrash().then(refreshGrid)}
      >
        Restore All
      </button>
      <button
        type="button"
        data-testid="v2-trash-empty"
        onclick={() => void handleEmptyTrash().then(refreshGrid)}
      >
        Empty Trash
      </button>
    </div>
  </header>
  <V2SquareTimeline
    {timelineManager}
    {options}
    group={viewState.group}
    zoom={viewState.zoom}
    onAssetClick={openAsset}
    emptyTitle="Trash is empty"
    emptyBody="Deleted assets appear here before they are permanently removed."
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
