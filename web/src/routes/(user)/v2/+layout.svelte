<script lang="ts">
  import { page } from '$app/state';
  import V2Shell from '$lib/components/heirloom/shell/V2Shell.svelte';
  import '$lib/heirloom/heirloom-v2.css';
  import type { Snippet } from 'svelte';

  interface Props {
    children?: Snippet;
  }

  let { children }: Props = $props();

  // Settings has no grid toolbar; every other V2 section does.
  const showToolbar = $derived(!page.url.pathname.startsWith('/v2/settings'));
</script>

<V2Shell toolbar={showToolbar}>
  {@render children?.()}
</V2Shell>
