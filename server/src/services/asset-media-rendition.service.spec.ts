import { BadRequestException } from '@nestjs/common';
import { AssetFileType, JobName } from 'src/enum.js';
import { AssetMediaService } from 'src/services/asset-media.service.js';
import { AssetFactory } from 'test/factories/asset.factory.js';
import { authStub } from 'test/fixtures/auth.stub.js';
import { getForAsset } from 'test/mappers.js';
import { ServiceMocks, newTestService } from 'test/utils.js';

const renditionFile = {
  uuid: 'rendition-uuid',
  originalPath: 'upload/rendition.jpeg',
  checksum: Buffer.from('rendition hash', 'utf8'),
  originalName: 'rendition.jpeg',
  size: 42,
};

describe(`${AssetMediaService.name} rendition`, () => {
  let sut: AssetMediaService;
  let mocks: ServiceMocks;

  beforeEach(() => {
    ({ sut, mocks } = newTestService(AssetMediaService));
  });

  const grantOwnerAccess = (id: string) => {
    mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([id]));
  };

  describe('uploadRendition', () => {
    it('should require owner-write access', async () => {
      await expect(sut.uploadRendition(authStub.admin, 'asset-1', renditionFile)).rejects.toBeInstanceOf(
        BadRequestException,
      );

      expect(mocks.asset.getById).not.toHaveBeenCalled();
      expect(mocks.asset.upsertFile).not.toHaveBeenCalled();
    });

    it('should reject a non-image/video mime like the asset upload path', async () => {
      const asset = AssetFactory.create();
      grantOwnerAccess(asset.id);
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      await expect(
        sut.uploadRendition(authStub.admin, asset.id, { ...renditionFile, originalName: 'notes.txt' }),
      ).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.asset.upsertFile).not.toHaveBeenCalled();
      expect(mocks.storage.rename).not.toHaveBeenCalled();
    });

    it('should store the upload as the edited fullsize file and queue thumbnail regeneration', async () => {
      const asset = AssetFactory.create();
      grantOwnerAccess(asset.id);
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      const result = await sut.uploadRendition(authStub.admin, asset.id, renditionFile);

      expect(mocks.storage.rename).toHaveBeenCalledWith(
        renditionFile.originalPath,
        expect.stringContaining(`${asset.id}_${AssetFileType.FullSize}_edited.jpeg`),
      );
      expect(mocks.asset.upsertFile).toHaveBeenCalledWith({
        assetId: asset.id,
        path: expect.stringContaining(`${asset.id}_${AssetFileType.FullSize}_edited.jpeg`),
        type: AssetFileType.FullSize,
        isEdited: true,
      });
      expect(mocks.job.queue).toHaveBeenCalledWith({
        name: JobName.AssetEditThumbnailGeneration,
        data: { id: asset.id },
      });
      // response is the asset DTO: no new asset is ever created
      expect(mocks.asset.create).not.toHaveBeenCalled();
      expect(result).toEqual(expect.objectContaining({ id: asset.id }));
      expect(result).not.toHaveProperty('status');
    });

    it('should clean up the previous rendition file when it is replaced', async () => {
      const previousPath = '/thumbs/ab/cd/previous_fullsize_edited.webp';
      const asset = AssetFactory.from()
        .file({ type: AssetFileType.FullSize, isEdited: true, path: previousPath })
        .build();
      grantOwnerAccess(asset.id);
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      await sut.uploadRendition(authStub.admin, asset.id, renditionFile);

      expect(mocks.job.queue).toHaveBeenCalledWith({
        name: JobName.FileDelete,
        data: { files: [previousPath] },
      });
    });

    it('should throw when the asset does not exist', async () => {
      grantOwnerAccess('asset-1');
      mocks.asset.getById.mockResolvedValue(undefined);

      await expect(sut.uploadRendition(authStub.admin, 'asset-1', renditionFile)).rejects.toBeInstanceOf(
        BadRequestException,
      );

      expect(mocks.asset.upsertFile).not.toHaveBeenCalled();
    });
  });

  describe('removeRendition', () => {
    it('should require owner-write access', async () => {
      await expect(sut.removeRendition(authStub.admin, 'asset-1')).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.asset.getById).not.toHaveBeenCalled();
      expect(mocks.asset.deleteFile).not.toHaveBeenCalled();
    });

    it('should be idempotent when no rendition exists', async () => {
      const asset = AssetFactory.create();
      grantOwnerAccess(asset.id);
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      await expect(sut.removeRendition(authStub.admin, asset.id)).resolves.toBeUndefined();

      expect(mocks.asset.deleteFile).not.toHaveBeenCalled();
      expect(mocks.job.queue).not.toHaveBeenCalled();
    });

    it('should delete the edited file and queue fallback thumbnail regeneration', async () => {
      const renditionPath = '/thumbs/ab/cd/asset-1_fullsize_edited.jpeg';
      const asset = AssetFactory.from()
        .file({ type: AssetFileType.FullSize, isEdited: true, path: renditionPath })
        .build();
      grantOwnerAccess(asset.id);
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      await expect(sut.removeRendition(authStub.admin, asset.id)).resolves.toBeUndefined();

      expect(mocks.asset.deleteFile).toHaveBeenCalledWith({
        assetId: asset.id,
        type: AssetFileType.FullSize,
        edited: true,
      });
      expect(mocks.job.queue).toHaveBeenCalledWith({
        name: JobName.FileDelete,
        data: { files: [renditionPath] },
      });
      expect(mocks.job.queue).toHaveBeenCalledWith({
        name: JobName.AssetEditThumbnailGeneration,
        data: { id: asset.id },
      });
    });

    it('should throw when the asset does not exist', async () => {
      grantOwnerAccess('asset-1');
      mocks.asset.getById.mockResolvedValue(undefined);

      await expect(sut.removeRendition(authStub.admin, 'asset-1')).rejects.toBeInstanceOf(BadRequestException);
    });
  });
});
