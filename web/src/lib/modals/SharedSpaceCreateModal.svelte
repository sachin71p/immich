<script lang="ts">
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { handleError } from '$lib/utils/handle-error';
  import * as sdk from '@immich/sdk';
  import { Field, FormModal, Input, Textarea, toastManager } from '@immich/ui';
  import { mdiAccountMultiplePlusOutline } from '@mdi/js';
  import { t } from 'svelte-i18n';

  type Props = { onClose: () => void; onCreated?: (space: sdk.SharedSpaceResponseDto) => void };
  let { onClose, onCreated }: Props = $props();
  let name = $state('');
  let description = $state('');
  let error = $state('');
  const valid = $derived(name.trim().length > 0);

  const onSubmit = async () => {
    error = '';
    try {
      const space = await sdk.create({ sharedSpaceCreateDto: { name: name.trim(), description: description.trim() || undefined } });
      sharedSpaces.upsert(space);
      onCreated?.(space);
      toastManager.primary($t('shared_library_created'));
      onClose();
    } catch (error_) {
      error = error_ instanceof Error ? error_.message : $t('errors.something_went_wrong');
      handleError(error_, $t('errors.something_went_wrong'));
    }
  };
</script>

<FormModal icon={mdiAccountMultiplePlusOutline} title={$t('new_shared_library')} submitText={$t('create')} disabled={!valid} {onClose} {onSubmit}>
  <div class="flex flex-col gap-4">
    <Field label={$t('name')}><Input bind:value={name} autofocus /></Field>
    <Field label={$t('description')}><Textarea bind:value={description} /></Field>
    {#if error}<p class="text-sm text-red-500" role="alert">{error}</p>{/if}
  </div>
</FormModal>
