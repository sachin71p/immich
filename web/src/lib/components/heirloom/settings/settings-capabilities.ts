// Heirloom Web V2 — settings capability contract (WP9 slice 3, WP1 §8).
//
// Working-vs-unavailable decisions for `/v2/settings`. PLAN §2 forbids inert
// controls, so every row is either backed by a real browser implementation or
// carries an explicit explanation. In particular there is NO editable server
// URL row: the app is same-origin authenticated (native shows it read-only
// too), and the spec below locks that in.

/** Presentation status of a settings row. */
export type V2SettingsStatus = 'working' | 'unavailable';

export interface V2SettingsCapability {
  /** Stable id used by the page and tests. */
  id: string;
  /** Native section label (MacSettingsView). */
  label: string;
  status: V2SettingsStatus;
  /** Required when `unavailable`: the explanation rendered with the row. */
  explanation?: string;
}

/**
 * Capability table in native section order (MacSettingsView: Account,
 * Uploads, Timeline Sources, Cache & Offline, Uploads in Flight, Background
 * Agent). Working rows name the web implementation; unavailable rows explain
 * why instead of rendering a control that appears functional.
 */
export const V2_SETTINGS_CAPABILITIES: readonly V2SettingsCapability[] = [
  { id: 'account-server', label: 'Server', status: 'working' },
  { id: 'account-user', label: 'User', status: 'working' },
  { id: 'account-logout', label: 'Log Out', status: 'working' },
  { id: 'uploads-default-target', label: 'Default upload target', status: 'working' },
  { id: 'uploads-import-destination', label: 'Import destination', status: 'working' },
  { id: 'timeline-personal', label: 'Show personal library', status: 'working' },
  { id: 'timeline-spaces', label: 'Timeline spaces', status: 'working' },
  {
    id: 'server-url-edit',
    label: 'Change server URL',
    status: 'unavailable',
    explanation:
      'The browser app is served by, and authenticated against, this server. ' +
      'Changing servers means signing in elsewhere — use Log Out, then sign in at the other address.',
  },
  {
    id: 'cache-budget',
    label: 'Cache budget and offline pins',
    status: 'unavailable',
    explanation:
      'The browser manages its own storage quota; there is no separate Heirloom cache to budget or purge. ' +
      'Current origin usage is shown where the browser reports it.',
  },
  {
    id: 'background-agent',
    label: 'Sync in the background',
    status: 'unavailable',
    explanation:
      'Background sync needs a native login-item helper (SMAppService), which browsers cannot install. ' +
      'Uploads progress while this tab is open.',
  },
];

/** V2-only preference keys. Never touch classic keys (PLAN §9 rule 6). */
export const V2_UPLOAD_TARGET_KEY = 'heirloom-v2-upload-target';
export const V2_IMPORT_DESTINATION_KEY = 'heirloom-v2-import-destination';

/** Upload target vocabulary: personal library or a member space id. */
export type V2UploadTarget = 'personal' | `space:${string}`;

/**
 * Resolve the effective import destination: an explicit choice wins, `default`
 * follows the default upload target (native "Follow default upload target").
 */
export const resolveV2ImportDestination = (
  uploadTarget: V2UploadTarget,
  importDestination: 'default' | V2UploadTarget,
): V2UploadTarget => (importDestination === 'default' ? uploadTarget : importDestination);

/** Parse a persisted upload-target value; unknown input falls back to personal. */
export const parseV2UploadTarget = (raw: string | null): V2UploadTarget => {
  if (raw === 'personal') {
    return 'personal';
  }
  if (raw?.startsWith('space:') && raw.length > 'space:'.length) {
    return raw as V2UploadTarget;
  }
  return 'personal';
};
