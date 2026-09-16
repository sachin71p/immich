<!-- Heirloom Web V2 — New Shared Library sheet (WP7, WP1 §6: 320 wide,
  Name + Description (optional), Create disabled on blank name). Service
  reuse: sdk.create + sharedSpaces.upsert + shared_library_created toast
  (same contract as SharedSpaceCreateModal).
-->
<script lang="ts">
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { handleError } from '$lib/utils/handle-error';
  import { create, type SharedSpaceResponseDto } from '@immich/sdk';
  import { toastManager } from '@immich/ui';
  import { t } from 'svelte-i18n';
  import V2Sheet from './V2Sheet.svelte';
  import { isSheetNameValid, SHEET_WIDTHS, validateSheetName } from './sheet-logic';

  interface Props {
    onClose: () => void;
    onCreated?: (space: SharedSpaceResponseDto) => void;
  }

  let { onClose, onCreated }: Props = $props();

  let name = $state('');
  let description = $state('');
  let attempted = $state(false);
  let saving = $state(false);

  const nameError = $derived(attempted && validateSheetName(name) ? $t('name_required') : null);

  const onSubmit = async () => {
    attempted = true;
    if (!isSheetNameValid(name) || saving) {
      return;
    }
    saving = true;
    try {
      const space = await create({
        sharedSpaceCreateDto: { name: name.trim(), description: description.trim() || undefined },
      });
      sharedSpaces.upsert(space);
      onCreated?.(space);
      toastManager.primary($t('shared_library_created'));
      onClose();
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
      saving = false;
    }
  };
</script>

<V2Sheet title={$t('new_shared_library')} width={SHEET_WIDTHS.newSpace} error={nameError} {onClose}>
  <form
    onsubmit={(event) => {
      event.preventDefault();
      void onSubmit();
    }}
  >
    <div>
      <label class="v2-field-label" for="v2-new-space-name">{$t('name')}</label>
      <input id="v2-new-space-name" class="v2-input" data-autofocus autocomplete="off" bind:value={name} />
    </div>
    <div style="margin-top: 12px">
      <label class="v2-field-label" for="v2-new-space-description">{$t('description')}</label>
      <textarea id="v2-new-space-description" class="v2-textarea" rows="2" bind:value={description}></textarea>
    </div>
  </form>
  {#snippet footer()}
    <button type="button" class="v2-btn" onclick={onClose}>{$t('cancel')}</button>
    <button
      type="button"
      class="v2-btn v2-btn-primary"
      disabled={!isSheetNameValid(name) || saving}
      onclick={() => void onSubmit()}
    >
      {$t('create')}
    </button>
  {/snippet}
</V2Sheet>
