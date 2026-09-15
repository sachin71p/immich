// fork: shared-libraries - T1 backfill unit coverage for rows whose E tier
// cannot reach the branch deterministically (unwritable upload path, reserved
// storage label). E counterparts live in external-libraries.e2e-spec.ts
// ([R9-03]) and disk.e2e-spec.ts ([R17-02]).
import { Stats } from 'node:fs';
import { UserAdminCreateSchema } from 'src/dtos/user.dto.js';
import { LibraryService } from 'src/services/library.service.js';
import { newTestService } from 'test/utils.js';

describe('fork T1 upload-path and storage-label validation', () => {
  describe('[R9-03] validateUploadPath', () => {
    const imports = ['/import/archive'];

    const setup = () => {
      const { sut, mocks } = newTestService(LibraryService);
      mocks.storage.stat.mockResolvedValue({ isDirectory: () => true } as Stats);
      mocks.storage.checkFileExists.mockResolvedValue(true);
      return { sut, mocks };
    };

    it('rejects a path outside every import path', async () => {
      const { sut } = setup();
      await expect(sut.validateUploadPath('/elsewhere/incoming', imports)).resolves.toBe(
        'Path must be inside an import path',
      );
    });

    it('rejects a relative path', async () => {
      const { sut } = setup();
      await expect(sut.validateUploadPath('relative/incoming', imports)).resolves.toBe('Path must be absolute');
    });

    it('rejects an unwritable directory', async () => {
      const { sut, mocks } = setup();
      mocks.storage.checkFileExists.mockResolvedValue(false);
      await expect(sut.validateUploadPath('/import/archive/incoming', imports)).resolves.toBe(
        'Lacking write permission',
      );
    });

    it('accepts a writable directory inside an import path', async () => {
      const { sut } = setup();
      await expect(sut.validateUploadPath('/import/archive/incoming', imports)).resolves.toBeUndefined();
    });
  });

  describe('[R17-02] reserved storage label', () => {
    it.each(['shared', 'Shared', 'SHARED'])('rejects %s', (storageLabel) => {
      const result = UserAdminCreateSchema.safeParse({
        email: 'user@test.com',
        password: 'Password123',
        name: 'user',
        storageLabel,
      });
      expect(result.success).toBe(false);
      expect(result.error?.issues.map((issue) => issue.message)).toContain('Storage label "shared" is reserved');
    });

    it('accepts any other label', () => {
      expect(() =>
        UserAdminCreateSchema.parse({
          email: 'user@test.com',
          password: 'Password123',
          name: 'user',
          storageLabel: 'family',
        }),
      ).not.toThrow();
    });
  });
});
