<script lang="ts">
  import { initInput } from '$lib/actions/focus';
  import UserAvatar from '$lib/components/shared-components/UserAvatar.svelte';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { normalizeSearchString } from '$lib/utils/string-utils';
  import * as sdk from '@immich/sdk';
  import { FormModal, ListButton, LoadingSpinner, Stack, Text } from '@immich/ui';
  import { sortBy } from 'lodash-es';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import { SvelteMap } from 'svelte/reactivity';

  type Props = { space: sdk.SharedSpaceResponseDto; onClose: () => void };
  let { space, onClose }: Props = $props();
  let search = $state('');
  let users = $state<sdk.UserResponseDto[]>([]);
  let memberIds = $state<string[]>([]);
  let loading = $state(true);
  const selected = new SvelteMap<string, sdk.UserResponseDto>();
  const candidates = $derived(sortBy(users.filter((user) => !memberIds.includes(user.id) && normalizeSearchString(user.name).includes(normalizeSearchString(search))), ['name']));

  const toggle = (user: sdk.UserResponseDto) => selected.has(user.id) ? selected.delete(user.id) : selected.set(user.id, user);
  const onSubmit = async () => {
    await sdk.addMembers2({ id: space.id, sharedSpaceMembersDto: { userIds: [...selected.keys()] } });
    await sharedSpaces.refresh();
    onClose();
  };
  onMount(async () => {
    const [allUsers, members] = await Promise.all([sdk.searchUsers(), sdk.getMembers2({ id: space.id })]);
    users = allUsers;
    memberIds = members.map(({ userId }) => userId);
    loading = false;
  });
</script>

<FormModal title={$t('shared_library_members')} submitText={$t('add')} cancelText={$t('back')} disabled={selected.size === 0} {onClose} {onSubmit}>
  {#if loading}<div class="flex justify-center"><LoadingSpinner /></div>
  {:else}<Stack>
    <input class="border-b-4 border-immich-bg px-6 py-2 text-2xl focus:border-immich-primary dark:border-immich-dark-gray" placeholder={$t('search')} bind:value={search} use:initInput />
    {#each candidates as user (user.id)}
      <ListButton selected={selected.has(user.id)} onclick={() => toggle(user)}><UserAvatar {user} size="md" /><div class="grow text-start"><Text fontWeight="medium">{user.name}</Text><Text size="tiny" color="muted">{user.email}</Text></div></ListButton>
    {:else}<Text class="py-6">{$t('no_users_available')}</Text>{/each}
  </Stack>{/if}
</FormModal>
