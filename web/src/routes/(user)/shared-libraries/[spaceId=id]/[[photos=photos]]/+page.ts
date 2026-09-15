import * as sdk from '@immich/sdk';
import { authenticate } from '$lib/utils/auth';
import type { PageLoad } from './$types';

export const load = (async ({ params, url, depends }) => {
  await authenticate(url);
  depends('shared-space:data');
  const space = await sdk.getSharedSpacesById({ id: params.spaceId });
  return { space, meta: { title: space.name } };
}) satisfies PageLoad;
