// fork: shared-libraries
// Container-aware edit/favorite permission helper (DECISIONS §4). Operates on the fields
// available on the full AssetResponseDto (ownerId + spaceId + libraryId); the lightweight
// TimelineAsset used by the bulk timeline grid does not carry spaceId/libraryId, so bulk
// timeline selections still fall back to ownerId-only checks (see S8b handoff).

export type PermissionAsset = {
  ownerId: string;
  spaceId?: string | null;
  libraryId?: string | null;
};

export type PermissionContext = {
  userId: string;
  spaceIds: ReadonlySet<string>;
  libraryIds: ReadonlySet<string>;
};

/** Edit metadata, edit image, archive, trash, restore, permanently delete: owner-access, space members, library members. */
export const canEditAsset = (asset: PermissionAsset, context: PermissionContext): boolean => {
  if (asset.ownerId === context.userId) {
    return true;
  }
  if (asset.spaceId && context.spaceIds.has(asset.spaceId)) {
    return true;
  }
  if (asset.libraryId && context.libraryIds.has(asset.libraryId)) {
    return true;
  }
  return false;
};

/** Personal container only (DECISIONS I7: Locked visibility is personal-only). */
export const isPersonalAsset = (asset: PermissionAsset): boolean => !asset.spaceId && !asset.libraryId;

/** Favorite: everyone canEditAsset() covers, plus members of any album containing the asset. Partners: no. */
export const canFavoriteAsset = (
  asset: PermissionAsset,
  context: PermissionContext,
  options: { isAlbumMember?: boolean } = {},
): boolean => canEditAsset(asset, context) || !!options.isAlbumMember;
