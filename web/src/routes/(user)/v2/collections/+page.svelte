<!-- Heirloom Web V2 — Collections (WP9 slice 1).
  Owned/shared albums composition reusing the classic albums index verbatim:
  the same `getAllAlbums({ isOwned })` + `getAllAlbums({ isShared })` loader
  and the same `AlbumsList` component with the shared album-view settings.
  Read-only in slice 1 (`allowEdit` stays off): album CRUD, member/role, and
  creation sheets are WP7. Album cards navigate to the classic album route
  until the V2 album slice lands (recorded in the slice-1 report). -->
<script lang="ts">
  import AlbumsList from '$lib/components/album-page/AlbumsList.svelte';
  import { albumViewSettings } from '$lib/stores/preferences.store';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();
</script>

<section aria-label="Collections" data-testid="v2-collections">
  <h1>Collections</h1>
  <AlbumsList ownedAlbums={data.albums} sharedAlbums={data.sharedAlbums} userSettings={$albumViewSettings}>
    {#snippet empty()}
      <p data-testid="v2-collections-empty">No collections yet. Albums you create or join will appear here.</p>
    {/snippet}
  </AlbumsList>
</section>
