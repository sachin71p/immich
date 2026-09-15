import CoreModel

/// Mirrors DECISIONS §4 (Roles & permissions) exactly. `server/src/utils/access.ts` is the source of
/// truth; keep these branches in lock-step with it.
public enum Permissions {
  /// Owner-access, space membership, or library membership/ownership on `container` — the baseline every
  /// other permission in the §4 table builds on ("View / download", "Upload", "Edit metadata …" rows).
  public static func hasContainerAccess(_ container: Container, in ctx: AccessContext) -> Bool {
    switch container {
    case .personal(let ownerId):
      return ownerId == ctx.currentUserId
    case .space(let spaceId):
      return ctx.memberSpaceIds.contains(spaceId)
    case .library(let libraryId):
      return ctx.accessibleLibraryIds.contains(libraryId)
    }
  }

  /// "Edit metadata, edit image, favorite, archive, trash, restore, permanently delete space assets" —
  /// owner and contributor both get full edit rights; non-members get none. §4.
  public static func canEdit(_ asset: Asset, in ctx: AccessContext) -> Bool {
    hasContainerAccess(asset.container, in: ctx)
  }

  /// Favorites are broader than `canEdit`: owner-access, space/library members, or any album member for
  /// this asset — but never partners. §4 "Favorites (R16)".
  public static func canFavorite(_ asset: Asset, in ctx: AccessContext) -> Bool {
    hasContainerAccess(asset.container, in: ctx) || !ctx.memberAlbumIds(for: asset.id).isEmpty
  }

  /// Trash / permanently delete — same membership rule as edit. §4.
  public static func canDelete(_ asset: Asset, in ctx: AccessContext) -> Bool {
    hasContainerAccess(asset.container, in: ctx)
  }

  /// Whether the asset may move to `target` at all (container access + target-specific rule); does not
  /// evaluate live-photo/stack group expansion or duplicate collisions — see `MoveTargets`. §6.
  public static func canMove(_ asset: Asset, to target: MoveTarget, in ctx: AccessContext) -> Bool {
    MoveTargets.allowed(for: asset, in: ctx).contains(target)
  }
}
