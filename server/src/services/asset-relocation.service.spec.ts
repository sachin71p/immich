import { vitest } from 'vitest';
import { StorageCore } from 'src/cores/storage.core.js';
import { AssetFileType, AssetPathType, ChecksumAlgorithm, JobStatus } from 'src/enum.js';
import { AssetRelocationService, isPathInside } from 'src/services/asset-relocation.service.js';
import { StorageTemplateService } from 'src/services/storage-template.service.js';
import { newTestService } from 'test/utils.js';

describe('asset relocation import-path guard', () => {
  it('requires an actual import-path boundary', () => {
    expect(isPathInside('/imports/foo/asset.jpg', '/imports/foo')).toBe(true);
    expect(isPathInside('/imports/foo2/asset.jpg', '/imports/foo')).toBe(false);
  });
});

// fork: shared-libraries (S10) - report-only §7 container-paths audit.
const forRelocationAudit = (overrides: Record<string, unknown>) => ({
  id: 'asset-1',
  ownerId: 'user-1',
  spaceId: null,
  libraryId: null,
  originalPath: '/audit/upload/user-1/ab/cd/abcdef.jpg',
  originalFileName: 'abcdef.jpg',
  livePhotoVideoId: null,
  checksum: Buffer.from('checksum'),
  isExternal: false,
  fileSizeInByte: 100,
  spaceStorageLabel: null,
  uploadPath: null,
  importPaths: null,
  ownerStorageLabel: null,
  files: [],
  ...overrides,
});

const setupAudit = (templateEnabled: boolean, assets: Record<string, ReturnType<typeof forRelocationAudit>>) => {
  const { sut, mocks } = newTestService(AssetRelocationService);
  // Set after construction: the service constructor wires the StorageCore singleton.
  StorageCore.setMediaLocation('/audit');
  mocks.asset.getAuditIds.mockResolvedValue(Object.keys(assets));
  mocks.asset.getForRelocation.mockImplementation((id: string) => Promise.resolve(assets[id] as never));
  vitest.spyOn(sut, 'getConfig').mockResolvedValue({ storageTemplate: { enabled: templateEnabled } } as never);
  return sut;
};

describe('auditContainerPaths', () => {
  it('reports nothing when every file is at its §7 path (template off)', async () => {
    const asset = forRelocationAudit({
      files: [
        {
          type: AssetFileType.Thumbnail,
          path: '/audit/thumbs/user-1/as/se/asset-1_thumbnail.webp',
          isEdited: false,
        },
        { type: AssetFileType.Sidecar, path: '/audit/upload/user-1/ab/cd/abcdef.jpg.xmp', isEdited: false },
      ],
    });
    const sut = setupAudit(false, { 'asset-1': asset });
    await expect(sut.auditContainerPaths()).resolves.toEqual([]);
  });

  it('flags a misplaced original, sidecar, and thumbnail (template off)', async () => {
    const asset = forRelocationAudit({
      originalPath: '/audit/upload/shared/space-1/ab/cd/abcdef.jpg',
      files: [
        { type: AssetFileType.Thumbnail, path: '/audit/thumbs/user-1/as/se/stale_thumbnail.webp', isEdited: false },
        { type: AssetFileType.Sidecar, path: '/audit/upload/user-1/zz/yy/abcdef.jpg.xmp', isEdited: false },
      ],
    });
    const sut = setupAudit(false, { 'asset-1': asset });
    await expect(sut.auditContainerPaths()).resolves.toEqual([
      {
        assetId: 'asset-1',
        kind: 'original',
        actual: '/audit/upload/shared/space-1/ab/cd/abcdef.jpg',
        expected: '/audit/upload/user-1/ab/cd/abcdef.jpg',
      },
      {
        assetId: 'asset-1',
        kind: 'sidecar',
        actual: '/audit/upload/user-1/zz/yy/abcdef.jpg.xmp',
        expected: '/audit/upload/shared/space-1/ab/cd/abcdef.jpg.xmp',
      },
      {
        assetId: 'asset-1',
        kind: 'derived',
        actual: '/audit/thumbs/user-1/as/se/stale_thumbnail.webp',
        expected: '/audit/thumbs/user-1/as/se/asset-1_thumbnail.webp',
      },
    ]);
  });

  it('checks template-on originals by container root', async () => {
    const good = forRelocationAudit({
      originalPath: '/audit/library/user-1/2024/01-01/abcdef.jpg',
    });
    const bad = forRelocationAudit({
      id: 'asset-2',
      originalPath: '/audit/library/shared/family-mobile/2024/abcdef.jpg',
    });
    const sut = setupAudit(true, { 'asset-1': good, 'asset-2': bad });
    await expect(sut.auditContainerPaths()).resolves.toEqual([
      {
        assetId: 'asset-2',
        kind: 'original',
        actual: '/audit/library/shared/family-mobile/2024/abcdef.jpg',
        expected: '/audit/library/user-1',
      },
    ]);
  });

  it('accepts space originals under the shared label root (template on)', async () => {
    const asset = forRelocationAudit({
      spaceId: 'space-1',
      spaceStorageLabel: 'family-mobile',
      originalPath: '/audit/library/shared/family-mobile/2024/abcdef.jpg',
    });
    const sut = setupAudit(true, { 'asset-1': asset });
    await expect(sut.auditContainerPaths()).resolves.toEqual([]);
  });

  it('flags library originals outside every known root', async () => {
    const asset = forRelocationAudit({
      libraryId: 'lib-1',
      uploadPath: '/up',
      importPaths: ['/imp'],
      originalPath: '/elsewhere/a.jpg',
    });
    const sut = setupAudit(false, { 'asset-1': asset });
    await expect(sut.auditContainerPaths()).resolves.toEqual([
      { assetId: 'asset-1', kind: 'original', actual: '/elsewhere/a.jpg', expected: '/up' },
    ]);
  });

  it('the audit job succeeds and reports misplaced files without moving them', async () => {
    const asset = forRelocationAudit({ originalPath: '/audit/upload/shared/space-1/ab/cd/abcdef.jpg' });
    const sut = setupAudit(false, { 'asset-1': asset });
    await expect(sut.handleContainerPathsAudit()).resolves.toBe(JobStatus.Success);
    await expect(sut.auditContainerPaths()).resolves.toHaveLength(1);
  });
});

describe('relocation failure handling', () => {
  it('[I6] keeps the relocation row pending when storage-template movement fails', async () => {
    const { sut, mocks } = newTestService(AssetRelocationService);
    const asset = forRelocationAudit({ files: [] });
    mocks.asset.getForRelocation.mockResolvedValue(asset as never);
    vitest.spyOn(sut, 'getConfig').mockResolvedValue({ storageTemplate: { enabled: true } } as never);
    vitest
      .spyOn(StorageTemplateService, 'getInstance')
      .mockReturnValue({ moveAssetToTemplatePath: vitest.fn().mockRejectedValue(new Error('disk full')) } as never);

    await expect(sut.handleRelocate({ id: asset.id })).rejects.toThrow('disk full');

    expect(mocks.asset.completeRelocation).not.toHaveBeenCalled();
    expect(mocks.asset.failRelocation).toHaveBeenCalledWith(asset.id, 'disk full');
  });
});

// fork: shared-libraries (R10-02/R17-01) - library-exit and sidecar/derived handling.
const forLibraryExit = (overrides: Record<string, unknown>) =>
  forRelocationAudit({
    spaceId: 'space-1',
    spaceStorageLabel: 'family-mobile',
    originalPath: '/imp/fork-13.webp',
    originalFileName: 'fork-13.webp',
    importPaths: ['/imp'],
    checksum: Buffer.from('path-checksum'),
    checksumAlgorithm: ChecksumAlgorithm.sha1Path,
    fileSizeInByte: 12_416,
    files: [],
    ...overrides,
  });

const setupRelocate = (templateEnabled: boolean, asset: Record<string, unknown>) => {
  const { sut, mocks } = newTestService(AssetRelocationService);
  StorageCore.setMediaLocation('/audit');
  mocks.asset.getForRelocation.mockResolvedValue(asset as never);
  vitest.spyOn(sut, 'getConfig').mockResolvedValue({ storageTemplate: { enabled: templateEnabled } } as never);
  return { sut, mocks };
};

describe('library-exit relocation', () => {
  it('[R10-02] adopts a content checksum when a scanned asset leaves its library', async () => {
    const asset = forLibraryExit({});
    const { sut, mocks } = setupRelocate(false, asset);
    const contentHash = Buffer.from('content-hash');
    mocks.crypto.hashFile.mockResolvedValue(contentHash);
    const moveFile = vitest.spyOn(StorageCore.prototype, 'moveFile').mockResolvedValue(undefined);

    await expect(sut.handleRelocate({ id: asset.id })).resolves.toBe(JobStatus.Success);

    expect(mocks.asset.update).toHaveBeenCalledWith({
      id: asset.id,
      checksum: contentHash,
      checksumAlgorithm: ChecksumAlgorithm.sha1File,
    });
    const originalCall = moveFile.mock.calls.find(([request]) => request.pathType === AssetPathType.Original);
    expect(originalCall?.[0]).toMatchObject({ oldPath: '/imp/fork-13.webp' });
    expect(originalCall?.[0].assetInfo?.checksum).toBe(contentHash);
    expect(mocks.asset.completeRelocation).toHaveBeenCalledWith(asset.id);
    moveFile.mockRestore();
  });

  it('reuses the sibling checksum when a concurrent adoption wins the race', async () => {
    const asset = forLibraryExit({});
    const adopted = forLibraryExit({
      checksum: Buffer.from('sibling-hash'),
      checksumAlgorithm: ChecksumAlgorithm.sha1File,
    });
    const { sut, mocks } = setupRelocate(false, asset);
    mocks.asset.getForRelocation.mockResolvedValueOnce(asset as never).mockResolvedValue(adopted as never);
    mocks.crypto.hashFile.mockRejectedValue(Object.assign(new Error('gone'), { code: 'ENOENT' }));
    const moveFile = vitest.spyOn(StorageCore.prototype, 'moveFile').mockResolvedValue(undefined);

    await expect(sut.handleRelocate({ id: asset.id })).resolves.toBe(JobStatus.Success);

    expect(mocks.asset.update).not.toHaveBeenCalled();
    const originalCall = moveFile.mock.calls.find(([request]) => request.pathType === AssetPathType.Original);
    expect(originalCall?.[0].assetInfo?.checksum).toBe(adopted.checksum);
    expect(mocks.asset.completeRelocation).toHaveBeenCalledWith(asset.id);
    moveFile.mockRestore();
  });

  it('skips checksum adoption for content-addressed assets', async () => {
    const asset = forRelocationAudit({ files: [], checksumAlgorithm: ChecksumAlgorithm.sha1File });
    const { sut, mocks } = setupRelocate(false, asset);

    await expect(sut.handleRelocate({ id: asset.id })).resolves.toBe(JobStatus.Success);

    expect(mocks.crypto.hashFile).not.toHaveBeenCalled();
    expect(mocks.asset.update).not.toHaveBeenCalled();
    expect(mocks.asset.completeRelocation).toHaveBeenCalledWith(asset.id);
  });

  it('[R17-01] co-locates a staging sidecar when the original is already placed', async () => {
    const asset = forRelocationAudit({
      checksumAlgorithm: ChecksumAlgorithm.sha1File,
      files: [{ type: AssetFileType.Sidecar, path: '/audit/upload/user-1/zz/yy/abcdef.jpg.xmp', isEdited: false }],
    });
    const { sut, mocks } = setupRelocate(false, asset);
    const moveFile = vitest.spyOn(StorageCore.prototype, 'moveFile').mockResolvedValue(undefined);

    await expect(sut.handleRelocate({ id: asset.id })).resolves.toBe(JobStatus.Success);

    expect(moveFile).toHaveBeenCalledWith({
      entityId: asset.id,
      pathType: AssetFileType.Sidecar,
      oldPath: '/audit/upload/user-1/zz/yy/abcdef.jpg.xmp',
      newPath: '/audit/upload/user-1/ab/cd/abcdef.jpg.xmp',
    });
    expect(mocks.asset.completeRelocation).toHaveBeenCalledWith(asset.id);
    moveFile.mockRestore();
  });

  it('[R17-01] a failing derived file does not strand the rest', async () => {
    const asset = forRelocationAudit({
      checksumAlgorithm: ChecksumAlgorithm.sha1File,
      files: [
        { type: AssetFileType.Thumbnail, path: '/audit/thumbs/stale/bad.webp', isEdited: false },
        { type: AssetFileType.Thumbnail, path: '/audit/thumbs/stale/good.webp', isEdited: false },
      ],
    });
    const { sut, mocks } = setupRelocate(false, asset);
    const moveFile = vitest
      .spyOn(StorageCore.prototype, 'moveFile')
      .mockImplementation((request) =>
        request.oldPath === '/audit/thumbs/stale/bad.webp' ? Promise.reject(new Error('bad thumb')) : Promise.resolve(),
      );

    await expect(sut.handleRelocate({ id: asset.id })).rejects.toThrow('bad thumb');

    expect(moveFile).toHaveBeenCalledTimes(2);
    expect(mocks.asset.completeRelocation).not.toHaveBeenCalled();
    expect(mocks.asset.failRelocation).toHaveBeenCalledWith(asset.id, 'bad thumb');
    moveFile.mockRestore();
  });
});
