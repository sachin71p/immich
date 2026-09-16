<!-- Heirloom Web V2 — People (WP9 slice 2).
  Native (`MacPeopleView`) is a minimal per-owner list — plain rows with an
  `Unnamed` fallback, no cards or stories — so V2 matches the list and
  navigates to a detail page for rename/merge/hide. Rows compose the
  classic person thumbnail + person service (`updatePerson`); the merge
  flow reuses the classic person page merge action via real navigation. -->
<script lang="ts">
  import ImageThumbnail from '$lib/components/assets/thumbnail/ImageThumbnail.svelte';
  import {
    countV2VisiblePeople,
    filterV2PersonRows,
    toV2PersonRows,
  } from '$lib/components/heirloom/people/people-list';
  import { getPeopleThumbnailUrl } from '$lib/utils';
  import { handleError } from '$lib/utils/handle-error';
  import { updatePerson, type PersonResponseDto } from '@immich/sdk';
  import { Icon } from '@immich/ui';
  import { mdiAccountOff, mdiHeart, mdiHeartOutline, mdiEyeOffOutline, mdiChevronRight } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  let query = $state('');
  let people = $state<PersonResponseDto[]>(data.people?.people ?? []);

  const rows = $derived(toV2PersonRows(people.filter((person) => !person.isHidden)));
  const visible = $derived(filterV2PersonRows(rows, query));
  const count = $derived(countV2VisiblePeople(people));

  const thumbs = $derived(new Map(people.map((person) => [person.id, person] as const)));
  const visibleWithThumbs = $derived(
    visible.map((row) => ({ row, person: thumbs.get(row.id) }) as {
      row: (typeof visible)[number];
      person: PersonResponseDto | undefined;
    }),
  );

  const toggleFavorite = async (person: PersonResponseDto) => {
    try {
      const updated = await updatePerson({
        id: person.id,
        personUpdateDto: { isFavorite: !person.isFavorite },
      });
      people = people.map((entry) => (entry.id === updated.id ? updated : entry));
    } catch (error) {
      handleError(error, $t('errors.unable_to_add_remove_favorites', { values: { favorite: person.isFavorite } }));
    }
  };

  const hidePerson = async (person: PersonResponseDto) => {
    try {
      const updated = await updatePerson({ id: person.id, personUpdateDto: { isHidden: true } });
      people = people.map((entry) => (entry.id === updated.id ? updated : entry));
    } catch (error) {
      handleError(error, $t('errors.unable_to_hide_person'));
    }
  };
</script>

<section aria-label="People" data-testid="v2-people" class="mx-auto flex size-full min-h-0 w-full max-w-3xl flex-col">
  {#if data.loadError || !data.people}
    <div class="flex flex-1 flex-col items-center justify-center gap-2 p-8 text-center" role="alert" data-testid="v2-people-error">
      <p class="text-lg font-medium">{$t('errors.failed_to_load_people')}</p>
      <p><a href="/v2/people" class="underline" data-sveltekit-reload>Try again</a></p>
    </div>
  {:else}
    <div class="flex items-center justify-between gap-4 px-4 py-2">
      <h2 class="text-base font-semibold" data-testid="v2-people-count">
        {$t('people')} ({count.toLocaleString()})
      </h2>
      {#if people.length > 0}
        <input
          type="search"
          class="w-40 rounded-full border border-gray-200 bg-white px-3 py-1.5 text-sm sm:w-56 dark:border-gray-700 dark:bg-gray-800"
          placeholder={$t('search_people')}
          aria-label={$t('search_people')}
          bind:value={query}
        />
      {/if}
    </div>
    {#if visible.length > 0}
      <ul class="min-h-0 flex-1 divide-y divide-gray-100 overflow-y-auto dark:divide-gray-800" data-testid="v2-people-list">
        {#each visibleWithThumbs as { row, person } (row.id)}
          <li class="flex items-center gap-3 px-4 py-2">
            <a
              href="/v2/people/{row.id}"
              class="flex min-w-0 flex-1 items-center gap-3"
              aria-label={row.displayName}
            >
              <span class="size-10 shrink-0 overflow-hidden rounded-full bg-gray-300/40 dark:bg-gray-700/40">
                {#if person}
                  <ImageThumbnail
                    url={getPeopleThumbnailUrl(person)}
                    altText={row.displayName}
                    title={row.displayName}
                    widthStyle="100%"
                    circle
                    preload={false}
                  />
                {/if}
              </span>
              <span class="min-w-0 flex-1 truncate text-sm {row.isUnnamed ? 'opacity-60' : ''}">{row.displayName}</span>
              {#if row.isFavorite}
                <Icon icon={mdiHeart} size="16" class="shrink-0 opacity-70" />
              {/if}
              <Icon icon={mdiChevronRight} size="18" class="shrink-0 opacity-40" />
            </a>
            <button
              type="button"
              class="shrink-0 rounded-full p-2 hover:bg-gray-200 dark:hover:bg-gray-700"
              title={row.isFavorite ? $t('unfavorite') : $t('to_favorite')}
              aria-label={row.isFavorite ? $t('unfavorite') : $t('to_favorite')}
              aria-pressed={row.isFavorite}
              onclick={() => person && void toggleFavorite(person)}
            >
              <Icon icon={row.isFavorite ? mdiHeart : mdiHeartOutline} size="18" />
            </button>
            <button
              type="button"
              class="shrink-0 rounded-full p-2 hover:bg-gray-200 dark:hover:bg-gray-700"
              title={$t('hide_person')}
              aria-label={`${$t('hide_person')}: ${row.displayName}`}
              onclick={() => person && void hidePerson(person)}
            >
              <Icon icon={mdiEyeOffOutline} size="18" />
            </button>
          </li>
        {/each}
      </ul>
    {:else}
      <div
        class="flex flex-1 flex-col items-center justify-center gap-3 p-8 text-center"
        data-testid="v2-people-empty"
      >
        <Icon icon={mdiAccountOff} size="3em" />
        <p class="text-xl font-medium">
          {$t(query ? 'search_no_people_named' : 'search_no_people', { values: { name: query } })}
        </p>
      </div>
    {/if}
  {/if}
</section>
