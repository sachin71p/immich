import { OutputInfo } from 'sharp';
import { AssetEditAction } from 'src/dtos/editing.dto.js';
import { AssetFileType, AssetType, JobStatus } from 'src/enum.js';
import { MediaService } from 'src/services/media.service.js';
import { AssetFactory } from 'test/factories/asset.factory.js';
import { probeStub } from 'test/fixtures/media.stub.js';
import { getForGenerateThumbnail } from 'test/mappers.js';
import { ServiceMocks, newTestService } from 'test/utils.js';

const renditionPath = '/thumbs/ab/cd/rendition_fullsize_edited.jpeg';

describe(`${MediaService.name} rendition`, () => {
  let sut: MediaService;
  let mocks: ServiceMocks;

  beforeEach(() => {
    ({ sut, mocks } = newTestService(MediaService));
    mocks.person.getFaces.mockResolvedValue([]);
    mocks.ocr.getByAssetId.mockResolvedValue([]);
    const rawInfo = { width: 100, height: 100, channels: 3 };
    const rawBuffer = Buffer.from('decoded image data');
    mocks.media.decodeImage.mockImplementation(() => Promise.resolve({ data: rawBuffer, info: rawInfo as OutputInfo }));
    mocks.media.getImageMetadata.mockResolvedValue({ width: 100, height: 100, isTransparent: false });
    mocks.media.generateThumbhash.mockResolvedValue(Buffer.from('a thumbhash', 'utf8'));
  });

  const renditionFile = { type: AssetFileType.FullSize, isEdited: true, path: renditionPath };

  describe('handleAssetEditThumbnailGeneration', () => {
    it('should derive thumbnails from the rendition when present', async () => {
      const asset = AssetFactory.from().exif().file(renditionFile).build();
      mocks.assetJob.getForGenerateThumbnailJob.mockResolvedValue(getForGenerateThumbnail(asset));

      await sut.handleAssetEditThumbnailGeneration({ id: asset.id });

      // the rendition is the decode source, not the original
      expect(mocks.media.decodeImage).toHaveBeenCalledWith(renditionPath, expect.anything());
      expect(mocks.media.decodeImage).not.toHaveBeenCalledWith(asset.originalPath, expect.anything());
      // edited preview + thumbnail are (re)generated ...
      expect(mocks.asset.upsertFiles).toHaveBeenCalledWith(
        expect.arrayContaining([
          expect.objectContaining({ type: AssetFileType.Preview, isEdited: true }),
          expect.objectContaining({ type: AssetFileType.Thumbnail, isEdited: true }),
        ]),
      );
      // ... but the rendition itself is never rewritten or deleted
      const upserted = mocks.asset.upsertFiles.mock.calls.flatMap(([files]) => files);
      expect(upserted).not.toContainEqual(expect.objectContaining({ type: AssetFileType.FullSize }));
      expect(mocks.asset.deleteFiles).not.toHaveBeenCalled();
      expect(mocks.job.queue).not.toHaveBeenCalledWith({
        name: expect.anything(),
        data: { files: expect.arrayContaining([renditionPath]) },
      });
    });

    it('should apply server edits on top of the rendition', async () => {
      const asset = AssetFactory.from()
        .exif()
        .file(renditionFile)
        .edit({ action: AssetEditAction.Rotate, parameters: { angle: 90 } })
        .build();
      mocks.assetJob.getForGenerateThumbnailJob.mockResolvedValue(getForGenerateThumbnail(asset));

      await sut.handleAssetEditThumbnailGeneration({ id: asset.id });

      expect(mocks.media.decodeImage).toHaveBeenCalledWith(renditionPath, expect.anything());
      expect(mocks.media.generateThumbnail).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          edits: [{ action: AssetEditAction.Rotate, parameters: { angle: 90 } }],
        }),
        expect.anything(),
      );
      expect(mocks.media.generateThumbhash).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          edits: [{ action: AssetEditAction.Rotate, parameters: { angle: 90 } }],
        }),
      );
    });

    it('should derive video thumbnails from the rendition when present', async () => {
      const asset = AssetFactory.from({ type: AssetType.Video, originalPath: '/original/video.mp4' })
        .exif()
        .file(renditionFile)
        .build();
      mocks.assetJob.getForGenerateThumbnailJob.mockResolvedValue({
        ...getForGenerateThumbnail(asset),
        ...probeStub.videoStream2160p,
      });

      await sut.handleAssetEditThumbnailGeneration({ id: asset.id });

      expect(mocks.media.transcode).toHaveBeenCalledTimes(2);
      expect(mocks.media.transcode).toHaveBeenCalledWith(renditionPath, expect.any(String), expect.anything());
      expect(mocks.media.transcode).not.toHaveBeenCalledWith(asset.originalPath, expect.any(String), expect.anything());
      expect(mocks.asset.upsertFiles).toHaveBeenCalledWith(
        expect.arrayContaining([
          expect.objectContaining({ type: AssetFileType.Preview, isEdited: true }),
          expect.objectContaining({ type: AssetFileType.Thumbnail, isEdited: true }),
        ]),
      );
    });

    it('should fall back to the original when no rendition exists', async () => {
      const asset = AssetFactory.from().exif().build();
      mocks.assetJob.getForGenerateThumbnailJob.mockResolvedValue(getForGenerateThumbnail(asset));

      const status = await sut.handleAssetEditThumbnailGeneration({ id: asset.id });

      expect(status).toBe(JobStatus.Success);
      expect(mocks.media.decodeImage).toHaveBeenCalledWith(asset.originalPath, expect.anything());
      expect(mocks.media.generateThumbnail).not.toHaveBeenCalled();
    });

    it('should re-derive from the original after a revert when server edits remain', async () => {
      const asset = AssetFactory.from()
        .exif()
        .edit({ action: AssetEditAction.Rotate, parameters: { angle: 90 } })
        .build();
      mocks.assetJob.getForGenerateThumbnailJob.mockResolvedValue(getForGenerateThumbnail(asset));

      await sut.handleAssetEditThumbnailGeneration({ id: asset.id });

      expect(mocks.media.decodeImage).toHaveBeenCalledWith(asset.originalPath, expect.anything());
      expect(mocks.media.generateThumbnail).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          edits: [{ action: AssetEditAction.Rotate, parameters: { angle: 90 } }],
        }),
        expect.anything(),
      );
    });
  });
});
