// Heirloom Web V2 — settings capability specs (WP9 slice 3, WP1 §8).
//
// Lock the working-vs-unavailable contract: every unavailable row carries an
// explanation, and an editable server URL never appears as a working control.

import { describe, expect, it } from 'vitest';
import {
  parseV2UploadTarget,
  resolveV2ImportDestination,
  V2_SETTINGS_CAPABILITIES,
} from './settings-capabilities';

describe('V2_SETTINGS_CAPABILITIES', () => {
  it('marks account, upload, timeline-source, and pending-upload rows working', () => {
    for (const id of [
      'account-server',
      'account-user',
      'account-logout',
      'uploads-default-target',
      'uploads-import-destination',
      'timeline-personal',
      'timeline-spaces',
    ]) {
      expect(V2_SETTINGS_CAPABILITIES.find((row) => row.id === id)?.status).toBe('working');
    }
  });

  it('explains every unavailable row (no inert controls)', () => {
    const unavailable = V2_SETTINGS_CAPABILITIES.filter((row) => row.status === 'unavailable');
    expect(unavailable.length).toBeGreaterThan(0);
    for (const row of unavailable) {
      expect(row.explanation, row.id).toBeTruthy();
    }
  });

  it('forbids an editable server URL: server-URL editing is unavailable-with-explanation', () => {
    const row = V2_SETTINGS_CAPABILITIES.find((candidate) => candidate.id === 'server-url-edit');
    expect(row?.status).toBe('unavailable');
    expect(row?.explanation).toBeTruthy();
  });

  it('never marks server-URL editing working under any id or label', () => {
    const offenders = V2_SETTINGS_CAPABILITIES.filter(
      (row) =>
        row.status === 'working' &&
        /server.*url|url.*server|change.*server/i.test(`${row.id} ${row.label}`),
    );
    expect(offenders).toEqual([]);
  });

  it('covers cache budget and the background agent as unavailable-with-explanation', () => {
    expect(V2_SETTINGS_CAPABILITIES.find((row) => row.id === 'cache-budget')?.status).toBe('unavailable');
    expect(V2_SETTINGS_CAPABILITIES.find((row) => row.id === 'background-agent')?.status).toBe(
      'unavailable',
    );
  });
});

describe('resolveV2ImportDestination', () => {
  it('follows the upload target when set to default', () => {
    expect(resolveV2ImportDestination('space:abc', 'default')).toBe('space:abc');
    expect(resolveV2ImportDestination('personal', 'default')).toBe('personal');
  });

  it('prefers an explicit import destination', () => {
    expect(resolveV2ImportDestination('space:abc', 'personal')).toBe('personal');
  });
});

describe('parseV2UploadTarget', () => {
  it('accepts personal and space targets', () => {
    expect(parseV2UploadTarget('personal')).toBe('personal');
    expect(parseV2UploadTarget('space:abc')).toBe('space:abc');
  });

  it('falls back to personal for missing or malformed values', () => {
    expect(parseV2UploadTarget(null)).toBe('personal');
    expect(parseV2UploadTarget('library:xyz')).toBe('personal');
    expect(parseV2UploadTarget('space:')).toBe('personal');
  });
});
