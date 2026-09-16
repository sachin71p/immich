<!-- Heirloom Web V2 — permission-aware drop target wrapper (WP6).
  The parent computes `state` with decideAssetDrop() (allow-list from
  computeMoveTargets) and renders the label/reason; this component only owns the
  drag-event mechanics + visual state attribute:
  - internal asset drags: preventDefault so the drop can land, expose
    data-drop-state="allowed"|"denied" for styling.
  - OS file drags: claimed ONLY when the parent provides onFilesDrop (V2 route
    with an explicit destination). Otherwise events pass through untouched so the
    global UploadCover stays the single file-drop owner (no duplicate handling). -->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import {
    decodeHeirloomDragPayload,
    hasFilePayload,
    hasHeirloomPayload,
    HEIRLOOM_ASSET_MIME,
    type HeirloomDragPayload,
  } from '$lib/heirloom/drag-drop';

  export type DropVisualState = 'idle' | 'allowed' | 'denied';

  type Props = {
    dropState?: DropVisualState;
    label?: string;
    denyHint?: string | null;
    onAssetDrop?: (payload: HeirloomDragPayload) => void;
    onFilesDrop?: (files: File[]) => void;
    children: Snippet;
  };

  let { dropState = 'idle', label = 'Drop target', denyHint = null, onAssetDrop, onFilesDrop, children }: Props = $props();

  let dragging = $state(false);

  const typesOf = (event: DragEvent): string[] => Array.from(event.dataTransfer?.types ?? []);

  const claims = (event: DragEvent): boolean => {
    const types = typesOf(event);
    if (hasHeirloomPayload(types)) {
      return true;
    }
    return hasFilePayload(types) && !!onFilesDrop;
  };

  const onDragEnter = (event: DragEvent) => {
    if (!claims(event)) {
      return;
    }
    event.preventDefault();
    dragging = true;
  };

  const onDragOver = (event: DragEvent) => {
    if (!claims(event)) {
      return;
    }
    event.preventDefault();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = dropState === 'denied' ? 'none' : 'copy';
    }
  };

  const onDragLeave = () => {
    dragging = false;
  };

  const onDrop = (event: DragEvent) => {
    dragging = false;
    const types = typesOf(event);
    if (hasHeirloomPayload(types)) {
      event.preventDefault();
      const payload = decodeHeirloomDragPayload(event.dataTransfer?.getData(HEIRLOOM_ASSET_MIME));
      if (payload) {
        onAssetDrop?.(payload);
      }
      return;
    }
    if (hasFilePayload(types) && onFilesDrop) {
      event.preventDefault();
      onFilesDrop(Array.from(event.dataTransfer?.files ?? []));
    }
  };
</script>

<div
  class="hv2-drop-target"
  data-testid="hv2-drop-target"
  role="group"
  aria-label={label}
  data-drop-state={dragging ? dropState : 'idle'}
  data-deny-hint={denyHint ?? undefined}
  title={dropState === 'denied' && denyHint ? denyHint : undefined}
  ondragenter={onDragEnter}
  ondragover={onDragOver}
  ondragleave={onDragLeave}
  ondrop={onDrop}
>
  {@render children()}
</div>

<style>
  .hv2-drop-target[data-drop-state='allowed'] {
    outline: 2px solid currentColor;
    outline-offset: -2px;
  }
  .hv2-drop-target[data-drop-state='denied'] {
    outline: 2px dashed currentColor;
    outline-offset: -2px;
    opacity: 0.85;
  }
</style>
