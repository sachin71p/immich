/// Where an asset lives — DECISIONS §10 `ContainerScope`. `personal` carries the owning user id so
/// `Permissions` can tell "my personal library" from "someone else's" (e.g. a partner's).
public enum Container: Sendable, Hashable {
  case personal(String)
  case space(String)
  case library(String)

  public var kind: ContainerKind {
    switch self {
    case .personal: return .personal
    case .space: return .space
    case .library: return .library
    }
  }
}

/// Mirrors the `AssetMoveDto.target` discriminated union (`open-api/immich-openapi-specs.json`,
/// operation `moveAssets`) — DECISIONS §6.
public enum MoveTarget: Sendable, Hashable {
  case personal
  case space(String)
  case library(String)
}

/// Mirrors `AssetMoveResponseDto.results[].status`.
public enum MoveStatus: String, Sendable, Codable {
  case moved
  case noop
  case error
}

public struct MoveResult: Sendable, Hashable {
  public var assetId: String
  public var status: MoveStatus
  public var reason: String?

  public init(assetId: String, status: MoveStatus, reason: String? = nil) {
    self.assetId = assetId
    self.status = status
    self.reason = reason
  }
}
