import XCTest

/// Library sort parity: oldest-first, opens at the bottom (Photos behavior).
/// Fixture default world: fx000001 oldest … fx000012 newest (fx000003 is
/// locked out, fx000006m is a video-half — neither is a timeline item).
final class GridOrderUITests: XCTestCase {
  func test_libraryGrid_oldestFirst_opensAtBottom() throws {
    let app = Parity.launch()
    // Newest exists and is on screen without any scroll (opens at bottom).
    let newest = app.collectionViews.cells["grid-cell-fx000012"]
    XCTAssertTrue(newest.waitForExistence(timeout: 10), "newest cell should exist")
    var newestVisible = false
    for _ in 0..<10 {
      if newest.isHittable { newestVisible = true; break }
      sleep(1)
    }
    XCTAssertTrue(newestVisible, "grid should open scrolled to the bottom (newest visible)")
    // On-screen order runs oldest-first top-to-bottom. Only materialized
    // (virtualized) cells are queried — off-screen cells have no AX element.
    let rank = [
      "fx000001", "fx000002", "fx000004", "fx000005", "fx000006", "fx000007",
      "fx000008", "fx000009", "fx000010", "fx000011", "fx000012",
    ]
    let cells = app.collectionViews.cells.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "grid-cell-"))
    XCTAssertGreaterThan(cells.count, 3, "several cells should be materialized")
    var positioned: [(row: Int, x: CGFloat, id: String)] = []
    for i in 0..<cells.count {
      let cell = cells.element(boundBy: i)
      guard cell.exists else { continue }
      let id = String(cell.identifier.dropFirst("grid-cell-".count))
      positioned.append((Int(cell.frame.minY / 8), cell.frame.minX, id))
    }
    XCTAssertGreaterThan(positioned.count, 3, "several positioned cells expected")
    positioned.sort { $0.row == $1.row ? $0.x < $1.x : $0.row < $1.row }
    let ranks = positioned.compactMap { rank.firstIndex(of: $0.id) }
    XCTAssertEqual(ranks.count, positioned.count, "all visible cells should be fixture items")
    XCTAssertEqual(ranks, ranks.sorted(), "visible cells should run oldest-first top-to-bottom")
    XCTAssertEqual(
      positioned.last?.id, "fx000012", "newest item should sit at the bottom")
  }

  func test_libraryGrid_scrollToTop_reachesOldest() throws {
    let app = Parity.launch()
    let grid = app.collectionViews.firstMatch
    XCTAssertTrue(grid.waitForExistence(timeout: 10), "grid should exist")
    let oldest = app.collectionViews.cells["grid-cell-fx000001"]
    for _ in 0..<6 {
      if oldest.isHittable { break }
      grid.swipeDown()
    }
    XCTAssertTrue(oldest.isHittable, "swiping down should reach the oldest cell at top")
  }
}
