import { redirect } from '@sveltejs/kit';

/** `/v2` redirects to `/v2/library` (PLAN §2). */
export const load = () => {
  throw redirect(307, '/v2/library');
};
