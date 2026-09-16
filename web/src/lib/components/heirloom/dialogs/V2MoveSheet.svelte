<!-- Heirloom Web V2 — Move to… sheet (WP7, WP1 §6: 320 wide, list
  min-height 160, `Move N items to…`, rows sorted by title, library targets
  confirm with the WP1-verbatim import-path notice, empty state when no
  destinations, per-asset result toast). Service reuse: computeMoveTargets +
  moveAssets/Status/Type5-7 (same counting/toast contract as
  MoveToLibraryModal). Cancel closes with no side effects.
-->
<script lang="ts">
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { handleError } from '$lib/utils/handle-error';
  import { computeMoveTargets, type MoveTarget } from '$lib/utils/move-targets';
  import { moveAssets, Status, Type5, Type6, Type7 } from '@immich/sdk';
  import { toastManager } from '@immich/ui';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import V2ConfirmSheet from './V2ConfirmSheet.svelte';
  import V2Sheet from './V2Sheet.svelte';
  import {
    MOVE_LIBRARY_CONFIRM_BODY,
    SHEET_LIST_MIN_HEIGHT,
    SHEET_WIDTHS,
    sortRowsByTitle,
    summarizeMoveResults,
  } from './sheet-logic';

  interface Props {
    assetIds: string[];
    assetOwnerIds: string[];
    onClose: (movedIds?: string[]) => void;
    onMoved?: (movedIds: string[]) => void;
  }

  let { assetIds, assetOwnerIds, onClose, onMoved }: Props = $props();

  let moving = $state(false);
  let pendingLibraryTarget: MoveTarget | null = $state(null);

  onMount(() => void sharedSpaces.ensureLoaded().catch(() => undefined));

  interface TargetRow {
    title: string;
    target: MoveTarget;
  }

  const rows = $derived<TargetRow[]>(
    authManager.authenticated
      ? sortRowsByTitle(
          computeMoveTargets(
            assetOwnerIds.map((ownerId) => ({ ownerId })),
            authManager.user.id,
            sharedSpaces.spaces,
            sharedSpaces.libraries,
          ).map((target) => ({
            title: target.type === 'personal' ? $t('move_to_personal') : target.name,
            target,
          })),
        )
      : [],
  );

  const toApiTarget = (target: MoveTarget) => {
    switch (target.type) {
      case 'personal': {
        return { type: Type5.Personal };
      }
      case 'space': {
        return { type: Type6.Space, id: target.id };
      }
      case 'library': {
        return { type: Type7.Library, id: target.id };
      }
    }
  };

  const performMove = async (target: MoveTarget) => {
    moving = true;
    try {
      const { results } = await moveAssets({ assetMoveDto: { assetIds, target: toApiTarget(target) } });
      const summary = summarizeMoveResults(results.map(({ status }) => status));
      const moved = results.filter((result) => result.status === Status.Moved).map((result) => result.id);
      if (summary.moved > 0 || summary.unchanged > 0) {
        toastManager.primary(
          $t('move_assets_partial', {
            values: { moved: summary.moved, noop: summary.unchanged, failed: summary.failed },
          }),
        );
      } else if (summary.failed > 0) {
        toastManager.danger($t('move_assets_failed'));
      }
      onMoved?.(moved);
      onClose(moved);
    } catch (error) {
      handleError(error, $t('move_assets_failed'));
      moving = false;
    }
  };

  const select = (target: MoveTarget) => {
    if (moving) {
      return;
    }
    // External-library targets confirm (WP1 §6) — files leave the import path.
    if (target.type === 'library') {
      pendingLibraryTarget = target;
      return;
    }
    void performMove(target);
  };
</script>

{#if pendingLibraryTarget}
  <V2ConfirmSheet
    title={$t('move_to_library')}
    body={MOVE_LIBRARY_CONFIRM_BODY}
    confirmLabel={$t('move')}
    tone="danger"
    onClose={(confirmed) => {
      const target = pendingLibraryTarget;
      pendingLibraryTarget = null;
      if (confirmed && target) {
        void performMove(target);
      }
    }}
  />
{:else}
  <V2Sheet
    title={`${$t('move_to_library')} · ${$t('assets_count', { values: { count: assetIds.length } })}`}
    width={SHEET_WIDTHS.move}
    onClose={() => onClose()}
  >
    <div class="v2-sheet-list" style={`min-height: ${SHEET_LIST_MIN_HEIGHT}px`} role="listbox">
      {#if rows.length === 0}
        <p class="v2-sheet-empty">{$t('move_target_empty')}</p>
      {:else}
        {#each rows as { title, target } (target.type === 'personal' ? 'personal' : target.id)}
          <button type="button" role="option" aria-selected="false" class="v2-row-btn" disabled={moving} onclick={() => select(target)}>
            <span class="v2-row-title">{title}</span>
          </button>
        {/each}
      {/if}
    </div>
    {#snippet footer()}
      <button type="button" class="v2-btn" onclick={() => onClose()}>{$t('cancel')}</button>
    {/snippet}
  </V2Sheet>
{/if}
