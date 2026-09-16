// Heirloom Web V2 — URL-backed source/group/zoom state (PLAN §9).
//
// Precedence per field: valid URL param > V2-only saved preference > native
// default. Preferences use the `heirloom-v2-*` keys and never touch classic
// keys (`timeline-library-source`, …). Pure resolution lives in the
// lead-owned `url-state.ts` (read-only); this module binds it to navigation
// and `PersistedLocalStorage`.

import { goto } from '$app/navigation';
import { page } from '$app/state';
import { PersistedLocalStorage } from '$lib/utils/persisted';
import {
  resolveV2LibraryState,
  toV2SearchParams,
  V2_PREF_GROUP_KEY,
  V2_PREF_SOURCE_KEY,
  V2_PREF_ZOOM_KEY,
  type V2LibraryState,
} from './url-state';

const sourcePreference = new PersistedLocalStorage<string>(V2_PREF_SOURCE_KEY, 'all');
const groupPreference = new PersistedLocalStorage<string>(V2_PREF_GROUP_KEY, 'months');
const zoomPreference = new PersistedLocalStorage<number>(V2_PREF_ZOOM_KEY, 120);

const readPreferences = () => ({
  source: sourcePreference.current,
  group: groupPreference.current,
  zoom: zoomPreference.current,
});

const persistState = (state: V2LibraryState) => {
  sourcePreference.current = state.source;
  groupPreference.current = state.group;
  zoomPreference.current = state.zoom;
};

const currentState = (): V2LibraryState => resolveV2LibraryState(page.url.searchParams, readPreferences());

export const v2ViewState = {
  /** Effective state for the current URL (re-read on every access). */
  get current(): V2LibraryState {
    return currentState();
  },

  /**
   * Apply a partial update: persist V2 prefs, then replace the URL query
   * without a reload loop (serialization round-trips through the resolver).
   */
  async update(patch: Partial<V2LibraryState>): Promise<void> {
    const next: V2LibraryState = { ...currentState(), ...patch };
    persistState(next);
    const params = toV2SearchParams(next);
    await goto(`${page.url.pathname}?${params.toString()}`, { replaceState: true, noScroll: true });
  },

  /** Persist without navigating (e.g. remembering last-used state). */
  remember(state: V2LibraryState): void {
    persistState(state);
  },
};

export type { V2Group, V2LibraryState } from './url-state';
