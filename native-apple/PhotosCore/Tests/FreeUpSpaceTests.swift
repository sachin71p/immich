import CoreModel
import Foundation
import Testing
@testable import LocalStore
@testable import Media

private let day: TimeInterval = 86_400

private func photo(
  _ id: String,
  daysAgo: Double?,
  favorite: Bool = false,
  albums: Set<String> = [],
  bytes: Int = 1_000_000
) -> DevicePhoto {
  DevicePhoto(
    localIdentifier: "L\(id)",
    checksum: "sha-\(id)",
    creationDate: daysAgo.map { Date(timeIntervalSinceNow: -$0 * day) },
    isFavorite: favorite,
    albumIds: albums,
    estimatedBytes: bytes
  )
}

@Suite struct FreeUpSpaceTests {
  @Test("[AP-03] cutoff keeps recent photos, offers old backed-up ones")
  func cutoff() {
    let now = Date()
    let photos = [photo("old", daysAgo: 60), photo("new", daysAgo: 5)]
    let backed: Set<String> = ["sha-old", "sha-new"]
    let got = FreeUpSpacePlanner.selectCandidates(
      photos: photos, backedUpChecksums: backed,
      options: FreeUpSpaceOptions(
        cutoffDate: now.addingTimeInterval(-30 * day), keepLastNDays: nil),
      now: now)
    #expect(got.map(\.localIdentifier) == ["Lold"])
  }

  @Test("[AP-03] keep-last-N-days window excludes recent photos")
  func keepLastNDays() {
    let now = Date()
    let photos = [photo("old", daysAgo: 60), photo("new", daysAgo: 5)]
    let backed: Set<String> = ["sha-old", "sha-new"]
    let got = FreeUpSpacePlanner.selectCandidates(
      photos: photos, backedUpChecksums: backed,
      options: FreeUpSpaceOptions(keepLastNDays: 30),
      now: now)
    #expect(got.map(\.localIdentifier) == ["Lold"])
  }

  @Test("[AP-03] favorites kept by default, offered when the toggle is off")
  func favorites() {
    let photos = [photo("fav", daysAgo: 60, favorite: true)]
    let backed: Set<String> = ["sha-fav"]
    let kept = FreeUpSpacePlanner.selectCandidates(
      photos: photos, backedUpChecksums: backed,
      options: FreeUpSpaceOptions(keepFavorites: true, keepLastNDays: 30))
    #expect(kept.isEmpty)
    let offered = FreeUpSpacePlanner.selectCandidates(
      photos: photos, backedUpChecksums: backed,
      options: FreeUpSpaceOptions(keepFavorites: false, keepLastNDays: 30))
    #expect(offered.map(\.localIdentifier) == ["Lfav"])
  }

  @Test("[AP-03] kept albums are excluded even when old and backed up")
  func keptAlbums() {
    let photos = [
      photo("kept", daysAgo: 60, albums: ["album-1"]),
      photo("free", daysAgo: 60, albums: ["album-2"]),
    ]
    let backed: Set<String> = ["sha-kept", "sha-free"]
    let got = FreeUpSpacePlanner.selectCandidates(
      photos: photos, backedUpChecksums: backed,
      options: FreeUpSpaceOptions(keepAlbumIds: ["album-1"], keepLastNDays: 30))
    #expect(got.map(\.localIdentifier) == ["Lfree"])
  }

  @Test("[AP-03] server-missing and server-trashed checksums are never candidates")
  func serverVerification() {
    // `backedUpChecksums` is the post-verification set: the verifier already
    // dropped missing (bulk-check `accept`) and trashed (`isTrashed`) entries.
    let photos = [photo("gone", daysAgo: 60), photo("trashed", daysAgo: 60), photo("ok", daysAgo: 60)]
    let backed: Set<String> = ["sha-ok"]
    let got = FreeUpSpacePlanner.selectCandidates(
      photos: photos, backedUpChecksums: backed,
      options: FreeUpSpaceOptions(keepLastNDays: 30))
    #expect(got.map(\.localIdentifier) == ["Lok"])
  }

  @Test("[AP-03] unknown dates and unbounded options offer nothing")
  func safeDegenerates() {
    let backed: Set<String> = ["sha-nodate"]
    let nodate = FreeUpSpacePlanner.selectCandidates(
      photos: [photo("nodate", daysAgo: nil)], backedUpChecksums: backed,
      options: FreeUpSpaceOptions(keepLastNDays: 30))
    #expect(nodate.isEmpty)
    let unbounded = FreeUpSpacePlanner.selectCandidates(
      photos: [photo("old", daysAgo: 60)], backedUpChecksums: ["sha-old"],
      options: FreeUpSpaceOptions())
    #expect(unbounded.isEmpty)
  }

  @Test("[AP-03] preview sums counts + bytes; batches chunk the deletion pass")
  func previewAndBatches() {
    let photos = (0..<250).map { photo("p\($0)", daysAgo: 60, bytes: 2_000_000) }
    let (count, bytes) = FreeUpSpacePlanner.preview(photos)
    #expect(count == 250)
    #expect(bytes == 500_000_000)
    let chunks = FreeUpSpacePlanner.batches(photos)
    #expect(chunks.count == 3)
    #expect(chunks.map(\.count) == [100, 100, 50])
    #expect(FreeUpSpacePlanner.batches([]).isEmpty)
  }

  @Test("[AP-03] budget steps are shared; iOS and macOS defaults differ")
  func budgetPresets() {
    #expect(StoragePrefs.budgetStepsBytes.first == 0)
    #expect(StoragePrefs.budgetStepsBytes == StoragePrefs.budgetStepsBytes.sorted())
    #expect(StoragePrefs.iOSDefaultOriginalBudgetBytes == 256 * 1_000_000)
    #expect(StoragePrefs.macDefaultOriginalBudgetBytes == 2_000_000_000)
    #expect(StoragePrefs.budgetStepsBytes.contains(StoragePrefs.iOSDefaultOriginalBudgetBytes))
    #expect(StoragePrefs.budgetStepsBytes.contains(StoragePrefs.macDefaultOriginalBudgetBytes))
    #expect(StoragePrefs().keepFavoritesOnFreeUp == true)
    #expect(StoragePrefs().suggestFreeUpAfterBackup == true)
  }

  @Test("[AP-03] StoragePrefs round-trips through LocalStore and defaults fresh")
  func storagePrefsPersistence() async throws {
    let store = try PhotosLocalStore(inMemory: true)
    #expect(await (try store.storagePrefs(for: "u1")) == StoragePrefs())
    var prefs = StoragePrefs()
    prefs.optimizeStorage = true
    prefs.originalTierBudgetBytes = StoragePrefs.macDefaultOriginalBudgetBytes
    prefs.pinnedContainerIds = ["lib-1", "album-2"]
    prefs.keepFavoritesOnFreeUp = false
    prefs.freeUpKeepLastNDays = 14
    try await store.setStoragePrefs(prefs, for: "u1")
    let reloaded = try await store.storagePrefs(for: "u1")
    #expect(reloaded == prefs)
    #expect(reloaded.isPinnedContainer("lib-1"))
    #expect(!reloaded.isPinnedContainer("lib-9"))
    #expect(await (try store.anyStoragePrefs()) == prefs)
  }
}
