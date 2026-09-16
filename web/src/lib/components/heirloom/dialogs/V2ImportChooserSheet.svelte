<!-- Heirloom Web V2 — import destination chooser (WP7, WP1 §6: 360 wide,
  `Import N files`, first 5 names + `…and K more`, destination picker,
  Upload → queue toast / dedupe note, Done). Service reuse:
  sharedSpaces for space destinations + fileUploadHandler from file-uploader
  (same queue/progress contract as openFileUploadDialog, minus its internal
  file picker — the caller supplies already-picked external files).

  G2 (WP2 §5, verified against AssetMediaCreateDto): the upload endpoint
  accepts `spaceId` but has NO `libraryId`, so direct upload into an external
  library is unsupported server-side. Destinations here are Personal + member
  spaces; external-library arrivals go upload-then-move via V2MoveSheet (see
  README). No `libraryId` upload parameter is invented.
-->
<script lang="ts">
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { fileUploadHandler } from '$lib/utils/file-uploader';
  import { handleError } from '$lib/utils/handle-error';
  import { toastManager } from '@immich/ui';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import V2Sheet from './V2Sheet.svelte';
  import {
    formatImportOverflow,
    SHEET_WIDTHS,
    summarizeImportFiles,
  } from './sheet-logic';

  interface Props {
    files: File[];
    onClose: () => void;
    onQueued?: (assetIds: string[]) => void;
  }

  let { files, onClose, onQueued }: Props = $props();

  /** '' = Personal library; otherwise a space id. */
  let destination = $state('');
  let uploading = $state(false);

  onMount(() => void sharedSpaces.ensureLoaded().catch(() => undefined));

  const preview = $derived(summarizeImportFiles(files.map((file) => file.name)));

  const upload = async () => {
    if (uploading || files.length === 0) {
      return;
    }
    uploading = true;
    try {
      // NOTE: no locale key exists for the WP1 queue toast; WP1-verbatim
      // English is used until the lead adds one (out of dialogs/** scope).
      const assetIds = await fileUploadHandler({
        files,
        spaceId: destination === '' ? undefined : destination,
      });
      toastManager.primary(`Queued ${files.length} files for upload.`);
      onQueued?.(assetIds);
      onClose();
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
      uploading = false;
    }
  };
</script>

<V2Sheet
  title={$t('upload_to_immich', { values: { count: files.length } })}
  width={SHEET_WIDTHS.importChooser}
  {onClose}
>
  <ul style="list-style: none; margin: 0; padding: 0">
    {#each preview.shown as fileName (fileName)}
      <li class="v2-row-title" style="padding: 2px 0">{fileName}</li>
    {/each}
    {#if preview.extra > 0}
      <li class="v2-row-sub">{formatImportOverflow(preview.extra)}</li>
    {/if}
  </ul>

  <div>
    <!-- NOTE: no `destination`/library-hint locale keys exist; literals until the lead adds them. -->
    <label class="v2-field-label" for="v2-import-destination">Destination</label>
    <select
      id="v2-import-destination"
      class="v2-select"
      data-autofocus
      bind:value={destination}
      disabled={uploading}
    >
      <option value="">{$t('personal')}</option>
      {#each sharedSpaces.spaces as space (space.id)}
        <option value={space.id}>{space.name}</option>
      {/each}
    </select>
    <p class="v2-helper" style="margin-top: 4px">
      External libraries are served upload-then-move: upload here, then move the assets.
    </p>
  </div>

  {#snippet footer()}
    <button type="button" class="v2-btn" onclick={onClose}>{$t('cancel')}</button>
    <button type="button" class="v2-btn v2-btn-primary" disabled={uploading || files.length === 0} onclick={() => void upload()}>
      {$t('upload')}
    </button>
  {/snippet}
</V2Sheet>
