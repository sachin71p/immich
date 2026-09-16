<!-- Heirloom Web V2 — Imports (WP9 slice 3).
  Recency composition (lead decision D2): native `.recents` and `.imports`
  share one arm, so V2 maps Imports to the classic recently-added upload-order
  pattern verbatim (`buildV2RecencyOptions`); the caption documents that
  "Imports" means recent uploads. The Import button honors the V2 upload /
  import-destination preferences from Settings (default upload target, or an
  explicit import destination following it). Viewer stays URL-backed through
  the `view` param. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import {
    parseV2UploadTarget,
    resolveV2ImportDestination,
    V2_IMPORT_DESTINATION_KEY,
    V2_UPLOAD_TARGET_KEY,
    type V2UploadTarget,
  } from '$lib/components/heirloom/settings/settings-capabilities';
  import { getV2ViewerId, setV2ViewerId } from '$lib/heirloom/slice3-options';
  import { buildV2RecencyOptions } from '$lib/heirloom/route-options';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { openFileUploadDialog } from '$lib/utils/file-uploader';
  import { PersistedLocalStorage } from '$lib/utils/persisted';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import type { AssetResponseDto } from '@immich/sdk';
  import { onDestroy } from 'svelte';

  const timelineManager = new TimelineManager();
  onDestroy(() => timelineManager.destroy());

  const uploadTargetPref = new PersistedLocalStorage<string>(V2_UPLOAD_TARGET_KEY, 'personal');
  const importDestinationPref = new PersistedLocalStorage<string>(V2_IMPORT_DESTINATION_KEY, 'default');

  const viewState = $derived(v2ViewState.current);
  const options = $derived(buildV2RecencyOptions());
  const viewerId = $derived(getV2ViewerId(page.url.search));
  const collectionHref = $derived(`${page.url.pathname}${setV2ViewerId(page.url.search, null)}`);
  const assetHref = (id: string) => `${page.url.pathname}${setV2ViewerId(page.url.search, id)}`;

  const openAsset = (asset: TimelineAsset) => {
    void goto(assetHref(asset.id));
  };

  const refreshAsset = (asset: AssetResponseDto) => {
    timelineManager.upsertAssets([toTimelineAsset(asset)]);
  };

  const importFiles = () => {
    const destination: V2UploadTarget = resolveV2ImportDestination(
      parseV2UploadTarget(uploadTargetPref.current),
      importDestinationPref.current === 'default'
        ? 'default'
        : parseV2UploadTarget(importDestinationPref.current),
    );
    const spaceId = destination.startsWith('space:') ? destination.slice('space:'.length) : undefined;
    void openFileUploadDialog(spaceId ? { spaceId } : {});
  };
</script>

<section aria-label="Imports" data-testid="v2-imports">
  <header>
    <p data-testid="v2-imports-caption">Recently uploaded assets, newest first.</p>
    <button type="button" data-testid="v2-imports-upload" onclick={importFiles}>Import</button>
  </header>
  <V2SquareTimeline
    {timelineManager}
    {options}
    group={viewState.group}
    zoom={viewState.zoom}
    onAssetClick={openAsset}
    emptyTitle="No imports"
    emptyBody="Imported assets will appear here."
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
