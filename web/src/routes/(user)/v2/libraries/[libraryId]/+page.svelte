<!-- Heirloom Web V2 — external-library timeline (WP9 slice 3).
  Buckets `{ libraryId }` (mirrors the space pattern; the param exists on
  `getTimeBuckets`). Metadata comes from the existing `sharedSpaces.libraries`
  cache; an unknown id renders the unauthorized state. Upload destinations
  follow G2 (closed): `AssetMediaCreateDto` carries no `libraryId`, so direct
  upload into an external library is unsupported server-side — the Upload
  button targets Personal and captions the upload-then-move path served by the
  Move sheet. Viewer stays URL-backed through the `view` param. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import {
    buildV2ExternalLibraryBucketOptions,
    getV2ViewerId,
    setV2ViewerId,
  } from '$lib/heirloom/slice3-options';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { openFileUploadDialog } from '$lib/utils/file-uploader';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import type { AssetResponseDto, SharedLibraryResponseDto } from '@immich/sdk';
  import { onDestroy, onMount } from 'svelte';

  const timelineManager = new TimelineManager();
  onDestroy(() => timelineManager.destroy());

  const libraryId = $derived(page.params.libraryId ?? '');
  const viewState = $derived(v2ViewState.current);
  const options = $derived(buildV2ExternalLibraryBucketOptions(libraryId));
  const viewerId = $derived(getV2ViewerId(page.url.search));
  const collectionHref = $derived(`${page.url.pathname}${setV2ViewerId(page.url.search, null)}`);
  const assetHref = (id: string) => `${page.url.pathname}${setV2ViewerId(page.url.search, id)}`;

  let storeFailed = $state(false);

  onMount(() => void sharedSpaces.ensureLoaded().catch(() => (storeFailed = true)));

  const library = $derived<SharedLibraryResponseDto | undefined>(
    sharedSpaces.libraries.find((candidate) => candidate.id === libraryId),
  );
  /** Unknown after load = not found or no access; never render a timeline for it. */
  const unknown = $derived(sharedSpaces.loaded && !library);

  const openAsset = (asset: TimelineAsset) => {
    void goto(assetHref(asset.id));
  };

  const refreshAsset = (asset: AssetResponseDto) => {
    timelineManager.upsertAssets([toTimelineAsset(asset)]);
  };
</script>

<section aria-label="External library" data-testid="v2-library-detail">
  {#if unknown || storeFailed}
    <div role="alert" data-testid="v2-library-unauthorized">
      <p>This external library could not be found, or you no longer have access to it.</p>
      <p><a href="/v2/library">Back to Library</a></p>
    </div>
  {:else if library}
    <header>
      <h1 data-testid="v2-library-name">{library.name}</h1>
      <div>
        <button
          type="button"
          data-testid="v2-library-upload"
          onclick={() => void openFileUploadDialog()}
        >
          Upload
        </button>
        <p data-testid="v2-library-upload-note">
          Uploads land in your Personal library; move them here afterwards with the Move action.
        </p>
      </div>
    </header>
    <V2SquareTimeline
      {timelineManager}
      {options}
      group={viewState.group}
      zoom={viewState.zoom}
      onAssetClick={openAsset}
      emptyTitle="No photos"
      emptyBody="Assets in this external library will appear here."
    />
  {:else}
    <p aria-busy="true" data-testid="v2-library-loading">Loading…</p>
  {/if}
</section>

{#if viewerId}
  <V2ViewerSlot
    assetId={viewerId}
    backHref={collectionHref}
    {assetHref}
    onAssetChange={refreshAsset}
  />
{/if}
