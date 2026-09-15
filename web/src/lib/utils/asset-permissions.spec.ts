import { canEditAsset, canFavoriteAsset, type PermissionContext } from '$lib/utils/asset-permissions';

const context = (overrides: Partial<PermissionContext> = {}): PermissionContext => ({
  userId: 'me',
  spaceIds: new Set(),
  libraryIds: new Set(),
  ...overrides,
});

describe('canEditAsset', () => {
  it('grants access to the asset owner', () => {
    expect(canEditAsset({ ownerId: 'me' }, context())).toBe(true);
  });

  it('grants access to a member of the asset space', () => {
    const asset = { ownerId: 'other', spaceId: 'space-1' };
    expect(canEditAsset(asset, context({ spaceIds: new Set(['space-1']) }))).toBe(true);
  });

  it('grants access to a member of the asset library', () => {
    const asset = { ownerId: 'other', libraryId: 'library-1' };
    expect(canEditAsset(asset, context({ libraryIds: new Set(['library-1']) }))).toBe(true);
  });

  it('denies access when the user is not the owner and not a space/library member', () => {
    const asset = { ownerId: 'other', spaceId: 'space-1', libraryId: 'library-1' };
    expect(canEditAsset(asset, context())).toBe(false);
  });

  it('denies access to a member of a different space', () => {
    const asset = { ownerId: 'other', spaceId: 'space-1' };
    expect(canEditAsset(asset, context({ spaceIds: new Set(['space-2']) }))).toBe(false);
  });
});

describe('canFavoriteAsset', () => {
  it('grants access when canEditAsset would grant access', () => {
    expect(canFavoriteAsset({ ownerId: 'me' }, context())).toBe(true);
  });

  it('grants access to an album member even without edit access', () => {
    const asset = { ownerId: 'other' };
    expect(canFavoriteAsset(asset, context(), { isAlbumMember: true })).toBe(true);
  });

  it('denies access to a non-member, non-owner, non-album-member', () => {
    const asset = { ownerId: 'other' };
    expect(canFavoriteAsset(asset, context(), { isAlbumMember: false })).toBe(false);
  });
});
