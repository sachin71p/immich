<!-- Heirloom Web V2 — grid interaction glue (WP6).
  Composes the read-only V2SquareTimeline grid with full keyboard parity, the
  selection toolbar, internal asset drag-out, and external file-drop delegation:
  - single / Cmd-or-Ctrl-toggle / Shift-range / Cmd+A / arrows (grid-aware via
    squareColumns) / Return (open viewer) / Space (preview, falls back to open
    when the route provides no preview handler) / Escape (clear, then
    close-request) / type-to-date with a 1s buffer reset.
  - V2SquareTimeline is NEVER edited: modifier clicks are intercepted in the
    capture phase and plain clicks flow to its onAssetClick; tiles are made
    draggable lazily (mouseover/focusin) since the grid owns its buttons.
  - Persistent actions use existing authorization-aware services only:
    downloadArchive (explicit Download instead of Finder promises), the
    read-only MoveToLibraryModal via modalManager, and fileUploadHandler for
    external files (the same handler the global UploadCover uses — V2 claims
    file drops only when `acceptFileDrops` is set with a destination).
  - Failures toast an actionable error and preserve the selection; moves prune
    only the ids the server confirmed as moved. -->
<script lang="ts">
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import { normalizeSquareZoom, squareColumns } from '$lib/components/heirloom/timeline/square-layout';
  import {
    encodeHeirloomDragPayload,
    HEIRLOOM_ASSET_MIME,
    type HeirloomDragSource,
  } from '$lib/heirloom/drag-drop';
  import type { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset, TimelineManagerOptions } from '$lib/managers/timeline-manager/types';
  import MoveToLibraryModal from '$lib/modals/MoveToLibraryModal.svelte';
  import { downloadArchive } from '$lib/utils/asset-utils';
  import { fileUploadHandler } from '$lib/utils/file-uploader';
  import { handleError } from '$lib/utils/handle-error';
  import { modalManager } from '@immich/ui';
  import type { Snippet } from 'svelte';
  import { describeGridKey, findDateMatch, isTypeAheadKey, TypeAheadBuffer } from './keyboard-controller';
  import { HeirloomSelectionModel, orderChecksum } from './selection-model';
  import V2SelectionToolbar from './V2SelectionToolbar.svelte';

  type Props = {
    dragSource: HeirloomDragSource;
    timelineManager?: TimelineManager;
    options?: TimelineManagerOptions;
    assets?: TimelineAsset[];
    group?: 'years' | 'months' | 'all';
    zoom?: number;
    loading?: boolean;
    error?: string | null;
    uploadDestination?: { albumId?: string; spaceId?: string };
    /** Claim OS file drops with the upload destination (default false: UploadCover owns them). */
    acceptFileDrops?: boolean;
    onOpenAsset: (asset: TimelineAsset) => void;
    onPreviewAsset?: (asset: TimelineAsset) => void;
    onSelectionChange?: (assetIds: string[]) => void;
    onMove?: (movedIds: string[]) => void;
    onAddToAlbum?: (assetIds: string[]) => void;
    onFavorite?: (assetIds: string[]) => void;
    onDelete?: (assetIds: string[]) => void;
    onCloseRequest?: () => void;
    onExternalFiles?: (files: File[]) => void;
    toolbarSuffix?: Snippet;
  };

  let {
    dragSource,
    timelineManager,
    options,
    assets,
    group = 'months',
    zoom = 120,
    loading = false,
    error = null,
    uploadDestination = {},
    acceptFileDrops = false,
    onOpenAsset,
    onPreviewAsset,
    onSelectionChange,
    onMove,
    onAddToAlbum,
    onFavorite,
    onDelete,
    onCloseRequest,
    onExternalFiles,
    toolbarSuffix,
  }: Props = $props();

  const selection = new HeirloomSelectionModel();
  const typeAhead = new TypeAheadBuffer();
  // Reactive mirror of the (plain-class) model: every mutation republishes it.
  let selectedSnapshot = $state<string[]>([]);
  let busy = $state(false);
  let wrapper: HTMLElement | undefined = $state();
  let containerWidth = $state(0);
  let resizeObserver: ResizeObserver | undefined;
  let orderKey = $state('');

  const selectedCount = $derived(selectedSnapshot.length);
  const selectedIds = $derived(new Set(selectedSnapshot));

  $effect(() => {
    if (!wrapper) {
      return;
    }
    containerWidth = wrapper.clientWidth || 0;
    resizeObserver?.disconnect();
    resizeObserver = new ResizeObserver(() => {
      if (wrapper) {
        containerWidth = wrapper.clientWidth;
      }
    });
    resizeObserver.observe(wrapper);
    return () => resizeObserver?.disconnect();
  });

  /** Flatten the same manager months the timeline renders (newest-first grid order). */
  const flatAssets = (): TimelineAsset[] => {
    if (assets !== undefined) {
      return assets;
    }
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

  const notifySelection = () => {
    selectedSnapshot = selection.selectedIds();
    onSelectionChange?.(selectedSnapshot);
  };

  /** Keep the model order in sync; prune ids that left the grid (e.g. after a move). */
  const syncOrder = (): TimelineAsset[] => {
    const list = flatAssets();
    // WP11 P1: length+ends checksum instead of a per-interaction O(n) id join.
    const ids = list.map(({ id }) => id);
    const key = orderChecksum(ids);
    if (key !== orderKey) {
      orderKey = key;
      const pruned = selection.setOrder(ids);
      if (pruned.length > 0) {
        notifySelection();
      }
    }
    return list;
  };

  // Track grid membership reactively: prune the selection when assets leave the grid.
  $effect(() => {
    syncOrder();
  });

  const byId = (list: TimelineAsset[], id: string): TimelineAsset | undefined =>
    list.find((asset) => asset.id === id);

  const selectedAssets = (list: TimelineAsset[]): TimelineAsset[] => {
    const ids = new Set(selection.selectedIds());
    return list.filter((asset) => ids.has(asset.id));
  };

  const columns = (): number => squareColumns(Math.max(1, containerWidth), normalizeSquareZoom(zoom));

  const scrollToId = (id: string) => {
    wrapper
      ?.querySelector(`[data-asset-id="${CSS.escape(id)}"]`)
      ?.scrollIntoView({ block: 'nearest', behavior: 'auto' });
  };

  const focusTile = (id: string) => {
    (wrapper?.querySelector(`[data-asset-id="${CSS.escape(id)}"]`) as HTMLElement | null)?.focus({
      preventScroll: true,
    });
  };

  const tileOf = (target: EventTarget | null): HTMLElement | null => {
    const element = target as HTMLElement | null;
    return (element?.closest?.('[data-asset-id]') as HTMLElement | null) ?? null;
  };

  const tileIdOf = (target: EventTarget | null): string | null => tileOf(target)?.dataset.assetId ?? null;

  // -- plain tile activation (modifier clicks are captured before reaching the grid) --
  const handleTileClick = (asset: TimelineAsset) => {
    syncOrder();
    selection.click(asset.id);
    notifySelection();
  };

  // -- capture-phase click: toggle/extend without disturbing the grid's own handler --
  const onCaptureClick = (event: MouseEvent) => {
    const id = tileIdOf(event.target);
    if (!id) {
      return;
    }
    if (event.metaKey || event.ctrlKey || event.shiftKey) {
      event.stopPropagation();
      event.preventDefault();
      const list = syncOrder();
      if (!byId(list, id)) {
        return;
      }
      if (event.shiftKey) {
        selection.extend(id);
      } else {
        selection.toggle(id);
      }
      selection.focus(id);
      scrollToId(id);
      notifySelection();
    }
  };

  const onFocusIn = (event: FocusEvent) => {
    const id = tileIdOf(event.target);
    if (id) {
      selection.focus(id);
    }
  };

  // Tiles are owned by the grid; mark them draggable on press so drag-out works.
  // (mousedown precedes dragstart; keyboard focus needs no draggable flag.)
  const onPrepareDrag = (event: Event) => {
    tileOf(event.target)?.setAttribute('draggable', 'true');
  };

  const onDragStart = (event: DragEvent) => {
    const id = tileIdOf(event.target);
    if (!id || !event.dataTransfer) {
      return;
    }
    const list = syncOrder();
    const asset = byId(list, id);
    if (!asset) {
      return;
    }
    if (!selection.isSelected(id)) {
      selection.click(id);
      notifySelection();
    }
    const chosen = selectedAssets(list);
    event.dataTransfer.setData(
      HEIRLOOM_ASSET_MIME,
      encodeHeirloomDragPayload({
        version: 1,
        assetIds: chosen.map(({ id: assetId }) => assetId),
        ownerIds: chosen.map(({ ownerId }) => ownerId),
        source: dragSource,
      }),
    );
    event.dataTransfer.effectAllowed = 'copy';
  };

  const inGrid = (event: Event): boolean =>
    !!(event.target as HTMLElement | null)?.closest?.('[data-testid="hv2-square-timeline"]');

  const targetAsset = (list: TimelineAsset[]): TimelineAsset | undefined => {
    const focused = selection.focusedId;
    if (focused) {
      const asset = byId(list, focused);
      if (asset) {
        return asset;
      }
    }
    const [first] = selectedAssets(list);
    return first ?? list[0];
  };

  const onKeyDown = (event: KeyboardEvent) => {
    if (!inGrid(event)) {
      return;
    }
    // Arrow navigation is grid-geometry aware (up/down jump a full row).
    if (event.key.startsWith('Arrow')) {
      const list = syncOrder();
      if (list.length === 0) {
        return;
      }
      const delta =
        event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : event.key === 'ArrowDown' ? columns() : -columns();
      event.preventDefault();
      const id = selection.moveFocusBy(delta, { extend: event.shiftKey });
      if (id) {
        scrollToId(id);
        focusTile(id);
        notifySelection();
      }
      return;
    }
    if (isTypeAheadKey(event.key) && !event.metaKey && !event.ctrlKey) {
      const list = syncOrder();
      const buffer = typeAhead.push(event.key, Date.now());
      const match = findDateMatch(list, buffer);
      if (match) {
        event.preventDefault();
        selection.click(match);
        scrollToId(match);
        focusTile(match);
        notifySelection();
      }
      return;
    }
    const action = describeGridKey({
      key: event.key,
      metaKey: event.metaKey,
      ctrlKey: event.ctrlKey,
      shiftKey: event.shiftKey,
    });
    switch (action.type) {
      case 'select-all': {
        event.preventDefault();
        syncOrder();
        selection.selectAll();
        notifySelection();
        break;
      }
      case 'clear': {
        if (selection.count > 0) {
          syncOrder();
          selection.clear();
          notifySelection();
        } else {
          onCloseRequest?.();
        }
        break;
      }
      case 'open': {
        const asset = targetAsset(syncOrder());
        if (asset) {
          event.preventDefault();
          onOpenAsset(asset);
        }
        break;
      }
      case 'preview': {
        const asset = targetAsset(syncOrder());
        if (asset && onPreviewAsset) {
          event.preventDefault();
          onPreviewAsset(asset);
        } else if (asset) {
          event.preventDefault();
          onOpenAsset(asset);
        }
        break;
      }
      case 'ignore': {
        break;
      }
    }
  };

  // -- toolbar actions (all through existing authorization-aware services) --
  const handleDownload = async () => {
    const ids = selection.selectedIds();
    if (ids.length === 0 || busy) {
      return;
    }
    busy = true;
    try {
      await downloadArchive('heirloom-selection', { assetIds: ids });
    } catch (error_) {
      handleError(error_, 'Download failed — selection kept, try again.');
    } finally {
      busy = false;
    }
  };

  const handleMove = async () => {
    const list = syncOrder();
    const chosen = selectedAssets(list);
    if (chosen.length === 0 || busy) {
      return;
    }
    busy = true;
    try {
      const movedIds = await modalManager.show(MoveToLibraryModal, {
        assetIds: chosen.map(({ id }) => id),
        assetOwnerIds: chosen.map(({ ownerId }) => ownerId),
      });
      if (movedIds && movedIds.length > 0) {
        const moved = new Set(movedIds as string[]);
        selection.setOrder(list.filter((asset) => !moved.has(asset.id)).map(({ id }) => id));
        notifySelection();
        onMove?.(movedIds as string[]);
      }
      // No ids moved (cancel or failure toast inside the modal): selection preserved.
    } catch (error_) {
      handleError(error_, 'Move failed — selection kept, try again.');
    } finally {
      busy = false;
    }
  };

  const handleFileDrop = async (files: File[]) => {
    if (files.length === 0) {
      return;
    }
    if (onExternalFiles) {
      onExternalFiles(files);
      return;
    }
    try {
      await fileUploadHandler({ files, albumId: uploadDestination.albumId, spaceId: uploadDestination.spaceId });
    } catch (error_) {
      handleError(error_, 'Import failed — drop the files again to retry.');
    }
  };

  const claimsFileDrop = (event: DragEvent): boolean => {
    if (!acceptFileDrops) {
      return false; // global UploadCover owns file drops on this route
    }
    return Array.from(event.dataTransfer?.types ?? []).includes('Files');
  };

  const onDragOverFiles = (event: DragEvent) => {
    if (claimsFileDrop(event)) {
      event.preventDefault();
    }
  };

  const onDropFiles = (event: DragEvent) => {
    if (!claimsFileDrop(event)) {
      return;
    }
    const files = Array.from(event.dataTransfer?.files ?? []);
    if (files.length > 0) {
      event.preventDefault();
      void handleFileDrop(files);
    }
  };

</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions --
  Delegation container (same pattern as timeline Month.svelte): tiles are native
  buttons inside role=list; this wrapper only delegates their events. -->
<div
  class="hv2-interactions"
  data-testid="hv2-interactions"
  role="group"
  aria-label="Photo browser"
  bind:this={wrapper}
  onclickcapture={onCaptureClick}
  onfocusin={onFocusIn}
  onmousedown={onPrepareDrag}
  ondragstart={onDragStart}
  onkeydown={onKeyDown}
  ondragover={onDragOverFiles}
  ondrop={onDropFiles}
>
  {#if selectedCount > 0}
    {#key selectedSnapshot.join(',')}
      <V2SelectionToolbar
        selectedCount={selectedCount}
        {busy}
        onDownload={() => void handleDownload()}
        onMove={() => void handleMove()}
        onClear={() => {
          selection.clear();
          notifySelection();
        }}
        onAddToAlbum={onAddToAlbum
          ? () => onAddToAlbum(selection.selectedIds())
          : undefined}
        onFavorite={onFavorite ? () => onFavorite(selection.selectedIds()) : undefined}
        onDelete={onDelete ? () => onDelete(selection.selectedIds()) : undefined}
      />
    {/key}
  {/if}
  <V2SquareTimeline
    {timelineManager}
    {options}
    {assets}
    {group}
    {zoom}
    {loading}
    {error}
    selectedIds={selectedIds}
    onAssetClick={handleTileClick}
  />
  {#if toolbarSuffix}
    {@render toolbarSuffix()}
  {/if}
</div>

<style>
  .hv2-interactions {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }
</style>
