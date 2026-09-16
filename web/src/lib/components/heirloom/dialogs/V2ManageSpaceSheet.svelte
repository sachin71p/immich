<!-- Heirloom Web V2 — Manage Shared Library sheet (WP7, WP1 §6: 360 wide,
  title = space name; Name/Description + Save; member rows with role
  secondary + link-style Remove except self; add-member field + Add disabled
  when empty; Leave (contributor only) / Delete Library (owner only); Done).
  Service reuse (same contracts as the classic space page + members modal):
  sdk.update + sharedSpaces.upsert, sdk.getMembers2/addMembers2/removeMember2,
  sdk.searchUsers, leave via sdk.getMyUser + removeMember2 + sharedSpaces.remove,
  delete via sdk.deleteSharedSpacesById + sharedSpaces.remove. Role-gating via
  sheet-logic (describeSpacePermissions/decideRemoveMember); role-restricted
  controls are absent-or-disabled, never inert.
-->
<script lang="ts">
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { handleError } from '$lib/utils/handle-error';
  import { normalizeSearchString } from '$lib/utils/string-utils';
  import {
    addMembers2,
    deleteSharedSpacesById,
    getMembers2,
    getMyUser,
    removeMember2,
    searchUsers,
    SharedSpaceRole,
    update,
    type SharedSpaceMemberResponseDto,
    type SharedSpaceResponseDto,
    type UserResponseDto,
  } from '@immich/sdk';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import V2ConfirmSheet from './V2ConfirmSheet.svelte';
  import V2Sheet from './V2Sheet.svelte';
  import {
    decideRemoveMember,
    describeSpacePermissions,
    isSheetNameValid,
    SHEET_WIDTHS,
    validateSheetName,
  } from './sheet-logic';

  interface Props {
    space: SharedSpaceResponseDto;
    onClose: () => void;
    onUpdated?: (space: SharedSpaceResponseDto) => void;
    onLeft?: (spaceId: string) => void;
    onDeleted?: (spaceId: string) => void;
  }

  let { space, onClose, onUpdated, onLeft, onDeleted }: Props = $props();

  let name = $state(space.name);
  let description = $state(space.description ?? '');
  let attemptedSave = $state(false);
  let saving = $state(false);

  let members: SharedSpaceMemberResponseDto[] = $state([]);
  let users: UserResponseDto[] = $state([]);
  let membersLoading = $state(true);
  let search = $state('');
  let selectedIds: string[] = $state([]);
  let adding = $state(false);
  let error: string | null = $state(null);

  /** 'leave' | 'delete' | null — which destructive confirm is showing. */
  let confirming: 'leave' | 'delete' | null = $state(null);

  const myUserId = $derived(authManager.authenticated ? authManager.user.id : '');
  const permissions = $derived(describeSpacePermissions(space.role));
  const nameError = $derived(attemptedSave && validateSheetName(name) ? $t('name_required') : error);

  const memberIds = $derived(new Set(members.map(({ userId }) => userId)));
  const candidates = $derived(
    users
      .filter(
        (user) =>
          !memberIds.has(user.id) && normalizeSearchString(user.name).includes(normalizeSearchString(search)),
      )
      .toSorted((a, b) => a.name.localeCompare(b.name)),
  );

  const roleLabel = (role: SharedSpaceRole): string =>
    role === SharedSpaceRole.Owner ? $t('owner') : role;

  onMount(async () => {
    try {
      const [allUsers, spaceMembers] = await Promise.all([searchUsers(), getMembers2({ id: space.id })]);
      users = allUsers;
      members = spaceMembers;
    } catch (error_) {
      error = error_ instanceof Error ? error_.message : $t('errors.something_went_wrong');
      handleError(error_, $t('errors.something_went_wrong'));
    } finally {
      membersLoading = false;
    }
  });

  const save = async () => {
    attemptedSave = true;
    if (!isSheetNameValid(name) || saving || !permissions.canEditDetails) {
      return;
    }
    saving = true;
    try {
      const updated = await update({
        id: space.id,
        sharedSpaceUpdateDto: { name: name.trim(), description: description.trim() },
      });
      space = updated;
      sharedSpaces.upsert(updated);
      onUpdated?.(updated);
    } catch (error_) {
      handleError(error_, $t('errors.something_went_wrong'));
    } finally {
      saving = false;
    }
  };

  const toggleCandidate = (userId: string) => {
    selectedIds = selectedIds.includes(userId)
      ? selectedIds.filter((id) => id !== userId)
      : [...selectedIds, userId];
  };

  const addSelected = async () => {
    if (selectedIds.length === 0 || adding || !permissions.canAddMembers) {
      return;
    }
    adding = true;
    try {
      await addMembers2({ id: space.id, sharedSpaceMembersDto: { userIds: selectedIds } });
      await sharedSpaces.refresh();
      members = await getMembers2({ id: space.id });
      selectedIds = [];
    } catch (error_) {
      handleError(error_, $t('errors.something_went_wrong'));
    } finally {
      adding = false;
    }
  };

  const removeMember = async (userId: string) => {
    const decision = decideRemoveMember(space.role, userId, myUserId);
    if (!decision.allowed) {
      return;
    }
    try {
      await removeMember2({ id: space.id, userId });
      members = members.filter((member) => member.userId !== userId);
      await sharedSpaces.refresh();
    } catch (error_) {
      handleError(error_, $t('errors.something_went_wrong'));
    }
  };

  const leave = async () => {
    const me = await getMyUser();
    await removeMember2({ id: space.id, userId: me.id });
    sharedSpaces.remove(space.id);
    onLeft?.(space.id);
    onClose();
  };

  const remove = async () => {
    await deleteSharedSpacesById({ id: space.id });
    sharedSpaces.remove(space.id);
    onDeleted?.(space.id);
    onClose();
  };
</script>

{#if confirming === 'leave'}
  <V2ConfirmSheet
    title={$t('leave_shared_library')}
    body={$t('leave_shared_library_description')}
    confirmLabel={$t('leave')}
    tone="danger"
    onClose={(confirmed) => {
      confirming = null;
      if (confirmed) {
        void leave().catch((error) => handleError(error, $t('errors.something_went_wrong')));
      }
    }}
  />
{:else if confirming === 'delete'}
  <V2ConfirmSheet
    title={$t('delete_shared_library')}
    body={$t('delete_shared_library_description')}
    confirmLabel={$t('delete')}
    tone="danger"
    onClose={(confirmed) => {
      confirming = null;
      if (confirmed) {
        void remove().catch((error) => handleError(error, $t('errors.something_went_wrong')));
      }
    }}
  />
{:else}
  <V2Sheet title={space.name} width={SHEET_WIDTHS.manageSpace} error={nameError} {onClose}>
    <section aria-label={$t('description')}>
      <label class="v2-field-label" for="v2-manage-space-name">{$t('name')}</label>
      <input
        id="v2-manage-space-name"
        class="v2-input"
        data-autofocus
        autocomplete="off"
        bind:value={name}
        disabled={!permissions.canEditDetails}
      />
      <div style="margin-top: 12px">
        <label class="v2-field-label" for="v2-manage-space-description">{$t('description')}</label>
        <textarea
          id="v2-manage-space-description"
          class="v2-textarea"
          rows="2"
          bind:value={description}
          disabled={!permissions.canEditDetails}
        ></textarea>
      </div>
      {#if permissions.canEditDetails}
        <div style="margin-top: 8px">
          <button type="button" class="v2-btn" disabled={!isSheetNameValid(name) || saving} onclick={() => void save()}>
            {$t('save')}
          </button>
        </div>
      {/if}
    </section>

    <section aria-label={$t('shared_library_members')}>
      <h3 class="v2-field-label">{$t('shared_library_members')}</h3>
      {#if membersLoading}
        <p class="v2-helper">{$t('loading')}</p>
      {:else if members.length === 0}
        <p class="v2-helper">{$t('no_users_available')}</p>
      {:else}
        <ul style="list-style: none; margin: 0; padding: 0">
          {#each members as member (member.userId)}
            {@const removal = decideRemoveMember(space.role, member.userId, myUserId)}
            <li style="display: flex; align-items: center; gap: 8px; padding: 4px 0">
              <span class="v2-row-title">{member.userId}</span>
              <span class="v2-row-sub">{roleLabel(member.role)}</span>
              <span style="flex: 1"></span>
              {#if removal.allowed}
                <button type="button" class="v2-link-btn" onclick={() => void removeMember(member.userId)}>
                  {$t('remove')}
                </button>
              {/if}
            </li>
          {/each}
        </ul>
      {/if}

      {#if permissions.canAddMembers}
        <div style="margin-top: 8px">
          <label class="v2-field-label" for="v2-manage-space-search">{$t('add')}</label>
          <input
            id="v2-manage-space-search"
            class="v2-input"
            autocomplete="off"
            placeholder={$t('search')}
            bind:value={search}
          />
          {#if candidates.length > 0}
            <div class="v2-sheet-list" style="margin-top: 8px; max-height: 160px" role="listbox" aria-label={$t('search')}>
              {#each candidates as user (user.id)}
                <button
                  type="button"
                  role="option"
                  aria-selected={selectedIds.includes(user.id)}
                  class="v2-row-btn"
                  onclick={() => toggleCandidate(user.id)}
                >
                  <span class="v2-row-title">{user.name}</span>
                  <span class="v2-row-sub">{user.email}</span>
                </button>
              {/each}
            </div>
          {/if}
          <div style="margin-top: 8px">
            <button type="button" class="v2-btn" disabled={selectedIds.length === 0 || adding} onclick={() => void addSelected()}>
              {$t('add')}
            </button>
          </div>
        </div>
      {/if}
    </section>

    {#snippet footer()}
      {#if permissions.canDelete}
        <button type="button" class="v2-btn v2-btn-ghost-danger" onclick={() => (confirming = 'delete')}>
          {$t('delete_library')}
        </button>
      {:else if permissions.canLeave}
        <button type="button" class="v2-btn" onclick={() => (confirming = 'leave')}>
          {$t('leave')}
        </button>
      {/if}
      <button type="button" class="v2-btn v2-btn-primary" onclick={onClose}>{$t('done')}</button>
    {/snippet}
  </V2Sheet>
{/if}
