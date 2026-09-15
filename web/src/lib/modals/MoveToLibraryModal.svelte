<script lang="ts">
  // fork: shared-libraries — lists allowed "Move to…" destinations and performs the move
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { handleError } from '$lib/utils/handle-error';
  import { computeMoveTargets, type MoveTarget } from '$lib/utils/move-targets';
  import { moveAssets, Status, Type5, Type6, Type7 } from '@immich/sdk';
  import { ListButton, Modal, ModalBody, Text, toastManager } from '@immich/ui';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  type Props = { assetIds: string[]; assetOwnerIds: string[]; onClose: (movedIds?: string[]) => void };
  let { assetIds, assetOwnerIds, onClose }: Props = $props();

  let loading = $state(false);

  onMount(() => void sharedSpaces.ensureLoaded());

  const targets = $derived(
    authManager.authenticated
      ? computeMoveTargets(
          assetOwnerIds.map((ownerId) => ({ ownerId })),
          authManager.user.id,
          sharedSpaces.spaces,
          sharedSpaces.libraries,
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

  const handleSelect = async (target: MoveTarget) => {
    loading = true;
    try {
      const { results } = await moveAssets({ assetMoveDto: { assetIds, target: toApiTarget(target) } });
      const moved = results.filter((result) => result.status === Status.Moved).map((result) => result.id);
      const noop = results.filter((result) => result.status === Status.Noop).length;
      const failed = results.filter((result) => result.status === Status.Error).length;

      if (moved.length > 0 || noop > 0) {
        toastManager.primary($t('move_assets_partial', { values: { moved: moved.length, noop, failed } }));
      } else if (failed > 0) {
        toastManager.danger($t('move_assets_failed'));
      }

      onClose(moved);
    } catch (error) {
      handleError(error, $t('move_assets_failed'));
      loading = false;
    }
  };
</script>

<Modal title={$t('move_to_library')} {onClose} size="small">
  <ModalBody>
    {#if targets.length === 0}
      <Text class="px-2 py-6">{$t('move_target_empty')}</Text>
    {:else}
      {#each targets as target (target.type === 'personal' ? 'personal' : target.id)}
        <ListButton disabled={loading} onclick={() => handleSelect(target)}>
          <div class="grow text-start">
            <Text fontWeight="medium">{target.type === 'personal' ? $t('move_to_personal') : target.name}</Text>
          </div>
        </ListButton>
      {/each}
    {/if}
  </ModalBody>
</Modal>
