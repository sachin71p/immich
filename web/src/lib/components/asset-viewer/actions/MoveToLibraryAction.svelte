<script lang="ts">
  // fork: shared-libraries — viewer "Move to…" action
  import MenuOption from '$lib/components/shared-components/context-menu/MenuOption.svelte';
  import { AssetAction } from '$lib/constants';
  import MoveToLibraryModal from '$lib/modals/MoveToLibraryModal.svelte';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import type { AssetResponseDto } from '@immich/sdk';
  import { modalManager } from '@immich/ui';
  import { mdiFolderMoveOutline } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import type { PreAction } from './action';

  interface Props {
    asset: AssetResponseDto;
    preAction: PreAction;
  }

  let { asset, preAction }: Props = $props();

  const handleMove = async () => {
    const movedIds = await modalManager.show(MoveToLibraryModal, {
      assetIds: [asset.id],
      assetOwnerIds: [asset.ownerId],
    });
    if (movedIds?.includes(asset.id)) {
      preAction({ type: AssetAction.MOVE, asset: toTimelineAsset(asset) });
    }
  };
</script>

<MenuOption icon={mdiFolderMoveOutline} onClick={handleMove} text={$t('move_to_library')} />
