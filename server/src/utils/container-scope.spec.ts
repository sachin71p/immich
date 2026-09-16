import { ForbiddenException } from '@nestjs/common';
import { vitest } from 'vitest';
import { UserMetadataKey } from 'src/enum.js';
import { ContainerScopeService } from 'src/utils/container-scope.js';
import { AuthFactory } from 'test/factories/auth.factory.js';

describe(ContainerScopeService.name, () => {
  const spaces = vitest.fn();
  const libraries = vitest.fn();
  const metadata = vitest.fn();
  const partners = { getAll: vitest.fn() };
  const members = vitest.fn();
  let sut: ContainerScopeService;

  beforeEach(() => {
    spaces.mockReset().mockResolvedValue([]);
    libraries.mockReset().mockResolvedValue([]);
    metadata.mockReset().mockResolvedValue([]);
    members.mockReset().mockResolvedValue(true);
    sut = new ContainerScopeService(
      { getMetadata: metadata } as never,
      partners as never,
      { getAll: spaces, isMember: members } as never,
      { getShared: libraries } as never,
    );
  });

  it('uses enabled personal, space, and library containers for the timeline', async () => {
    const auth = AuthFactory.create();
    spaces.mockResolvedValue([
      { id: 'space-on', showInTimeline: true },
      { id: 'space-off', showInTimeline: false },
    ]);
    libraries.mockResolvedValue([
      { id: 'library-owner', ownerId: auth.user.id, showInTimeline: null },
      { id: 'library-member', ownerId: 'other', showInTimeline: true },
      { id: 'library-hidden', ownerId: 'other', showInTimeline: false },
    ]);
    metadata.mockResolvedValue([
      { key: UserMetadataKey.Preferences, value: { sharedLibraries: { hiddenOwnedLibraryIds: ['library-owner'] } } },
    ]);

    await expect(sut.resolve(auth, { purpose: 'timeline' })).resolves.toEqual({
      personalUserIds: [auth.user.id],
      spaceIds: ['space-on'],
      libraryIds: ['library-member'],
    });
  });

  it('includes disabled member containers for management but no partners', async () => {
    const auth = AuthFactory.create();
    spaces.mockResolvedValue([{ id: 'space-off', showInTimeline: false }]);
    libraries.mockResolvedValue([{ id: 'library-off', ownerId: 'other', showInTimeline: false }]);

    await expect(sut.resolve(auth, { purpose: 'manage', withPartners: true })).resolves.toEqual({
      personalUserIds: [auth.user.id],
      spaceIds: ['space-off'],
      libraryIds: ['library-off'],
    });
  });

  it('keeps locked visibility personal', async () => {
    const auth = AuthFactory.create();
    await expect(sut.resolve(auth, { purpose: 'locked' })).resolves.toEqual({
      personalUserIds: [auth.user.id],
      spaceIds: [],
      libraryIds: [],
    });
  });

  it('returns an empty timeline scope when every membership branch is hidden', async () => {
    const auth = AuthFactory.create();
    metadata.mockResolvedValue([
      { key: UserMetadataKey.Preferences, value: { sharedLibraries: { showPersonalInTimeline: false } } },
    ]);
    spaces.mockResolvedValue([{ id: 'space-off', showInTimeline: false }]);
    libraries.mockResolvedValue([{ id: 'library-off', ownerId: 'other', showInTimeline: false }]);

    await expect(sut.resolve(auth, { purpose: 'timeline' })).resolves.toEqual({
      personalUserIds: [],
      spaceIds: [],
      libraryIds: [],
    });
  });

  it('returns exactly the requested accessible container', async () => {
    const auth = AuthFactory.create();
    await expect(sut.resolve(auth, { purpose: 'timeline', filter: { spaceId: 'space-1' } })).resolves.toEqual({
      personalUserIds: [],
      spaceIds: ['space-1'],
      libraryIds: [],
    });
  });

  it('rejects stale container filters', async () => {
    const auth = AuthFactory.create();
    members.mockResolvedValue(false);
    await expect(sut.resolve(auth, { purpose: 'timeline', filter: { spaceId: 'gone' } })).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });
});
