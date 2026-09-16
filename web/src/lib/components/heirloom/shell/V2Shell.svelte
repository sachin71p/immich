<script lang="ts">
  import type { Snippet } from 'svelte';
  import V2Sidebar from '$lib/components/heirloom/sidebar/V2Sidebar.svelte';
  import V2Toolbar from '$lib/components/heirloom/toolbar/V2Toolbar.svelte';

  interface Props {
    children?: Snippet;
    /** Grid routes show the source/group/zoom toolbar; settings does not. */
    toolbar?: boolean;
  }

  let { children, toolbar = true }: Props = $props();
</script>

<div data-heirloom-v2 data-testid="v2-shell" class="v2-shell">
  <V2Sidebar />
  <div class="v2-main">
    {#if toolbar}
      <V2Toolbar />
    {/if}
    <main aria-label="Heirloom content" data-testid="v2-content" class="v2-content">
      {@render children?.()}
    </main>
  </div>
</div>
