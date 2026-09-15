import type { SharedLibraryResponseDto, SharedSpaceResponseDto } from '@immich/sdk';
import { computeMoveTargets } from '$lib/utils/move-targets';

const space = (id: string, name = id): SharedSpaceResponseDto =>
  ({ id, name, description: '', assetCount: 0, memberCount: 1, showInTimeline: true }) as SharedSpaceResponseDto;

const library = (id: string, hasUploadPath: boolean, name = id): SharedLibraryResponseDto =>
  ({ id, name, hasUploadPath, isOwner: true, assetCount: 0, showInTimeline: true }) as SharedLibraryResponseDto;

describe('computeMoveTargets', () => {
  it('includes personal only when every selected asset is owned by the acting user', () => {
    const targets = computeMoveTargets([{ ownerId: 'me' }, { ownerId: 'me' }], 'me', [], []);
    expect(targets).toEqual([{ type: 'personal' }]);
  });

  it('excludes personal when any selected asset belongs to someone else', () => {
    const targets = computeMoveTargets([{ ownerId: 'me' }, { ownerId: 'other' }], 'me', [], []);
    expect(targets).toEqual([]);
  });

  it('excludes personal for an empty selection', () => {
    expect(computeMoveTargets([], 'me', [], [])).toEqual([]);
  });

  it('includes every space the user is a member of', () => {
    const targets = computeMoveTargets([{ ownerId: 'other' }], 'me', [space('s1'), space('s2')], []);
    expect(targets).toEqual([
      { type: 'space', id: 's1', name: 's1' },
      { type: 'space', id: 's2', name: 's2' },
    ]);
  });

  it('includes only libraries with an upload path', () => {
    const targets = computeMoveTargets([{ ownerId: 'other' }], 'me', [], [library('l1', true), library('l2', false)]);
    expect(targets).toEqual([{ type: 'library', id: 'l1', name: 'l1' }]);
  });

  it('combines personal, spaces and libraries', () => {
    const targets = computeMoveTargets([{ ownerId: 'me' }], 'me', [space('s1')], [library('l1', true)]);
    expect(targets).toEqual([
      { type: 'personal' },
      { type: 'space', id: 's1', name: 's1' },
      { type: 'library', id: 'l1', name: 'l1' },
    ]);
  });
});
