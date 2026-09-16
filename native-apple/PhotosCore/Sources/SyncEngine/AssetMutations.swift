import CoreModel
import ImmichAPI
import LocalStore
import Rules

/// Brief task 5: "Mutations through API then local optimistic update" — the server call always runs
/// first; the local write only happens once it succeeds, so a failed request never leaves the UI showing
/// a state the server doesn't have. `Rules.Permissions`/`MoveTargets` are the caller's job (the app layer
/// checks before even offering the action); these methods trust the caller already did that.
public struct AssetMutations: Sendable {
  let connection: ImmichConnection
  let localStore: PhotosLocalStore

  public init(connection: ImmichConnection, localStore: PhotosLocalStore) {
    self.connection = connection
    self.localStore = localStore
  }

  /// DECISIONS §4 "Favorites (R16)".
  public func setFavorite(ids: [String], isFavorite: Bool) async throws {
    let input = Operations.updateAssets.Input(body: .json(.init(ids: ids, isFavorite: isFavorite)))
    _ = try await connection.client.updateAssets(input)
    try await localStore.setFavorite(ids: ids, isFavorite: isFavorite)
  }

  public func setArchived(ids: [String], isArchived: Bool) async throws {
    let visibility: Components.Schemas.AssetVisibility = isArchived ? .archive : .timeline
    let input = Operations.updateAssets.Input(body: .json(.init(ids: ids, visibility: visibility)))
    _ = try await connection.client.updateAssets(input)
    try await localStore.setVisibility(ids: ids, visibility: isArchived ? .archive : .timeline)
  }

  /// Hides/unhides via the same bulk-update visibility field as archive (DECISIONS §4 edit rights).
  public func setHidden(ids: [String], isHidden: Bool) async throws {
    let visibility: Components.Schemas.AssetVisibility = isHidden ? .hidden : .timeline
    let input = Operations.updateAssets.Input(body: .json(.init(ids: ids, visibility: visibility)))
    _ = try await connection.client.updateAssets(input)
    try await localStore.setVisibility(ids: ids, visibility: isHidden ? .hidden : .timeline)
  }

  /// Locked media is deliberately a separate visibility state from Hidden. App shells must only
  /// offer this mutation for assets in the signed-in user's personal library, after local-device
  /// authentication has succeeded.
  public func setLocked(ids: [String], isLocked: Bool) async throws {
    let visibility: Components.Schemas.AssetVisibility = isLocked ? .locked : .timeline
    let input = Operations.updateAssets.Input(body: .json(.init(ids: ids, visibility: visibility)))
    _ = try await connection.client.updateAssets(input)
    try await localStore.setVisibility(ids: ids, visibility: isLocked ? .locked : .timeline)
  }

  /// Trash (soft delete, `force: false`).
  public func trash(ids: [String]) async throws {
    let input = Operations.deleteAssets.Input(body: .json(.init(force: false, ids: ids)))
    _ = try await connection.client.deleteAssets(input)
    try await localStore.trash(ids: ids)
  }

  /// Restore out of trash.
  public func restore(ids: [String]) async throws {
    let input = Operations.restoreAssets.Input(body: .json(.init(ids: ids)))
    _ = try await connection.client.restoreAssets(input)
    try await localStore.restore(ids: ids)
  }

  /// Permanently delete (`force: true`) — only reachable from the trash per DECISIONS §8.
  public func permanentlyDelete(ids: [String]) async throws {
    let input = Operations.deleteAssets.Input(body: .json(.init(force: true, ids: ids)))
    _ = try await connection.client.deleteAssets(input)
    try await localStore.permanentlyDelete(ids: ids)
  }

  /// `POST /assets/move` — DECISIONS §6. Applies the per-asset `moved` results locally; `noop`/`error`
  /// results are left untouched (the caller surfaces `reason` for `error`).
  @discardableResult
  public func move(ids: [String], to target: MoveTarget) async throws -> [MoveResult] {
    let wireTarget: Components.Schemas.AssetMoveDto.targetPayload
    switch target {
    case .personal:
      wireTarget = .case1(.init(_type: .personal))
    case .space(let id):
      wireTarget = .case2(.init(_type: .space, id: id))
    case .library(let id):
      wireTarget = .case3(.init(_type: .library, id: id))
    }
    let input = Operations.moveAssets.Input(body: .json(.init(assetIds: ids, target: wireTarget)))
    let output = try await connection.client.moveAssets(input)
    guard case let .created(response) = output, case let .json(body) = response.body else {
      throw AssetMutationError.unexpectedResponse
    }
    let results = body.results.map { result in
      MoveResult(assetId: result.id, status: MoveStatus(rawValue: result.status.rawValue) ?? .error, reason: result.reason)
    }
    try await localStore.applyMoveResults(results, target: target)
    return results
  }
}

public enum AssetMutationError: Error, Sendable {
  case unexpectedResponse
}
