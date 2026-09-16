import { BadRequestException } from '@nestjs/common';
import { DateTime } from 'luxon';
import { AssetJobName, AssetMoveDto, AssetStatsResponseDto } from 'src/dtos/asset.dto.js';
import { AssetEditAction } from 'src/dtos/editing.dto.js';
import {
  AssetFileType,
  AssetMetadataKey,
  AssetStatus,
  AssetType,
  AssetVisibility,
  JobName,
  JobStatus,
} from 'src/enum.js';
import { AssetStats } from 'src/repositories/asset.repository.js';
import { AssetService } from 'src/services/asset.service.js';
import { AssetFactory } from 'test/factories/asset.factory.js';
import { AuthFactory } from 'test/factories/auth.factory.js';
import { authStub } from 'test/fixtures/auth.stub.js';
import { getForAsset, getForAssetDeletion } from 'test/mappers.js';
import { factory, newUuid } from 'test/small.factory.js';
import { ServiceMocks, makeStream, newTestService } from 'test/utils.js';

const stats: AssetStats = {
  [AssetType.Image]: 10,
  [AssetType.Video]: 23,
  [AssetType.Audio]: 0,
  [AssetType.Other]: 0,
};

const statResponse: AssetStatsResponseDto = {
  images: 10,
  videos: 23,
  total: 33,
};

describe(AssetService.name, () => {
  let sut: AssetService;
  let mocks: ServiceMocks;

  it('should work', () => {
    expect(sut).toBeDefined();
  });

  beforeEach(() => {
    ({ sut, mocks } = newTestService(AssetService));
  });

  describe('getStatistics', () => {
    it('should get the statistics for a user, excluding archived assets', async () => {
      const auth = AuthFactory.create();
      mocks.asset.getStatistics.mockResolvedValue(stats);
      await expect(sut.getStatistics(auth, { visibility: AssetVisibility.Timeline })).resolves.toEqual(statResponse);
      expect(mocks.asset.getStatistics).toHaveBeenCalledWith(auth.user.id, { visibility: AssetVisibility.Timeline });
    });

    it('should get the statistics for a user for archived assets', async () => {
      const auth = AuthFactory.create();
      mocks.asset.getStatistics.mockResolvedValue(stats);
      await expect(sut.getStatistics(auth, { visibility: AssetVisibility.Archive })).resolves.toEqual(statResponse);
      expect(mocks.asset.getStatistics).toHaveBeenCalledWith(auth.user.id, {
        visibility: AssetVisibility.Archive,
      });
    });

    it('should get the statistics for a user for favorite assets', async () => {
      const auth = AuthFactory.create();
      mocks.asset.getStatistics.mockResolvedValue(stats);
      await expect(sut.getStatistics(auth, { isFavorite: true })).resolves.toEqual(statResponse);
      expect(mocks.asset.getStatistics).toHaveBeenCalledWith(auth.user.id, { isFavorite: true });
    });

    it('should get the statistics for a user for all assets', async () => {
      const auth = AuthFactory.create();
      mocks.asset.getStatistics.mockResolvedValue(stats);
      await expect(sut.getStatistics(auth, {})).resolves.toEqual(statResponse);
      expect(mocks.asset.getStatistics).toHaveBeenCalledWith(auth.user.id, {});
    });
  });

  // fork: shared-libraries - move rules (DECISIONS §6)
  describe('move', () => {
    it('should move a personal asset into a space', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, spaceId: null, libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.access.space.checkMemberAccess.mockResolvedValue(new Set(['space-1']));
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getMoveGroup.mockResolvedValue([asset]);

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'space', id: 'space-1' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'moved' }] });
      expect(mocks.asset.moveWithRelocation).toHaveBeenCalledWith(
        [asset.id],
        { spaceId: 'space-1', libraryId: null, isExternal: false },
        auth.user.id,
      );
      expect(mocks.event.emit).toHaveBeenCalledWith('AssetMetadataExtracted', {
        assetId: asset.id,
        userId: asset.ownerId,
        source: 'sidecar-write',
      });
      expect(mocks.asset.moveWithRelocation.mock.invocationCallOrder[0]).toBeLessThan(
        mocks.event.emit.mock.invocationCallOrder[0],
      );
    });

    it('should move own asset from a space back to personal', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, spaceId: 'space-1', libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getMoveGroup.mockResolvedValue([asset]);

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'personal' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'moved' }] });
    });

    it("should reject moving another owner's space asset to personal", async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: newUuid(), spaceId: 'space-1', libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'personal' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'error', reason: 'target_access' }] });
      expect(mocks.asset.moveWithRelocation).not.toHaveBeenCalled();
    });

    it('should reject moving into a space without target membership', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, spaceId: 'space-1', libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.access.space.checkMemberAccess.mockResolvedValue(new Set());

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'space', id: 'space-2' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'error', reason: 'target_access' }] });
      expect(mocks.asset.moveWithRelocation).not.toHaveBeenCalled();
    });

    it('should reject moving out of a space the user is not a member of', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: newUuid(), spaceId: 'space-1', libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.access.space.checkMemberAccess.mockResolvedValue(new Set(['space-2']));
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set());
      mocks.access.asset.checkSpaceAccess.mockResolvedValue(new Set());

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'space', id: 'space-2' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'error', reason: 'source_access' }] });
      expect(mocks.asset.moveWithRelocation).not.toHaveBeenCalled();
    });

    it('should move between spaces when the user is a member of both', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: newUuid(), spaceId: 'space-1', libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.access.space.checkMemberAccess.mockResolvedValue(new Set(['space-2']));
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set());
      mocks.access.asset.checkSpaceAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getMoveGroup.mockResolvedValue([asset]);

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'space', id: 'space-2' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'moved' }] });
    });

    it('should reject moving into an external library without an uploadPath', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, spaceId: null, libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.library.get.mockResolvedValue(factory.library({ uploadPath: null }));

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'library', id: 'lib-1' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'error', reason: 'target_access' }] });
      expect(mocks.asset.moveWithRelocation).not.toHaveBeenCalled();
    });

    it('should move into an external library that has an uploadPath configured', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, spaceId: null, libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.library.get.mockResolvedValue(factory.library({ id: 'lib-1', uploadPath: '/data/lib' }));
      mocks.access.library.checkMemberAccess.mockResolvedValue(new Set(['lib-1']));
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getMoveGroup.mockResolvedValue([asset]);

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'library', id: 'lib-1' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'moved' }] });
      expect(mocks.asset.moveWithRelocation).toHaveBeenCalledWith(
        [asset.id],
        { spaceId: null, libraryId: 'lib-1', isExternal: true },
        auth.user.id,
      );
    });

    it('should reject a duplicate checksum in the target library', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, spaceId: null, libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.library.get.mockResolvedValue(factory.library({ id: 'lib-1', uploadPath: '/data/lib' }));
      mocks.access.library.checkMemberAccess.mockResolvedValue(new Set(['lib-1']));
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getMoveGroup.mockResolvedValue([asset]);
      mocks.asset.getByChecksumInContainer.mockResolvedValue(AssetFactory.create({ id: newUuid() }));

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'library', id: 'lib-1' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'error', reason: 'duplicate' }] });
      expect(mocks.asset.getByChecksumInContainer).toHaveBeenCalledWith({
        checksum: asset.checksum,
        ownerId: undefined,
        spaceId: null,
        libraryId: 'lib-1',
        excludeIds: [asset.id],
      });
      expect(mocks.asset.moveWithRelocation).not.toHaveBeenCalled();
    });

    it('should reject moving into a space that already holds the same bytes from another owner', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, spaceId: null, libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.access.space.checkMemberAccess.mockResolvedValue(new Set(['space-1']));
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getMoveGroup.mockResolvedValue([asset]);
      mocks.asset.getByChecksumInContainer.mockResolvedValue(
        AssetFactory.create({ id: newUuid(), ownerId: newUuid() }),
      );

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'space', id: 'space-1' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'error', reason: 'duplicate' }] });
      expect(mocks.asset.getByChecksumInContainer).toHaveBeenCalledWith({
        checksum: asset.checksum,
        ownerId: undefined,
        spaceId: 'space-1',
        libraryId: null,
        excludeIds: [asset.id],
      });
      expect(mocks.asset.moveWithRelocation).not.toHaveBeenCalled();
    });

    it('should scope the personal-target duplicate check to the moving user', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, spaceId: 'space-1', libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getMoveGroup.mockResolvedValue([asset]);

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'personal' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'moved' }] });
      expect(mocks.asset.getByChecksumInContainer).toHaveBeenCalledWith({
        checksum: asset.checksum,
        ownerId: auth.user.id,
        spaceId: null,
        libraryId: null,
        excludeIds: [asset.id],
      });
    });

    it('should expand the move to the whole live-photo pair', async () => {
      const auth = AuthFactory.create();
      const video = AssetFactory.create({ id: newUuid(), ownerId: auth.user.id, spaceId: null });
      const still = AssetFactory.create({
        ownerId: auth.user.id,
        spaceId: null,
        livePhotoVideoId: video.id,
      });
      mocks.asset.getByIds.mockResolvedValue([still]);
      mocks.access.space.checkMemberAccess.mockResolvedValue(new Set(['space-1']));
      const owned = new Set([still.id, video.id]);
      mocks.access.asset.checkOwnerAccess.mockImplementation((_userId, ids) =>
        Promise.resolve(ids.intersection(owned)),
      );
      mocks.asset.getMoveGroup.mockResolvedValue([still, video]);

      const dto: AssetMoveDto = { assetIds: [still.id], target: { type: 'space', id: 'space-1' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: still.id, status: 'moved' }] });
      expect(mocks.asset.moveWithRelocation).toHaveBeenCalledWith(
        [still.id, video.id],
        { spaceId: 'space-1', libraryId: null, isExternal: false },
        auth.user.id,
      );
      expect(mocks.event.emit).toHaveBeenCalledWith('AssetMetadataExtracted', {
        assetId: still.id,
        userId: still.ownerId,
        source: 'sidecar-write',
      });
      expect(mocks.event.emit).toHaveBeenCalledWith('AssetMetadataExtracted', {
        assetId: video.id,
        userId: video.ownerId,
        source: 'sidecar-write',
      });
    });

    it('should reject moving a Locked asset', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, visibility: AssetVisibility.Locked });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.access.space.checkMemberAccess.mockResolvedValue(new Set(['space-1']));

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'space', id: 'space-1' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'error', reason: 'locked' }] });
      expect(mocks.asset.moveWithRelocation).not.toHaveBeenCalled();
    });

    it('should return noop when the asset is already in the target container', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, spaceId: 'space-1', libraryId: null });
      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.access.space.checkMemberAccess.mockResolvedValue(new Set(['space-1']));
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));

      const dto: AssetMoveDto = { assetIds: [asset.id], target: { type: 'space', id: 'space-1' } };
      const result = await sut.move(auth, dto);

      expect(result).toEqual({ results: [{ id: asset.id, status: 'noop' }] });
      expect(mocks.asset.moveWithRelocation).not.toHaveBeenCalled();
    });
  });

  describe('get', () => {
    it('should allow owner access', async () => {
      const asset = AssetFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      await sut.get(authStub.admin, asset.id);

      expect(mocks.access.asset.checkOwnerAccess).toHaveBeenCalledWith(
        authStub.admin.user.id,
        new Set([asset.id]),
        undefined,
      );
    });

    it('should allow shared link access', async () => {
      const asset = AssetFactory.create();
      mocks.access.asset.checkSharedLinkAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      await sut.get(authStub.adminSharedLink, asset.id);

      expect(mocks.access.asset.checkSharedLinkAccess).toHaveBeenCalledWith(
        authStub.adminSharedLink.sharedLink?.id,
        new Set([asset.id]),
      );
    });

    it('should strip metadata for shared link if exif is disabled', async () => {
      const asset = AssetFactory.from().exif({ description: 'foo' }).build();
      mocks.access.asset.checkSharedLinkAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      const result = await sut.get(
        { ...authStub.adminSharedLink, sharedLink: { ...authStub.adminSharedLink.sharedLink!, showExif: false } },
        asset.id,
      );

      expect(result).toEqual(expect.objectContaining({ hasMetadata: false }));
      expect(result).not.toHaveProperty('exifInfo');
      expect(mocks.access.asset.checkSharedLinkAccess).toHaveBeenCalledWith(
        authStub.adminSharedLink.sharedLink?.id,
        new Set([asset.id]),
      );
    });

    it('should allow partner sharing access', async () => {
      const asset = AssetFactory.create();
      mocks.access.asset.checkPartnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      await sut.get(authStub.admin, asset.id);

      expect(mocks.access.asset.checkPartnerAccess).toHaveBeenCalledWith(authStub.admin.user.id, new Set([asset.id]));
    });

    it('should allow shared album access', async () => {
      const asset = AssetFactory.create();
      mocks.access.asset.checkAlbumAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      await sut.get(authStub.admin, asset.id);

      expect(mocks.access.asset.checkAlbumAccess).toHaveBeenCalledWith(authStub.admin.user.id, new Set([asset.id]));
    });

    it('should throw an error for no access', async () => {
      await expect(sut.get(authStub.admin, AssetFactory.create().id)).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.asset.getById).not.toHaveBeenCalled();
    });

    it('should throw an error for an invalid shared link', async () => {
      await expect(sut.get(authStub.adminSharedLink, AssetFactory.create().id)).rejects.toBeInstanceOf(
        BadRequestException,
      );

      expect(mocks.access.asset.checkOwnerAccess).not.toHaveBeenCalled();
      expect(mocks.asset.getById).not.toHaveBeenCalled();
    });

    it('should throw an error if the asset could not be found', async () => {
      const asset = AssetFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));

      await expect(sut.get(authStub.admin, asset.id)).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('getFullExif', () => {
    it('[R12-01] should allow the owner and merge sidecar tags while stripping binary values', async () => {
      const asset = AssetFactory.from().file({ type: AssetFileType.Sidecar, path: '/data/upload/asset.xmp' }).build();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));
      mocks.metadata.readFullTags.mockResolvedValueOnce({
        'EXIF:ISO': 200,
        'MakerNotes:PreviewImage': { bytes: 42, rawValue: 'binary' },
      });
      mocks.metadata.readFullTags.mockResolvedValueOnce({ 'XMP:Label': 'edited in sidecar' });

      await expect(sut.getFullExif(authStub.admin, asset.id)).resolves.toEqual({
        groups: {
          EXIF: { ISO: 200 },
          MakerNotes: { PreviewImage: { binary: true, bytes: 42 } },
          XMP: { Label: 'edited in sidecar' },
        },
      });
      expect(mocks.metadata.readFullTags).toHaveBeenNthCalledWith(1, asset.originalPath);
      expect(mocks.metadata.readFullTags).toHaveBeenNthCalledWith(2, '/data/upload/asset.xmp');
    });

    it('[R12-02] should allow a shared-space member', async () => {
      const asset = AssetFactory.create({ ownerId: newUuid(), spaceId: newUuid() });
      mocks.access.asset.checkSpaceAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));
      mocks.metadata.readFullTags.mockResolvedValue({});

      await expect(sut.getFullExif(authStub.user1, asset.id)).resolves.toEqual({ groups: {} });
    });

    it('[R12-02] should allow a shared-album member', async () => {
      const asset = AssetFactory.create({ ownerId: newUuid() });
      mocks.access.asset.checkAlbumAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));
      mocks.metadata.readFullTags.mockResolvedValue({});

      await expect(sut.getFullExif(authStub.user1, asset.id)).resolves.toEqual({ groups: {} });
    });

    it('[R12-02] should deny a stranger before reading file metadata', async () => {
      const asset = AssetFactory.create({ ownerId: newUuid() });

      await expect(sut.getFullExif(authStub.user1, asset.id)).rejects.toBeInstanceOf(BadRequestException);
      expect(mocks.asset.getById).not.toHaveBeenCalled();
      expect(mocks.metadata.readFullTags).not.toHaveBeenCalled();
    });
  });

  describe('update', () => {
    it('should require asset write access for the id', async () => {
      await expect(
        sut.update(authStub.admin, 'asset-1', { visibility: AssetVisibility.Timeline }),
      ).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.asset.update).not.toHaveBeenCalled();
    });

    it('[I7] should reject Locked visibility for a space asset', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, spaceId: 'space-1' });
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      await expect(sut.update(auth, asset.id, { visibility: AssetVisibility.Locked })).rejects.toBeInstanceOf(
        BadRequestException,
      );

      expect(mocks.asset.update).not.toHaveBeenCalled();
    });

    it('should update the asset', async () => {
      const asset = AssetFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));
      mocks.asset.update.mockResolvedValue(getForAsset(asset));

      await sut.update(authStub.admin, asset.id, { isFavorite: true });

      expect(mocks.asset.update).toHaveBeenCalledWith({ id: asset.id, isFavorite: true });
    });

    it('should allow an album member to update only favorite', async () => {
      const asset = AssetFactory.create();
      mocks.access.asset.checkAlbumMemberAccess.mockResolvedValue(new Set([asset.id]));
      mocks.access.asset.checkAlbumAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));
      mocks.asset.update.mockResolvedValue(getForAsset(asset));

      await sut.update(authStub.user1, asset.id, { isFavorite: true });

      expect(mocks.access.asset.checkAlbumMemberAccess).toHaveBeenCalledWith(
        authStub.user1.user.id,
        new Set([asset.id]),
      );
      expect(mocks.access.asset.checkOwnerAccess).toHaveBeenCalledWith(
        authStub.user1.user.id,
        new Set([asset.id]),
        undefined,
      );
    });

    it('should update the exif description', async () => {
      const asset = AssetFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));
      mocks.asset.update.mockResolvedValue(getForAsset(asset));

      await sut.update(authStub.admin, asset.id, { description: 'Test description' });

      expect(mocks.asset.upsertExif).toHaveBeenCalledWith(
        expect.objectContaining({
          exif: { assetId: asset.id, description: 'Test description', lockedProperties: ['description'] },
          lockedPropertiesBehavior: 'append',
        }),
      );
    });

    it('should update the exif rating', async () => {
      const asset = AssetFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValueOnce(getForAsset(asset));
      mocks.asset.update.mockResolvedValueOnce(getForAsset(asset));

      await sut.update(authStub.admin, asset.id, { rating: 3 });

      expect(mocks.asset.upsertExif).toHaveBeenCalledWith(
        expect.objectContaining({
          exif: {
            assetId: asset.id,
            rating: 3,
            lockedProperties: ['rating'],
          },
          lockedPropertiesBehavior: 'append',
        }),
      );
    });

    it('should fail linking a live video if the motion part could not be found', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));

      await expect(
        sut.update(auth, asset.id, {
          livePhotoVideoId: 'unknown',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.asset.update).not.toHaveBeenCalledWith({
        id: asset.id,
        livePhotoVideoId: 'unknown',
      });
      expect(mocks.asset.update).not.toHaveBeenCalledWith({
        id: 'unknown',
        visibility: AssetVisibility.Timeline,
      });
      expect(mocks.event.emit).not.toHaveBeenCalledWith('AssetShow', {
        assetId: 'unknown',
        userId: auth.user.id,
      });
    });

    it('should fail linking a live video if the motion part is not a video', async () => {
      const auth = AuthFactory.create();
      const motionAsset = AssetFactory.from().owner(auth.user).build();
      const asset = AssetFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(asset));

      await expect(
        sut.update(authStub.admin, asset.id, {
          livePhotoVideoId: motionAsset.id,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.asset.update).not.toHaveBeenCalledWith({
        id: asset.id,
        livePhotoVideoId: motionAsset.id,
      });
      expect(mocks.asset.update).not.toHaveBeenCalledWith({
        id: motionAsset.id,
        visibility: AssetVisibility.Timeline,
      });
      expect(mocks.event.emit).not.toHaveBeenCalledWith('AssetShow', {
        assetId: motionAsset.id,
        userId: auth.user.id,
      });
    });

    it('should fail linking a live video if the motion part has a different owner', async () => {
      const auth = AuthFactory.create();
      const motionAsset = AssetFactory.create({ type: AssetType.Video });
      const asset = AssetFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValue(getForAsset(motionAsset));

      await expect(
        sut.update(auth, asset.id, {
          livePhotoVideoId: motionAsset.id,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.asset.update).not.toHaveBeenCalledWith({
        id: asset.id,
        livePhotoVideoId: motionAsset.id,
      });
      expect(mocks.asset.update).not.toHaveBeenCalledWith({
        id: motionAsset.id,
        visibility: AssetVisibility.Timeline,
      });
      expect(mocks.event.emit).not.toHaveBeenCalledWith('AssetShow', {
        assetId: motionAsset.id,
        userId: auth.user.id,
      });
    });

    it('should link a live video', async () => {
      const motionAsset = AssetFactory.create({ type: AssetType.Video, visibility: AssetVisibility.Timeline });
      const stillAsset = AssetFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([stillAsset.id]));
      mocks.asset.getById.mockResolvedValueOnce(getForAsset(motionAsset));
      mocks.asset.getById.mockResolvedValueOnce(getForAsset(stillAsset));
      mocks.asset.update.mockResolvedValue(getForAsset(stillAsset));
      const auth = AuthFactory.from(motionAsset.owner).build();

      await sut.update(auth, stillAsset.id, { livePhotoVideoId: motionAsset.id });

      expect(mocks.asset.update).toHaveBeenCalledWith({ id: motionAsset.id, visibility: AssetVisibility.Hidden });
      expect(mocks.event.emit).toHaveBeenCalledWith('AssetHide', { assetId: motionAsset.id, userId: auth.user.id });
      expect(mocks.asset.update).toHaveBeenCalledWith({ id: stillAsset.id, livePhotoVideoId: motionAsset.id });
    });

    it('should throw an error if asset could not be found after update', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset-1']));
      await expect(sut.update(AuthFactory.create(), 'asset-1', { isFavorite: true })).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });

    it('should unlink a live video', async () => {
      const auth = AuthFactory.create();
      const motionAsset = AssetFactory.from({ type: AssetType.Video, visibility: AssetVisibility.Hidden })
        .owner(auth.user)
        .build();
      const asset = AssetFactory.create({ livePhotoVideoId: motionAsset.id });
      const unlinkedAsset = AssetFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValueOnce(getForAsset(asset));
      mocks.asset.getById.mockResolvedValueOnce(getForAsset(motionAsset));
      mocks.asset.getById.mockResolvedValueOnce(getForAsset(unlinkedAsset));
      mocks.asset.update.mockResolvedValueOnce(getForAsset(unlinkedAsset));

      await sut.update(auth, asset.id, { livePhotoVideoId: null });

      expect(mocks.asset.update).toHaveBeenCalledWith({
        id: asset.id,
        livePhotoVideoId: null,
      });
      expect(mocks.asset.update).toHaveBeenCalledWith({
        id: motionAsset.id,
        visibility: asset.visibility,
      });
      expect(mocks.event.emit).toHaveBeenCalledWith('AssetShow', {
        assetId: motionAsset.id,
        userId: auth.user.id,
      });
    });

    it('should fail unlinking a live video if the asset could not be found', async () => {
      const asset = AssetFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getById.mockResolvedValueOnce(void 0);

      await expect(sut.update(authStub.admin, asset.id, { livePhotoVideoId: null })).rejects.toBeInstanceOf(
        BadRequestException,
      );

      expect(mocks.asset.update).not.toHaveBeenCalled();
      expect(mocks.event.emit).not.toHaveBeenCalled();
    });
  });

  describe('updateAll', () => {
    it('should require asset write access for all ids', async () => {
      const auth = AuthFactory.create();
      await expect(sut.updateAll(auth, { ids: ['asset-1'] })).rejects.toBeInstanceOf(BadRequestException);
    });

    it('should update all assets', async () => {
      const auth = AuthFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset-1', 'asset-2']));

      await sut.updateAll(auth, { ids: ['asset-1', 'asset-2'], visibility: AssetVisibility.Archive });

      expect(mocks.asset.updateAll).toHaveBeenCalledWith(['asset-1', 'asset-2'], {
        visibility: AssetVisibility.Archive,
      });
    });

    it('[I7] should reject Locked visibility when any asset is in a container', async () => {
      const auth = AuthFactory.create();
      const asset = AssetFactory.create({ ownerId: auth.user.id, spaceId: 'space-1' });
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.asset.getByIds.mockResolvedValue([asset]);

      await expect(
        sut.updateAll(auth, { ids: [asset.id], visibility: AssetVisibility.Locked }),
      ).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.asset.updateAll).not.toHaveBeenCalled();
    });

    it('should allow an album member to bulk update only favorite', async () => {
      const auth = AuthFactory.create();
      mocks.access.asset.checkAlbumMemberAccess.mockResolvedValue(new Set(['asset-1']));

      await sut.updateAll(auth, { ids: ['asset-1'], isFavorite: true });

      expect(mocks.access.asset.checkAlbumMemberAccess).toHaveBeenCalledWith(auth.user.id, new Set(['asset-1']));
      expect(mocks.asset.updateAll).toHaveBeenCalledWith(['asset-1'], { isFavorite: true });
    });

    it('should reject a mixed update by an album member', async () => {
      const auth = AuthFactory.create();
      mocks.access.asset.checkAlbumMemberAccess.mockResolvedValue(new Set(['asset-1']));

      await expect(
        sut.updateAll(auth, { ids: ['asset-1'], isFavorite: true, description: 'nope' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('should reject locking a shared asset', async () => {
      mocks.access.asset.checkSpaceAccess.mockResolvedValue(new Set(['asset-1']));
      mocks.asset.getByIds.mockResolvedValue([getForAsset(AssetFactory.create({ spaceId: 'space-1' }))]);

      await expect(
        sut.updateAll(authStub.admin, { ids: ['asset-1'], visibility: AssetVisibility.Locked }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('should not update Assets table if no relevant fields are provided', async () => {
      const auth = AuthFactory.create();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset-1']));

      await sut.updateAll(auth, {
        ids: ['asset-1'],
        latitude: 0,
        longitude: 0,
        isFavorite: undefined,
        duplicateId: undefined,
        rating: undefined,
      });
      expect(mocks.asset.updateAll).not.toHaveBeenCalled();
    });

    it('should update Assets table if visibility field is provided', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset-1']));

      await sut.updateAll(authStub.admin, {
        ids: ['asset-1'],
        latitude: 0,
        longitude: 0,
        visibility: AssetVisibility.Archive,
        isFavorite: false,
        duplicateId: undefined,
        rating: undefined,
      });
      expect(mocks.asset.updateAll).toHaveBeenCalled();
      expect(mocks.asset.updateAllExif).toHaveBeenCalledWith(['asset-1'], { latitude: 0, longitude: 0 });
      expect(mocks.job.queueAll).toHaveBeenCalledWith([{ name: JobName.SidecarWrite, data: { id: 'asset-1' } }]);
    });

    it('should update exif table if latitude field is provided', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset-1']));
      const dateTimeOriginal = new Date().toISOString();
      await sut.updateAll(authStub.admin, {
        ids: ['asset-1'],
        latitude: 30,
        longitude: 50,
        dateTimeOriginal,
        isFavorite: false,
        duplicateId: undefined,
        rating: undefined,
      });
      expect(mocks.asset.updateAll).toHaveBeenCalled();
      expect(mocks.asset.updateAllExif).toHaveBeenCalledWith(['asset-1'], {
        dateTimeOriginal,
        latitude: 30,
        longitude: 50,
      });
      expect(mocks.job.queueAll).toHaveBeenCalledWith([{ name: JobName.SidecarWrite, data: { id: 'asset-1' } }]);
    });

    it('should update Assets table if duplicateId is provided as null', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset-1']));

      await sut.updateAll(authStub.admin, {
        ids: ['asset-1'],
        latitude: 0,
        longitude: 0,
        isFavorite: undefined,
        duplicateId: null,
        rating: undefined,
      });
      expect(mocks.asset.updateAll).toHaveBeenCalled();
    });

    it('should update exif table if dateTimeRelative and timeZone field is provided', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset-1']));
      const dateTimeRelative = 35;
      const timeZone = 'UTC+2';
      mocks.asset.updateDateTimeOriginal.mockResolvedValue([
        { assetId: 'asset-1', dateTimeOriginal: new Date('2020-02-25T04:41:00'), timeZone },
      ]);
      await sut.updateAll(authStub.admin, {
        ids: ['asset-1'],
        dateTimeRelative,
        timeZone,
      });
      expect(mocks.asset.updateDateTimeOriginal).toHaveBeenCalledWith(['asset-1'], dateTimeRelative, timeZone);
      expect(mocks.job.queueAll).toHaveBeenCalledWith([{ name: JobName.SidecarWrite, data: { id: 'asset-1' } }]);
    });
  });

  describe('deleteAll', () => {
    it('should require asset delete access for all ids', async () => {
      await expect(
        sut.deleteAll(authStub.user1, {
          ids: ['asset-1'],
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('should force delete a batch of assets', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset1', 'asset2']));

      await sut.deleteAll(authStub.user1, { ids: ['asset1', 'asset2'], force: true });

      expect(mocks.event.emit).toHaveBeenCalledWith('AssetDeleteAll', {
        assetIds: ['asset1', 'asset2'],
        userId: 'user-id',
      });
    });

    it('should soft delete a batch of assets', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset1', 'asset2']));

      await sut.deleteAll(authStub.user1, { ids: ['asset1', 'asset2'], force: false });

      expect(mocks.asset.updateAll).toHaveBeenCalledWith(['asset1', 'asset2'], {
        deletedAt: expect.any(Date),
        status: AssetStatus.Trashed,
      });
      expect(mocks.job.queue.mock.calls).toEqual([]);
    });
  });

  describe('handleAssetDeletionCheck', () => {
    beforeAll(() => {
      vi.useFakeTimers();
    });

    afterAll(() => {
      vi.useRealTimers();
    });

    it('should immediately queue assets for deletion if trash is disabled', async () => {
      const asset = AssetFactory.create();

      mocks.assetJob.streamForDeletedJob.mockReturnValue(makeStream([asset]));
      mocks.systemMetadata.get.mockResolvedValue({ trash: { enabled: false } });

      await expect(sut.handleAssetDeletionCheck()).resolves.toBe(JobStatus.Success);

      expect(mocks.assetJob.streamForDeletedJob).toHaveBeenCalledWith(new Date());
      expect(mocks.job.queueAll).toHaveBeenCalledWith([
        { name: JobName.AssetDelete, data: { id: asset.id, deleteOnDisk: true } },
      ]);
    });

    it('should queue assets for deletion after trash duration', async () => {
      const asset = AssetFactory.create();

      mocks.assetJob.streamForDeletedJob.mockReturnValue(makeStream([asset]));
      mocks.systemMetadata.get.mockResolvedValue({ trash: { enabled: true, days: 7 } });

      await expect(sut.handleAssetDeletionCheck()).resolves.toBe(JobStatus.Success);

      expect(mocks.assetJob.streamForDeletedJob).toHaveBeenCalledWith(DateTime.now().minus({ days: 7 }).toJSDate());
      expect(mocks.job.queueAll).toHaveBeenCalledWith([
        { name: JobName.AssetDelete, data: { id: asset.id, deleteOnDisk: true } },
      ]);
    });
  });

  describe('handleAssetDeletion', () => {
    it('should clean up files', async () => {
      const asset = AssetFactory.from()
        .file({ type: AssetFileType.Thumbnail })
        .file({ type: AssetFileType.Preview })
        .file({ type: AssetFileType.FullSize })
        .file({ type: AssetFileType.Preview, isEdited: true })
        .file({ type: AssetFileType.Thumbnail, isEdited: true })
        .build();
      mocks.assetJob.getForAssetDeletion.mockResolvedValue(getForAssetDeletion(asset));

      await sut.handleAssetDeletion({ id: asset.id, deleteOnDisk: true });

      expect(mocks.job.queue.mock.calls).toEqual([
        [
          {
            name: JobName.FileDelete,
            data: {
              files: [...asset.files.map(({ path }) => path), asset.originalPath],
            },
          },
        ],
      ]);
      expect(mocks.asset.remove).toHaveBeenCalledWith(getForAssetDeletion(asset));
    });

    it('should delete the entire stack if deleted asset was the primary asset and the stack would only contain one asset afterwards', async () => {
      const asset = AssetFactory.from()
        .stack({}, (builder) => builder.asset())
        .build();
      mocks.stack.delete.mockResolvedValue();
      mocks.assetJob.getForAssetDeletion.mockResolvedValue(getForAssetDeletion(asset));

      await sut.handleAssetDeletion({ id: asset.id, deleteOnDisk: true });

      expect(mocks.stack.delete).toHaveBeenCalledWith(asset.stackId);
    });

    it('should delete the stack when a non-primary asset is deleted and only the primary would remain', async () => {
      const asset = AssetFactory.from().build();
      const deletionAsset = {
        ...getForAssetDeletion(asset),
        stack: { id: newUuid(), primaryAssetId: newUuid(), assets: [{ id: asset.id }] },
      };
      mocks.stack.delete.mockResolvedValue();
      mocks.assetJob.getForAssetDeletion.mockResolvedValue(deletionAsset);

      await sut.handleAssetDeletion({ id: asset.id, deleteOnDisk: true });

      expect(mocks.stack.delete).toHaveBeenCalledWith(deletionAsset.stack.id);
    });

    it('should keep the stack when a non-primary asset is deleted and the primary plus another asset remain', async () => {
      const asset = AssetFactory.from().build();
      const deletionAsset = {
        ...getForAssetDeletion(asset),
        stack: { id: newUuid(), primaryAssetId: newUuid(), assets: [{ id: asset.id }, { id: newUuid() }] },
      };
      mocks.assetJob.getForAssetDeletion.mockResolvedValue(deletionAsset);

      await sut.handleAssetDeletion({ id: asset.id, deleteOnDisk: true });

      expect(mocks.stack.delete).not.toHaveBeenCalled();
      expect(mocks.stack.update).not.toHaveBeenCalled();
    });

    it('should delete a live photo', async () => {
      const motionAsset = AssetFactory.from({ type: AssetType.Video, visibility: AssetVisibility.Hidden }).build();
      const asset = AssetFactory.create({ livePhotoVideoId: motionAsset.id });
      mocks.assetJob.getForAssetDeletion.mockResolvedValue(getForAssetDeletion(asset));
      mocks.asset.getLivePhotoCount.mockResolvedValue(0);

      await sut.handleAssetDeletion({
        id: asset.id,
        deleteOnDisk: true,
      });

      expect(mocks.job.queue.mock.calls).toEqual([
        [{ name: JobName.AssetDelete, data: { id: motionAsset.id, deleteOnDisk: true } }],
        [{ name: JobName.FileDelete, data: { files: [asset.originalPath] } }],
      ]);
    });

    it('should not delete a live motion part if it is being used by another asset', async () => {
      const asset = AssetFactory.create({ livePhotoVideoId: newUuid() });
      mocks.asset.getLivePhotoCount.mockResolvedValue(2);
      mocks.assetJob.getForAssetDeletion.mockResolvedValue(getForAssetDeletion(asset));

      await sut.handleAssetDeletion({ id: asset.id, deleteOnDisk: true });

      expect(mocks.job.queue.mock.calls).toEqual([
        [{ name: JobName.FileDelete, data: { files: [`/data/library/IMG_${asset.id}.jpg`] } }],
      ]);
    });

    it('should update usage', async () => {
      const asset = AssetFactory.from().exif({ fileSizeInByte: 5000 }).build();
      mocks.assetJob.getForAssetDeletion.mockResolvedValue(getForAssetDeletion(asset));
      await sut.handleAssetDeletion({ id: asset.id, deleteOnDisk: true });
      expect(mocks.user.updateUsage).toHaveBeenCalledWith(asset.ownerId, -5000);
    });

    it('should fail if asset could not be found', async () => {
      mocks.assetJob.getForAssetDeletion.mockResolvedValue(void 0);
      await expect(sut.handleAssetDeletion({ id: AssetFactory.create().id, deleteOnDisk: true })).resolves.toBe(
        JobStatus.Failed,
      );
    });
  });

  describe('getOcr', () => {
    it('should require asset read permission', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set());

      await expect(sut.getOcr(authStub.admin, 'asset-1')).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.ocr.getByAssetId).not.toHaveBeenCalled();
    });

    it('should return OCR data for an asset', async () => {
      const ocr1 = factory.assetOcr({ text: 'Hello World' });
      const ocr2 = factory.assetOcr({ text: 'Test Image' });
      const asset = AssetFactory.from().exif().build();

      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.ocr.getByAssetId.mockResolvedValue([ocr1, ocr2]);
      mocks.asset.getForOcr.mockResolvedValue({ edits: [], ...asset.exifInfo });

      await expect(sut.getOcr(authStub.admin, asset.id)).resolves.toEqual([ocr1, ocr2]);

      expect(mocks.access.asset.checkOwnerAccess).toHaveBeenCalledWith(
        authStub.admin.user.id,
        new Set([asset.id]),
        undefined,
      );
      expect(mocks.ocr.getByAssetId).toHaveBeenCalledWith(asset.id);
    });

    it('should return empty array when no OCR data exists', async () => {
      const asset = AssetFactory.from().exif().build();
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));
      mocks.ocr.getByAssetId.mockResolvedValue([]);
      mocks.asset.getForOcr.mockResolvedValue({ edits: [], ...asset.exifInfo });
      await expect(sut.getOcr(authStub.admin, asset.id)).resolves.toEqual([]);

      expect(mocks.ocr.getByAssetId).toHaveBeenCalledWith(asset.id);
    });
  });

  describe('run', () => {
    it('should run the refresh faces job', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset-1']));

      await sut.run(authStub.admin, { assetIds: ['asset-1'], name: AssetJobName.REFRESH_FACES });

      expect(mocks.job.queueAll).toHaveBeenCalledWith([{ name: JobName.AssetDetectFaces, data: { id: 'asset-1' } }]);
    });

    it('should run the refresh metadata job', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset-1']));

      await sut.run(authStub.admin, { assetIds: ['asset-1'], name: AssetJobName.REFRESH_METADATA });

      expect(mocks.job.queueAll).toHaveBeenCalledWith([
        { name: JobName.AssetExtractMetadata, data: { id: 'asset-1' } },
      ]);
    });

    it('should run the refresh thumbnails job', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset-1']));

      await sut.run(authStub.admin, { assetIds: ['asset-1'], name: AssetJobName.REGENERATE_THUMBNAIL });

      expect(mocks.job.queueAll).toHaveBeenCalledWith([
        { name: JobName.AssetGenerateThumbnails, data: { id: 'asset-1' } },
      ]);
    });

    it('should run the transcode video', async () => {
      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set(['asset-1']));

      await sut.run(authStub.admin, { assetIds: ['asset-1'], name: AssetJobName.TRANSCODE_VIDEO });

      expect(mocks.job.queueAll).toHaveBeenCalledWith([{ name: JobName.AssetEncodeVideo, data: { id: 'asset-1' } }]);
    });
  });

  describe('upsertMetadata', () => {
    it('should throw a bad request exception if duplicate keys are sent', async () => {
      const asset = AssetFactory.create();
      const items = [
        { key: AssetMetadataKey.MobileApp, value: { iCloudId: 'id1' } },
        { key: AssetMetadataKey.MobileApp, value: { iCloudId: 'id1' } },
      ];

      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));

      await expect(sut.upsertMetadata(authStub.admin, asset.id, { items })).rejects.toThrowError(
        'Duplicate items are not allowed:',
      );

      expect(mocks.asset.upsertBulkMetadata).not.toHaveBeenCalled();
    });
  });

  describe('upsertBulkMetadata', () => {
    it('should throw a bad request exception if duplicate keys are sent', async () => {
      const asset = AssetFactory.create();
      const items = [
        { assetId: asset.id, key: AssetMetadataKey.MobileApp, value: { iCloudId: 'id1' } },
        { assetId: asset.id, key: AssetMetadataKey.MobileApp, value: { iCloudId: 'id1' } },
      ];

      mocks.access.asset.checkOwnerAccess.mockResolvedValue(new Set([asset.id]));

      await expect(sut.upsertBulkMetadata(authStub.admin, { items })).rejects.toThrowError(
        'Duplicate items are not allowed:',
      );

      expect(mocks.asset.upsertBulkMetadata).not.toHaveBeenCalled();
    });
  });

  describe('editAsset', () => {
    it('should enforce crop first', async () => {
      await expect(
        sut.editAsset(authStub.admin, 'asset-1', {
          edits: [
            {
              action: AssetEditAction.Rotate,
              parameters: { angle: 90 },
            },
            {
              action: AssetEditAction.Crop,
              parameters: { x: 0, y: 0, width: 100, height: 100 },
            },
          ],
        }),
      ).rejects.toBeInstanceOf(BadRequestException);

      expect(mocks.assetEdit.replaceAll).not.toHaveBeenCalled();
    });
  });
});
