<script lang="ts">
  import { initInput } from '$lib/actions/focus';
  import UserAvatar from '$lib/components/shared-components/UserAvatar.svelte';
  import { normalizeSearchString } from '$lib/utils/string-utils';
  import * as sdk from '@immich/sdk';
  import { Button, FormModal, ListButton, LoadingSpinner, Stack, Text } from '@immich/ui';
  import { sortBy } from 'lodash-es';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import { SvelteMap } from 'svelte/reactivity';

  type Props = { libraryId: string; onClose: () => void };
  let { libraryId, onClose }: Props = $props();
  let users = $state<sdk.UserResponseDto[]>([]); let memberIds = $state<string[]>([]); let search = $state(''); let loading = $state(true);
  const selected = new SvelteMap<string, sdk.UserResponseDto>();
  const candidates = $derived(sortBy(users.filter((user) => !memberIds.includes(user.id) && normalizeSearchString(user.name).includes(normalizeSearchString(search))), ['name']));
  const members = $derived(users.filter((user) => memberIds.includes(user.id)));
  const toggle = (user: sdk.UserResponseDto) => selected.has(user.id) ? selected.delete(user.id) : selected.set(user.id, user);
  const remove = async (userId: string) => { await sdk.removeMember({ id: libraryId, userId }); memberIds = memberIds.filter((id) => id !== userId); };
  const onSubmit = async () => { await sdk.addMembers({ id: libraryId, libraryMembersDto: { userIds: [...selected.keys()] } }); onClose(); };
  onMount(async () => { const [all, members] = await Promise.all([sdk.searchUsers(), sdk.getMembers({ id: libraryId })]); users = all; memberIds = members.map(({ userId }) => userId); loading = false; });
</script>
<FormModal title={$t('shared_library_members')} submitText={$t('add')} cancelText={$t('back')} disabled={selected.size === 0} {onClose} {onSubmit}>
  {#if loading}<div class="flex justify-center"><LoadingSpinner /></div>{:else}<Stack>
    {#each members as user (user.id)}<div class="flex items-center gap-3 px-2 py-1"><UserAvatar {user} size="sm" /><Text class="grow">{user.name}</Text><Button size="small" color="danger" variant="ghost" onclick={() => remove(user.id)}>{$t('remove')}</Button></div>{/each}
    <input class="border-b-4 border-immich-bg px-6 py-2 text-2xl focus:border-immich-primary dark:border-immich-dark-gray" placeholder={$t('search')} bind:value={search} use:initInput />
    {#each candidates as user (user.id)}<ListButton selected={selected.has(user.id)} onclick={() => toggle(user)}><UserAvatar {user} size="md" /><div class="grow text-start"><Text fontWeight="medium">{user.name}</Text><Text size="tiny" color="muted">{user.email}</Text></div></ListButton>{:else}<Text class="py-6">{$t('no_users_available')}</Text>{/each}
  </Stack>{/if}
</FormModal>
