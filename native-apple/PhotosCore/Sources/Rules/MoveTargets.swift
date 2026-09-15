import CoreModel

/// Mirrors DECISIONS §6 (Move rules, R4/R5/R10). Server source of truth: `POST /assets/move`
/// (`server/src/services/asset.service.ts` move handling).
public enum MoveTargets {
  /// Targets a single asset is allowed to move to, ignoring live-photo/stack group expansion (rule 5,
  /// the caller's job — see `allowed(selection:target:in:)`) and duplicate-checksum collisions (rule 8,
  /// server-only). The asset's current container is never included (rule 7: moving to the current
  /// container is a no-op, not an actionable move-sheet target).
  public static func allowed(for asset: Asset, in ctx: AccessContext) -> Set<MoveTarget> {
    // Rule 9: locked assets cannot move.
    guard !ctx.lockedAssetIds.contains(asset.id) else { return [] }
    // Rule 1: U needs container access to the source.
    guard Permissions.hasContainerAccess(asset.container, in: ctx) else { return [] }

    var targets: Set<MoveTarget> = []
    // Rule 2: personal target only if the asset is owned by U.
    if asset.ownerId == ctx.currentUserId {
      targets.insert(.personal)
    }
    // Rule 3: space target if U is a member.
    for spaceId in ctx.memberSpaceIds {
      targets.insert(.space(spaceId))
    }
    // Rule 4: external library target if U has access AND the library has an uploadPath.
    for libraryId in ctx.accessibleLibraryIds where ctx.libraryUploadPathIds.contains(libraryId) {
      targets.insert(.library(libraryId))
    }

    targets.remove(currentTarget(of: asset))
    return targets
  }

  /// Selection-level result: `groups` are pre-expanded by the caller to include live-photo pairs and
  /// stack siblings (rule 5). A group is only eligible for `target` if every member of the group allows
  /// it (or is already there); one asset failing fails the whole group, independent of other groups.
  public static func allowed(selection groups: [[Asset]], target: MoveTarget, in ctx: AccessContext) -> [String: Bool] {
    var result: [String: Bool] = [:]
    for group in groups {
      let eligible = group.allSatisfy { asset in
        currentTarget(of: asset) == target || allowed(for: asset, in: ctx).contains(target)
      }
      for asset in group {
        result[asset.id] = eligible
      }
    }
    return result
  }

  static func currentTarget(of asset: Asset) -> MoveTarget {
    switch asset.container {
    case .personal: return .personal
    case .space(let id): return .space(id)
    case .library(let id): return .library(id)
    }
  }
}
