import { vitest } from 'vitest';
import { StorageCore } from 'src/cores/storage.core.js';

vitest.mock('src/constants', () => ({
  IWorker: 'IWorker',
}));

describe('StorageCore', () => {
  describe('shared-library storage keys', () => {
    beforeAll(() => StorageCore.setMediaLocation('/photos'));

    it('keeps personal paths unchanged and namespaces shared-space derivatives', () => {
      const personal = { id: 'abcdef', ownerId: 'owner-id' };
      const space = { ...personal, spaceId: 'space-id' };
      expect(StorageCore.getStorageKey(personal)).toBe('owner-id');
      expect(StorageCore.getStorageKey(space)).toBe('shared/space-id');
      expect(StorageCore.getEncodedVideoPath(personal)).toBe('/photos/encoded-video/owner-id/ab/cd/abcdef.mp4');
      expect(StorageCore.getEncodedVideoPath(space)).toBe('/photos/encoded-video/shared/space-id/ab/cd/abcdef.mp4');
    });
  });

  describe('isImmichPath', () => {
    beforeAll(() => {
      StorageCore.setMediaLocation('/photos');
    });

    it('should return true for APP_MEDIA_LOCATION path', () => {
      const immichPath = '/photos';
      expect(StorageCore.isImmichPath(immichPath)).toBe(true);
    });

    it('should return true for paths within the APP_MEDIA_LOCATION', () => {
      const immichPath = '/photos/new/';
      expect(StorageCore.isImmichPath(immichPath)).toBe(true);
    });

    it('should return false for paths outside the APP_MEDIA_LOCATION and same starts', () => {
      const nonImmichPath = '/photos_new';
      expect(StorageCore.isImmichPath(nonImmichPath)).toBe(false);
    });

    it('should return false for paths outside the APP_MEDIA_LOCATION', () => {
      const nonImmichPath = '/some/other/path';
      expect(StorageCore.isImmichPath(nonImmichPath)).toBe(false);
    });
  });
});
