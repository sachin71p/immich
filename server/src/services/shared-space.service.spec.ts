import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { Mocked, vitest } from 'vitest';
import { Permission, SharedSpaceRole } from 'src/enum.js';
import { AssetRelocationService } from 'src/services/asset-relocation.service.js';
import { SharedSpaceService } from 'src/services/shared-space.service.js';
import { AuthFactory } from 'test/factories/auth.factory.js';
import { IAccessRepositoryMock, newAccessRepositoryMock } from 'test/repositories/access.repository.mock.js';

// fork: shared-libraries - SharedSpaceService does not extend BaseService, so it is constructed
// directly with hand-rolled mocks, matching the shape of its own constructor.
const newSharedSpaceRepositoryMock = () => ({
  getAll: vitest.fn().mockResolvedValue([]),
  get: vitest.fn(),
  create: vitest.fn(),
  getStorageLabelCandidates: vitest.fn().mockResolvedValue([]),
  update: vitest.fn(),
  getMembers: vitest.fn().mockResolvedValue([]),
  getOwnedSpaces: vitest.fn().mockResolvedValue([]),
  addMembers: vitest.fn().mockResolvedValue(true),
  removeMember: vitest.fn(),
  updateMember: vitest.fn(),
  transferOwner: vitest.fn().mockResolvedValue(undefined),
  deleteSpace: vitest.fn().mockResolvedValue(undefined),
  isMember: vitest.fn().mockResolvedValue(true),
});

const newAssetRelocationServiceMock = (): Mocked<AssetRelocationService> =>
  ({
    requestRelocation: vitest.fn().mockResolvedValue(undefined),
  }) as unknown as Mocked<AssetRelocationService>;

describe(SharedSpaceService.name, () => {
  let sut: SharedSpaceService;
  let access: IAccessRepositoryMock;
  let sharedSpaceMock: ReturnType<typeof newSharedSpaceRepositoryMock>;
  let relocationMock: Mocked<AssetRelocationService>;

  beforeEach(() => {
    access = newAccessRepositoryMock();
    sharedSpaceMock = newSharedSpaceRepositoryMock();
    relocationMock = newAssetRelocationServiceMock();
    sut = new SharedSpaceService(access as never, sharedSpaceMock as never, relocationMock);
  });

  const space = {
    id: 'space-1',
    name: 'Trip',
    description: '',
    thumbnailAssetId: null,
    createdAt: new Date(),
    updatedAt: new Date(),
    role: SharedSpaceRole.Owner,
    showInTimeline: true,
    memberCount: 1,
    assetCount: 0,
  };

  describe('create', () => {
    it('should create a space with a unique storage label slug derived from the name', async () => {
      const auth = AuthFactory.create();
      sharedSpaceMock.getStorageLabelCandidates.mockResolvedValue(['trip']);
      sharedSpaceMock.create.mockResolvedValue({ ...space });

      await sut.create(auth, { name: 'Trip', description: undefined });

      expect(sharedSpaceMock.create).toHaveBeenCalledWith({
        name: 'Trip',
        description: undefined,
        createdById: auth.user.id,
        storageLabel: 'trip-2',
      });
    });
  });

  describe('get', () => {
    it('should require member access', async () => {
      const auth = AuthFactory.create();
      access.space.checkMemberAccess.mockResolvedValue(new Set());

      await expect(sut.get(auth, space.id)).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('should return the space for a member', async () => {
      const auth = AuthFactory.create();
      access.space.checkMemberAccess.mockResolvedValue(new Set([space.id]));
      sharedSpaceMock.get.mockResolvedValue(space);

      await expect(sut.get(auth, space.id)).resolves.toMatchObject({ id: space.id, role: SharedSpaceRole.Owner });
    });
  });

  describe('delete', () => {
    it('should reject a contributor deleting the space', async () => {
      const auth = AuthFactory.create();
      access.space.checkOwnerAccess.mockResolvedValue(new Set());

      await expect(sut.delete(auth, space.id)).rejects.toBeInstanceOf(ForbiddenException);
      expect(sharedSpaceMock.deleteSpace).not.toHaveBeenCalled();
    });

    it('should let the owner delete the space and request relocation for its assets', async () => {
      const auth = AuthFactory.create();
      access.space.checkOwnerAccess.mockResolvedValue(new Set([space.id]));
      sharedSpaceMock.deleteSpace.mockImplementation(async (id, onAssets) => {
        await onAssets(['asset-1', 'asset-2'], {} as never);
      });

      await sut.delete(auth, space.id);

      expect(sharedSpaceMock.deleteSpace).toHaveBeenCalledWith(space.id, expect.any(Function));
      expect(relocationMock.requestRelocation).toHaveBeenCalledWith(
        ['asset-1', 'asset-2'],
        auth.user.id,
        expect.anything(),
      );
    });
  });

  describe('removeMember', () => {
    it('should not allow removing the owner', async () => {
      const auth = AuthFactory.create();
      access.space.checkMemberAccess.mockResolvedValue(new Set([space.id]));
      sharedSpaceMock.getMembers.mockResolvedValue([
        { userId: 'owner-1', role: SharedSpaceRole.Owner, showInTimeline: true, createdAt: new Date() },
      ]);

      await expect(sut.removeMember(auth, space.id, 'owner-1')).rejects.toBeInstanceOf(BadRequestException);
      expect(sharedSpaceMock.removeMember).not.toHaveBeenCalled();
    });

    it('should allow a member to remove a contributor', async () => {
      const auth = AuthFactory.create();
      access.space.checkMemberAccess.mockResolvedValue(new Set([space.id]));
      sharedSpaceMock.getMembers.mockResolvedValue([
        { userId: auth.user.id, role: SharedSpaceRole.Owner, showInTimeline: true, createdAt: new Date() },
        { userId: 'contributor-1', role: SharedSpaceRole.Contributor, showInTimeline: true, createdAt: new Date() },
      ]);

      await sut.removeMember(auth, space.id, 'contributor-1');

      expect(sharedSpaceMock.removeMember).toHaveBeenCalledWith(space.id, 'contributor-1');
    });
  });

  describe('transferOwner', () => {
    it('should reject a contributor transferring ownership', async () => {
      const auth = AuthFactory.create();
      access.space.checkOwnerAccess.mockResolvedValue(new Set());

      await expect(sut.transferOwner(auth, space.id, { userId: 'contributor-1' })).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      expect(sharedSpaceMock.transferOwner).not.toHaveBeenCalled();
    });

    it('should reject transferring to a non-member', async () => {
      const auth = AuthFactory.create();
      access.space.checkOwnerAccess.mockResolvedValue(new Set([space.id]));
      sharedSpaceMock.isMember.mockResolvedValue(false);

      await expect(sut.transferOwner(auth, space.id, { userId: 'not-a-member' })).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });

    it('should transfer ownership to a contributor', async () => {
      const auth = AuthFactory.create();
      access.space.checkOwnerAccess.mockResolvedValue(new Set([space.id]));
      sharedSpaceMock.isMember.mockResolvedValue(true);

      await sut.transferOwner(auth, space.id, { userId: 'contributor-1' });

      expect(sharedSpaceMock.transferOwner).toHaveBeenCalledWith(space.id, auth.user.id, 'contributor-1');
    });
  });

  describe('addMembers', () => {
    it('should reject users that do not exist or are already members', async () => {
      const auth = AuthFactory.create();
      access.space.checkMemberAccess.mockResolvedValue(new Set([space.id]));
      sharedSpaceMock.addMembers.mockResolvedValue(false);

      await expect(sut.addMembers(auth, space.id, { userIds: ['user-1'] })).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe(Permission.SharedSpaceMemberUpdate, () => {
    it('should update the caller timeline preference for the space', async () => {
      const auth = AuthFactory.create();
      access.space.checkMemberAccess.mockResolvedValue(new Set([space.id]));

      await sut.updateMyTimeline(auth, space.id, { showInTimeline: false });

      expect(sharedSpaceMock.updateMember).toHaveBeenCalledWith(space.id, auth.user.id, { showInTimeline: false });
    });
  });
});
