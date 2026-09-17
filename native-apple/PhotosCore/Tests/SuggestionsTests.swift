import CoreModel
import Foundation
import LocalStore
import Rules
import Testing

/// WP5 S2a coverage: the local-first suggestion queries behind the Search chips.
/// Seeded programmatically through the public `apply()` path — no world fixtures.
struct SuggestionsTests {
  private static func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 0)
  }

  private static func seed() async throws -> PhotosLocalStore {
    let store = try PhotosLocalStore(inMemory: true)
    let alice = "user-alice"
    let changes: [SyncChange] = [
      .user(User(id: alice, name: "Alice", email: "alice@example.com")),
      .asset(
        Asset(
          id: "a-sf", ownerId: alice, originalFileName: "IMG_1.JPG", checksum: "c1",
          localDateTime: Self.date("2024-06-01T12:00:00Z"), type: .image)),
      .assetExif(
        AssetExif(
          assetId: "a-sf", city: "San Francisco", make: "Canon", model: "EOS R5",
          lensModel: "RF 24-70mm")),
      .asset(
        Asset(
          id: "a-sf2", ownerId: alice, originalFileName: "IMG_2.HEIC", checksum: "c2",
          localDateTime: Self.date("2024-06-02T12:00:00Z"), type: .image)),
      .assetExif(
        AssetExif(
          assetId: "a-sf2", city: "San Francisco", make: "Canon", model: "EOS R5",
          lensModel: "RF 24-70mm")),
      .asset(
        Asset(
          id: "a-to", ownerId: alice, originalFileName: "VID_3.MOV", checksum: "c3",
          localDateTime: Self.date("2024-06-03T12:00:00Z"), type: .video)),
      .assetExif(
        AssetExif(assetId: "a-to", city: "Toronto", make: "Apple", lensModel: "Back Camera")),
      .asset(
        Asset(
          id: "a-blank-exif", ownerId: alice, originalFileName: "NOEXT", checksum: "c4",
          localDateTime: Self.date("2024-06-04T12:00:00Z"), type: .image)),
      .assetExif(AssetExif(assetId: "a-blank-exif", city: "  ", lensModel: "")),
      .person(
        Person(
          id: "person-ada", createdAt: Self.date("2024-01-01T00:00:00Z"),
          updatedAt: Self.date("2024-01-01T00:00:00Z"), ownerId: alice, name: "Ada")),
      .person(
        Person(
          id: "person-blank", createdAt: Self.date("2024-01-01T00:00:00Z"),
          updatedAt: Self.date("2024-01-01T00:00:00Z"), ownerId: alice, name: "  ")),
    ]
    try await store.apply(changes, currentUserId: alice)
    return store
  }

  private static let scope = ContainerScope(personalUserIds: ["user-alice"])

  @Test func citiesServePlacesChipsLocally() async throws {
    let store = try await Self.seed()
    // Most-photographed city first; blank cities never surface.
    #expect(try await store.distinctCities(scope: Self.scope) == ["San Francisco", "Toronto"])
  }

  @Test func lensesServeLensChipsLocally() async throws {
    let store = try await Self.seed()
    #expect(try await store.distinctLensModels(scope: Self.scope) == ["RF 24-70mm", "Back Camera"])
  }

  @Test func extensionsServeFileTypeChipsLocally() async throws {
    let store = try await Self.seed()
    let exts = try await store.distinctFileExtensions(scope: Self.scope)
    #expect(exts.contains("jpg") && exts.contains("heic") && exts.contains("mov"))
    #expect(!exts.contains("noext"))
  }

  @Test func blankPersonNamesNeverSurface() async throws {
    let store = try await Self.seed()
    #expect(try await store.namedPeople(forOwner: "user-alice").map(\.name) == ["Ada"])
  }
}
