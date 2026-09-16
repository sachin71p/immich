<!-- Heirloom Web V2 — Person detail (WP9 slice 2).
  Rename/hide/favorite compose the person service (`updatePerson`); merge
  reuses the classic person-page merge flow through real navigation
  (`Route.viewPerson` with the merge action); the asset grid is a buckets
  timeline over the `personId` filter (WP2 row) with a deep-linkable V2
  viewer. -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import ImageThumbnail from '$lib/components/assets/thumbnail/ImageThumbnail.svelte';
  import { buildV2PersonAssetsOptions } from '$lib/components/heirloom/people/people-list';
  import V2ViewerSlot from '$lib/components/heirloom/shared/V2ViewerSlot.svelte';
  import V2SquareTimeline from '$lib/components/heirloom/timeline/V2SquareTimeline.svelte';
  import { v2CollectionPath } from '$lib/heirloom/route-options';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { Route } from '$lib/route';
  import { getPeopleThumbnailUrl } from '$lib/utils';
  import { handleError } from '$lib/utils/handle-error';
  import { getPerson, updatePerson, type PersonResponseDto } from '@immich/sdk';
  import { Icon } from '@immich/ui';
  import { mdiArrowLeft, mdiEyeOffOutline, mdiEyeOutline, mdiHeart, mdiHeartOutline } from '@mdi/js';
  import { onDestroy } from 'svelte';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  const timelineManager = new TimelineManager();
  onDestroy(() => timelineManager.destroy());

  let person = $state<PersonResponseDto | null>(data.person);
  let name = $state(data.person?.name ?? '');
  let renaming = $state(false);

  const displayName = $derived(!person || person.name === '' ? 'Unnamed' : person.name);
  const options = $derived(data.person ? buildV2PersonAssetsOptions(data.person.id) : undefined);
  const assetId = $derived(page.params.assetId);
  const backHref = $derived(`${v2CollectionPath(page.url.pathname)}${page.url.search}`);
  const assetHref = (id: string) => `/v2/people/${data.person?.id}/${id}`;
  // Merge reuses the classic person-page flow; V2 returns here afterwards.
  const mergeHref = $derived(
    data.person ? Route.viewPerson({ id: data.person.id }, { previousRoute: `/v2/people/${data.person.id}`, action: 'merge' }) : '',
  );

  const refresh = async () => {
    if (!data.person) {
      return;
    }
    person = await getPerson({ id: data.person.id });
    name = person.name;
  };

  const submitRename = async (event: SubmitEvent) => {
    event.preventDefault();
    if (!person || renaming || name === person.name) {
      return;
    }
    renaming = true;
    try {
      await updatePerson({ id: person.id, personUpdateDto: { name } });
      await refresh();
    } catch (error) {
      handleError(error, $t('errors.unable_to_save_name'));
    } finally {
      renaming = false;
    }
  };

  const toggleHidden = async () => {
    if (!person) {
      return;
    }
    const isHidden = !person.isHidden;
    try {
      await updatePerson({ id: person.id, personUpdateDto: { isHidden } });
      await refresh();
    } catch (error) {
      handleError(error, $t('errors.unable_to_hide_person'));
    }
  };

  const toggleFavorite = async () => {
    if (!person) {
      return;
    }
    try {
      await updatePerson({ id: person.id, personUpdateDto: { isFavorite: !person.isFavorite } });
      await refresh();
    } catch (error) {
      handleError(error, $t('errors.unable_to_add_remove_favorites', { values: { favorite: person.isFavorite } }));
    }
  };

  const openAsset = (asset: TimelineAsset) => {
    void goto(`${assetHref(asset.id)}${page.url.search}`);
  };
</script>

<section aria-label="Person" data-testid="v2-person-detail" class="flex size-full min-h-0 flex-col">
  {#if data.loadError || !person}
    <div class="flex flex-1 flex-col items-center justify-center gap-2 p-8 text-center" role="alert" data-testid="v2-person-error">
      <p class="text-lg font-medium">Couldn't load this person.</p>
      <p><a href="/v2/people" class="underline">Back to People</a></p>
    </div>
  {:else}
    <div class="flex items-center gap-3 px-4 py-2">
      <a href="/v2/people" aria-label="Back to People" class="rounded-full p-2 hover:bg-gray-200 dark:hover:bg-gray-700">
        <Icon icon={mdiArrowLeft} size="20" />
      </a>
      <span class="size-12 shrink-0 overflow-hidden rounded-full bg-gray-300/40 dark:bg-gray-700/40">
        <ImageThumbnail
          url={getPeopleThumbnailUrl(person)}
          altText={displayName}
          title={displayName}
          widthStyle="100%"
          circle
          preload={false}
        />
      </span>
      <h2 class="min-w-0 flex-1 truncate text-base font-semibold" data-testid="v2-person-name">{displayName}</h2>
      <button
        type="button"
        class="shrink-0 rounded-full p-2 hover:bg-gray-200 dark:hover:bg-gray-700"
        aria-label={person.isFavorite ? $t('unfavorite') : $t('to_favorite')}
        aria-pressed={person.isFavorite}
        onclick={() => void toggleFavorite()}
      >
        <Icon icon={person.isFavorite ? mdiHeart : mdiHeartOutline} size="20" />
      </button>
      <button
        type="button"
        class="shrink-0 rounded-full p-2 hover:bg-gray-200 dark:hover:bg-gray-700"
        aria-label={person.isHidden ? $t('unhide_person') : $t('hide_person')}
        aria-pressed={person.isHidden}
        onclick={() => void toggleHidden()}
      >
        <Icon icon={person.isHidden ? mdiEyeOutline : mdiEyeOffOutline} size="20" />
      </button>
    </div>
    <div class="flex flex-wrap items-center gap-2 px-4 pb-2">
      <form class="flex min-w-0 flex-1 items-center gap-2" onsubmit={submitRename}>
        <label for="v2-person-name-input" class="sr-only">{$t('add_a_name')}</label>
        <input
          id="v2-person-name-input"
          type="text"
          class="min-w-0 flex-1 rounded-full border border-gray-200 bg-white px-3 py-1.5 text-sm dark:border-gray-700 dark:bg-gray-800"
          placeholder={$t('add_a_name')}
          bind:value={name}
        />
        <button
          type="submit"
          class="shrink-0 rounded-full px-3 py-1.5 text-sm underline disabled:opacity-40"
          disabled={renaming || name === person.name}
        >
          Save
        </button>
      </form>
      <a href={mergeHref} class="shrink-0 rounded-full px-3 py-1.5 text-sm underline">Merge…</a>
    </div>
    <div class="min-h-0 flex-1">
      {#if options}
        <V2SquareTimeline
          {timelineManager}
          {options}
          group="all"
          onAssetClick={openAsset}
          emptyTitle="No photos of {displayName}"
          emptyBody="Assets tagged with this person will appear here."
        />
      {/if}
    </div>
  {/if}
</section>

{#if assetId && data.person}
  <V2ViewerSlot assetId={assetId} {backHref} {assetHref} />
{/if}
