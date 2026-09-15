import CoreModel
import Foundation
import LocalStore

/// Deterministic in-app fixture world for previews and the XCUITest smoke test
/// (`-useFixtureStore` launch arg). Mirrors `A3SmokeTests.makeWorld` (PhotosCoreTests): Alice (u1)
/// + Bob (u2), two member spaces, one owned library with an upload path, personal/space/locked/
//// GPS assets, an album, and a person. Seeded through the public `apply(_:)` pipeline — the same
/// path real sync data takes — so the smoke test exercises production code, not a stub.
enum FixtureSeed {
  static let userId = "u1"

  static func seed(into store: PhotosLocalStore) async throws {
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
      currentUserId: userId
    )
    try await store.setLibraryUploadPath(libraryId: "L1", uploadPath: "/incoming")
  }
}
