<script lang="ts">
  // fork: shared-libraries — bulk "Move to…" action for the timeline multi-select bar
  import MenuOption from '$lib/components/shared-components/context-menu/MenuOption.svelte';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import MoveToLibraryModal from '$lib/modals/MoveToLibraryModal.svelte';
  import type { OnMove } from '$lib/utils/actions';
  import { modalManager } from '@immich/ui';
  import { mdiFolderMoveOutline } from '@mdi/js';
  import { t } from 'svelte-i18n';

  type Props = {
    onMove?: OnMove;
    menuItem?: boolean;
  };

  let { onMove, menuItem = false }: Props = $props();

  const handleMove = async () => {
    const assets = assetMultiSelectManager.assets;
    const movedIds = await modalManager.show(MoveToLibraryModal, {
      assetIds: assets.map(({ id }) => id),
      assetOwnerIds: assets.map(({ ownerId }) => ownerId),
    });
    if (movedIds && movedIds.length > 0) {
      onMove?.(movedIds);
      assetMultiSelectManager.clear();
    }
  };
</script>

{#if menuItem}
  <MenuOption text={$t('move_to_library')} icon={mdiFolderMoveOutline} onClick={handleMove} />
{/if}
