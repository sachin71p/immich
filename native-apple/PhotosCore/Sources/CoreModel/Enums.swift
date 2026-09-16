/// Mirrors of server enums used across the fork. Kept as plain `String` raw values so they
/// round-trip through both the generated `ImmichAPI` JSON payloads and GRDB columns unchanged.

/// Mirrors `server/src/enum.ts` `AssetType`.
public enum AssetKind: String, Sendable, Codable, CaseIterable {
  case image = "IMAGE"
  case video = "VIDEO"
  case audio = "AUDIO"
  case other = "OTHER"
}

/// Mirrors `server/src/enum.ts` `AssetVisibility`.
public enum AssetVisibilityKind: String, Sendable, Codable, CaseIterable {
  case archive
  case timeline
  case hidden
  case locked
}

/// Mirrors `server/src/enum.ts` `AlbumUserRole`.
public enum AlbumUserRoleKind: String, Sendable, Codable, CaseIterable {
  case owner
  case editor
  case viewer
}

/// Mirrors `server/src/enum.ts` `SharedSpaceRole` — DECISIONS §4.
public enum SharedSpaceRoleKind: String, Sendable, Codable, CaseIterable {
  case owner
  case contributor
}

/// The three container kinds an asset can belong to — DECISIONS §10.
public enum ContainerKind: String, Sendable, Codable, CaseIterable {
  case personal
  case space
  case library
}
