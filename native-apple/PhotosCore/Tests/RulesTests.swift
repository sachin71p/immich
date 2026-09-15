import CoreModel
import Foundation
import Rules
import Testing

/// AP-02 (TESTING.md §5): "`rules-cases.json` passes in Swift `Rules` and in server unit tests (parity)".
/// `e2e/fork-assets/rules-cases.json` doesn't exist yet — it's produced by T0, which hasn't landed (⬜ in
/// STATUS.md) — so these cases are written directly from DECISIONS §4/§6/§10 instead, as the brief's own
/// Tests section asks for. Once T0 lands, a follow-up should cross-check this file against the generated
/// fixture rather than replace it (parity, not a rewrite).
@Suite struct RulesTests {
  // MARK: - §4 Roles & permissions

  private func spaceAsset(ownerId: String = "owner-1", spaceId: String = "space-1", id: String = "asset-1") -> Asset {
    Asset(id: id, ownerId: ownerId, originalFileName: "f.heic", checksum: "c", type: .image, spaceId: spaceId)
  }

  @Test("[AP-02] R4-01 space owner can edit/favorite/delete a space asset")
  func spaceOwnerHasFullAccess() {
    let ctx = AccessContext(currentUserId: "owner-1", memberSpaceIds: ["space-1"])
    let asset = spaceAsset()
    #expect(Permissions.canEdit(asset, in: ctx))
    #expect(Permissions.canFavorite(asset, in: ctx))
    #expect(Permissions.canDelete(asset, in: ctx))
  }

  @Test("[AP-02] R4-02 space contributor (not the owner) has the same edit/favorite/delete rights")
  func spaceContributorHasFullAccess() {
    let ctx = AccessContext(currentUserId: "contributor-1", memberSpaceIds: ["space-1"])
    let asset = spaceAsset(ownerId: "owner-1")
    #expect(Permissions.canEdit(asset, in: ctx))
    #expect(Permissions.canFavorite(asset, in: ctx))
    #expect(Permissions.canDelete(asset, in: ctx))
  }

  @Test("[AP-02] R4-03 a non-member has none of edit/favorite/delete on a space asset")
  func nonMemberHasNoAccess() {
    let ctx = AccessContext(currentUserId: "outsider")
    let asset = spaceAsset()
    #expect(!Permissions.canEdit(asset, in: ctx))
    #expect(!Permissions.canFavorite(asset, in: ctx))
    #expect(!Permissions.canDelete(asset, in: ctx))
  }

  @Test("[AP-02] R4-04/R16 favorite is granted via album membership alone, without container access")
  func favoriteViaAlbumMembership() {
    let asset = spaceAsset(ownerId: "owner-1")
    let ctx = AccessContext(currentUserId: "album-member", memberAlbumIdsByAsset: [asset.id: ["album-1"]])
    #expect(!Permissions.canEdit(asset, in: ctx))
    #expect(Permissions.canFavorite(asset, in: ctx))
  }

  @Test("[AP-02] R4-05 a partner (no container/album access) cannot favorite — DECISIONS §4 'Partners: no'")
  func partnerCannotFavorite() {
    let asset = Asset(id: "asset-2", ownerId: "owner-1", originalFileName: "f.heic", checksum: "c", type: .image)
    // A partner relationship never appears in AccessContext (it only ever grants timeline visibility,
    // never edit/favorite rights), so an accessContext with no membership for this asset models it exactly.
    let ctx = AccessContext(currentUserId: "partner-1")
    #expect(!Permissions.canFavorite(asset, in: ctx))
  }

  // MARK: - §6 Move rules

  @Test("[AP-02] R6-01 owner can move their own personal asset into a space they're a member of")
  func personalAssetCanMoveIntoMemberSpace() {
    let asset = Asset(id: "a", ownerId: "me", originalFileName: "f.heic", checksum: "c", type: .image)
    let ctx = AccessContext(currentUserId: "me", memberSpaceIds: ["space-1"])
    #expect(MoveTargets.allowed(for: asset, in: ctx) == [.space("space-1")])
  }

  @Test("[AP-02] R6-02 a space asset can move back to personal only if the acting user owns it")
  func spaceAssetMovesToPersonalOnlyForOwner() {
    let ownedByMe = Asset(id: "a", ownerId: "me", originalFileName: "f.heic", checksum: "c", type: .image, spaceId: "space-1")
    let ownedBySomeoneElse = Asset(id: "b", ownerId: "them", originalFileName: "f.heic", checksum: "c", type: .image, spaceId: "space-1")
    let ctx = AccessContext(currentUserId: "me", memberSpaceIds: ["space-1"])
    #expect(MoveTargets.allowed(for: ownedByMe, in: ctx).contains(.personal))
    #expect(!MoveTargets.allowed(for: ownedBySomeoneElse, in: ctx).contains(.personal))
  }

  @Test("[AP-02] R6-03 an external library is a move target only when its uploadPath is set")
  func libraryTargetRequiresUploadPath() {
    let asset = Asset(id: "a", ownerId: "me", originalFileName: "f.heic", checksum: "c", type: .image)
    let withoutUploadPath = AccessContext(currentUserId: "me", accessibleLibraryIds: ["lib-1"])
    let withUploadPath = AccessContext(currentUserId: "me", accessibleLibraryIds: ["lib-1"], libraryUploadPathIds: ["lib-1"])
    #expect(!MoveTargets.allowed(for: asset, in: withoutUploadPath).contains(.library("lib-1")))
    #expect(MoveTargets.allowed(for: asset, in: withUploadPath).contains(.library("lib-1")))
  }

  @Test("[AP-02] R6-07 moving to the current container is excluded from the move-sheet target set")
  func currentContainerIsExcluded() {
    let asset = Asset(id: "a", ownerId: "me", originalFileName: "f.heic", checksum: "c", type: .image, spaceId: "space-1")
    let ctx = AccessContext(currentUserId: "me", memberSpaceIds: ["space-1"])
    #expect(!MoveTargets.allowed(for: asset, in: ctx).contains(.space("space-1")))
  }

  @Test("[AP-02] R6-09 a locked asset has no move targets at all")
  func lockedAssetCannotMove() {
    let asset = Asset(id: "a", ownerId: "me", originalFileName: "f.heic", checksum: "c", type: .image)
    let ctx = AccessContext(currentUserId: "me", memberSpaceIds: ["space-1"], lockedAssetIds: ["a"])
    #expect(MoveTargets.allowed(for: asset, in: ctx).isEmpty)
  }

  @Test("[AP-02] R6-01 needs container access to the source; a non-member has no move targets")
  func nonMemberOfSourceCannotMove() {
    let asset = spaceAsset()
    let ctx = AccessContext(currentUserId: "outsider")
    #expect(MoveTargets.allowed(for: asset, in: ctx).isEmpty)
  }

  @Test("[AP-02] R6-05 a selection group fails together: one ineligible asset fails the whole group")
  func selectionGroupFailsTogether() {
    let eligible = Asset(id: "a", ownerId: "me", originalFileName: "f.heic", checksum: "c", type: .image)
    let ineligible = Asset(id: "b", ownerId: "someone-else", originalFileName: "f.heic", checksum: "c", type: .image)
    let ctx = AccessContext(currentUserId: "me", memberSpaceIds: ["space-1"])
    let result = MoveTargets.allowed(selection: [[eligible, ineligible]], target: .space("space-1"), in: ctx)
    #expect(result["a"] == false)
    #expect(result["b"] == false)
  }

  // MARK: - §10 Visibility scope

  @Test("[AP-02] R10-01 timeline scope includes the signed-in user and in-timeline partners")
  func timelineScopeIncludesPartners() {
    let ctx = TimelineContext(
      currentUserId: "me",
      partners: [Partner(sharedById: "partner-1", sharedWithId: "me", inTimeline: true)]
    )
    let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
    #expect(scope.personalUserIds == ["me", "partner-1"])
  }

  @Test("[AP-02] R10-01 a partner with inTimeline=false is excluded from timeline scope")
  func timelineScopeExcludesOptedOutPartner() {
    let ctx = TimelineContext(
      currentUserId: "me",
      partners: [Partner(sharedById: "partner-1", sharedWithId: "me", inTimeline: false)]
    )
    let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
    #expect(scope.personalUserIds == ["me"])
  }

  @Test("[AP-02] R9 showPersonalInTimeline=false removes the signed-in user's own assets from timeline scope")
  func showPersonalInTimelineToggle() {
    let ctx = TimelineContext(currentUserId: "me", prefs: SharedLibraryPrefs(showPersonalInTimeline: false))
    let scope = TimelineScope.resolve(purpose: .timeline, context: ctx)
    #expect(scope.personalUserIds.isEmpty)
  }

  @Test("[AP-02] R10-02 manage scope includes every member space regardless of showInTimeline, and no partners")
  func manageScopeIgnoresTimelineToggles() {
    let ctx = TimelineContext(
      currentUserId: "me",
      partners: [Partner(sharedById: "partner-1", sharedWithId: "me", inTimeline: true)],
      spaceMemberships: [SpaceMember(spaceId: "space-1", userId: "me", role: .contributor, showInTimeline: false)]
    )
    let scope = TimelineScope.resolve(purpose: .manage, context: ctx)
    #expect(scope.personalUserIds == ["me"])
    #expect(scope.spaceIds == ["space-1"])
  }

  @Test("[AP-02] R10-03 locked scope is personal-only, ignoring every membership")
  func lockedScopeIsPersonalOnly() {
    let ctx = TimelineContext(
      currentUserId: "me",
      spaceMemberships: [SpaceMember(spaceId: "space-1", userId: "me", role: .owner, showInTimeline: true)]
    )
    let scope = TimelineScope.resolve(purpose: .locked, context: ctx)
    #expect(scope == ContainerScope(personalUserIds: ["me"]))
  }

  @Test("[AP-02] R9 an owned library hidden via hiddenOwnedLibraryIds is excluded from timeline but included in manage")
  func hiddenOwnedLibraryToggle() {
    let ctx = TimelineContext(
      currentUserId: "me",
      prefs: SharedLibraryPrefs(hiddenOwnedLibraryIds: ["lib-1"]),
      ownedLibraries: ["lib-1"]
    )
    #expect(TimelineScope.resolve(purpose: .timeline, context: ctx).libraryIds.isEmpty)
    #expect(TimelineScope.resolve(purpose: .manage, context: ctx).libraryIds == ["lib-1"])
  }

  @Test("[AP-02] R9 an explicit filter for a space the user isn't a member of resolves to an empty scope")
  func explicitFilterIsAccessChecked() {
    let ctx = TimelineContext(currentUserId: "me", explicitFilter: .space("space-not-mine"))
    #expect(TimelineScope.resolve(purpose: .timeline, context: ctx) == .empty)
  }

  @Test("[AP-02] R9 an explicit personalOnly filter overrides preferences")
  func explicitPersonalOnlyFilter() {
    let ctx = TimelineContext(
      currentUserId: "me",
      prefs: SharedLibraryPrefs(showPersonalInTimeline: false),
      explicitFilter: .personalOnly
    )
    #expect(TimelineScope.resolve(purpose: .timeline, context: ctx) == ContainerScope(personalUserIds: ["me"]))
  }

  @Test("[AP-02] R10 ContainerScope.contains matches DECISIONS §10's membership formula")
  func containerScopeContainsFormula() {
    let scope = ContainerScope(personalUserIds: ["me"], spaceIds: ["space-1"], libraryIds: ["lib-1"])
    let personalMine = Asset(id: "1", ownerId: "me", originalFileName: "f", checksum: "c", type: .image)
    let personalOther = Asset(id: "2", ownerId: "them", originalFileName: "f", checksum: "c", type: .image)
    let inSpace = Asset(id: "3", ownerId: "them", originalFileName: "f", checksum: "c", type: .image, spaceId: "space-1")
    let inLibrary = Asset(id: "4", ownerId: "them", originalFileName: "f", checksum: "c", type: .image, libraryId: "lib-1")
    #expect(scope.contains(personalMine))
    #expect(!scope.contains(personalOther))
    #expect(scope.contains(inSpace))
    #expect(scope.contains(inLibrary))
  }
}
