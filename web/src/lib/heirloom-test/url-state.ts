/**
 * V2 URL-state test helpers (WP3 harness).
 * Builders construct raw V2 URLs for tests; the vectors table encodes the
 * PLAN section 9 contract (source/group/zoom, precedence, normalization)
 * as input/expected data — NOT as a product implementation. The WP4 product
 * code must satisfy these vectors; its own spec asserts them.
 */

export type V2SourceParam = `all` | `personal` | `space:${string}` | `library:${string}`;
export type V2GroupParam = 'years' | 'months' | 'all';

export interface V2LibraryState {
  source?: string;
  group?: string;
  zoom?: string;
}

const V2_SOURCE_RE = /^(all|personal|space:[0-9a-f-]{36}|library:[0-9a-f-]{36})$/i;
const V2_GROUPS: readonly string[] = ['years', 'months', 'all'];
const ZOOM_MIN = 64;
const ZOOM_MAX = 300;

/** Build a V2 library URL from raw param strings (no validation — pass anything). */
export function buildV2LibraryUrl(state: V2LibraryState = {}): string {
  const params = new URLSearchParams();
  if (state.source !== undefined) {
    params.set('source', state.source);
  }
  if (state.group !== undefined) {
    params.set('group', state.group);
  }
  if (state.zoom !== undefined) {
    params.set('zoom', state.zoom);
  }
  const query = params.toString();
  return query ? `/v2/library?${query}` : '/v2/library';
}

export interface NormalizationVector {
  name: string;
  input: V2LibraryState;
  /** Expected normalized params after product-code normalization. */
  expected: Required<V2LibraryState>;
}

/**
 * Contract vectors (PLAN section 9):
 * - valid URL state wins over preferences; invalid values normalize, never reload-loop;
 * - zoom clamps to [64, 300] integers; unknown source/group fall back (product picks
 *   preference-then-default — vectors assert only the "falls back" shape via `fallsBack: true`).
 */
export interface FallbackVector {
  name: string;
  input: V2LibraryState;
  fallsBack: true;
}

export const V2_NORMALIZATION_VECTORS: NormalizationVector[] = [
  {
    name: 'zoom below minimum clamps to 64',
    input: { zoom: '10' },
    expected: { source: 'all', group: 'months', zoom: '64' },
  },
  {
    name: 'zoom above maximum clamps to 300',
    input: { zoom: '999' },
    expected: { source: 'all', group: 'months', zoom: '300' },
  },
  {
    name: 'non-integer zoom normalizes (floor to integer)',
    input: { zoom: '128.7' },
    expected: { source: 'all', group: 'months', zoom: '128' },
  },
  {
    name: 'non-numeric zoom normalizes to default',
    input: { zoom: 'huge' },
    expected: { source: 'all', group: 'months', zoom: '128' },
  },
  {
    name: 'canonical valid state is preserved exactly',
    input: { source: 'personal', group: 'years', zoom: '200' },
    expected: { source: 'personal', group: 'years', zoom: '200' },
  },
  {
    name: 'space source with valid uuid is preserved',
    input: { source: 'space:00000000-0000-4000-8000-000000000001', group: 'all', zoom: '64' },
    expected: { source: 'space:00000000-0000-4000-8000-000000000001', group: 'all', zoom: '64' },
  },
];

export const V2_FALLBACK_VECTORS: FallbackVector[] = [
  { name: 'unknown source falls back (preference, else default)', input: { source: 'nebula' }, fallsBack: true },
  { name: 'malformed space source falls back', input: { source: 'space:not-a-uuid' }, fallsBack: true },
  { name: 'unknown group falls back', input: { group: 'decades' }, fallsBack: true },
  { name: 'empty params fall back entirely', input: {}, fallsBack: true },
];

export function isValidV2Source(value: string): boolean {
  return V2_SOURCE_RE.test(value);
}

export function isValidV2Group(value: string): boolean {
  return V2_GROUPS.includes(value);
}

/** Clamp helper for tests to compute expected zoom (mirrors contract, not product code). */
export function clampV2Zoom(value: number): number {
  if (!Number.isFinite(value)) {
    return 128;
  }
  return Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, Math.floor(value)));
}
