<!-- fork: shared-libraries -->
<script lang="ts">
  import { searchManager } from '$lib/managers/search-manager.svelte';
  import { Field, NumberInput, Text } from '@immich/ui';
  import { t } from 'svelte-i18n';

  let filters = $derived(searchManager.filter.exposure);
</script>

<div id="exposure-selection">
  <Text fontWeight="medium" class="pb-5">{$t('search_filter_exposure')}</Text>
  <div class="flex flex-col gap-4">
    <div>
      <Text size="small" color="muted">{$t('iso')}</Text>
      <div class="grid grid-auto-fit-40 gap-2 pt-1">
        <Field label={$t('search_filter_min')}>
          <NumberInput min={0} bind:value={filters.isoMin} />
        </Field>
        <Field label={$t('search_filter_max')}>
          <NumberInput min={0} bind:value={filters.isoMax} />
        </Field>
      </div>
    </div>

    <div>
      <Text size="small" color="muted">{$t('f_number')}</Text>
      <div class="grid grid-auto-fit-40 gap-2 pt-1">
        <Field label={$t('search_filter_min')}>
          <NumberInput min={0} bind:value={filters.fNumberMin} />
        </Field>
        <Field label={$t('search_filter_max')}>
          <NumberInput min={0} bind:value={filters.fNumberMax} />
        </Field>
      </div>
    </div>

    <div>
      <Text size="small" color="muted">{$t('focal_length')}</Text>
      <div class="grid grid-auto-fit-40 gap-2 pt-1">
        <Field label={$t('search_filter_min')}>
          <NumberInput min={0} bind:value={filters.focalLengthMin} />
        </Field>
        <Field label={$t('search_filter_max')}>
          <NumberInput min={0} bind:value={filters.focalLengthMax} />
        </Field>
      </div>
    </div>
  </div>
</div>
