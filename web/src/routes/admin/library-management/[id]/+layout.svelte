<script lang="ts">
  import { goto, invalidate } from '$app/navigation';
  import emptyFoldersUrl from '$lib/assets/empty-folders.svg';
  import AdminCard from '$lib/components/AdminCard.svelte';
  import AdminPageLayout from '$lib/components/layouts/AdminPageLayout.svelte';
  import OnEvents from '$lib/components/OnEvents.svelte';
  import ServerStatisticsCard from '$lib/components/server-statistics/ServerStatisticsCard.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/EmptyPlaceholder.svelte';
  import TableButton from '$lib/components/TableButton.svelte';
  import LibraryFolderAddModal from '$lib/modals/LibraryFolderAddModal.svelte';
  import LibraryMembersModal from '$lib/modals/LibraryMembersModal.svelte';
  import { Route } from '$lib/route';
  import {
    getLibraryActions,
    getLibraryExclusionPatternActions,
    getLibraryFolderActions,
  } from '$lib/services/library.service';
  import { getBytesWithUnit } from '$lib/utils/byte-units';
  import { handleUpdateLibrary } from '$lib/services/library.service';
  import { Button, Code, CommandPaletteDefaultProvider, Container, Field, Heading, Input, modalManager } from '@immich/ui';
  import { mdiAccountMultipleOutline, mdiCameraIris, mdiChartPie, mdiFilterMinusOutline, mdiFolderOutline, mdiPlayCircle } from '@mdi/js';
  import type { Snippet } from 'svelte';
  import { t } from 'svelte-i18n';
  import type { LayoutData } from './$types';

  type Props = {
    children?: Snippet;
    data: LayoutData;
  };

  const { children, data }: Props = $props();

  const photosPromise = $derived(data.statisticsPromise.then((stats) => ({ value: stats.photos })));

  const videosPromise = $derived(data.statisticsPromise.then((stats) => ({ value: stats.videos })));

  const usagePromise = $derived(
    data.statisticsPromise.then((stats) => {
      const [value, unit] = getBytesWithUnit(stats.usage);
      return { value, unit };
    }),
  );

  const library = $derived(data.library);

  const onLibraryUpdate = () => invalidate('app:library');

  const onLibraryDelete = async ({ id }: { id: string }) => {
    if (id === library.id) {
      await goto(Route.libraries());
    }
  };

  const { Edit, Delete, AddFolder, AddExclusionPattern, Scan } = $derived(getLibraryActions($t, library));
  let uploadPath = $state('');
  const saveUploadPath = async () => {
    if (await handleUpdateLibrary(library, { uploadPath: uploadPath.trim() || null })) {
      await invalidate('app:library');
    }
  };
</script>

<OnEvents {onLibraryUpdate} {onLibraryDelete} />

<CommandPaletteDefaultProvider name={$t('library')} actions={[Edit, Delete, AddFolder, AddExclusionPattern, Scan]} />

<AdminPageLayout
  breadcrumbs={[{ title: $t('external_libraries'), href: Route.libraries() }, { title: library.name }]}
  actions={[Scan, Edit, Delete]}
>
  <Container size="large" center>
    <div class="grid w-full grid-cols-1 gap-4 lg:grid-cols-2">
      <Heading tag="h1" size="large" class="col-span-full my-4">{library.name}</Heading>
      <div class="col-span-full flex flex-col gap-4 lg:flex-row">
        <ServerStatisticsCard icon={mdiCameraIris} title={$t('photos')} valuePromise={photosPromise} />
        <ServerStatisticsCard icon={mdiPlayCircle} title={$t('videos')} valuePromise={videosPromise} />
        <ServerStatisticsCard icon={mdiChartPie} title={$t('usage')} valuePromise={usagePromise} />
      </div>

      <AdminCard icon={mdiFolderOutline} title={$t('folders')} headerAction={AddFolder}>
        {#if library.importPaths.length === 0}
          <EmptyPlaceholder
            src={emptyFoldersUrl}
            text={$t('admin.library_folder_description')}
            fullWidth
            onClick={() => modalManager.show(LibraryFolderAddModal, { library })}
          />
        {:else}
          <table class="w-full">
            <tbody>
              {#each library.importPaths as folder (folder)}
                {@const { Edit, Delete } = getLibraryFolderActions($t, library, folder)}
                <tr class="h-12">
                  <td>
                    <Code>{folder}</Code>
                  </td>
                  <td class="flex justify-end gap-2">
                    <TableButton action={Edit} />
                    <TableButton action={Delete} />
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        {/if}
      </AdminCard>

      <AdminCard icon={mdiFilterMinusOutline} title={$t('exclusion_pattern')} headerAction={AddExclusionPattern}>
        <table class="w-full">
          <tbody>
            {#each library.exclusionPatterns as exclusionPattern (exclusionPattern)}
              {@const { Edit, Delete } = getLibraryExclusionPatternActions($t, library, exclusionPattern)}
              <tr class="h-12">
                <td>
                  <Code>{exclusionPattern}</Code>
                </td>
                <td class="flex justify-end gap-2">
                  <TableButton action={Edit} />
                  <TableButton action={Delete} />
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </AdminCard>

      <AdminCard icon={mdiAccountMultipleOutline} title={$t('shared_library_members')}>
        <div class="flex items-center justify-between gap-4"><p class="text-sm text-gray-500">{$t('external_library_members_description')}</p><Button size="small" onclick={() => modalManager.show(LibraryMembersModal, { libraryId: library.id })}>{$t('add')}</Button></div>
      </AdminCard>

      <AdminCard icon={mdiFolderOutline} title={$t('upload_path')}>
        <div class="flex gap-2"><Field label={$t('upload_path')} class="grow"><Input bind:value={uploadPath} placeholder="/library/import/upload" /></Field><Button class="self-end" size="small" onclick={saveUploadPath}>{$t('save')}</Button></div>
        <p class="mt-2 text-xs text-gray-500">{$t('upload_path_description')}</p>
      </AdminCard>
    </div>
    {@render children?.()}
  </Container>
</AdminPageLayout>
