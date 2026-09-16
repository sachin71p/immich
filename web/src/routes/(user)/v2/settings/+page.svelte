<!-- Heirloom Web V2 — settings (WP9 slice 3, WP1 §8).
  Native section order (MacSettingsView): Account, Uploads, Timeline Sources,
  Cache & Offline, Uploads in Flight, Background Agent. Every row is either
  backed by a real browser implementation or carries an explicit explanation
  (PLAN §2: no inert controls; the capability table in
  `settings-capabilities.ts` locks this contract and its spec forbids an
  editable server URL). Preferences use V2-only keys and never touch classic
  keys (PLAN §9 rule 6). -->
<script lang="ts">
  import V2SettingsSection from '$lib/components/heirloom/settings/V2SettingsSection.svelte';
  import {
    parseV2UploadTarget,
    V2_IMPORT_DESTINATION_KEY,
    V2_SETTINGS_CAPABILITIES,
    V2_UPLOAD_TARGET_KEY,
    type V2UploadTarget,
  } from '$lib/components/heirloom/settings/settings-capabilities';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { sharedSpaces } from '$lib/stores/shared-spaces.svelte';
  import { uploadAssetsStore } from '$lib/stores/upload';
  import { openFileUploadDialog } from '$lib/utils/file-uploader';
  import { handleError } from '$lib/utils/handle-error';
  import { PersistedLocalStorage } from '$lib/utils/persisted';
  import { getBaseUrl, updateMySpaceTimeline } from '@immich/sdk';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  const uploadTargetPref = new PersistedLocalStorage<string>(V2_UPLOAD_TARGET_KEY, 'personal');
  const importDestinationPref = new PersistedLocalStorage<string>(V2_IMPORT_DESTINATION_KEY, 'default');

  let uploadTarget = $state<V2UploadTarget>('personal');
  let importDestination = $state<'default' | V2UploadTarget>('default');
  let storageUsage = $state<string | null>(null);

  const pendingUploads = uploadAssetsStore.remainingUploads;

  const explanation = (id: string): string =>
    V2_SETTINGS_CAPABILITIES.find((row) => row.id === id)?.explanation ?? '';

  onMount(() => {
    uploadTarget = parseV2UploadTarget(uploadTargetPref.current);
    const rawImport = importDestinationPref.current;
    importDestination = rawImport === 'default' ? 'default' : parseV2UploadTarget(rawImport);
    void sharedSpaces.ensureLoaded().catch(() => undefined);
    void loadStorageUsage();
  });

  const loadStorageUsage = async () => {
    try {
      const estimate = await navigator.storage?.estimate?.();
      if (estimate?.usage !== undefined) {
        const megabytes = estimate.usage / 1_048_576;
        storageUsage =
          megabytes < 1024
            ? `${megabytes.toFixed(1)} MB`
            : `${(megabytes / 1024).toFixed(2)} GB`;
      }
    } catch {
      storageUsage = null;
    }
  };

  const saveUploadTarget = (value: string) => {
    uploadTarget = parseV2UploadTarget(value);
    uploadTargetPref.current = uploadTarget;
  };

  const saveImportDestination = (value: string) => {
    importDestination = value === 'default' ? 'default' : parseV2UploadTarget(value);
    importDestinationPref.current = importDestination;
  };

  const toggleSpaceTimeline = async (spaceId: string, showInTimeline: boolean) => {
    try {
      const updated = await updateMySpaceTimeline({ id: spaceId, sharedSpaceTimelineDto: { showInTimeline } });
      sharedSpaces.upsert(updated);
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    }
  };

  const uploadNow = () => {
    const spaceId = uploadTarget.startsWith('space:') ? uploadTarget.slice('space:'.length) : undefined;
    void openFileUploadDialog(spaceId ? { spaceId } : {});
  };
</script>

<div data-testid="v2-settings">
  <V2SettingsSection title="Account">
    <p data-testid="v2-settings-server">
      <span>Server</span>
      <span>{getBaseUrl() || 'This server (same origin)'}</span>
    </p>
    {#if authManager.authenticated}
      <p data-testid="v2-settings-user">
        <span>User</span>
        <span>{authManager.user.email}</span>
      </p>
    {/if}
    <button type="button" data-testid="v2-settings-logout" onclick={() => void authManager.logout()}>
      Log Out
    </button>
    <p data-testid="v2-settings-server-edit-note">{explanation('server-url-edit')}</p>
  </V2SettingsSection>

  <V2SettingsSection title="Uploads">
    <label>
      <span>Default upload target</span>
      <select
        data-testid="v2-settings-upload-target"
        value={uploadTarget}
        onchange={(event) => saveUploadTarget(event.currentTarget.value)}
      >
        <option value="personal">Personal Library</option>
        {#each sharedSpaces.spaces as space (space.id)}
          <option value={`space:${space.id}`}>{space.name}</option>
        {/each}
      </select>
    </label>
    <label>
      <span>Import destination</span>
      <select
        data-testid="v2-settings-import-destination"
        value={importDestination}
        onchange={(event) => saveImportDestination(event.currentTarget.value)}
      >
        <option value="default">Follow default upload target</option>
        <option value="personal">Personal Library</option>
        {#each sharedSpaces.spaces as space (space.id)}
          <option value={`space:${space.id}`}>{space.name}</option>
        {/each}
      </select>
    </label>
  </V2SettingsSection>

  <V2SettingsSection title="Timeline Sources">
    <p data-testid="v2-settings-personal-note">The Personal library is always included in the timeline.</p>
    {#each sharedSpaces.spaces as space (space.id)}
      <label>
        <input
          type="checkbox"
          data-testid={`v2-settings-space-${space.id}`}
          checked={space.showInTimeline}
          onchange={(event) => void toggleSpaceTimeline(space.id, event.currentTarget.checked)}
        />
        <span>{space.name}</span>
      </label>
    {/each}
    {#if sharedSpaces.libraries.length > 0}
      <p data-testid="v2-settings-libraries-note">
        External libraries appear under Shared External Libraries; per-library timeline toggles are not
        available in the browser.
      </p>
    {/if}
  </V2SettingsSection>

  <V2SettingsSection title="Cache & Offline">
    {#if storageUsage}
      <p data-testid="v2-settings-storage-usage">This origin uses {storageUsage} of browser storage.</p>
    {/if}
    <p data-testid="v2-settings-cache-note">{explanation('cache-budget')}</p>
  </V2SettingsSection>

  <V2SettingsSection title="Uploads in Flight">
    <p data-testid="v2-settings-pending-count">{$pendingUploads} pending uploads</p>
    <p>Uploads begin automatically while this tab is open.</p>
    <button type="button" data-testid="v2-settings-upload-now" onclick={uploadNow}>Upload Now</button>
  </V2SettingsSection>

  <V2SettingsSection title="Background Agent">
    <p data-testid="v2-settings-agent-note">{explanation('background-agent')}</p>
  </V2SettingsSection>
</div>
