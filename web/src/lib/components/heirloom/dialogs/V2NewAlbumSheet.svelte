<!-- Heirloom Web V2 — New Album sheet (WP7, WP1 §6: 300 wide, Name only,
  Create disabled on blank name). Service reuse: sdk.createAlbum +
  eventManager 'AlbumCreate' (same contract as album-utils.createAlbum); the
  caller decides the post-create destination (V2 album route).
-->
<script lang="ts">
  import { eventManager } from '$lib/managers/event-manager.svelte';
  import { handleError } from '$lib/utils/handle-error';
  import { createAlbum, type AlbumResponseDto } from '@immich/sdk';
  import { t } from 'svelte-i18n';
  import V2Sheet from './V2Sheet.svelte';
  import { isSheetNameValid, SHEET_WIDTHS, validateSheetName } from './sheet-logic';

  interface Props {
    /** Pre-selected assets for the album (optional; empty = empty album). */
    assetIds?: string[];
    onClose: () => void;
    onCreated?: (album: AlbumResponseDto) => void;
  }

  let { assetIds = [], onClose, onCreated }: Props = $props();

  let name = $state('');
  let attempted = $state(false);
  let saving = $state(false);

  const nameError = $derived(
    attempted && validateSheetName(name) ? $t('name_required') : null,
  );

  const onSubmit = async () => {
    attempted = true;
    if (!isSheetNameValid(name) || saving) {
      return;
    }
    saving = true;
    try {
      const album = await createAlbum({
        createAlbumDto: { albumName: name.trim(), assetIds },
      });
      eventManager.emit('AlbumCreate', album);
      onCreated?.(album);
      onClose();
    } catch (error) {
      handleError(error, $t('errors.failed_to_create_album'));
      saving = false;
    }
  };
</script>

<V2Sheet title={$t('create_album')} width={SHEET_WIDTHS.newAlbum} error={nameError} {onClose}>
  <form
    onsubmit={(event) => {
      event.preventDefault();
      void onSubmit();
    }}
  >
    <label class="v2-field-label" for="v2-new-album-name">{$t('name')}</label>
    <input
      id="v2-new-album-name"
      class="v2-input"
      data-autofocus
      autocomplete="off"
      bind:value={name}
    />
  </form>
  {#snippet footer()}
    <button type="button" class="v2-btn" onclick={onClose}>{$t('cancel')}</button>
    <button type="button" class="v2-btn v2-btn-primary" disabled={!isSheetNameValid(name) || saving} onclick={() => void onSubmit()}>
      {$t('create')}
    </button>
  {/snippet}
</V2Sheet>
