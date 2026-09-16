<script lang="ts">
  import { goto } from '$app/navigation';
  import UserPageLayout from '$lib/components/layouts/UserPageLayout.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/EmptyPlaceholder.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import SharedSpaceMembersModal from '$lib/modals/SharedSpaceMembersModal.svelte';
  import { Route } from '$lib/route';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { openFileUploadDialog } from '$lib/utils/file-uploader';
  import { handleError } from '$lib/utils/handle-error';
  import * as sdk from '@immich/sdk';
  import { Button, ContextMenuButton, Field, Input, modalManager } from '@immich/ui';
  import { mdiAccountMultiplePlusOutline, mdiDeleteOutline, mdiDotsVertical, mdiLogout, mdiPencilOutline } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  interface Props { data: PageData; }
  let { data }: Props = $props();
  let space = $state(data.space);
  let manager = $state<TimelineManager>() as TimelineManager;
  let editing = $state(false);
  let name = $state(space.name); let description = $state(space.description);
  const options = $derived({ spaceId: space.id, withStacked: true });
  const isOwner = $derived(space.role === sdk.SharedSpaceRole.Owner);
  const save = async () => { try { space = await sdk.update({ id: space.id, sharedSpaceUpdateDto: { name: name.trim(), description: description.trim() } }); sharedSpaces.upsert(space); editing = false; } catch (error) { handleError(error, $t('errors.something_went_wrong')); } };
  const leave = async () => {
    const confirmed = await modalManager.showDialog({
      title: $t('leave_shared_library'),
      prompt: $t('leave_shared_library_description'),
    });
    if (!confirmed) {
      return;
    }
    const me = await sdk.getMyUser();
    await sdk.removeMember2({ id: space.id, userId: me.id });
    sharedSpaces.remove(space.id);
    await goto(Route.sharedLibraries());
  };
  const remove = async () => {
    const confirmed = await modalManager.showDialog({
      title: $t('delete_shared_library'),
      prompt: $t('delete_shared_library_description'),
    });
    if (!confirmed) {
      return;
    }
    await sdk.deleteSharedSpacesById({ id: space.id });
    sharedSpaces.remove(space.id);
    await goto(Route.sharedLibraries());
  };
</script>

<!-- fork: shared-libraries — uploads from this page target the space -->
<UserPageLayout title={space.name} scrollbar={false} uploadSpaceId={space.id}>
  {#snippet buttons()}<Button size="small" leadingIcon={mdiAccountMultiplePlusOutline} onclick={() => modalManager.show(SharedSpaceMembersModal, { space })}>{$t('shared_library_members')}</Button>{/snippet}
  <section class="mx-auto max-w-5xl px-4 pt-6">
    {#if editing}<div class="flex max-w-xl flex-col gap-3"><Field label={$t('name')}><Input bind:value={name} /></Field><Field label={$t('description')}><Input bind:value={description} /></Field><div><Button size="small" onclick={save}>{$t('save')}</Button></div></div>
    {:else}<h1 class="text-2xl font-semibold">{space.name}</h1><p class="mt-1 text-gray-500">{space.description}</p>{/if}
    <div class="mt-3 flex items-center gap-3"><label class="text-sm"><input type="checkbox" checked={space.showInTimeline} onchange={async (event) => { const showInTimeline = event.currentTarget.checked; await sdk.updateMySpaceTimeline({ id: space.id, sharedSpaceTimelineDto: { showInTimeline } }); space = { ...space, showInTimeline }; sharedSpaces.upsert(space); }} /> {$t('show_in_timeline')}</label>
      <ContextMenuButton aria-label={$t('menu')} icon={mdiDotsVertical} items={[{ title: $t('edit'), icon: mdiPencilOutline, onAction: () => (editing = true) }, ...(isOwner ? [{ title: $t('delete_shared_library'), icon: mdiDeleteOutline, onAction: remove }] : [{ title: $t('leave_shared_library'), icon: mdiLogout, onAction: leave }])]} />
    </div>
  </section>
  <Timeline enableRouting bind:timelineManager={manager} {options} assetInteraction={assetMultiSelectManager} withStacked><div class="pt-8"></div>{#snippet empty()}<EmptyPlaceholder text={$t('no_assets_message')} onClick={() => openFileUploadDialog({ spaceId: space.id })} class="mx-auto mt-10" />{/snippet}</Timeline>
</UserPageLayout>
