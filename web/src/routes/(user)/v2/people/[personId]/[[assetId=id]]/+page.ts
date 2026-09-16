import { authenticate } from '$lib/utils/auth';
import { getFormatter } from '$lib/utils/i18n';
import { getPerson } from '@immich/sdk';
import { error } from '@sveltejs/kit';
import type { PageLoad } from './$types';

export const load = (async ({ url, params }) => {
  await authenticate(url);
  const $t = await getFormatter();

  try {
    const person = await getPerson({ id: params.personId });
    return { person, loadError: null as string | null, meta: { title: person.name || $t('people') } };
  } catch (error_) {
    if ((error_ as { status?: number })?.status === 404) {
      throw error(404, 'Person not found');
    }
    return { person: null, loadError: 'errors.failed_to_load_person', meta: { title: $t('people') } };
  }
}) satisfies PageLoad;
