<!-- Heirloom Web V2 — square virtualized timeline (WP5).
  Opt-in square mode owned entirely by V2: 120px default tiles, 64–300 zoom,
  2px gaps, 8px inset, visible year+month headers (D1). The classic justified
  timeline is untouched and stays the default everywhere else.

  Data is composed (never forked): the caller passes a live TimelineManager
  plus TimelineManagerOptions (source filters, withStacked, visibility, …)
  which are forwarded via a single updateOptions driver — this component adds
  no fetch loop of its own. For fixtures/tests, pass `assets` directly and the
  manager is only read, never driven. -->
<script lang="ts">
  import Thumbnail from '$lib/components/assets/thumbnail/Thumbnail.svelte';
  import type { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset, TimelineManagerOptions } from '$lib/managers/timeline-manager/types';
  import { onDestroy, tick } from 'svelte';
  import {
    V2_SQUARE_GAP,
    V2_SQUARE_INSET,
    V2_SQUARE_OVERSCAN_PX,
    buildSquareSections,
    captureSquareAnchor,
    countVisibleTiles,
    describeV2TileLabel,
    layoutSquareGrid,
    normalizeSquareZoom,
    restoreSquareAnchor,
    visibleSquareRows,
    type SquareAnchor,
    type SquareSection,
    type V2SquareGroup,
  } from './square-layout';

  interface Props {
    /** Live manager to compose (read-only unless `options` is also given). */
    timelineManager?: TimelineManager;
    /** Forwarded to the manager through a single driver; carries source filters + withStacked. */
    options?: TimelineManagerOptions;
    /** Presentational override (fixtures/tests). When set, the manager is never driven. */
    assets?: TimelineAsset[];
    group?: V2SquareGroup;
    zoom?: number;
    loading?: boolean;
    error?: string | null;
    withStacked?: boolean;
    showArchiveIcon?: boolean;
    selectedIds?: Set<string>;
    emptyTitle?: string;
    emptyBody?: string;
    onAssetClick?: (asset: TimelineAsset) => void;
  }

  let {
    timelineManager,
    options,
    assets,
    group = 'months',
    zoom = 120,
    loading = false,
    error = null,
    withStacked = true,
    showArchiveIcon = false,
    selectedIds,
    emptyTitle = 'No photos',
    emptyBody = 'Assets you add will appear here.',
    onAssetClick = () => {},
  }: Props = $props();

  // Single driver: only this effect pushes options into the manager, so there
  // is exactly one fetch loop owned by TimelineManager itself.
  $effect(() => {
    if (timelineManager && options && assets === undefined) {
      void timelineManager.updateOptions(options);
    }
  });

  /** Flatten composed manager months (newest-first) without copying business logic. */
  const managerAssets = (): TimelineAsset[] => {
    if (!timelineManager) {
      return [];
    }
    const flat: TimelineAsset[] = [];
    for (const month of timelineManager.months) {
      for (const day of month.timelineDays) {
        for (const asset of day.assetsIterator()) {
          flat.push(asset);
        }
      }
    }
    return flat;
  };

  let scrollableElement: HTMLElement | undefined = $state();
  let scrollTop = $state(0);
  let viewportHeight = $state(800);
  let containerWidth = $state(0);
  let focusedAssetId: string | null = $state(null);
  let pendingAnchor: SquareAnchor | null = $state(null);
  let resizeObserver: ResizeObserver | undefined;

  const tile = $derived(normalizeSquareZoom(zoom));
  const sourceAssets: TimelineAsset[] = $derived(assets ?? managerAssets());
  const sections: SquareSection[] = $derived(buildSquareSections(sourceAssets, group));
  const layout = $derived(
    layoutSquareGrid(sections, { containerWidth: Math.max(1, containerWidth), tile }),
  );
  const rows = $derived(visibleSquareRows(layout, scrollTop, viewportHeight));
  const renderedTiles = $derived(countVisibleTiles(rows));

  const managerLoading = $derived((timelineManager?.isInitialized ?? true) === false);
  const isLoading = $derived(loading || (assets === undefined && managerLoading));
  const isEmpty = $derived(!isLoading && !error && sourceAssets.length === 0);

  const sectionById = (id: string): SquareSection | undefined => sections.find((s) => s.id === id);

  // WP11 A8: roving tabindex anchor — the focused tile, else the first
  // rendered tile so the grid costs exactly one Tab stop. Arrow handling is
  // unchanged (owned by HeirloomGridInteractions); focus events keep
  // `focusedAssetId` current so the tab stop follows keyboard navigation.
  const firstRenderedAssetId = $derived.by(() => {
    for (const row of rows) {
      if (row.kind !== 'tiles') {
        continue;
      }
      const first = sectionById(row.sectionId)?.assets[row.assetOffset];
      if (first) {
        return first.id;
      }
    }
    return null;
  });

  const tileTabIndex = (assetId: string): number =>
    focusedAssetId === assetId || (focusedAssetId === null && assetId === firstRenderedAssetId) ? 0 : -1;

  // WP11 A2: grid-global 1-based position for the tile label (section slices
  // restart per section, so the offset alone would repeat across months).
  const positionById = $derived.by(() => {
    const positions = new Map<string, number>();
    let position = 0;
    for (const section of sections) {
      for (const asset of section.assets) {
        position += 1;
        if (!positions.has(asset.id)) {
          positions.set(asset.id, position);
        }
      }
    }
    return positions;
  });

  const onScroll = () => {
    if (scrollableElement) {
      scrollTop = scrollableElement.scrollTop;
    }
  };

  const observe = (element: HTMLElement | undefined) => {
    resizeObserver?.disconnect();
    resizeObserver = undefined;
    if (!element) {
      return;
    }
    scrollTop = element.scrollTop;
    viewportHeight = element.clientHeight || 800;
    containerWidth = element.clientWidth || 0;
    resizeObserver = new ResizeObserver(() => {
      viewportHeight = element.clientHeight || 800;
      containerWidth = element.clientWidth || 0;
    });
    resizeObserver.observe(element);
  };

  $effect(() => observe(scrollableElement));

  onDestroy(() => resizeObserver?.disconnect());

  // Preserve the approximate scroll position + focus across zoom/regroup:
  // capture the anchor before the layout changes, restore after.
  $effect(() => {
    group;
    tile;
    containerWidth;
    if (scrollableElement && (scrollTop > 0 || focusedAssetId)) {
      pendingAnchor = captureSquareAnchor(layout, sections, scrollTop, viewportHeight);
    }
  });

  $effect(() => {
    // Runs after `layout` settles for the current group/tile/width.
    layout;
    const anchor = pendingAnchor;
    if (anchor && scrollableElement) {
      pendingAnchor = null;
      const next = restoreSquareAnchor(layout, sections, anchor, viewportHeight);
      if (Math.abs(next - scrollableElement.scrollTop) > 1) {
        scrollableElement.scrollTop = next;
        scrollTop = next;
      }
      if (focusedAssetId) {
        const id = focusedAssetId;
        void tick().then(() => {
          (scrollableElement?.querySelector(`[data-asset-id="${CSS.escape(id)}"]`) as HTMLElement | null)?.focus({
            preventScroll: true,
          });
        });
      }
    }
  });

  const handleTileClick = (asset: TimelineAsset) => {
    focusedAssetId = asset.id;
    onAssetClick(asset);
  };

  const handleTileFocus = (asset: TimelineAsset) => {
    focusedAssetId = asset.id;
  };
</script>

<div
  class="hv2-timeline"
  bind:this={scrollableElement}
  onscroll={onScroll}
  data-testid="hv2-square-timeline"
  data-rendered-tiles={renderedTiles}
  data-total-assets={sourceAssets.length}
  role="list"
  aria-label="Photo library grid"
>
  {#if error}
    <div class="hv2-state" data-testid="hv2-timeline-error" role="alert">
      <p class="hv2-state-title">Couldn't load photos</p>
      <p class="hv2-state-body">{error}</p>
    </div>
  {:else if isLoading}
    <div class="hv2-state" data-testid="hv2-timeline-loading" aria-busy="true">
      <p class="hv2-state-title">Loading…</p>
    </div>
  {:else if isEmpty}
    <div class="hv2-state" data-testid="hv2-timeline-empty">
      <p class="hv2-state-title">{emptyTitle}</p>
      <p class="hv2-state-body">{emptyBody}</p>
    </div>
  {:else}
    <div class="hv2-sizer" style:height={`${layout.totalHeight}px`}>
      {#each rows as row (row.kind + ':' + row.sectionId + ':' + row.top)}
        {#if row.kind === 'year'}
          <div
            class="hv2-year-header"
            style:top={`${row.top}px`}
            style:height={`${row.height}px`}
            style:left={`${V2_SQUARE_INSET}px`}
            style:right={`${V2_SQUARE_INSET}px`}
          >
            {row.title}
          </div>
        {:else if row.kind === 'month'}
          <div
            class="hv2-month-header"
            style:top={`${row.top}px`}
            style:height={`${row.height}px`}
            style:left={`${V2_SQUARE_INSET}px`}
            style:right={`${V2_SQUARE_INSET}px`}
          >
            {row.title}
          </div>
        {:else}
          {@const section = sectionById(row.sectionId)}
          {#if section}
            <div class="hv2-row" style:top={`${row.top}px`} style:height={`${row.height}px`}>
              {#each section.assets.slice(row.assetOffset, row.assetOffset + row.count) as asset, index (asset.id)}
                {@const column = (row.assetOffset + index) % layout.columns}
                {@const left = V2_SQUARE_INSET + column * (tile + V2_SQUARE_GAP)}
                <!-- WP11 A1/A3 (audit option a): tiles carry role=listitem so the
                  list owns valid items, and selection rides aria-selected. Both
                  compiler warnings below are the known cost of that choice
                  (interactive element with item role; selected on an item) —
                  kept deliberately so the aria-required-owned-elements gate
                  passes; host axe run confirms aria-allowed-attr. -->
                <!-- svelte-ignore a11y_no_interactive_element_to_noninteractive_role -->
                <!-- svelte-ignore a11y_role_supports_aria_props -->
                <button
                  type="button"
                  role="listitem"
                  class="hv2-tile"
                  class:hv2-selected={selectedIds?.has(asset.id) ?? false}
                  style:left={`${left}px`}
                  style:width={`${tile}px`}
                  style:height={`${tile}px`}
                  data-asset-id={asset.id}
                  aria-label={describeV2TileLabel(
                    asset,
                    positionById.get(asset.id) ?? row.assetOffset + index + 1,
                    sourceAssets.length,
                  )}
                  aria-selected={selectedIds?.has(asset.id) ?? false}
                  tabindex={tileTabIndex(asset.id)}
                  onclick={() => handleTileClick(asset)}
                  onfocus={() => handleTileFocus(asset)}
                >
                  <Thumbnail
                    {asset}
                    thumbnailWidth={tile}
                    thumbnailHeight={tile}
                    readonly
                    showStackedIcon={withStacked}
                    {showArchiveIcon}
                  />
                </button>
              {/each}
            </div>
          {/if}
        {/if}
      {/each}
    </div>
  {/if}
</div>

<style>
  /* Scoped under the V2 root: no selector here may leak into classic routes. */
  .hv2-timeline {
    position: relative;
    height: 100%;
    overflow-y: auto;
    background: var(--hv2-background, transparent);
  }
  .hv2-sizer {
    position: relative;
    width: 100%;
  }
  .hv2-year-header,
  .hv2-month-header {
    position: absolute;
    display: flex;
    align-items: center;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .hv2-year-header {
    font-size: 1.25rem;
  }
  .hv2-month-header {
    font-size: 1rem;
  }
  .hv2-row {
    position: absolute;
    left: 0;
    right: 0;
  }
  .hv2-tile {
    position: absolute;
    top: 0;
    padding: 0;
    border: 0;
    border-radius: 4px;
    overflow: hidden;
    background: transparent;
    cursor: pointer;
  }
  .hv2-tile:focus-visible {
    outline: 2px solid currentColor;
    outline-offset: 1px;
  }
  .hv2-tile.hv2-selected {
    outline: 2px solid currentColor;
    outline-offset: -2px;
  }
  /* WP11 A17: forced-colors minimum — selection/focus survive as a
    system-color outline when author colors are flattened. */
  @media (forced-colors: active) {
    .hv2-tile.hv2-selected,
    .hv2-tile:focus-visible {
      outline: 3px solid ButtonText;
    }
  }
  .hv2-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    min-height: 240px;
    padding: 24px;
    text-align: center;
  }
  .hv2-state-title {
    font-size: 1.125rem;
    font-weight: 600;
    margin: 0;
  }
  .hv2-state-body {
    margin: 0;
    opacity: 0.7;
  }
</style>
