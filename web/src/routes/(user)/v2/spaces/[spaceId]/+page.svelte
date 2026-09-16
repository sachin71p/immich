<!-- Heirloom Web V2 — space timeline (WP9 slice 3).
  Buckets `{ spaceId }` (classic shared-libraries space page pattern) through
  the composed V2SquareTimeline. Header metadata comes from the existing
  `sharedSpaces` store (same cache the V2 sidebar uses); an unknown id renders
  the unauthorized state instead of a timeline. Manage opens the WP7
  V2ManageSpaceSheet (role-gated Leave/Delete inside the sheet); uploads
  target the space via `openFileUploadDialog({ spaceId })`. Viewer stays
  URL-backed through the `view` param. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2ManageSpaceSheet from '$lib/components/heirloom/dialogs/V2ManageSpaceSheet.svelte';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import {
    buildV2SpaceBucketOptions,
    getV2ViewerId,
    setV2ViewerId,
  } from '$lib/heirloom/slice3-options';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { openFileUploadDialog } from '$lib/utils/file-uploader';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import type { AssetResponseDto, SharedSpaceResponseDto } from '@immich/sdk';
  import { onDestroy, onMount } from 'svelte';

  const timelineManager = new TimelineManager();
  onDestroy(() => timelineManager.destroy());

  const spaceId = $derived(page.params.spaceId ?? '');
  const viewState = $derived(v2ViewState.current);
  const options = $derived(buildV2SpaceBucketOptions(spaceId));
  const viewerId = $derived(getV2ViewerId(page.url.search));
  const collectionHref = $derived(`${page.url.pathname}${setV2ViewerId(page.url.search, null)}`);
  const assetHref = (id: string) => `${page.url.pathname}${setV2ViewerId(page.url.search, id)}`;

  let storeFailed = $state(false);
  let managing = $state(false);

  onMount(() => void sharedSpaces.ensureLoaded().catch(() => (storeFailed = true)));

  const space = $derived<SharedSpaceResponseDto | undefined>(
    sharedSpaces.spaces.find((candidate) => candidate.id === spaceId),
  );
  /** Unknown after load = not found or no access; never render a timeline for it. */
  const unknown = $derived(sharedSpaces.loaded && !space);

  const openAsset = (asset: TimelineAsset) => {
    void goto(assetHref(asset.id));
  };

  const refreshAsset = (asset: AssetResponseDto) => {
    timelineManager.upsertAssets([toTimelineAsset(asset)]);
  };
</script>

<section aria-label="Shared library" data-testid="v2-space">
  {#if unknown || storeFailed}
    <div role="alert" data-testid="v2-space-unauthorized">
      <p>This shared library could not be found, or you no longer have access to it.</p>
      <p><a href="/v2/library">Back to Library</a></p>
    </div>
  {:else if space}
    <header>
      <h1 data-testid="v2-space-name">{space.name}</h1>
      {#if space.description}
        <p data-testid="v2-space-description">{space.description}</p>
      {/if}
      <div>
        <button type="button" data-testid="v2-space-manage" onclick={() => (managing = true)}>
          Manage
        </button>
        <button
          type="button"
          data-testid="v2-space-upload"
          onclick={() => void openFileUploadDialog({ spaceId: space.id })}
        >
          Upload
        </button>
      </div>
    </header>
    <V2SquareTimeline
      {timelineManager}
      {options}
      group={viewState.group}
      zoom={viewState.zoom}
      onAssetClick={openAsset}
      emptyTitle="No photos"
      emptyBody="Upload into this shared library to get started."
    />
  {:else}
    <p aria-busy="true" data-testid="v2-space-loading">Loading…</p>
  {/if}
</section>

{#if managing && space}
  <V2ManageSpaceSheet
    {space}
    onClose={() => (managing = false)}
    onUpdated={() => (managing = false)}
    onLeft={() => void goto('/v2/library')}
    onDeleted={() => void goto('/v2/library')}
  />
{/if}

{#if viewerId}
  <V2ViewerSlot
    assetId={viewerId}
    backHref={collectionHref}
    {assetHref}
    onAssetChange={refreshAsset}
  />
{/if}
