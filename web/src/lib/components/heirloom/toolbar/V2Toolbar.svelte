<script lang="ts">
  import { goto, invalidateAll } from '$app/navigation';
  import { page } from '$app/state';
  import V2ManageSpaceSheet from '$lib/components/heirloom/dialogs/V2ManageSpaceSheet.svelte';
  import { V2_GROUPS, V2_MAX_ZOOM, V2_MIN_ZOOM, type V2Group } from '$lib/heirloom/url-state';
  import { v2ViewState } from '$lib/heirloom/view-state.svelte';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { onDestroy, onMount } from 'svelte';
  import { createZoomDebouncer } from './zoom-debounce';

  const GROUP_LABELS: Record<V2Group, string> = {
    years: 'Years',
    months: 'Months',
    all: 'All Photos',
  };

  onMount(() => {
    void sharedSpaces.ensureLoaded().catch(() => undefined);
  });

  const viewState = $derived(v2ViewState.current);
  const isSpaceRoute = $derived(page.url.pathname.startsWith('/v2/spaces/'));
  const space = $derived.by(() => {
    const id = page.params.spaceId;
    return sharedSpaces.spaces.find((entry) => entry.id === id);
  });
  let manageOpen = $state(false);

  const closeManage = () => {
    manageOpen = false;
  };

  const refreshSpaces = async () => {
    await sharedSpaces.refresh();
    await invalidateAll();
  };

  const handleSource = async (event: Event) => {
    const value = (event.target as HTMLSelectElement).value;
    await v2ViewState.update({ source: value });
  };

  const handleGroup = (group: V2Group) => async () => {
    await v2ViewState.update({ group });
  };

  // WP11 P2: coalesce per-tick slider input so a drag burst applies once;
  // anchor-restore effects in V2SquareTimeline cover jump restoration.
  const zoomDebouncer = createZoomDebouncer((value: number) => {
    void v2ViewState.update({ zoom: value });
  });

  onDestroy(() => zoomDebouncer.cancel());

  const handleZoom = (event: Event) => {
    const value = Number((event.target as HTMLInputElement).value);
    if (Number.isSafeInteger(value)) {
      zoomDebouncer.push(value);
    }
  };

  const handleZoomCommit = () => {
    zoomDebouncer.flush();
  };

  const handleSync = async () => {
    await invalidateAll();
  };
</script>

<div role="toolbar" aria-label="Heirloom view options" data-testid="v2-toolbar" class="v2-toolbar">
  <div class="v2-toolbar-group">
    <label for="v2-source-picker">Library</label>
    <select id="v2-source-picker" data-testid="v2-source-picker" value={viewState.source} onchange={handleSource}>
      <option value="all">All Libraries</option>
      <option value="personal">Personal</option>
      {#each sharedSpaces.spaces as space (space.id)}
        <option value="space:{space.id}">{space.name}</option>
      {/each}
      {#each sharedSpaces.libraries as library (library.id)}
        <option value="library:{library.id}">{library.name}</option>
      {/each}
    </select>
  </div>

  <div class="v2-toolbar-group v2-segmented" role="group" aria-label="Grouping">
    {#each V2_GROUPS as group (group)}
      <button
        type="button"
        aria-pressed={viewState.group === group}
        data-testid="v2-group-{group}"
        onclick={handleGroup(group)}
      >
        {GROUP_LABELS[group]}
      </button>
    {/each}
  </div>

  <div class="v2-toolbar-group">
    <label for="v2-zoom">Zoom</label>
    <input
      type="range"
      id="v2-zoom"
      data-testid="v2-zoom"
      min={V2_MIN_ZOOM}
      max={V2_MAX_ZOOM}
      step="1"
      value={viewState.zoom}
      oninput={handleZoom}
      onchange={handleZoomCommit}
    />
  </div>

  {#if isSpaceRoute}
    <div class="v2-toolbar-group">
      <button
        type="button"
        disabled={!space}
        title={space ? `Manage ${space.name}` : 'Loading shared library…'}
        data-testid="v2-manage"
        onclick={() => {
          manageOpen = true;
        }}
      >
        Manage
      </button>
    </div>
  {/if}
  {#if manageOpen && space}
    <V2ManageSpaceSheet
      {space}
      onClose={closeManage}
      onUpdated={async (updated) => {
        sharedSpaces.upsert(updated);
        await refreshSpaces();
        closeManage();
      }}
      onLeft={async () => {
        await refreshSpaces();
        closeManage();
        await goto('/v2/library');
      }}
      onDeleted={async () => {
        await refreshSpaces();
        closeManage();
        await goto('/v2/library');
      }}
    />
  {/if}

  <div class="v2-toolbar-group">
    <button type="button" data-testid="v2-sync" onclick={handleSync}>Sync</button>
  </div>
</div>
