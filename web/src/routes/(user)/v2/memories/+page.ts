import { memoryManager } from '$lib/managers/memory-manager.svelte';
import { authenticate } from '$lib/utils/auth';
import { getFormatter } from '$lib/utils/i18n';
import type { PageLoad } from './$types';

export const load = (async ({ url }) => {
  const user = await authenticate(url);
  const $t = await getFormatter();

  // Same composition as the classic memories page; failures surface as an
  // inline error state instead of throwing.
  try {
    await memoryManager.applyPreferences();
    return { user, loadError: null as string | null, meta: { title: $t('memories') } };
  } catch {
    return { user, loadError: 'errors.failed_to_load_memories', meta: { title: $t('memories') } };
  }
}) satisfies PageLoad;
