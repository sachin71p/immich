<!-- Heirloom Web V2 — selection toolbar (WP6).
  Rendered only when the grid selection is non-empty (parent gates on count).
  Every button is wired to a real handler: optional actions are OMITTED when the
  parent provides no callback, so no inert controls ever ship. Download and Move
  are owned by the grid-interactions glue; Add to Album / Favorite / Delete are
  injected by the route owner (WP7 sheets / WP9 pages). -->
<script lang="ts">
  type Props = {
    selectedCount: number;
    onDownload: () => void;
    onMove: () => void;
    onClear: () => void;
    onAddToAlbum?: () => void;
    onFavorite?: () => void;
    onDelete?: () => void;
    busy?: boolean;
  };

  let {
    selectedCount,
    onDownload,
    onMove,
    onClear,
    onAddToAlbum,
    onFavorite,
    onDelete,
    busy = false,
  }: Props = $props();
</script>

<div
  class="hv2-selection-toolbar"
  data-testid="hv2-selection-toolbar"
  role="toolbar"
  aria-label={`${selectedCount} selected`}
>
  <span class="hv2-selection-count" data-testid="hv2-selection-count">
    {selectedCount} selected
  </span>
  <button type="button" data-testid="hv2-action-download" disabled={busy} onclick={onDownload} title="Download">
    Download
  </button>
  <button type="button" data-testid="hv2-action-move" disabled={busy} onclick={onMove} title="Move to…">
    Move to…
  </button>
  {#if onAddToAlbum}
    <button type="button" data-testid="hv2-action-add-album" disabled={busy} onclick={onAddToAlbum}>
      Add to Album
    </button>
  {/if}
  {#if onFavorite}
    <button type="button" data-testid="hv2-action-favorite" disabled={busy} onclick={onFavorite} title="Favorite (.)">
      Favorite
    </button>
  {/if}
  {#if onDelete}
    <button type="button" data-testid="hv2-action-delete" disabled={busy} onclick={onDelete} title="Delete (⌘⌫)">
      Delete
    </button>
  {/if}
  <button type="button" data-testid="hv2-action-clear" disabled={busy} onclick={onClear} title="Clear selection (Esc)">
    Clear
  </button>
</div>

<style>
  .hv2-selection-toolbar {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
  }
  .hv2-selection-count {
    font-weight: 600;
    margin-right: 8px;
  }
</style>
