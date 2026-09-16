// WP6 — internal drag payload + drop-target permission matrix specs.
import { describe, expect, it } from 'vitest';
import {
  decideAssetDrop,
  decodeHeirloomDragPayload,
  encodeHeirloomDragPayload,
  hasFilePayload,
  hasHeirloomPayload,
  HEIRLOOM_ASSET_MIME,
  type HeirloomDragPayload,
  type HeirloomDropTarget,
} from './drag-drop';

const payload = (overrides: Partial<HeirloomDragPayload> = {}): HeirloomDragPayload => ({
  version: 1,
  assetIds: ['a1', 'a2'],
  ownerIds: ['u1', 'u1'],
  source: { type: 'personal' },
  ...overrides,
});

const spaceTarget = (id = 's1'): HeirloomDropTarget => ({ kind: 'space', id, name: 'Space' });
const libraryTarget = (hasUploadPath = true): HeirloomDropTarget => ({
  kind: 'library',
  id: 'l1',
  name: 'Library',
  hasUploadPath,
});

describe('heirloom drag payload', () => {
  it('round-trips through encode/decode', () => {
    const raw = encodeHeirloomDragPayload(payload());
    expect(decodeHeirloomDragPayload(raw)).toEqual(payload());
  });

  it('rejects missing, malformed, versioned, and empty payloads', () => {
    expect(decodeHeirloomDragPayload(null)).toBeNull();
    expect(decodeHeirloomDragPayload(undefined)).toBeNull();
    expect(decodeHeirloomDragPayload('')).toBeNull();
    expect(decodeHeirloomDragPayload('not-json')).toBeNull();
    expect(decodeHeirloomDragPayload(JSON.stringify({ version: 2, assetIds: ['a'], ownerIds: [], source: { type: 'personal' } }))).toBeNull();
    expect(decodeHeirloomDragPayload(JSON.stringify(payload({ assetIds: [] })))).toBeNull();
    expect(decodeHeirloomDragPayload(JSON.stringify(payload({ source: { type: 'space', id: '' } })))).toBeNull();
    expect(decodeHeirloomDragPayload(JSON.stringify(payload({ source: { type: 'bogus' } as never })))).toBeNull();
  });

  it('detects internal vs file drag types independently', () => {
    expect(hasHeirloomPayload([HEIRLOOM_ASSET_MIME])).toBe(true);
    expect(hasHeirloomPayload(['Files'])).toBe(false);
    expect(hasFilePayload(['Files'])).toBe(true);
    expect(hasFilePayload([HEIRLOOM_ASSET_MIME])).toBe(false);
    expect(hasHeirloomPayload([HEIRLOOM_ASSET_MIME, 'Files'])).toBe(true);
  });
});

describe('drop-target permission matrix', () => {
  const personalTargets = [{ type: 'personal' } as const];
  const spaceTargets = [{ type: 'space', id: 's1', name: 'Space' } as const];
  const libraryTargets = [{ type: 'library', id: 'l1', name: 'Library' } as const];

  it('allows album drops as add (except onto the same album)', () => {
    const album: HeirloomDropTarget = { kind: 'album', id: 'al1', name: 'Album' };
    expect(decideAssetDrop(payload(), album, []).reason).toBe('album-add');
    expect(decideAssetDrop(payload(), album, []).allowed).toBe(true);
    const same = payload({ source: { type: 'album', id: 'al1' } });
    expect(decideAssetDrop(same, album, [])).toEqual({ allowed: false, reason: 'same-container-noop' });
  });

  it('allows move drops only for targets in the allow-list', () => {
    expect(decideAssetDrop(payload({ source: { type: 'space', id: 's9' } }), spaceTarget(), spaceTargets)).toEqual({
      allowed: true,
      reason: 'move-allowed',
    });
    expect(decideAssetDrop(payload(), spaceTarget('s2'), spaceTargets)).toEqual({
      allowed: false,
      reason: 'target-not-permitted',
    });
    expect(
      decideAssetDrop(payload({ source: { type: 'space', id: 's9' } }), { kind: 'personal' }, []),
    ).toEqual({
      allowed: false,
      reason: 'target-not-permitted',
    });
    expect(
      decideAssetDrop(payload({ source: { type: 'space', id: 's9' } }), { kind: 'personal' }, personalTargets),
    ).toEqual({ allowed: true, reason: 'move-allowed' });
  });

  it('rejects drops back onto the source container as noops', () => {
    const fromSpace = payload({ source: { type: 'space', id: 's1' } });
    expect(decideAssetDrop(fromSpace, spaceTarget(), spaceTargets)).toEqual({
      allowed: false,
      reason: 'same-container-noop',
    });
    expect(decideAssetDrop(payload(), { kind: 'personal' }, personalTargets)).toEqual({
      allowed: false,
      reason: 'same-container-noop',
    });
  });

  it('rejects libraries without an upload path even when listed', () => {
    expect(decideAssetDrop(payload(), libraryTarget(false), libraryTargets)).toEqual({
      allowed: false,
      reason: 'library-missing-upload-path',
    });
    expect(decideAssetDrop(payload(), libraryTarget(true), libraryTargets).allowed).toBe(true);
  });

  it('rejects null or empty payloads', () => {
    expect(decideAssetDrop(null, spaceTarget(), spaceTargets)).toEqual({ allowed: false, reason: 'empty-selection' });
  });
});
