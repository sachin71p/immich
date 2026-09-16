import CoreModel
import Foundation
import Testing

private func row(
  id: String, date: Date? = nil, kind: TimelineMediaKind = .photo, favorite: Bool = false
) -> TimelineRow {
  TimelineRow(
    id: id, thumbhash: nil, aspectRatio: 1, mediaKind: kind, isFavorite: favorite,
    isTrashed: false, isArchived: false, localDateTime: date)
}

private func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

@Suite struct TimelineGridSnapshotTests {
  @Test("build filters, orders newest-first, and computes ranges/index/counts")
  func buildNewestFirst() {
    let sections = [
      TimelineSourceSection(
        header: "2026-09", kind: .month,
        rows: [row(id: "a", date: utc(2026, 9, 1)), row(id: "b", date: utc(2026, 9, 2))]),
      TimelineSourceSection(
        header: "2026-08", kind: .month, rows: [row(id: "c", date: utc(2026, 8, 5), kind: .video)]),
    ]
    let snapshot = TimelineGridSnapshot.build(
      sections: sections, order: .newestFirst, include: { _ in true }, generation: 7)
    #expect(snapshot.generation == 7)
    #expect(snapshot.revision == 0)
    #expect(snapshot.rows.map(\.id) == ["a", "b", "c"])
    #expect(snapshot.sections.count == 2)
    #expect(snapshot.sections[0].range == 0..<2)
    #expect(snapshot.sections[1].range == 2..<3)
    #expect(snapshot.indexById == ["a": 0, "b": 1, "c": 2])
    #expect(snapshot.photoCount == 2)
    #expect(snapshot.videoCount == 1)
    #expect(snapshot.dateRange?.lowerBound == utc(2026, 8, 5))
    #expect(snapshot.dateRange?.upperBound == utc(2026, 9, 2))
    #expect(snapshot.dayKeys == ["2026-09-01", "2026-09-02", "2026-08-05"])
  }

  @Test("include filters rows and drops emptied sections but keeps year markers")
  func filterAndYearMarkers() {
    let sections = [
      TimelineSourceSection(header: "2026", kind: .year, rows: []),
      TimelineSourceSection(
        header: "2026-09", kind: .month,
        rows: [row(id: "a", kind: .photo), row(id: "b", kind: .video)]),
      TimelineSourceSection(header: "2026-08", kind: .month, rows: [row(id: "c", kind: .photo)]),
    ]
    let snapshot = TimelineGridSnapshot.build(
      sections: sections, order: .newestFirst, include: { $0.mediaKind == .video },
      generation: 1)
    #expect(snapshot.rows.map(\.id) == ["b"])
    // Year marker kept (header only), emptied August dropped.
    #expect(snapshot.sections.count == 2)
    #expect(snapshot.sections[0].kind == .year)
    #expect(snapshot.sections[0].range.isEmpty)
    #expect(snapshot.sections[1].header == "2026-09")
    #expect(snapshot.sections[1].range == 0..<1)
    #expect(snapshot.photoCount == 0)
    #expect(snapshot.videoCount == 1)
  }

  @Test("oldestFirst reverses rows and keeps year headers attached to their months")
  func oldestFirstKeepsYearGroups() {
    let sections = [
      TimelineSourceSection(header: "2026", kind: .year, rows: []),
      TimelineSourceSection(
        header: "2026-09", kind: .month, rows: [row(id: "sep-1"), row(id: "sep-2")]),
      TimelineSourceSection(header: "2025", kind: .year, rows: []),
      TimelineSourceSection(header: "2025-01", kind: .month, rows: [row(id: "jan-1")]),
    ]
    let snapshot = TimelineGridSnapshot.build(
      sections: sections, order: .oldestFirst, include: { _ in true }, generation: 1)
    #expect(snapshot.rows.map(\.id) == ["jan-1", "sep-2", "sep-1"])
    let kinds = snapshot.sections.map(\.kind)
    #expect(kinds == [.year, .month, .year, .month])
    #expect(snapshot.sections[0].header == "2025")
    #expect(snapshot.sections[2].header == "2026")
  }

  @Test("patching flips flags in place and reports changed indexes")
  func patching() {
    let base = TimelineGridSnapshot.build(
      sections: [
        TimelineSourceSection(
          header: nil, kind: .none,
          rows: [row(id: "a"), row(id: "b"), row(id: "c")])
      ],
      order: .newestFirst, include: { _ in true }, generation: 3)
    let (patched, changed) = base.patching(ids: ["b", "missing"]) {
      $0.isFavorite = true
    }
    #expect(changed == [1])
    #expect(patched.rows[1].isFavorite)
    #expect(!patched.rows[0].isFavorite)
    #expect(patched.generation == 3)
    #expect(patched.revision == 1)
    #expect(patched.rows.map(\.id) == ["a", "b", "c"])
  }

  @Test("removing drops rows, compacts ranges, and prunes orphaned year markers")
  func removing() {
    let base = TimelineGridSnapshot.build(
      sections: [
        TimelineSourceSection(header: "2026", kind: .year, rows: []),
        TimelineSourceSection(
          header: "2026-09", kind: .month, rows: [row(id: "a"), row(id: "b")]),
        TimelineSourceSection(header: "2025", kind: .year, rows: []),
        TimelineSourceSection(header: "2025-01", kind: .month, rows: [row(id: "c")]),
      ],
      order: .newestFirst, include: { _ in true }, generation: 1)
    // Remove the whole 2025 month: its year marker must go too.
    let pruned = base.removing(ids: ["c"], generation: 2)
    #expect(pruned.rows.map(\.id) == ["a", "b"])
    #expect(pruned.sections.map(\.header) == ["2026", "2026-09"])
    #expect(pruned.generation == 2)
    #expect(pruned.indexById == ["a": 0, "b": 1])
    // Remove one row of a surviving month: marker stays, range compacts.
    let pruned2 = base.removing(ids: ["a"], generation: 3)
    #expect(pruned2.rows.map(\.id) == ["b", "c"])
    #expect(pruned2.sections.count == 4)
    #expect(pruned2.sections[1].range == 0..<1)
  }

  @Test("sectionAndItem round-trips flatIndex and skips year markers")
  func sectionItemRoundTrip() {
    let snapshot = TimelineGridSnapshot.build(
      sections: [
        TimelineSourceSection(header: "2026", kind: .year, rows: []),
        TimelineSourceSection(
          header: "2026-09", kind: .month, rows: [row(id: "a"), row(id: "b")]),
        TimelineSourceSection(header: "2026-08", kind: .month, rows: [row(id: "c")]),
      ],
      order: .newestFirst, include: { _ in true }, generation: 1)
    #expect(snapshot.sectionAndItem(forIndex: 0) == (1, 0))
    #expect(snapshot.sectionAndItem(forIndex: 2) == (2, 0))
    #expect(snapshot.flatIndex(section: 1, item: 1) == 1)
    #expect(snapshot.flatIndex(section: 2, item: 0) == 2)
  }

  @Test("dayKeys use GMT wall time and empty for unknown dates")
  func dayKeys() {
    let snapshot = TimelineGridSnapshot.build(
      sections: [
        TimelineSourceSection(
          header: nil, kind: .none, rows: [row(id: "a", date: utc(2026, 9, 16)), row(id: "b")])
      ],
      order: .newestFirst, include: { _ in true }, generation: 1)
    #expect(snapshot.dayKeys == ["2026-09-16", ""])
  }

  @Test("dayKey civil math agrees with Calendar GMT components across 1970–2035")
  func dayKeyAgreement() {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    // Every ~9 days plus leap-day / epoch / pre-epoch boundaries.
    var checked = 0
    for days in stride(from: -365, through: 24_000, by: 9) {
      let date = Date(timeIntervalSince1970: Double(days) * 86_400 + 12 * 3600)
      let key = TimelineGridSnapshot.build(
        sections: [
          TimelineSourceSection(header: nil, kind: .none, rows: [row(id: "x", date: date)])
        ],
        order: .newestFirst, include: { _ in true }, generation: 1
      ).dayKeys[0]
      #expect(key == formatter.string(from: date), "mismatch at \(date)")
      checked += 1
    }
    #expect(checked > 2000)
  }

  @Test("bucket titles render month/day/year keys and pass through garbage")
  func bucketTitles() {
    let month = TimelineBucketTitle.title(forKey: "2026-09", kind: .month)
    #expect(month != "2026-09")
    #expect(month.contains("2026"))
    let day = TimelineBucketTitle.title(forKey: "2026-09-16", kind: .day)
    #expect(day != "2026-09-16")
    #expect(day.contains("2026"))
    #expect(TimelineBucketTitle.title(forKey: "2026", kind: .year) == "2026")
    #expect(TimelineBucketTitle.title(forKey: "bogus", kind: .month) == "bogus")
    // Memoized second call agrees.
    #expect(TimelineBucketTitle.title(forKey: "2026-09", kind: .month) == month)
  }

  @Test("[perf] build for 102k rows completes in under 60ms")
  func buildPerformance() {
    var rows: [TimelineRow] = []
    rows.reserveCapacity(102_000)
    for index in 0..<102_000 {
      rows.append(
        row(
          id: "asset-\(index)", date: utc(2000 + (index % 26), 1 + (index % 12), 1 + (index % 28)),
          kind: index % 5 == 0 ? .video : .photo))
    }
    let sections = [
      TimelineSourceSection(header: nil, kind: .none, rows: rows)
    ]
    let start = DispatchTime.now()
    let snapshot = TimelineGridSnapshot.build(
      sections: sections, order: .newestFirst, include: { _ in true }, generation: 1)
    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    #expect(snapshot.rows.count == 102_000)
    #if DEBUG
    // Unoptimized: ~114ms on M-series. The 60ms budget is enforced by `-c release` runs.
    let budget = 400.0
    #else
    let budget = 60.0
    #endif
    #expect(elapsedMs < budget, "build took \(elapsedMs)ms, expected <\(budget)ms")
  }
}
