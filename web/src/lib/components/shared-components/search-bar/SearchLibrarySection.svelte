<!-- fork: shared-libraries -->
<script lang="ts">
  import Combobox, { type ComboBoxOption } from '$lib/components/shared-components/Combobox.svelte';
  import { searchManager } from '$lib/managers/search-manager.svelte';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { Text } from '@immich/ui';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import SearchButton from './SearchButton.svelte';

  let filters = $derived(searchManager.filter.library);

  onMount(() => {
    void sharedSpaces.ensureLoaded();
  });

  let containerOptions = $derived<ComboBoxOption[]>([
    ...sharedSpaces.spaces.map((space) => ({ id: space.id, label: space.name, value: `space:${space.id}` })),
    ...sharedSpaces.libraries.map((library) => ({ id: library.id, label: library.name, value: `library:${library.id}` })),
  ]);

  let selectedOption = $derived<ComboBoxOption | undefined>(
    filters.scope === 'space'
      ? containerOptions.find((option) => option.value === `space:${filters.spaceId}`)
      : filters.scope === 'library'
        ? containerOptions.find((option) => option.value === `library:${filters.libraryId}`)
        : undefined,
  );

  const selectContainer = (option?: ComboBoxOption) => {
    if (!option) {
      filters.scope = 'all';
      filters.spaceId = undefined;
      filters.libraryId = undefined;
      return;
    }

    const [kind, id] = option.value.split(':', 2);
    filters.scope = kind === 'space' ? 'space' : 'library';
    filters.spaceId = kind === 'space' ? id : undefined;
    filters.libraryId = kind === 'library' ? id : undefined;
  };

  const selectScope = (scope: 'all' | 'personal') => {
    filters.scope = filters.scope === scope ? 'all' : scope;
    filters.spaceId = undefined;
    filters.libraryId = undefined;
  };
</script>

<div id="library-selection">
  <fieldset>
    <Text class="pb-5" fontWeight="medium">{$t('library')}</Text>
    <div class="flex flex-wrap gap-2">
      <SearchButton checked active={filters.scope === 'all'} onclick={() => selectScope('all')}>
        {$t('all')}
      </SearchButton>
      <SearchButton checked active={filters.scope === 'personal'} onclick={() => selectScope('personal')}>
        {$t('personal_library')}
      </SearchButton>
    </div>
    {#if containerOptions.length > 0}
      <div class="w-full pt-2">
        <Combobox
          label={$t('shared_libraries')}
          onSelect={selectContainer}
          options={containerOptions}
          {selectedOption}
        />
      </div>
    {/if}
  </fieldset>
</div>
