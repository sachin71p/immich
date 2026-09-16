import CoreGraphics
import CoreModel
import Foundation
import Testing

/// Deterministic PRNG (LCG) so the brute-force agreement test is stable across runs.
private struct LCGRandom {
  var state: UInt64 = 0x1234_5678_9ABC_DEF1

  mutating func next() -> UInt64 {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return state >> 33
  }

  mutating func double(in range: ClosedRange<Double>) -> Double {
    range.lowerBound + (Double(next() % 1_000_000) / 1_000_000) * (range.upperBound - range.lowerBound)
  }
}

private func bruteItems(
  geometry: TimelineGridGeometry, section: Int, count: Int, rect: CGRect
) -> Range<Int> {
  var first: Int?
  var last = 0
  for item in 0..<count {
    if geometry.itemFrame(section: section, item: item).intersects(rect) {
      if first == nil { first = item }
      last = item
    }
  }
  guard let first else { return 0..<0 }
  return first..<(last + 1)
}

@Suite struct TimelineGridGeometryTests {
  @Test("column math fills the width exactly")
  func columnMath() {
    let config = TimelineGridGeometry.Config(width: 1000, targetItemSide: 200)
    let geometry = TimelineGridGeometry(config: config, sections: [(count: 10, kind: .month)])
    // contentWidth 984: floor((984 + 2) / 202) = 4; side floor((984 - 6) / 4) = 244.
    #expect(geometry.columns == 4)
    #expect(geometry.itemSide == 244)
    // 4 * 244 + 3 * 2 = 982 <= 984 (leftover 2px: trailing inset slack, never overflow).
    #expect(4 * geometry.itemSide + 3 * config.spacing <= 984)
    // Narrow widths still yield one column.
    let narrow = TimelineGridGeometry(
      config: TimelineGridGeometry.Config(width: 50, targetItemSide: 200),
      sections: [(count: 3, kind: .none)])
    #expect(narrow.columns == 1)
  }

  @Test("frames are continuous: no overlaps, everything inside the content height")
  func frameContinuity() {
    let geometry = TimelineGridGeometry(
      config: TimelineGridGeometry.Config(width: 800, targetItemSide: 150),
      sections: [
        (count: 0, kind: .year), (count: 37, kind: .month), (count: 5, kind: .month),
        (count: 200, kind: .month),
      ])
    #expect(geometry.headerFrame(section: 0)?.height == 56)
    #expect(geometry.headerFrame(section: 1)?.height == 40)
    // Row-major order is Y-nondecreasing within a section; sections never overlap.
    var sectionFloor: CGFloat = 0
    let counts = [0, 37, 5, 200]
    for section in 0..<geometry.sectionCount {
      if let header = geometry.headerFrame(section: section) {
        #expect(header.minY >= sectionFloor - 0.001)
        sectionFloor = max(sectionFloor, header.maxY)
      }
      let count = counts[section]
      var previousMinY: CGFloat = -1
      for item in 0..<count {
        let frame = geometry.itemFrame(section: section, item: item)
        #expect(frame.minY >= previousMinY - 0.001)
        previousMinY = frame.minY
        #expect(frame.maxY <= geometry.contentHeight + 0.001)
        sectionFloor = max(sectionFloor, frame.maxY)
      }
      // Items in the same row share Y; rows advance by side + spacing.
      if count > 1 {
        let rowAdvance =
          geometry.itemFrame(section: section, item: min(geometry.columns, count - 1)).minY
          - geometry.itemFrame(section: section, item: 0).minY
        #expect(rowAdvance == 0 || rowAdvance == geometry.itemSide + 2)
      }
    }
  }

  @Test("headerFrame is nil for headerless sections")
  func headerlessSections() {
    let geometry = TimelineGridGeometry(
      config: TimelineGridGeometry.Config(width: 800, targetItemSide: 150),
      sections: [(count: 10, kind: .none)])
    #expect(geometry.headerFrame(section: 0) == nil)
    #expect(geometry.headerFrame(section: 99) == nil)
  }

  @Test("visible-range queries agree with brute force on random rects (102k items)")
  func bruteForceAgreement() {
    var sectionSpecs: [(count: Int, kind: TimelineSectionKind)] = [(count: 0, kind: .year)]
    var remaining = 102_000
    var index = 0
    while remaining > 0 {
      let count = min(remaining, 100 + (index * 37) % 900)
      sectionSpecs.append((count: count, kind: .month))
      remaining -= count
      index += 1
    }
    let geometry = TimelineGridGeometry(
      config: TimelineGridGeometry.Config(width: 1200, targetItemSide: 180),
      sections: sectionSpecs)
    #expect(sectionSpecs.reduce(0) { $0 + $1.count } == 102_000)
    #expect(geometry.sectionCount == sectionSpecs.count)
    var rng = LCGRandom()
    for _ in 0..<200 {
      let y = rng.double(in: 0...Double(geometry.contentHeight))
      let height = rng.double(in: 10...3000)
      let x = rng.double(in: 0...1200)
      let width = rng.double(in: 10...1200)
      let rect = CGRect(x: x, y: y, width: width, height: height)
      let sections = geometry.sections(intersecting: rect)
      // Brute-force section spans from frames: a section overlaps when its span —
      // header/rows plus the uniform bottom gap (`spacing * 4`, which holds no frames) —
      // overlaps the rect, mirroring `sections(intersecting:)`'s own comparison.
      let gap: CGFloat = 2 * 4
      var expected: [Int] = []
      for (index, spec) in sectionSpecs.enumerated() {
        var top: CGFloat?
        var bottom: CGFloat?
        if let header = geometry.headerFrame(section: index) {
          top = header.minY
          bottom = header.maxY
        }
        if spec.count > 0 {
          let first = geometry.itemFrame(section: index, item: 0)
          let last = geometry.itemFrame(section: index, item: spec.count - 1)
          top = min(top ?? first.minY, first.minY)
          bottom = max(bottom ?? last.maxY, last.maxY)
        }
        if let top, let bottom, top < rect.maxY, bottom + gap > rect.minY {
          expected.append(index)
        }
      }
      let expectedRange: Range<Int> =
        if let first = expected.first, let last = expected.last { first..<(last + 1) } else {
          0..<0
        }
      #expect(sections == expectedRange)
      for section in sections {
        let count = sectionSpecs[section].count
        #expect(
          geometry.items(in: section, intersecting: rect) == bruteItems(
            geometry: geometry, section: section, count: count, rect: rect))
      }
    }
  }

  @Test("[perf] init for 300 sections completes in under 1ms")
  func initPerformance() {
    let specs = Array(repeating: (count: 340, kind: TimelineSectionKind.month), count: 300)
    let config = TimelineGridGeometry.Config(width: 1200, targetItemSide: 180)
    let start = DispatchTime.now()
    let geometry = TimelineGridGeometry(config: config, sections: specs)
    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    #expect(geometry.sectionCount == 300)
    #expect(elapsedMs < 1, "init took \(elapsedMs)ms, expected <1ms")
  }

  @Test("zoom anchor lands on the row at y and skips header-only markers")
  func zoomAnchor() {
    let geometry = TimelineGridGeometry(
      config: TimelineGridGeometry.Config(width: 800, targetItemSide: 150),
      sections: [(count: 0, kind: .year), (count: 50, kind: .month)])
    let headerEnd =
      (geometry.headerFrame(section: 1)?.maxY ?? 0)
    // Just below the month header: first row.
    let anchor = geometry.indexPathNearest(y: headerEnd + 1)
    #expect(anchor?.section == 1)
    #expect(anchor?.item == 0)
    // Top of content (inside the year marker): skips to the month section.
    #expect(geometry.indexPathNearest(y: 0)?.section == 1)
    // originY agrees with itemFrame.
    #expect(geometry.originY(section: 1, item: 7) == geometry.itemFrame(section: 1, item: 7).minY)
  }
}
