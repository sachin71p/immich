import CoreModel

/// Mirrors DECISIONS §10 (Visibility scope): `ContainerScope = { personalUserIds, spaceIds, libraryIds }`.
public struct ContainerScope: Sendable, Hashable {
  public var personalUserIds: Set<String>
  public var spaceIds: Set<String>
  public var libraryIds: Set<String>

  public init(personalUserIds: Set<String> = [], spaceIds: Set<String> = [], libraryIds: Set<String> = []) {
    self.personalUserIds = personalUserIds
    self.spaceIds = spaceIds
    self.libraryIds = libraryIds
  }

  public static let empty = ContainerScope()

  /// `(spaceId IS NULL AND libraryId IS NULL AND ownerId = ANY(personalUserIds)) OR spaceId = ANY(spaceIds)
  /// OR libraryId = ANY(libraryIds)` — §10.
  public func contains(_ asset: Asset) -> Bool {
    if let spaceId = asset.spaceId { return spaceIds.contains(spaceId) }
    if let libraryId = asset.libraryId { return libraryIds.contains(libraryId) }
    return personalUserIds.contains(asset.ownerId)
  }
}

/// The purpose a timeline query is for — §10 "Scope purposes".
public enum TimelinePurpose: Sendable, Hashable {
  /// Timeline, favorites view, search, map, explore, memories, stats, calendar.
  case timeline
  /// Trash, archive.
  case manage
  /// Locked view: personal = [me] only, no partners, no containers.
  case locked
}

/// An explicit, mutually-exclusive filter — mirrors the timeline/search DTOs' `spaceId`, `libraryId`,
/// `personalOnly` fields (§9/§10). Overrides preferences when access-checked.
public enum ExplicitContainerFilter: Sendable, Hashable {
  case personalOnly
  case space(String)
  case library(String)
}

/// Everything `TimelineScope.resolve` needs about the signed-in user's prefs and memberships.
public struct TimelineContext: Sendable {
  public var currentUserId: String
  public var prefs: SharedLibraryPrefs
  /// Partners sharing *with* the current user (`sharedWithId == currentUserId`).
  public var partners: [Partner]
  public var spaceMemberships: [SpaceMember]
  public var ownedLibraries: Set<String>
  public var libraryMemberships: [LibraryMember]
  public var explicitFilter: ExplicitContainerFilter?

  public init(
    currentUserId: String,
    prefs: SharedLibraryPrefs = SharedLibraryPrefs(),
    partners: [Partner] = [],
    spaceMemberships: [SpaceMember] = [],
    ownedLibraries: Set<String> = [],
    libraryMemberships: [LibraryMember] = [],
    explicitFilter: ExplicitContainerFilter? = nil
  ) {
    self.currentUserId = currentUserId
    self.prefs = prefs
    self.partners = partners
    self.spaceMemberships = spaceMemberships
    self.ownedLibraries = ownedLibraries
    self.libraryMemberships = libraryMemberships
    self.explicitFilter = explicitFilter
  }
}

public enum TimelineScope {
  /// Resolves the DECISIONS §10 `ContainerScope` for a query purpose, honouring an explicit filter first.
  public static func resolve(purpose: TimelinePurpose, context ctx: TimelineContext) -> ContainerScope {
    if let explicit = ctx.explicitFilter {
      return resolveExplicit(explicit, context: ctx)
    }
    switch purpose {
    case .timeline:
      var personal: Set<String> = []
      if ctx.prefs.showPersonalInTimeline { personal.insert(ctx.currentUserId) }
      for partner in ctx.partners where partner.inTimeline { personal.insert(partner.sharedById) }

      let spaceIds = Set(ctx.spaceMemberships.filter(\.showInTimeline).map(\.spaceId))

      var libraryIds = Set(
        ctx.libraryMemberships.filter(\.showInTimeline).map(\.libraryId)
      )
      libraryIds.formUnion(ctx.ownedLibraries.subtracting(Set(ctx.prefs.hiddenOwnedLibraryIds)))

      return ContainerScope(personalUserIds: personal, spaceIds: spaceIds, libraryIds: libraryIds)

    case .manage:
      let spaceIds = Set(ctx.spaceMemberships.map(\.spaceId))
      var libraryIds = Set(ctx.libraryMemberships.map(\.libraryId))
      libraryIds.formUnion(ctx.ownedLibraries)
      return ContainerScope(personalUserIds: [ctx.currentUserId], spaceIds: spaceIds, libraryIds: libraryIds)

    case .locked:
      return ContainerScope(personalUserIds: [ctx.currentUserId])
    }
  }

  /// An explicit filter still has to be access-checked (§9): a container the user isn't a member of
  /// resolves to an empty scope rather than leaking assets.
  private static func resolveExplicit(_ filter: ExplicitContainerFilter, context ctx: TimelineContext) -> ContainerScope {
    switch filter {
    case .personalOnly:
      return ContainerScope(personalUserIds: [ctx.currentUserId])
    case .space(let spaceId):
      guard ctx.spaceMemberships.contains(where: { $0.spaceId == spaceId }) else { return .empty }
      return ContainerScope(spaceIds: [spaceId])
    case .library(let libraryId):
      let hasAccess = ctx.ownedLibraries.contains(libraryId)
        || ctx.libraryMemberships.contains(where: { $0.libraryId == libraryId })
      guard hasAccess else { return .empty }
      return ContainerScope(libraryIds: [libraryId])
    }
  }
}
