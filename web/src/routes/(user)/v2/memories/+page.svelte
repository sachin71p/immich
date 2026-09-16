<!-- Heirloom Web V2 — Memories (WP9 slice 2).
  Native (`MacMemoriesView`): a Stories shelf (120×150 covers + caption
  title, 12 px spacing) and an On This Day shelf (44×44 thumbs + long
  date), plus the auto-advance player. Data composes `memoryManager`
  (`searchMemories`); hide/delete/save reuse the manager + memory service.
  No licensed music: the player toggle records the preference only. -->
<script lang="ts">
  import {
    toV2OnThisDayRows,
    toV2StoryCovers,
    V2_OTD_THUMB_SIZE,
    V2_STORY_COVER_HEIGHT,
    V2_STORY_COVER_WIDTH,
  } from '$lib/components/heirloom/memories/memory-shelf';
  import V2MemoryPlayer from '$lib/components/heirloom/memories/V2MemoryPlayer.svelte';
  import { memoryManager } from '$lib/managers/memory-manager.svelte';
  import { getAssetMediaUrl, handlePromiseError, memoryLaneTitle } from '$lib/utils';
  import { handleError } from '$lib/utils/handle-error';
  import { deleteMemory, updateMemory, type MemoryResponseDto } from '@immich/sdk';
  import { LoadingSpinner } from '@immich/ui';
  import { DateTime } from 'luxon';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  const laneTitle = memoryLaneTitle;
  let playing = $state<MemoryResponseDto | null>(null);

  const titleFor = (memory: MemoryResponseDto): string => $laneTitle(memory);
  const covers = $derived(toV2StoryCovers(memoryManager.memories, titleFor));
  const otdRows = $derived(toV2OnThisDayRows(memoryManager.memories));
  const total = $derived(memoryManager.total);
  const loading = $derived(memoryManager.loading && memoryManager.memories.length === 0);

  const openPlayer = (memoryId: string) => {
    playing = memoryManager.memories.find((memory) => memory.id === memoryId) ?? null;
  };

  const toggleSaved = async (memory: MemoryResponseDto) => {
    const isSaved = !memory.isSaved;
    try {
      await updateMemory({ id: memory.id, memoryUpdateDto: { isSaved } });
      memory.isSaved = isSaved;
      if (playing?.id === memory.id) {
        playing = memory;
      }
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    }
  };

  const hideAsset = async (memory: MemoryResponseDto, assetId: string) => {
    await memoryManager.hideAssets([assetId]);
    if ((playing?.assets.length ?? 0) === 0) {
      playing = null;
    }
  };

  const deleteCurrentMemory = async (memory: MemoryResponseDto) => {
    try {
      playing = null;
      await deleteMemory({ id: memory.id });
      await memoryManager.refresh();
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    }
  };

  const otdLabel = (memoryAt: string): string =>
    DateTime.fromISO(memoryAt).toLocaleString(DateTime.DATE_FULL);
</script>

<section aria-label="Memories" data-testid="v2-memories" class="flex size-full min-h-0 flex-col overflow-y-auto">
  {#if data.loadError}
    <div class="flex flex-1 flex-col items-center justify-center gap-2 p-8 text-center" role="alert" data-testid="v2-memories-error">
      <p class="text-lg font-medium">Couldn't load memories.</p>
      <p><a href="/v2/memories" class="underline" data-sveltekit-reload>Try again</a></p>
    </div>
  {:else if loading}
    <div class="flex flex-1 items-center justify-center" aria-busy="true" data-testid="v2-memories-loading">
      <LoadingSpinner size="giant" />
    </div>
  {:else}
    <div class="px-4 py-2">
      <h2 class="text-base font-semibold">
        {$t('memories')}{#if total !== undefined} ({total.toLocaleString()}){/if}
      </h2>
    </div>
    <div class="px-4 pb-2">
      <h3 class="pb-2 text-sm font-medium opacity-70">Stories</h3>
      {#if covers.length > 0}
        <div class="flex gap-3 overflow-x-auto pb-2" data-testid="v2-memory-stories">
          {#each covers as cover (cover.memoryId)}
            <button
              type="button"
              class="flex w-[120px] shrink-0 flex-col gap-1 text-start"
              onclick={() => openPlayer(cover.memoryId)}
              aria-label={cover.title}
              data-testid="v2-memory-cover-{cover.memoryId}"
            >
              <span class="block overflow-hidden rounded-lg bg-gray-300/40 dark:bg-gray-700/40">
                <img
                  src={getAssetMediaUrl({ id: cover.coverAssetId })}
                  alt={cover.title}
                  draggable="false"
                  width={V2_STORY_COVER_WIDTH}
                  height={V2_STORY_COVER_HEIGHT}
                  class="h-[150px] w-[120px] object-cover"
                />
              </span>
              <span class="line-clamp-1 text-xs">{cover.title}</span>
            </button>
          {/each}
        </div>
      {:else}
        <p class="pb-2 text-sm opacity-70" data-testid="v2-memory-stories-empty">No saved memories yet.</p>
      {/if}
    </div>
    <div class="px-4 pb-4">
      <h3 class="pb-2 text-sm font-medium opacity-70">On This Day</h3>
      {#if otdRows.length > 0}
        <ul class="flex flex-col" data-testid="v2-memory-otd">
          {#each otdRows as row (row.assetId)}
            <li>
              <button
                type="button"
                class="flex w-full items-center gap-3 py-1.5 text-start"
                onclick={() => openPlayer(row.memoryId)}
                aria-label={otdLabel(row.memoryAt)}
              >
                <span class="block shrink-0 overflow-hidden rounded-md bg-gray-300/40 dark:bg-gray-700/40">
                  <img
                    src={getAssetMediaUrl({ id: row.assetId })}
                    alt=""
                    draggable="false"
                    width={V2_OTD_THUMB_SIZE}
                    height={V2_OTD_THUMB_SIZE}
                    class="size-[44px] object-cover"
                  />
                </span>
                <span class="min-w-0 flex-1 truncate text-sm">{otdLabel(row.memoryAt)}</span>
              </button>
            </li>
          {/each}
        </ul>
      {:else}
        <p class="pb-2 text-sm opacity-70" data-testid="v2-memory-otd-empty">
          Nothing captured on this date in past years.
        </p>
      {/if}
    </div>
  {/if}
</section>

{#if playing}
  <V2MemoryPlayer
    title={titleFor(playing)}
    assetIds={playing.assets.map((asset) => asset.id)}
    isSaved={playing.isSaved}
    onClose={() => (playing = null)}
    onToggleSaved={() => handlePromiseError(toggleSaved(playing!))}
    onHideAsset={(assetId) => handlePromiseError(hideAsset(playing!, assetId))}
    onDeleteMemory={() => handlePromiseError(deleteCurrentMemory(playing!))}
  />
{/if}
