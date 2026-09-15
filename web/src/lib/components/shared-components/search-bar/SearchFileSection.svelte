<!-- fork: shared-libraries -->
<script lang="ts">
  import { searchManager } from '$lib/managers/search-manager.svelte';
  import { Field, Input, NumberInput, Text } from '@immich/ui';
  import { t } from 'svelte-i18n';
  import SearchButton from './SearchButton.svelte';

  let filters = $derived(searchManager.filter.file);

  let extensionsText = $derived(filters.fileExtensions.join(', '));
  let mimeTypesText = $derived(filters.mimeTypes.join(', '));

  const parseList = (value: string): string[] =>
    value
      .split(',')
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
</script>

<div id="file-selection">
  <Text fontWeight="medium" class="pb-5">{$t('search_filter_file')}</Text>
  <div class="flex flex-col gap-4">
    <div class="grid grid-auto-fit-40 gap-2">
      <Field label={$t('file_extensions')}>
        <Input
          placeholder="jpg, png"
          value={extensionsText}
          oninput={(event) => (filters.fileExtensions = parseList(event.currentTarget.value))}
        />
      </Field>
      <Field label={$t('mime_type')}>
        <Input
          placeholder="image/jpeg"
          value={mimeTypesText}
          oninput={(event) => (filters.mimeTypes = parseList(event.currentTarget.value))}
        />
      </Field>
    </div>

    <div>
      <Text size="small" color="muted">{$t('file_size')}</Text>
      <div class="grid grid-auto-fit-40 gap-2 pt-1">
        <Field label={$t('search_filter_min')}>
          <NumberInput min={0} bind:value={filters.fileSizeMin} />
        </Field>
        <Field label={$t('search_filter_max')}>
          <NumberInput min={0} bind:value={filters.fileSizeMax} />
        </Field>
      </div>
    </div>

    <div>
      <Text size="small" color="muted">{$t('min_dimensions')}</Text>
      <div class="grid grid-auto-fit-40 gap-2 pt-1">
        <Field label={$t('width')}>
          <NumberInput min={0} bind:value={filters.widthMin} />
        </Field>
        <Field label={$t('height')}>
          <NumberInput min={0} bind:value={filters.heightMin} />
        </Field>
      </div>
    </div>

    <div>
      <Text size="small" color="muted">{$t('fps')}</Text>
      <div class="grid grid-auto-fit-40 gap-2 pt-1">
        <Field label={$t('search_filter_min')}>
          <NumberInput min={0} bind:value={filters.fpsMin} />
        </Field>
        <Field label={$t('search_filter_max')}>
          <NumberInput min={0} bind:value={filters.fpsMax} />
        </Field>
      </div>
    </div>

    <div class="flex flex-wrap gap-2">
      <SearchButton checked active={Boolean(filters.is360)} onclick={() => (filters.is360 = !filters.is360)}>
        {$t('panorama_360')}
      </SearchButton>
      <SearchButton
        checked
        active={Boolean(filters.hasLocation)}
        onclick={() => (filters.hasLocation = !filters.hasLocation)}
      >
        {$t('gps')}
      </SearchButton>
    </div>
  </div>
</div>
