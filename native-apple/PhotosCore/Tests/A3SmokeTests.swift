import CoreModel
import Foundation
import Rules
import Testing

@testable import LocalStore

/// A3 iOS app backing tests (TESTING.md §5 Apple rows AP-04/AP-07): the exact store/Rules flow the
/// brief's UI smoke test drives — fixture DB → grid buckets render → viewer loads → move sheet
/// lists `Rules.MoveTargets` — plus the `LocalStore+Browse` queries the Collections/Spaces/Albums/
/// Settings screens read. Tests never hit a real server (in-memory store + `SyncChange.apply`).
@Suite struct A3SmokeTests {
  /// Builds the A3 world: Alice (u1) + Bob (u2); s1 member space (u1 contributor), s2 member space;
  /// L1 Alice-owned library with an upload path; m1 Alice personal; m2 Bob space asset in s1;
  /// m3 Alice space asset, locked; m4 Alice personal with GPS.
  static func makeWorld() async throws -> PhotosLocalStore {
    let store = try PhotosLocalStore(inMemory: true)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func day(_ offset: Int) -> Date { now.addingTimeInterval(Double(offset) * 86_400) }
    try await store.apply(
      [
        .space(Space(id: "s1", name: "Family", description: "", createdAt: now, updatedAt: now)),
        .space(Space(id: "s2", name: "Camera", description: "", createdAt: now, updatedAt: now)),
        .spaceMember(SpaceMember(spaceId: "s1", userId: "u1", role: .contributor, showInTimeline: true)),
        .spaceMember(SpaceMember(spaceId: "s1", userId: "u2", role: .owner, showInTimeline: true)),
        .spaceMember(SpaceMember(spaceId: "s2", userId: "u1", role: .owner, showInTimeline: true)),
        .spaceMember(SpaceMember(spaceId: "s2", userId: "u2", role: .contributor, showInTimeline: true)),
        .library(Library(id: "L1", name: "Archive", ownerId: "u1", createdAt: now, updatedAt: now)),
        .asset(
          Asset(
            id: "m1", ownerId: "u1", originalFileName: "IMG_1.heic", checksum: "c1",
            localDateTime: day(-10), type: .image)),
        .asset(
          Asset(
            id: "m2", ownerId: "u2", originalFileName: "IMG_2.heic", checksum: "c2",
            localDateTime: day(-9), type: .image, spaceId: "s1")),
        .asset(
          Asset(
            id: "m3", ownerId: "u1", originalFileName: "IMG_3.heic", checksum: "c3",
            localDateTime: day(-8), type: .image, visibility: .locked, spaceId: "s1")),
        .asset(
          Asset(
            id: "m4", ownerId: "u1", originalFileName: "VID_4.mov", checksum: "c4",
            localDateTime: day(-7), durationSeconds: 12, type: .video)),
        .assetExif(AssetExif(assetId: "m4", latitude: 37.7749, longitude: -122.4194, make: "Apple")),
        .album(Album(id: "al1", name: "Trip", description: "", createdAt: now, updatedAt: now)),
        .albumUser(AlbumMember(albumId: "al1", userId: "u1", role: .editor)),
        .albumUser(AlbumMember(albumId: "al1", userId: "u2", role: .viewer)),
        .albumAsset(albumId: "al1", assetId: "m1"),
        .albumAsset(albumId: "al1", assetId: "m2"),
        .person(
          Person(
            id: "p1", createdAt: now, updatedAt: now, ownerId: "u1", name: "Bob",
            faceAssetId: "m1")),
        .face(
          Face(
            id: "f1", assetId: "m1", personId: "p1", imageWidth: 100, imageHeight: 200,
            boundingBoxX1: 1, boundingBoxY1: 2, boundingBoxX2: 3, boundingBoxY2: 4,
            sourceType: "machine")),
      ],
      currentUserId: "u1"
    )
    try await store.setLibraryUploadPath(libraryId: "L1", uploadPath: "/incoming")
    return store
  }

  // MARK: - AP-07 smoke flow (fixture DB → grid → viewer → move sheet data)

  @Test("[AP-07] fixture DB renders grid buckets and the viewer loads the tapped asset")
  func gridAndViewerFlow() async throws {
    let store = try await Self.makeWorld()
    let tctx = try await store.timelineContext(for: "u1")
    let scope = TimelineScope.resolve(purpose: .timeline, context: tctx)

    // Grid: buckets render (m1 + m4 personal, m2 space; locked m3 excluded from the grid).
    let buckets = try await store.timelineBuckets(scope: scope, granularity: .month)
    #expect(buckets.map(\.key) == ["2023-11"])
    #expect(buckets.first?.count == 3)

    // Grid page: rows carry everything the cell badges need without further fetches.
    let rows = try await store.timelineAssets(scope: scope, bucketKey: "2023-11")
    #expect(Set(rows.map(\.id)) == ["m1", "m2", "m4"])
    let video = try #require(rows.first { $0.id == "m4" })
    #expect(video.mediaKind == .video)

    // Viewer: the tapped row hydrates to the full asset + exif (info panel).
    let tapped = try #require(try await store.asset(id: "m4"))
    #expect(tapped.durationSeconds == 12)
    let exif = try #require(try await store.exif(for: "m4"))
    #expect(exif.make == "Apple")
    #expect(exif.latitude == 37.7749)
  }

  // MARK: - AP-04 move sheet targets

  @Test("[AP-04] move sheet targets match DECISIONS §6 for each world selection")
  func moveSheetTargets() async throws {
    let store = try await Self.makeWorld()
    let ctx = try await store.accessContext(for: "u1")
    let m1 = try #require(try await store.asset(id: "m1"))
    let m2 = try #require(try await store.asset(id: "m2"))
    let m3 = try #require(try await store.asset(id: "m3"))

    // Own personal asset: every member space + the uploadPath library (current container excluded).
    #expect(MoveTargets.allowed(for: m1, in: ctx) == [.space("s1"), .space("s2"), .library("L1")])
    // Other member's space asset: personal is NOT offered (rule 2); the current space is
    // excluded as a no-op target (rule 7); the other space + library are offered.
    #expect(MoveTargets.allowed(for: m2, in: ctx) == [.space("s2"), .library("L1")])
    // Locked asset: nothing is offered (rule 9).
    #expect(MoveTargets.allowed(for: m3, in: ctx).isEmpty)

    // Selection-level: moving [own, other's] to personal allows only the own asset (rule 5 groups).
    let verdict = MoveTargets.allowed(selection: [[m1], [m2]], target: .personal, in: ctx)
    #expect(verdict == ["m1": true, "m2": false])
  }

  // MARK: - browse queries backing Collections / Spaces / Albums / Settings

  @Test("[AP-07] collections screens read spaces, libraries, albums, people, and places")
  func browseQueries() async throws {
    let store = try await Self.makeWorld()

    #expect(try await store.spacesForUser("u1").map(\.id).sorted() == ["s1", "s2"])
    #expect(try await store.spaceRole(spaceId: "s1", userId: "u1") == .contributor)
    #expect(try await store.membersOfSpace("s1").count == 2)
    #expect(try await store.librariesForUser("u1").map(\.id) == ["L1"])

    let albums = try await store.albumsForUser("u1")
    #expect(albums.map(\.id) == ["al1"])
    #expect(try await store.membersOfAlbum("al1").count == 2)
    #expect(try await store.albumAssetCount("al1") == 2)
    let albumRows = try await store.albumAssets(albumId: "al1")
    #expect(Set(albumRows.map(\.id)) == ["m1", "m2"])

    // People stay per-owner (DECISIONS §11): Alice sees her own set with the face's asset.
    #expect(try await store.peopleForOwner("u1").map(\.id) == ["p1"])
    #expect(try await store.peopleForOwner("u2").isEmpty)
    #expect(try await store.assetIds(forPerson: "p1") == ["m1"])

    // Places: only the GPS asset pins.
    let tctx = try await store.timelineContext(for: "u1")
    let scope = TimelineScope.resolve(purpose: .timeline, context: tctx)
    let pins = try await store.locatedAssets(scope: scope)
    #expect(pins.map(\.id) == ["m4"])
  }

  @Test("[AP-07] archive utility reads the archived asset under the manage scope")
  func archiveUtility() async throws {
    let store = try await Self.makeWorld()
    try await store.setVisibility(ids: ["m1"], visibility: .archive)
    var tctx = try await store.timelineContext(for: "u1")
    tctx = TimelineContext(
      currentUserId: tctx.currentUserId, prefs: tctx.prefs, partners: tctx.partners,
      spaceMemberships: tctx.spaceMemberships, ownedLibraries: tctx.ownedLibraries,
      libraryMemberships: tctx.libraryMemberships)
    let scope = TimelineScope.resolve(purpose: .manage, context: tctx)
    let archived = try await store.visibilityAssets(.archive, scope: scope)
    #expect(archived.map(\.id) == ["m1"])
  }

  @Test("[AP-07] ownership transfer swaps roles and the timeline toggle sticks locally")
  func spaceMembershipWrites() async throws {
    let store = try await Self.makeWorld()
    try await store.swapSpaceOwnership(spaceId: "s2", fromUserId: "u1", toUserId: "u2")
    #expect(try await store.spaceRole(spaceId: "s2", userId: "u1") == .contributor)
    #expect(try await store.spaceRole(spaceId: "s2", userId: "u2") == .owner)

    // Only the acting user's own row changes — the other member keeps their toggle.
    try await store.setSpaceShowInTimeline(spaceId: "s1", userId: "u1", show: false)
    let members = try await store.membersOfSpace("s1")
    #expect(members.first { $0.userId == "u1" }?.showInTimeline == false)
    #expect(members.first { $0.userId == "u2" }?.showInTimeline == true)
  }

  @Test("[AP-07] album member add/remove round-trips locally")
  func albumMemberWrites() async throws {
    let store = try await Self.makeWorld()
    try await store.upsertAlbumMember(AlbumMember(albumId: "al1", userId: "u3", role: .viewer))
    #expect(try await store.albumMemberRole(albumId: "al1", userId: "u3") == .viewer)
    try await store.removeAlbumMemberLocally(albumId: "al1", userId: "u3")
    #expect(try await store.albumMemberRole(albumId: "al1", userId: "u3") == nil)
  }
}
