<!-- Heirloom Web V2 — Add to Album sheet (WP7, WP1 §6: 300 wide, list
  min-height 160, album rows, toast on success). Service reuse:
  sdk.getAllAlbums for rows + addAssetsToAlbums from album.service (same
  notify/event contract as the classic picker, including the added-to-album
  toast). Cancel closes with no side effects.
-->
<script lang="ts">
  import { addAssetsToAlbums } from '$lib/services/album.service';
  import { handleError } from '$lib/utils/handle-error';
  import { getAllAlbums, type AlbumResponseDto } from '@immich/sdk';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import V2Sheet from './V2Sheet.svelte';
  import { SHEET_LIST_MIN_HEIGHT, SHEET_WIDTHS, sortRowsByTitle } from './sheet-logic';

  interface Props {
    assetIds: string[];
    onClose: () => void;
    onAdded?: (albumIds: string[]) => void;
  }

  let { assetIds, onClose, onAdded }: Props = $props();

  let albums: AlbumResponseDto[] = $state([]);
  let loading = $state(true);
  let error: string | null = $state(null);
  let adding = $state(false);

  const rows = $derived(sortRowsByTitle(albums.map((album) => ({ title: album.albumName, album }))));

  onMount(async () => {
    try {
      albums = await getAllAlbums({});
    } catch (error_) {
      error = error_ instanceof Error ? error_.message : $t('errors.something_went_wrong');
      handleError(error_, $t('errors.something_went_wrong'));
    } finally {
      loading = false;
    }
  });

  const addTo = async (album: AlbumResponseDto) => {
    if (adding) {
      return;
    }
    adding = true;
    const ok = await addAssetsToAlbums(
      [album.id],
      assetIds,
      { notify: true },
    );
    if (ok) {
      onAdded?.([album.id]);
      onClose();
    } else {
      adding = false;
    }
  };
</script>

<V2Sheet title={$t('add_to_album')} width={SHEET_WIDTHS.addToAlbum} {error} {onClose}>
  <div class="v2-sheet-list" style={`min-height: ${SHEET_LIST_MIN_HEIGHT}px`} role="listbox" aria-label={$t('albums')}>
    {#if loading}
      <p class="v2-sheet-empty">{$t('loading')}</p>
    {:else if rows.length === 0}
      <p class="v2-sheet-empty">{$t('no_albums_yet')}</p>
    {:else}
      {#each rows as { album } (album.id)}
        <button type="button" role="option" aria-selected="false" class="v2-row-btn" disabled={adding} onclick={() => void addTo(album)}>
          <span class="v2-row-title">{album.albumName}</span>
        </button>
      {/each}
    {/if}
  </div>
  {#snippet footer()}
    <button type="button" class="v2-btn" onclick={onClose}>{$t('cancel')}</button>
  {/snippet}
</V2Sheet>
