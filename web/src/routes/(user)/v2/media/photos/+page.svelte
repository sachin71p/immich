<!-- Heirloom Web V2 — Photos (WP9 slice 3).
  Search-backed IMAGE listing: `getTimeBuckets` carries no `type` param (WP2
  §1), so this route composes `searchAssets` with the server `type` filter
  instead of buckets + client filtering (correct for large libraries). Scope
  composes through the shared library-source vocabulary via V2SearchScope.
  Viewer stays URL-backed through the `view` param; grid params round-trip so
  back/forward restores scope and paging. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2SearchScope from '$lib/components/heirloom/search/V2SearchScope.svelte';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import { buildV2MediaSearchFilter, getV2ViewerId, setV2ViewerId } from '$lib/heirloom/slice3-options';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { handleError } from '$lib/utils/handle-error';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import { AssetVisibility, searchAssets, type AssetResponseDto } from '@immich/sdk';
  import { untrack } from 'svelte';
  import { t } from 'svelte-i18n';

  let scope = $state('all');
  let results = $state<AssetResponseDto[]>([]);
  let nextPage = $state(0);
  let isLoading = $state(false);
  let searchFailed = $state(false);

  const viewState = $derived(v2ViewState.current);
  const assets = $derived(results.map((asset) => toTimelineAsset(asset)));
  const viewerId = $derived(getV2ViewerId(page.url.search));
  const collectionHref = $derived(`${page.url.pathname}${setV2ViewerId(page.url.search, null)}`);
  const assetHref = (id: string) => `${page.url.pathname}${setV2ViewerId(page.url.search, id)}`;

  $effect(() => {
    scope;
    untrack(() => void runSearch());
  });

  const runSearch = async () => {
    results = [];
    nextPage = 1;
    searchFailed = false;
    await loadNextPage(true);
  };

  // eslint-disable-next-line svelte/valid-prop-names-in-kit-pages
  export const loadNextPage = async (force?: boolean) => {
    if (!nextPage || (isLoading && !force)) {
      return;
    }
    isLoading = true;
    try {
      const { assets: paged } = await searchAssets({
        metadataSearchDto: {
          visibility: AssetVisibility.Timeline,
          page: nextPage,
          withExif: true,
          ...buildV2MediaSearchFilter('photos', scope),
        },
      });
      results.push(...paged.items);
      nextPage = Number(paged.nextPage) || 0;
    } catch (error) {
      searchFailed = true;
      handleError(error, $t('loading_search_results_failed'));
    } finally {
      isLoading = false;
    }
  };

  const openAsset = (asset: TimelineAsset) => {
    void goto(assetHref(asset.id));
  };

  const refreshAsset = (asset: AssetResponseDto) => {
    results = results.map((existing) => (existing.id === asset.id ? asset : existing));
  };
</script>

<section aria-label="Photos" data-testid="v2-media-photos">
  <V2SearchScope value={scope} onChange={(next) => (scope = next)} />

  {#if searchFailed}
    <div role="alert" data-testid="v2-media-offline">
      <p>Server search unavailable — showing offline results.</p>
      <button type="button" data-testid="v2-media-retry" onclick={() => void runSearch()}>Retry</button>
    </div>
  {/if}

  <p data-testid="v2-media-count">{results.length} photos</p>
  <V2SquareTimeline
    {assets}
    group="all"
    zoom={viewState.zoom}
    loading={isLoading && results.length === 0}
    onAssetClick={openAsset}
    emptyTitle="No photos"
    emptyBody="Photos you add will appear here."
  />
  {#if nextPage !== 0 && !isLoading}
    <button type="button" data-testid="v2-media-load-more" onclick={() => void loadNextPage()}>
      Load more
    </button>
  {/if}
</section>

{#if viewerId}
  <V2ViewerSlot
    assetId={viewerId}
    backHref={collectionHref}
    assets={results.some((asset) => asset.id === viewerId) ? results : undefined}
    {assetHref}
    onAssetChange={refreshAsset}
  />
{/if}
