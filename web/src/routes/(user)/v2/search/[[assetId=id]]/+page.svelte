<!-- Heirloom Web V2 — Search (WP9 slice 1).
  Square results composed from the classic search stack: the `?query=` DTO
  convention, `searchSmart`/`searchAssets` selection (verbatim classic
  conditions incl. smart-search flag, `withExif`, Timeline visibility), and
  `toTimelineAsset` into the presentational V2SquareTimeline path (single
  grid section per WP1 §6). URL terms stay the source of truth so
  back/forward restores the query; the shared SearchManager is kept in sync
  (its `submit` targets classic routes and is never called here). Server
  failure renders the WP1 §6 offline state with the exact message plus a
  working retry; partial results stay visible as the offline rows. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import { QueryParameter } from '$lib/constants';
  import {
    hasV2SearchTerms,
    parseV2SearchTerms,
    v2CollectionPath,
    type V2SearchTerms,
  } from '$lib/heirloom/route-options';
  import { v2SearchAsset } from '$lib/heirloom/routes';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import { featureFlagsManager } from '$lib/managers/feature-flags-manager.svelte';
  import { searchManager } from '$lib/managers/search-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { lang } from '$lib/stores/preferences.store';
  import { handleError } from '$lib/utils/handle-error';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import {
    AssetVisibility,
    searchAssets,
    searchSmart,
    type AssetResponseDto,
  } from '@immich/sdk';
  import { untrack } from 'svelte';
  import { t } from 'svelte-i18n';

  let results = $state<AssetResponseDto[]>([]);
  let nextPage = $state(0);
  let isLoading = $state(false);
  let searchFailed = $state(false);
  let draft = $state('');

  const rawQuery = $derived(page.url.searchParams.get(QueryParameter.QUERY));
  const terms = $derived<V2SearchTerms>(parseV2SearchTerms(rawQuery));
  const showResults = $derived(hasV2SearchTerms(terms));
  const smartSearchEnabled = $derived(featureFlagsManager.value.smartSearch);
  const viewState = $derived(v2ViewState.current);
  const assets = $derived(results.map((asset) => toTimelineAsset(asset)));
  const assetId = $derived(page.params.assetId);
  const backHref = $derived(`${v2CollectionPath(page.url.pathname)}${page.url.search}`);

  // Keep the URL draft aligned when navigation (back/forward/submit) changes the query.
  $effect(() => {
    draft = typeof terms.query === 'string' ? terms.query : '';
  });

  // Keep the shared manager coherent with the URL terms. `submit` is never
  // called: it navigates to the classic search route.
  $effect(() => {
    searchManager.setQuery(terms);
  });

  $effect(() => {
    // Reactive only on `terms` + the smart-search flag; the fetch itself is untracked.
    terms;
    smartSearchEnabled;
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
    if (!showResults || !nextPage || (isLoading && !force)) {
      return;
    }
    isLoading = true;

    const searchDto = {
      page: nextPage,
      withExif: true,
      ...terms,
    };

    try {
      const { assets: paged } =
        (('query' in searchDto || 'queryAssetId' in searchDto) && smartSearchEnabled
          ? await searchSmart({
              smartSearchDto: { visibility: AssetVisibility.Timeline, ...searchDto, language: $lang },
            })
          : await searchAssets({
              metadataSearchDto: { visibility: AssetVisibility.Timeline, ...searchDto },
            }));

      results.push(...paged.items);
      nextPage = Number(paged.nextPage) || 0;
    } catch (error) {
      searchFailed = true;
      handleError(error, $t('loading_search_results_failed'));
    } finally {
      isLoading = false;
    }
  };

  const submitSearch = () => {
    const query = draft.trim();
    void goto(query ? `/v2/search?${QueryParameter.QUERY}=${encodeURIComponent(JSON.stringify({ query }))}` : '/v2/search');
  };

  const openAsset = (asset: TimelineAsset) => {
    void goto(`${v2SearchAsset(asset.id)}${page.url.search}`);
  };

  // Search-local refresh: replace the server-confirmed asset in place.
  const refreshAsset = (asset: AssetResponseDto) => {
    results = results.map((existing) => (existing.id === asset.id ? asset : existing));
  };
</script>

<section aria-label="Search" data-testid="v2-search">
  <form
    role="search"
    aria-label="Search photos"
    data-testid="v2-search-form"
    onsubmit={(event) => {
      event.preventDefault();
      submitSearch();
    }}
  >
    <label for="v2-search-field">Search photos</label>
    <input
      id="v2-search-field"
      data-testid="v2-search-field"
      type="search"
      autocomplete="off"
      bind:value={draft}
    />
    <button type="submit" data-testid="v2-search-submit">Search</button>
  </form>

  {#if searchFailed}
    <div role="alert" data-testid="v2-search-offline">
      <p>Server search unavailable — showing offline results.</p>
      <button type="button" data-testid="v2-search-retry" onclick={() => void runSearch()}>Retry</button>
    </div>
  {/if}

  {#if showResults}
    <p data-testid="v2-search-count" role="status">{results.length} results</p>
    <V2SquareTimeline
      {assets}
      group="all"
      zoom={viewState.zoom}
      loading={isLoading && results.length === 0}
      onAssetClick={openAsset}
      emptyTitle="No results"
      emptyBody="Try a different search."
    />
    {#if nextPage !== 0 && !isLoading}
      <button type="button" data-testid="v2-search-load-more" onclick={() => void loadNextPage()}>
        Load more
      </button>
    {/if}
  {:else}
    <p data-testid="v2-search-idle">Search your photos by description, place, camera, or file details.</p>
  {/if}
</section>

{#if assetId}
  <!-- Full result context only once loaded; otherwise the slot fetches the
    single asset so deep links resolve during (or without) a query load. -->
  <V2ViewerSlot
    assetId={assetId}
    {backHref}
    assets={showResults && !isLoading ? results : undefined}
    assetHref={v2SearchAsset}
    onAssetChange={refreshAsset}
  />
{/if}
