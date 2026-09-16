import { authenticate } from '$lib/utils/auth';
import { getFormatter } from '$lib/utils/i18n';
import { getAllPeople } from '@immich/sdk';
import type { PageLoad } from './$types';

export const load = (async ({ url }) => {
  await authenticate(url);
  const $t = await getFormatter();

  // Same composition as the classic people page; failures surface as an
  // inline error state instead of throwing.
  try {
    const people = await getAllPeople({ withHidden: true });
    return { people, loadError: null as 'errors.failed_to_load_people' | null, meta: { title: $t('people') } };
  } catch {
    return { people: null, loadError: 'errors.failed_to_load_people', meta: { title: $t('people') } };
  }
}) satisfies PageLoad;
