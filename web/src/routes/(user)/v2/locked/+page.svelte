<!-- Heirloom Web V2 — Locked (WP9 slice 3).
  Buckets `{ visibility: Locked }` (classic locked page pattern). Personal-
  only (WP2 R3): no space/library scoping is offered anywhere on this route —
  no scope selector, no source filter. The Lock action reuses the existing
  user-service action (same contract as the classic locked page). Viewer stays
  URL-backed through the `view` param. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import { buildV2VisibilityOptions, getV2ViewerId, setV2ViewerId } from '$lib/heirloom/slice3-options';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { getUserActions } from '$lib/services/user.service';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import { AssetVisibility, type AssetResponseDto } from '@immich/sdk';
  import { ActionButton } from '@immich/ui';
  import { onDestroy } from 'svelte';
  import { t } from 'svelte-i18n';

  const timelineManager = new TimelineManager();
  onDestroy(() => timelineManager.destroy());

  const viewState = $derived(v2ViewState.current);
  const options = $derived(buildV2VisibilityOptions(AssetVisibility.Locked));
  const viewerId = $derived(getV2ViewerId(page.url.search));
  const collectionHref = $derived(`${page.url.pathname}${setV2ViewerId(page.url.search, null)}`);
  const assetHref = (id: string) => `${page.url.pathname}${setV2ViewerId(page.url.search, id)}`;

  const { LockSession } = $derived(getUserActions($t));

  const openAsset = (asset: TimelineAsset) => {
    void goto(assetHref(asset.id));
  };

  const refreshAsset = (asset: AssetResponseDto) => {
    timelineManager.upsertAssets([toTimelineAsset(asset)]);
  };
</script>

<section aria-label="Locked" data-testid="v2-locked">
  <header>
    <p data-testid="v2-locked-caption">Personal assets only. Lock the session to hide this folder.</p>
    <ActionButton action={LockSession} />
  </header>
  <V2SquareTimeline
    {timelineManager}
    {options}
    group={viewState.group}
    zoom={viewState.zoom}
    onAssetClick={openAsset}
    emptyTitle="No locked assets"
    emptyBody="Lock assets to keep them private on this device."
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
