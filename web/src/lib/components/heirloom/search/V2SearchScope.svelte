<!-- Heirloom Web V2 — search scope selector (WP9 slice 3).
  Scope vocabulary reuses the shared `parseLibrarySource` contract verbatim
  (WP2 §0): `all`, `personal`, `space:<uuid>`, `library:<uuid>`. Member lists
  come from the existing `sharedSpaces` store (same cache the V2 sidebar
  uses); the component adds no fetch logic beyond `ensureLoaded`. -->
<script lang="ts">
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { onMount } from 'svelte';

  interface Props {
    /** Current scope in library-source vocabulary. */
    value: string;
    /** Emitted when the user picks a different scope. */
    onChange: (scope: string) => void;
  }

  let { value, onChange }: Props = $props();

  onMount(() => void sharedSpaces.ensureLoaded().catch(() => undefined));
</script>

<label data-testid="v2-search-scope">
  <span>Scope</span>
  <select
    data-testid="v2-search-scope-select"
    value={value}
    onchange={(event) => onChange(event.currentTarget.value)}
  >
    <option value="all">All libraries</option>
    <option value="personal">Personal library</option>
    {#if sharedSpaces.spaces.length > 0}
      <optgroup label="Shared libraries">
        {#each sharedSpaces.spaces as space (space.id)}
          <option value={`space:${space.id}`}>{space.name}</option>
        {/each}
      </optgroup>
    {/if}
    {#if sharedSpaces.libraries.length > 0}
      <optgroup label="External libraries">
        {#each sharedSpaces.libraries as library (library.id)}
          <option value={`library:${library.id}`}>{library.name}</option>
        {/each}
      </optgroup>
    {/if}
  </select>
</label>
