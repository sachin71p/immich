import CoreModel
import Foundation
import LocalStore
import XCTest

/// WP-T T0/T1: the sized fixtures are exact, deterministic, and fast; the stub
/// server answers every fixture route. Runs via `verify.sh mac-unit`.
final class FixtureSeedTests: XCTestCase {
  // MARK: - sizes

  func testSmallFixtureHasExactly2000AssetRows() {
    let changes = FixtureSeed.sizedChanges(assetTarget: FixtureSeed.smallAssetTarget)
    XCTAssertEqual(FixtureSeed.assetRowCount(changes), 2_000)
  }

  func testLargeFixtureHasExactly102000AssetRows() {
    let changes = FixtureSeed.sizedChanges(assetTarget: FixtureSeed.largeAssetTarget)
    XCTAssertEqual(FixtureSeed.assetRowCount(changes), 102_000)
  }

  func testBaseFixtureKeepsLegacyWorld() {
    let changes = FixtureSeed.baseChanges()
    let ids = Set(changes.compactMap { change -> String? in
      if case .asset(let asset) = change { return asset.id }
      return nil
    })
    for id in ["asset-personal-1", "asset-personal-2", "asset-space-video", "asset-library-1"] {
      XCTAssertTrue(ids.contains(id), "legacy asset \(id) still seeded")
    }
    // Exactly one curated favorite: the functional test favorites two more and
    // asserts a floor, so the base must not grow favorites silently.
    let favorites = changes.compactMap { change -> String? in
      if case .asset(let asset) = change, asset.isFavorite { return asset.id }
      return nil
    }
    XCTAssertEqual(favorites, ["asset-personal-1"])
  }

  func testBaseCoversBriefInventory() {
    let changes = FixtureSeed.baseChanges()
    func count(_ include: (SyncChange) -> Bool) -> Int { changes.filter(include).count }
    XCTAssertEqual(count { if case .album = $0 { true } else { false } }, 12, "12 albums")
    XCTAssertEqual(count { if case .space = $0 { true } else { false } }, 2, "2 shared libraries")
    XCTAssertEqual(count { if case .person = $0 { true } else { false } }, 8, "6 named + 2 unnamed people")
    XCTAssertEqual(count { if case .memory = $0 { true } else { false } }, 3, "3 memories")
    let unnamed = changes.compactMap { change -> String? in
      if case .person(let person) = change, person.name.isEmpty { return person.id }
      return nil
    }
    XCTAssertEqual(unnamed.count, 2, "2 unnamed people render as Add Name")
    let live = changes.compactMap { change -> String? in
      if case .asset(let asset) = change, asset.livePhotoVideoId != nil { return asset.id }
      return nil
    }
    XCTAssertFalse(live.isEmpty, "live photos present")
    let edited = changes.compactMap { change -> String? in
      if case .asset(let asset) = change, asset.isEdited { return asset.id }
      return nil
    }
    XCTAssertFalse(edited.isEmpty, "edited assets present")
    let places = changes.compactMap { change -> String? in
      if case .assetExif(let exif) = change, exif.latitude != nil { return exif.assetId }
      return nil
    }
    XCTAssertFalse(places.isEmpty, "places with coordinates present")
  }

  // MARK: - determinism + ordering

  func testSizedFixtureIsDeterministic() {
    func assetIDs(_ changes: [SyncChange]) -> [String] {
      changes.compactMap { if case .asset(let asset) = $0 { asset.id } else { nil } }
    }
    XCTAssertEqual(
      assetIDs(FixtureSeed.sizedChanges(assetTarget: 2_000)),
      assetIDs(FixtureSeed.sizedChanges(assetTarget: 2_000)))
  }

  func testGeneratedRowsSortBelowCuratedBase() {
    let changes = FixtureSeed.sizedChanges(assetTarget: FixtureSeed.smallAssetTarget)
    let cutoff = Date(timeIntervalSince1970: 1_641_090_000)  // 2022-01-01
    for change in changes {
      if case .asset(let asset) = change, asset.id.hasPrefix("asset-gen-") {
        XCTAssertLessThan(asset.localDateTime ?? .distantFuture, cutoff, "\(asset.id) sorts below base")
      }
    }
  }

  // MARK: - beach

  func testEveryBeachIDHasAnExifTagRow() {
    let target = FixtureSeed.smallAssetTarget
    let changes = FixtureSeed.sizedChanges(assetTarget: target)
    let tagged = Set(changes.compactMap { change -> String? in
      if case .assetExif(let exif) = change, exif.description?.contains("beach") == true {
        return exif.assetId
      }
      return nil
    })
    let expected = Set(FixtureSeed.baseBeachAssetIDs
      + FixtureSeed.generatedBeachIDs(primaryCount: FixtureSeed.primaryCount(forTarget: target)))
    XCTAssertFalse(expected.isEmpty)
    XCTAssertTrue(expected.isSubset(of: tagged), "untagged beach ids: \(expected.subtracting(tagged))")
  }

  // MARK: - batching + speed (T6/T7 large-fixture path)

  func testBatchedChangesCoversAllChanges() {
    let all = FixtureSeed.baseChanges() + FixtureSeed.generatedChanges(count: 500)
    let batches = stride(from: 0, to: all.count, by: 100).map { Array(all[$0..<min($0 + 100, all.count)]) }
    XCTAssertEqual(batches.flatMap { $0 }.count, all.count)
  }

  /// The full large fixture applies in-memory in well under the 20 s budget,
  /// in 10k-row transactions (the chunking the app seed path uses).
  func testLargeFixtureSeedsUnder20Seconds() async throws {
    let changes = FixtureSeed.sizedChanges(assetTarget: FixtureSeed.largeAssetTarget)
    let store = try PhotosLocalStore(inMemory: true)
    let start = Date()
    for startIndex in stride(from: 0, to: changes.count, by: 10_000) {
      let batch = Array(changes[startIndex..<min(startIndex + 10_000, changes.count)])
      try await store.apply(batch, currentUserId: FixtureSeed.userId)
    }
    XCTAssertLessThan(Date().timeIntervalSince(start), 20, "large seed under 20 s")
  }

  // MARK: - synthetic media determinism

  func testSyntheticImageIsDeterministic() {
    let a = FixtureMedia.pngData(seed: "asset-base-beach-1")
    let b = FixtureMedia.pngData(seed: "asset-base-beach-1")
    XCTAssertFalse(a.isEmpty)
    XCTAssertEqual(a, b, "same seed, same bytes")
    XCTAssertNotEqual(a, FixtureMedia.pngData(seed: "asset-personal-1"), "seeds vary")
    XCTAssertEqual(a.prefix(8).map { $0 }, [137, 80, 78, 71, 13, 10, 26, 10], "PNG magic")
  }

  func testVideoClipGeneratesAndCaches() throws {
    let first = try FixtureMedia.videoFileURL(seed: "fixture-test-video")
    let second = try FixtureMedia.videoFileURL(seed: "fixture-test-video")
    XCTAssertEqual(first, second, "cached by seed variant")
    let bytes = try Data(contentsOf: first)
    XCTAssertGreaterThan(bytes.count, 1_000, "non-trivial clip")
  }
}
