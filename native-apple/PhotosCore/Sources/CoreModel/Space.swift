import Foundation

/// Mirrors `SyncSharedSpaceV1` — DECISIONS §4/§10 "space".
public struct Space: Sendable, Identifiable, Hashable {
  public var id: String
  public var name: String
  public var description: String
  public var createdAt: Date
  public var updatedAt: Date

  public init(id: String, name: String, description: String, createdAt: Date, updatedAt: Date) {
    self.id = id
    self.name = name
    self.description = description
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// Mirrors `SyncSharedSpaceMemberV1`.
public struct SpaceMember: Sendable, Hashable {
  public var spaceId: String
  public var userId: String
  public var role: SharedSpaceRoleKind
  public var showInTimeline: Bool

  public init(spaceId: String, userId: String, role: SharedSpaceRoleKind, showInTimeline: Bool) {
    self.spaceId = spaceId
    self.userId = userId
    self.role = role
    self.showInTimeline = showInTimeline
  }
}

/// Mirrors `SyncSharedLibraryV1` — DECISIONS §4/§10 "external library".
public struct Library: Sendable, Identifiable, Hashable {
  public var id: String
  public var name: String
  public var ownerId: String
  public var createdAt: Date
  public var updatedAt: Date

  public init(id: String, name: String, ownerId: String, createdAt: Date, updatedAt: Date) {
    self.id = id
    self.name = name
    self.ownerId = ownerId
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// A library member. The sync stream backfills these the same way space membership backfills (S6
/// handoff); the fork does not currently emit a dedicated `SyncEntityType` for library members
/// (see CODEMAP-FIX in the A1 handoff) so membership is instead inferred from `SharedLibraryAssets*`
/// coverage — kept here for `Permissions`/`Rules` call sites that need the shape regardless.
public struct LibraryMember: Sendable, Hashable {
  public var libraryId: String
  public var userId: String
  public var role: SharedSpaceRoleKind
  public var showInTimeline: Bool

  public init(libraryId: String, userId: String, role: SharedSpaceRoleKind, showInTimeline: Bool) {
    self.libraryId = libraryId
    self.userId = userId
    self.role = role
    self.showInTimeline = showInTimeline
  }
}
