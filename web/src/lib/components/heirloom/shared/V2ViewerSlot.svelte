<!-- Heirloom Web V2 — viewer slot (WP9 slice 1).
  Renders HeirloomViewer per the viewer README interface doc: URL-backed
  assetId, sibling AssetResponseDto[] context for wrap-around paging,
  shell-owned assetHref/onNavigate/onClose, onAssetChange refresh hint.

  Lead decision D3: the parent `(user)/+layout` drives the classic
  `asset-viewer-manager` from `page.data.asset` on EVERY child route with an
  assetId param — including V2 asset URLs — which would flip the classic
  manager to viewing and hide this whole tree behind its `display-none`
  wrapper. This slot therefore neutralizes the classic view state on V2
  route ids (read-only manager call, no shared-file edit); the classic
  viewer is never mounted inside `/v2`, so nothing renders twice.

  Viewer context: when the shell passes `assets` (search results), that list
  is the paging context verbatim and an unknown assetId falls through to the
  viewer's own error state. Otherwise the single asset is fetched through the
  existing `assetCacheManager` (same call the classic layout loader uses),
  giving loading/unknown-id states with no new data logic. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import HeirloomViewer from '$lib/components/heirloom/viewer/HeirloomViewer.svelte';
  import { isV2ViewerRoute } from '$lib/components/heirloom/viewer/viewer-variant';
  import { assetCacheManager } from '$lib/managers/AssetCacheManager.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import type { AlbumResponseDto, AssetResponseDto } from '@immich/sdk';

  interface Props {
    /** Current asset id. URL-backed: owned by the shell route (`[[assetId]]`). */
    assetId: string;
    /** Collection URL restored on close (includes source/group/zoom or `?query=`). */
    backHref: string;
    /** Viewer context (sibling list) for wrap-around paging. */
    assets?: AssetResponseDto[];
    /** Album context for add/remove/cover scoping, when opened from an album. */
    album?: AlbumResponseDto | null;
    /** Builds the real V2 asset URL for an id; enables paging + new-window. */
    assetHref?: (assetId: string) => string;
    /** Shell refresh hint after mutations that may move the asset out of source. */
    onAssetChange?: (asset: AssetResponseDto) => void;
  }

  let { assetId, backHref, assets, album = null, assetHref, onAssetChange }: Props = $props();

  $effect(() => {
    if (isV2ViewerRoute(page.route.id)) {
      assetViewerManager.showAssetViewer(false);
    }
  });

  let fetched = $state<AssetResponseDto | null>(null);
  let fetching = $state(false);
  let fetchFailed = $state(false);

  $effect(() => {
    const id = assetId;
    const provided = assets;
    fetched = null;
    fetchFailed = false;
    if (provided?.some((asset) => asset.id === id)) {
      fetching = false;
      return;
    }
    fetching = true;
    void assetCacheManager.getAsset({ id }, false).then(
      (asset) => {
        if (assetId === id) {
          fetched = asset;
          fetching = false;
        }
      },
      () => {
        if (assetId === id) {
          fetchFailed = true;
          fetching = false;
        }
      },
    );
  });

  const context = $derived(assets ?? (fetched ? [fetched] : []));

  const handleNavigate = (id: string) => {
    if (assetHref && id !== assetId) {
      void goto(`${assetHref(id)}${page.url.search}`);
    }
  };

  const handleClose = () => {
    void goto(backHref);
  };
</script>

<section
  aria-label="Asset viewer"
  data-testid="v2-viewer-slot"
  data-v2-viewer-asset={assetId}
  class="v2-viewer-slot"
>
  {#if fetching}
    <p data-testid="v2-viewer-loading" aria-busy="true">Loading…</p>
  {:else if context.length === 0}
    <p data-testid="v2-viewer-error" role="alert">Couldn't load this photo.</p>
    <p><a href={backHref} data-testid="v2-viewer-close">Back to collection</a></p>
  {:else}
    <HeirloomViewer
      {assetId}
      assets={context}
      {album}
      {assetHref}
      onNavigate={handleNavigate}
      onClose={handleClose}
      {onAssetChange}
    />
  {/if}
</section>
