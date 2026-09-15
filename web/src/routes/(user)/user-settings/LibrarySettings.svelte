<script lang="ts">
  import SettingDropdown from '$lib/components/shared-components/settings/SettingDropdown.svelte';
  import SettingSwitch from '$lib/components/shared-components/settings/SettingSwitch.svelte';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { handleError } from '$lib/utils/handle-error';
  import * as sdk from '@immich/sdk';
  import type { RenderedOption } from '$lib/elements/Dropdown.svelte';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  let showPersonal = $state(authManager.preferences.sharedLibraries.showPersonalInTimeline);
  let selectedTarget = $state<RenderedOption>({ title: $t('personal_library'), value: 'personal' });
  const targetOptions = $derived<RenderedOption[]>([{ title: $t('personal_library'), value: 'personal' }, ...sharedSpaces.spaces.map((space) => ({ title: space.name, value: space.id }))]);

  const savePreferences = async (sharedLibraries: sdk.SharedLibrariesUpdate | undefined) => {
    try { authManager.setPreferences(await sdk.updateMyPreferences({ userPreferencesUpdateDto: { sharedLibraries } })); }
    catch (error) { handleError(error, $t('errors.unable_to_update_settings')); }
  };
  const setTarget = async (option: RenderedOption) => {
    selectedTarget = option;
    await savePreferences({ defaultUploadTarget: option.value === 'personal' ? { type: sdk.Type3.Personal } : { type: sdk.Type4.Space, spaceId: option.value as string } });
  };
  const setPersonal = async (value: boolean) => { showPersonal = value; await savePreferences({ showPersonalInTimeline: value }); };
  const setSpaceTimeline = async (spaceId: string, showInTimeline: boolean) => { await sdk.updateMyTimeline2({ id: spaceId, sharedSpaceTimelineDto: { showInTimeline } }); await sharedSpaces.refresh(); };
  const setLibraryTimeline = async (libraryId: string, showInTimeline: boolean) => { await sdk.updateMyTimeline({ id: libraryId, libraryTimelineDto: { showInTimeline } }); await sharedSpaces.refresh(); };
  onMount(async () => {
    await sharedSpaces.ensureLoaded();
    const target = authManager.preferences.sharedLibraries.defaultUploadTarget;
    selectedTarget = target.type === 'space' ? targetOptions.find((option) => option.value === target.spaceId) ?? targetOptions[0] : targetOptions[0];
  });
</script>

<section class="my-4"><div class="flex flex-col gap-4 sm:ms-8">
  <SettingDropdown title={$t('default_upload_target')} subtitle={$t('default_upload_target_description')} options={targetOptions} bind:selectedOption={selectedTarget} onToggle={setTarget} />
  <h3 class="text-sm font-medium">{$t('timeline_sources')}</h3>
  <SettingSwitch title={$t('personal_library')} checked={showPersonal} onToggle={setPersonal} />
  {#each sharedSpaces.spaces as space (space.id)}<SettingSwitch title={space.name} checked={space.showInTimeline} onToggle={(value) => setSpaceTimeline(space.id, value)} />{/each}
  {#each sharedSpaces.libraries as library (library.id)}<SettingSwitch title={library.name} checked={library.showInTimeline} onToggle={(value) => setLibraryTimeline(library.id, value)} />{/each}
  <a class="text-sm text-immich-primary underline" href="/user-settings?isOpen=sharing">{$t('manage_partners')}</a>
</div></section>
