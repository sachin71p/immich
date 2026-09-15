<!-- fork: shared-libraries -->
<script lang="ts">
  import { copyToClipboard } from '$lib/utils';
  import { handleError } from '$lib/utils/handle-error';
  import { getAssetFullExif, type AssetFullExifResponseDto } from '@immich/sdk';
  import { Icon, LoadingSpinner, Text } from '@immich/ui';
  import { mdiChevronDown, mdiChevronUp } from '@mdi/js';
  import { t } from 'svelte-i18n';

  interface Props {
    assetId: string;
  }

  let { assetId }: Props = $props();

  let isOpen = $state(false);
  let loading = $state(false);
  let groups = $state<AssetFullExifResponseDto['groups']>();
  let query = $state('');

  const isBinary = (value: unknown): value is { binary: true; bytes: number } =>
    typeof value === 'object' && value !== null && (value as { binary?: unknown }).binary === true;

  const formatValue = (value: unknown): string => {
    if (isBinary(value)) {
      return $t('search_filter_full_metadata_binary', { values: { bytes: value.bytes } });
    }
    return typeof value === 'string' ? value : JSON.stringify(value);
  };

  const load = async () => {
    if (groups || loading) {
      return;
    }

    loading = true;
    try {
      const response = await getAssetFullExif({ id: assetId });
      groups = response.groups;
    } catch (error) {
      handleError(error, $t('errors.failed_to_load_full_metadata'));
    } finally {
      loading = false;
    }
  };

  const toggle = () => {
    isOpen = !isOpen;
    if (isOpen) {
      void load();
    }
  };

  let filteredGroups = $derived.by(() => {
    if (!groups) {
      return undefined;
    }

    const term = query.trim().toLowerCase();
    if (!term) {
      return groups;
    }

    const filtered: typeof groups = {};
    for (const [group, entries] of Object.entries(groups)) {
      const matches = Object.entries(entries).filter(([key]) => key.toLowerCase().includes(term));
      if (matches.length > 0) {
        filtered[group] = Object.fromEntries(matches);
      }
    }
    return filtered;
  });
</script>

<section class="p-4">
  <button
    type="button"
    class="flex h-10 w-full items-center justify-between text-sm"
    onclick={toggle}
    aria-expanded={isOpen}
  >
    <Text size="small" color="muted">{$t('search_filter_full_metadata_title')}</Text>
    <Icon icon={isOpen ? mdiChevronUp : mdiChevronDown} />
  </button>

  {#if isOpen}
    <div class="pt-2">
      {#if loading}
        <LoadingSpinner size="small" />
      {:else if filteredGroups}
        <input
          type="search"
          class="mb-2 immich-form-input w-full text-sm"
          placeholder={$t('search_filter_full_metadata_search_placeholder')}
          bind:value={query}
        />
        {#each Object.entries(filteredGroups) as [group, entries] (group)}
          <details class="mb-2" open={Boolean(query)}>
            <summary class="cursor-pointer text-sm font-medium">{group}</summary>
            <dl class="pt-1 pl-2 text-xs">
              {#each Object.entries(entries) as [key, value] (key)}
                <div class="flex justify-between gap-2 py-0.5">
                  <dt class="text-muted-foreground shrink-0">{key}</dt>
                  <dd class="m-0 min-w-0">
                    <button
                      type="button"
                      class="max-w-full truncate text-end hover:text-primary"
                      title={$t('copy_to_clipboard')}
                      onclick={() => copyToClipboard(formatValue(value))}
                    >
                      {formatValue(value)}
                    </button>
                  </dd>
                </div>
              {/each}
            </dl>
          </details>
        {/each}
      {/if}
    </div>
  {/if}
</section>
