<!-- Heirloom Web V2 — album timeline (WP9 slice 3).
  Album metadata through the existing `getAlbumInfo` call; the grid composes
  buckets `{ timelineAlbumId }` (classic album page browse-mode pattern).
  Mutations reuse existing service/SDK contracts, never forks: uploads target
  the album via `openFileUploadDialog({ albumId })`, removal uses
  `removeAssetFromAlbum`, and cover updates use `updateAlbumInfo` with
  `albumThumbnailAssetId` (classic `updateThumbnail` path). Add/remove/cover
  controls are member-gated (any album member may add/remove; DECISIONS R11);
  non-members get a read-only timeline. A failed `getAlbumInfo` (unknown id or
  no access) renders the error state instead of a timeline. The viewer
  receives the album context so its actions stay album-scoped. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import {
    buildV2AlbumBucketOptions,
    getV2ViewerId,
    setV2ViewerId,
  } from '$lib/heirloom/slice3-options';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { handleError } from '$lib/utils/handle-error';
  import { openFileUploadDialog } from '$lib/utils/file-uploader';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import {
    getAlbumInfo,
    removeAssetFromAlbum,
    updateAlbumInfo,
    type AlbumResponseDto,
    type AssetResponseDto,
  } from '@immich/sdk';
  import { modalManager, toastManager } from '@immich/ui';
  import { onDestroy, onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  const timelineManager = new TimelineManager();
  onDestroy(() => timelineManager.destroy());

  const albumId = $derived(page.params.albumId ?? '');
  const viewState = $derived(v2ViewState.current);
  const options = $derived(buildV2AlbumBucketOptions(albumId));
  const viewerId = $derived(getV2ViewerId(page.url.search));
  const collectionHref = $derived(`${page.url.pathname}${setV2ViewerId(page.url.search, null)}`);
  const assetHref = (id: string) => `${page.url.pathname}${setV2ViewerId(page.url.search, id)}`;

  let album = $state<AlbumResponseDto | null>(null);
  let loadFailed = $state(false);

  onMount(() => void loadAlbum());

  const loadAlbum = async () => {
    album = null;
    loadFailed = false;
    try {
      album = await getAlbumInfo({ id: albumId });
    } catch (error) {
      loadFailed = true;
      handleError(error, $t('errors.something_went_wrong'));
    }
  };

  const isMember = $derived(
    authManager.authenticated &&
      !!album?.albumUsers.some(({ user }) => user.id === authManager.user.id),
  );

  const openAsset = (asset: TimelineAsset) => {
    void goto(assetHref(asset.id));
  };

  const refreshAsset = (asset: AssetResponseDto) => {
    timelineManager.upsertAssets([toTimelineAsset(asset)]);
  };

  const closeViewer = () => {
    void goto(collectionHref);
  };

  const removeViewedAsset = async () => {
    if (!album || !viewerId) {
      return;
    }
    const confirmed = await modalManager.showDialog({
      prompt: $t('remove_assets_album_confirmation', { values: { count: 1 } }),
    });
    if (!confirmed) {
      return;
    }
    try {
      await removeAssetFromAlbum({ id: album.id, bulkIdsDto: { ids: [viewerId] } });
      timelineManager.removeAssets([viewerId]);
      album = await getAlbumInfo({ id: album.id });
      toastManager.primary($t('assets_removed_count', { values: { count: 1 } }));
      closeViewer();
    } catch (error) {
      handleError(error, $t('errors.error_removing_assets_from_album'));
    }
  };

  const setViewedAssetAsCover = async () => {
    if (!album || !viewerId) {
      return;
    }
    try {
      album = await updateAlbumInfo({
        id: album.id,
        updateAlbumDto: { albumThumbnailAssetId: viewerId },
      });
      toastManager.primary($t('album_cover_updated'));
    } catch (error) {
      handleError(error, $t('errors.unable_to_update_album_cover'));
    }
  };
</script>

<section aria-label="Album" data-testid="v2-album">
  {#if loadFailed}
    <div role="alert" data-testid="v2-album-error">
      <p>This album could not be found, or you no longer have access to it.</p>
      <p><a href="/v2/collections">Back to Collections</a></p>
      <button type="button" data-testid="v2-album-retry" onclick={() => void loadAlbum()}>Retry</button>
    </div>
  {:else if album}
    <header>
      <h1 data-testid="v2-album-name">{album.albumName}</h1>
      {#if album.description}
        <p data-testid="v2-album-description">{album.description}</p>
      {/if}
      {#if isMember}
        <div>
          <button
            type="button"
            data-testid="v2-album-upload"
            onclick={() => {
              const id = album?.id;
              if (id) {
                void openFileUploadDialog({ albumId: id });
              }
            }}
          >
            Add photos
          </button>
          {#if viewerId}
            <button type="button" data-testid="v2-album-remove-viewed" onclick={() => void removeViewedAsset()}>
              Remove from album
            </button>
            <button type="button" data-testid="v2-album-cover-viewed" onclick={() => void setViewedAssetAsCover()}>
              Set as cover
            </button>
          {/if}
        </div>
      {/if}
    </header>
    <V2SquareTimeline
      {timelineManager}
      {options}
      group={viewState.group}
      zoom={viewState.zoom}
      onAssetClick={openAsset}
      emptyTitle="No photos"
      emptyBody="Add photos to this album to get started."
    />
  {:else}
    <p aria-busy="true" data-testid="v2-album-loading">Loading…</p>
  {/if}
</section>

{#if viewerId && album}
  <V2ViewerSlot
    assetId={viewerId}
    backHref={collectionHref}
    {album}
    {assetHref}
    onAssetChange={refreshAsset}
  />
{/if}
