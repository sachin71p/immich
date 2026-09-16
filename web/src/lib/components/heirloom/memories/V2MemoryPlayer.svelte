<!-- Heirloom Web V2 — memory story player (WP9 slice 2).
  Native (`MacStoryPlayerView`): black canvas, title, Music toggle
  default-off with a no-licensed-tracks note, Close, 5 s auto-advance,
  dismiss at end. Minimum plane 700×520 on desktop viewports; the toggle
  records only the preference (no licensed music is bundled — same as
  native). Pure step logic (`advanceV2StoryPlayer`) is unit-tested in
  `memory-shelf.spec.ts`; this component only renders it. -->
<script lang="ts">
  import { advanceV2StoryPlayer, V2_STORY_ADVANCE_MS } from './memory-shelf';
  import { captureFocusRestore } from '$lib/components/heirloom/dialogs/sheet-logic';
  import { getAssetMediaUrl } from '$lib/utils';
  import { AssetMediaSize } from '@immich/sdk';
  import { onDestroy } from 'svelte';

  interface Props {
    title: string;
    assetIds: string[];
    startIndex?: number;
    isSaved?: boolean;
    onClose: () => void;
    onToggleSaved?: () => void;
    onHideAsset?: (assetId: string) => void;
    onDeleteMemory?: () => void;
  }

  let {
    title,
    assetIds,
    startIndex = 0,
    isSaved = false,
    onClose,
    onToggleSaved,
    onHideAsset,
    onDeleteMemory,
  }: Props = $props();

  let index = $state(Math.min(Math.max(startIndex, 0), Math.max(assetIds.length - 1, 0)));
  let paused = $state(false);
  let musicEnabled = $state(false);
  let timer: ReturnType<typeof setInterval> | undefined;
  let dialog: HTMLElement | null = $state(null);

  // WP11 A10: dialog-grade focus contract for the player.
  // The Tab trap below deliberately duplicates V2Sheet's trap
  // (dialogs/V2Sheet.svelte) instead of extracting it, so the sheet stays
  // untouched; only the already-shared `captureFocusRestore` is reused.
  $effect(() => {
    const restoreFocus = captureFocusRestore(document);
    const root = dialog;

    const focusables = (): HTMLElement[] => {
      if (!root) {
        return [];
      }
      const nodes = root.querySelectorAll<HTMLElement>(
        'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
      );
      return [...nodes].filter((node) => node.offsetParent !== null || node === document.activeElement);
    };

    const initial = root?.querySelector<HTMLElement>('[data-autofocus]') ?? focusables()[0] ?? root;
    initial?.focus();

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Tab' || !root) {
        return;
      }
      const items = focusables();
      if (items.length === 0) {
        return;
      }
      const first = items[0];
      const last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', onKeyDown, true);
    return () => {
      document.removeEventListener('keydown', onKeyDown, true);
      restoreFocus();
    };
  });

  const currentId = $derived(assetIds[index]);
  const src = $derived(
    currentId ? getAssetMediaUrl({ id: currentId, size: AssetMediaSize.Preview }) : undefined,
  );

  const step = () => {
    const result = advanceV2StoryPlayer(index, assetIds.length);
    if ('dismiss' in result) {
      onClose();
    } else {
      index = result.next;
    }
  };

  $effect(() => {
    paused;
    index;
    assetIds.length;
    if (timer) {
      clearInterval(timer);
      timer = undefined;
    }
    if (!paused && assetIds.length > 0) {
      timer = setInterval(step, V2_STORY_ADVANCE_MS);
    }
    return () => {
      if (timer) {
        clearInterval(timer);
        timer = undefined;
      }
    };
  });

  onDestroy(() => {
    if (timer) {
      clearInterval(timer);
    }
  });

  const onKey = (event: KeyboardEvent) => {
    if (event.key === 'Escape') {
      onClose();
    } else if (event.key === 'ArrowRight') {
      step();
    } else if (event.key === 'ArrowLeft' && index > 0) {
      index -= 1;
    } else if (event.key === ' ') {
      event.preventDefault();
      paused = !paused;
    }
  };
</script>

<svelte:window onkeydown={onKey} />

<div
  bind:this={dialog}
  class="fixed inset-0 z-50 flex items-center justify-center bg-black/90 p-4"
  role="dialog"
  aria-modal="true"
  aria-label={title}
  tabindex="-1"
  data-testid="v2-memory-player"
>
  <div
    class="flex max-h-full w-full max-w-4xl flex-col bg-black text-white sm:min-h-[520px] sm:min-w-[min(700px,90vw)]"
  >
    <div class="flex items-center gap-3 px-4 py-2">
      <h2 class="min-w-0 flex-1 truncate text-base font-semibold" data-testid="v2-memory-player-title">{title}</h2>
      <span class="text-xs opacity-70" data-testid="v2-memory-player-count">{index + 1} / {assetIds.length}</span>
      <label class="flex shrink-0 cursor-pointer items-center gap-2 text-sm">
        <input type="checkbox" class="size-4 accent-gray-400" bind:checked={musicEnabled} />
        Music
      </label>
      <button
        type="button"
        class="shrink-0 rounded-full px-3 py-1.5 text-sm underline"
        onclick={onClose}
        aria-label="Close player"
      >
        Close
      </button>
    </div>
    {#if musicEnabled}
      <p class="px-4 pb-1 text-xs text-gray-400">Music on — no licensed tracks are bundled with this build.</p>
    {/if}
    <div class="flex gap-1 px-4" aria-hidden="true">
      {#each assetIds as id, i (id)}
        <span class="h-1 flex-1 rounded-full {i <= index ? 'bg-white' : 'bg-white/25'}"></span>
      {/each}
    </div>
    <div class="flex min-h-0 flex-1 items-center justify-center p-4">
      {#if src}
        <img
          src={src}
          alt={title}
          draggable="false"
          class="max-h-[60vh] max-w-full bg-gray-800 object-contain"
          data-testid="v2-memory-player-image"
        />
      {/if}
    </div>
    <div class="flex items-center justify-center gap-2 px-4 pb-4">
      <button
        type="button"
        class="rounded-full px-3 py-1.5 text-sm underline disabled:opacity-40"
        disabled={index === 0}
        onclick={() => (index -= 1)}
      >
        Previous
      </button>
      <button
        type="button"
        class="rounded-full px-3 py-1.5 text-sm underline"
        onclick={() => (paused = !paused)}
        aria-pressed={paused}
      >
        {paused ? 'Play' : 'Pause'}
      </button>
      <button
        type="button"
        class="rounded-full px-3 py-1.5 text-sm underline"
        onclick={step}
      >
        {index >= assetIds.length - 1 ? 'Finish' : 'Next'}
      </button>
      {#if onToggleSaved}
        <button
          type="button"
          class="rounded-full px-3 py-1.5 text-sm underline"
          aria-pressed={isSaved}
          onclick={onToggleSaved}
        >
          {isSaved ? 'Unsave' : 'Save'}
        </button>
      {/if}
      {#if onHideAsset && currentId}
        <button type="button" class="rounded-full px-3 py-1.5 text-sm underline" onclick={() => onHideAsset(currentId)}>
          Hide photo
        </button>
      {/if}
      {#if onDeleteMemory}
        <button type="button" class="rounded-full px-3 py-1.5 text-sm text-red-300 underline" onclick={onDeleteMemory}>
          Delete memory
        </button>
      {/if}
    </div>
  </div>
</div>
