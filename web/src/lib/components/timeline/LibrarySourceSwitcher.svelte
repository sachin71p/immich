<script lang="ts">
  // fork: shared-libraries — Apple-style library switcher for the /photos timeline header
  import { userPreferencesManager } from '$lib/managers/user-preferences-manager.svelte';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { ALL_LIBRARY_SOURCE, librarySource, PERSONAL_LIBRARY_SOURCE, spaceLibrarySource } from '$lib/utils/library-source';
  import { Select, type SelectOption } from '@immich/ui';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  onMount(() => void sharedSpaces.ensureLoaded());

  let options = $derived<SelectOption<string>[]>([
    { value: ALL_LIBRARY_SOURCE, label: $t('all_timeline_sources') },
    { value: PERSONAL_LIBRARY_SOURCE, label: $t('personal') },
    ...sharedSpaces.spaces.map((space) => ({ value: spaceLibrarySource(space.id), label: space.name })),
    ...sharedSpaces.libraries.map((library) => ({ value: librarySource(library.id), label: library.name })),
  ]);
</script>

<Select
  {options}
  size="small"
  placeholder={$t('libraries')}
  value={userPreferencesManager.timelineLibrarySource}
  onChange={(value) => (userPreferencesManager.timelineLibrarySource = value)}
/>
