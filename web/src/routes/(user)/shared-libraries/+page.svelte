<script lang="ts">
  import UserPageLayout from '$lib/components/layouts/UserPageLayout.svelte';
  import SharedSpaceCreateModal from '$lib/modals/SharedSpaceCreateModal.svelte';
  import { Route } from '$lib/route';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { getAssetMediaUrl } from '$lib/utils';
  import type { PageData } from './$types';
  import { Button, Card, Icon, modalManager } from '@immich/ui';
  import { mdiAccountMultiplePlusOutline, mdiImageMultipleOutline } from '@mdi/js';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  interface Props { data: PageData; }
  let { data }: Props = $props();
  onMount(() => sharedSpaces.ensureLoaded());
</script>

<UserPageLayout title={data.meta.title}>
  {#snippet buttons()}<Button size="small" leadingIcon={mdiAccountMultiplePlusOutline} onclick={() => modalManager.show(SharedSpaceCreateModal, {})}>{$t('new_shared_library')}</Button>{/snippet}
  <section class="mx-auto max-w-6xl p-4">
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {#each sharedSpaces.spaces as space (space.id)}
        <a href={Route.sharedLibrary(space)} class="block"><Card class="overflow-hidden transition hover:shadow-lg">
          <div class="h-32 bg-gray-200 bg-cover bg-center dark:bg-gray-700" style={space.thumbnailAssetId ? `background-image:url('${getAssetMediaUrl({ id: space.thumbnailAssetId })}')` : ''}></div>
          <div class="p-4"><div class="flex items-center justify-between gap-2"><h2 class="truncate font-semibold">{space.name}</h2><span class="rounded-sm bg-immich-primary/10 px-2 py-0.5 text-xs text-immich-primary">{space.role}</span></div>
          <p class="mt-1 line-clamp-2 text-sm text-gray-500">{space.description}</p><p class="mt-3 text-xs text-gray-500">{space.memberCount} {$t('shared_library_members')} · {space.assetCount} {$t('photos')}</p></div>
        </Card></a>
      {:else}<div class="col-span-full py-16 text-center text-gray-500"><Icon icon={mdiImageMultipleOutline} size="3em" /><p>{$t('no_shared_libraries')}</p></div>{/each}
    </div>
  </section>
</UserPageLayout>
