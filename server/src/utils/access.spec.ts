import { AlbumUserRole, Permission } from 'src/enum.js';
import { AccessRepository } from 'src/repositories/access.repository.js';
import { checkAccess } from 'src/utils/access.js';
import { AuthFactory } from 'test/factories/auth.factory.js';
import { newAccessRepositoryMock } from 'test/repositories/access.repository.mock.js';

describe('shared-library access', () => {
  const assetIds = new Set(['asset-1', 'asset-2']);

  it('allows a space member to manage a space asset, but not a non-member', async () => {
    const auth = AuthFactory.create();
    const access = newAccessRepositoryMock();
    access.asset.checkSpaceAccess.mockResolvedValue(new Set(['asset-1']));

    await expect(
      checkAccess(access as unknown as AccessRepository, { auth, permission: Permission.AssetUpdate, ids: assetIds }),
    ).resolves.toEqual(new Set(['asset-1']));
  });

  it('allows a library member to read an external-library asset', async () => {
    const auth = AuthFactory.create();
    const access = newAccessRepositoryMock();
    access.asset.checkLibraryMemberAccess.mockResolvedValue(new Set(['asset-1']));

    await expect(
      checkAccess(access as unknown as AccessRepository, { auth, permission: Permission.AssetRead, ids: assetIds }),
    ).resolves.toEqual(new Set(['asset-1']));
  });

  it.each([
    ['PERM-01-contributor', Permission.AssetFileDownload],
    ['PERM-03-contributor', Permission.AssetEditGet],
  ])('%s allows a container contributor to %s', async (contractId, permission) => {
    const auth = AuthFactory.create();
    const access = newAccessRepositoryMock();

    if (permission === Permission.AssetFileDownload) {
      access.assetFile.checkSpaceAccess.mockResolvedValue(new Set(['asset-1']));
      access.assetFile.checkLibraryMemberAccess.mockResolvedValue(new Set(['asset-2']));
    } else {
      access.asset.checkSpaceAccess.mockResolvedValue(new Set(['asset-1']));
      access.asset.checkLibraryMemberAccess.mockResolvedValue(new Set(['asset-2']));
    }

    await expect(
      checkAccess(access as unknown as AccessRepository, { auth, permission, ids: new Set(['asset-1', 'asset-2']) }),
    ).resolves.toEqual(new Set(['asset-1', 'asset-2']));
  });

  it.each([Permission.AlbumAssetCreate, Permission.AlbumAssetDelete])(
    'allows album viewers to manage album assets (R11): %s',
    async (permission) => {
      const auth = AuthFactory.create();
      const access = newAccessRepositoryMock();
      access.album.checkSharedAlbumAccess.mockResolvedValue(new Set(['album-1']));

      await expect(
        checkAccess(access as unknown as AccessRepository, { auth, permission, ids: new Set(['album-1']) }),
      ).resolves.toEqual(new Set(['album-1']));
      expect(access.album.checkSharedAlbumAccess).toHaveBeenCalledWith(
        auth.user.id,
        new Set(['album-1']),
        AlbumUserRole.Viewer,
      );
    },
  );

  it('allows album members to favorite, but not update, album assets', async () => {
    const auth = AuthFactory.create();
    const access = newAccessRepositoryMock();
    access.asset.checkAlbumMemberAccess.mockResolvedValue(new Set(['asset-1']));
    access.asset.checkAlbumAccess.mockResolvedValue(new Set(['asset-1']));

    await expect(
      checkAccess(access as unknown as AccessRepository, { auth, permission: Permission.AssetFavorite, ids: assetIds }),
    ).resolves.toEqual(new Set(['asset-1']));
    await expect(
      checkAccess(access as unknown as AccessRepository, { auth, permission: Permission.AssetUpdate, ids: assetIds }),
    ).resolves.toEqual(new Set());
  });
});
