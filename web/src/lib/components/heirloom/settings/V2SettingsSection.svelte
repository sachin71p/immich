<!-- Heirloom Web V2 — settings section shell (WP9 slice 3).
  Native grouped-form section: title + slotted rows. Unavailable rows render
  their explanation as secondary text (PLAN §2: no inert controls). -->
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    title: string;
    children: Snippet;
  }

  let { title, children }: Props = $props();
</script>

<section aria-label={title} data-testid="v2-settings-section" class="v2-settings-section">
  <h2>{title}</h2>
  {@render children()}
</section>

<style>
  .v2-settings-section {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    max-width: 32rem;
  }

  .v2-settings-section h2 {
    font-size: 0.8125rem;
    font-weight: 600;
  }
</style>
