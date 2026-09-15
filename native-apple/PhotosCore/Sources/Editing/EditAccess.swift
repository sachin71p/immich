import CoreModel
import Foundation
import Rules

/// Permission gating for the editor (brief Tests: "permission gating via Rules";
/// DECISIONS section 4 "who may edit"). Editing requires `Permissions.canEdit` — owner
/// access or space/library membership on the asset's container. Albums never grant edit.
public enum EditAccess {
  public static func canEdit(_ asset: Asset, in ctx: AccessContext) -> Bool {
    Permissions.canEdit(asset, in: ctx)
  }

  public static func requireEdit(_ asset: Asset, in ctx: AccessContext) throws {
    guard canEdit(asset, in: ctx) else { throw EditAccessError.notPermitted }
  }
}

public enum EditAccessError: Error, Sendable, Equatable {
  case notPermitted
}
