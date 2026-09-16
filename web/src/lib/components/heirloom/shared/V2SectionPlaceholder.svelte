<script lang="ts">
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';

  interface Props {
    title: string;
    description: string;
    viewerAssetId?: string | undefined;
    backHref?: string | undefined;
  }

  let { title, description, viewerAssetId, backHref }: Props = $props();
</script>

<div data-testid="v2-section-placeholder" class="v2-placeholder">
  <h1>{title}</h1>
  <p>{description}</p>
  {#if viewerAssetId && backHref}
    <V2ViewerSlot assetId={viewerAssetId} {backHref} />
  {/if}
</div>
