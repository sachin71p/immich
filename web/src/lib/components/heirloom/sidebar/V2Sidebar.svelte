<script lang="ts">
  import { page } from '$app/state';
  import { getAllAlbums, type AlbumResponseDto } from '@immich/sdk';
  import { onMount } from 'svelte';
  import {
    v2ActiveItemHrefForPath,
    v2Album,
    v2ExternalLibrary,
    v2Space,
    V2_SETTINGS,
    V2_SIDEBAR_SECTIONS,
  } from '$lib/heirloom/routes';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';

  let albums = $state<AlbumResponseDto[]>([]);

  onMount(() => {
    void sharedSpaces.ensureLoaded().catch(() => undefined);
    void getAllAlbums({ isOwned: true })
      .then((owned) => {
        albums = owned;
      })
      .catch(() => {
        albums = [];
      });
  });

  const activeHref = $derived(v2ActiveItemHrefForPath(page.url.pathname));
</script>

<nav aria-label="Heirloom library" data-testid="v2-sidebar" class="v2-sidebar">
  {#each V2_SIDEBAR_SECTIONS as section (section.id)}
    <div class="v2-sidebar-section" data-testid="v2-section-{section.id}">
      {#if section.title}
        <h2 class="v2-sidebar-heading">{section.title}</h2>
      {/if}
      <ul class="v2-sidebar-list">
        {#if section.dynamic === 'spaces'}
          {#each sharedSpaces.spaces as space (space.id)}
            <li>
              <a
                href={v2Space(space.id)}
                aria-current={activeHref === v2Space(space.id) ? 'page' : undefined}
                data-testid="v2-space-{space.id}"
                class="v2-sidebar-link"
              >
                {space.name}
              </a>
            </li>
          {/each}
        {/if}
        {#if section.dynamic === 'libraries'}
          {#each sharedSpaces.libraries as library (library.id)}
            <li>
              <a
                href={v2ExternalLibrary(library.id)}
                aria-current={activeHref === v2ExternalLibrary(library.id) ? 'page' : undefined}
                data-testid="v2-library-{library.id}"
                class="v2-sidebar-link"
              >
                {library.name}
              </a>
            </li>
          {/each}
        {/if}
        {#if section.dynamic === 'albums'}
          {#each albums as album (album.id)}
            <li>
              <a
                href={v2Album(album.id)}
                aria-current={activeHref === v2Album(album.id) ? 'page' : undefined}
                data-testid="v2-album-{album.id}"
                class="v2-sidebar-link"
              >
                {album.albumName}
              </a>
            </li>
          {/each}
        {/if}
        {#each section.items as item (item.id)}
          <li>
            {#if item.unavailable}
              <!-- WP11 A15: a real disabled control (exposed to AT) with its
                reason in an aria-describedby explanation — never a
                focus-invisible, announcement-invisible span. -->
              <button
                type="button"
                disabled
                aria-describedby="v2-nav-{item.id}-why"
                data-testid="v2-nav-{item.id}"
                class="v2-sidebar-link"
              >
                {item.label}
              </button>
              <p id="v2-nav-{item.id}-why" class="v2-visually-hidden">
                {item.label} is available with management sheets.
              </p>
            {:else}
              <a
                href={item.href}
                aria-current={activeHref === item.href ? 'page' : undefined}
                data-testid="v2-nav-{item.id}"
                class="v2-sidebar-link"
              >
                {item.label}
              </a>
            {/if}
          </li>
        {/each}
      </ul>
    </div>
  {/each}
  <div class="v2-sidebar-section" data-testid="v2-section-settings">
    <ul class="v2-sidebar-list">
      <li>
        <a
          href={V2_SETTINGS}
          aria-current={activeHref === V2_SETTINGS ? 'page' : undefined}
          data-testid="v2-nav-settings"
          class="v2-sidebar-link"
        >
          Settings
        </a>
      </li>
    </ul>
  </div>
</nav>
