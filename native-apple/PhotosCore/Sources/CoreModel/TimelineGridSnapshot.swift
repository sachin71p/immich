import Foundation

/// Section granularity for the timeline grid — mirrors how WP2's loader groups rows.
public enum TimelineSectionKind: Sendable {
  /// A flat grid with no headers (search results, person timelines).
  case none
  /// A header-only year marker (empty range; WP3's layout renders it as a header).
  case year
  /// A month bucket carrying rows.
  case month
}

/// One grouped input to `TimelineGridSnapshot.build` — the loader's month buckets plus
/// optional interleaved year markers (`kind == .year`, empty `rows`).
public struct TimelineSourceSection: Sendable {
  public var header: String?
  public var kind: TimelineSectionKind
  public var rows: [TimelineRow]

  public init(header: String? = nil, kind: TimelineSectionKind, rows: [TimelineRow]) {
    self.header = header
    self.kind = kind
    self.rows = rows
  }
}

/// Display order of snapshot rows.
public enum TimelineOrder: Sendable {
  case newestFirst
  case oldestFirst
}

/// An immutable, reference-typed grid snapshot — the fix for R2.
///
/// Why a reference type: assigning 102k `TimelineRow` structs to an `@Observable` stored
/// property runs a value-by-value `==` (the 1.8–2.0 s hangs in the baseline). A final class
/// compares by identity, so publishing a new snapshot is O(1). All stored state is a `let`,
/// so the class is `Sendable` without locks. `generation` bumps on structural change
/// (WP3 calls `reloadData`); `revision` bumps on in-place patches (WP3 calls `reloadItems`).
public final class TimelineGridSnapshot: Sendable {
  public struct Section: Sendable {
    public let header: String?
    public let kind: TimelineSectionKind
    /// Range into `rows`. Year markers have an empty range (header only).
    public let range: Range<Int>

    public init(header: String?, kind: TimelineSectionKind, range: Range<Int>) {
      self.header = header
      self.kind = kind
      self.range = range
    }
  }

  public let generation: Int
  public let revision: Int
  /// Flat rows in display order.
  public let rows: [TimelineRow]
  public let sections: [Section]
  public let indexById: [String: Int]
  /// "yyyy-MM-dd" per row ("" if unknown) for type-to-jump. Built from `dateComponents`
  /// with integer formatting — never a `DateFormatter` per row (R4).
  public let dayKeys: [String]
  public let photoCount: Int
  public let videoCount: Int
  public let dateRange: ClosedRange<Date>?
  /// Only for the viewer paging context — O(n) by design, call once per navigation.
  public var ids: [String] { rows.map(\.id) }
  public static let empty = TimelineGridSnapshot(
    generation: 0, revision: 0, rows: [], sections: [], indexById: [:], dayKeys: [],
    photoCount: 0, videoCount: 0, dateRange: nil)

  init(
    generation: Int, revision: Int, rows: [TimelineRow], sections: [Section],
    indexById: [String: Int], dayKeys: [String], photoCount: Int, videoCount: Int,
    dateRange: ClosedRange<Date>?
  ) {
    self.generation = generation
    self.revision = revision
    self.rows = rows
    self.sections = sections
    self.indexById = indexById
    self.dayKeys = dayKeys
    self.photoCount = photoCount
    self.videoCount = videoCount
    self.dateRange = dateRange
  }

  /// Builds a snapshot in a single pass over the rows: filters, orders, computes ranges,
  /// the index map, counts, the date range and dayKeys.
  ///
  /// Ordering: `oldestFirst` reverses row order. Year markers stay attached to their year:
  /// a `.year` marker plus the following `.month` sections form a group, groups reverse as
  /// a unit, and months reverse within the group — so "2025" still heads 2025's months in
  /// both orders. (Without year markers this is exactly "reverse sections and rows".)
  ///
  /// Empty non-year sections are dropped; empty `.year` sections are kept as header-only
  /// markers (their `range` is empty).
  public static func build(
    sections: [TimelineSourceSection], order: TimelineOrder,
    include: @Sendable (TimelineRow) -> Bool, generation: Int
  ) -> TimelineGridSnapshot {
    // Group year markers with their months so reversal keeps headers attached.
    var groups: [[TimelineSourceSection]] = []
    for section in sections {
      if section.kind == .year, section.rows.isEmpty {
        groups.append([section])
      } else if section.kind == .month, let lastGroup = groups.last, lastGroup.count >= 1,
        lastGroup[0].kind == .year, lastGroup[0].rows.isEmpty
      {
        groups[groups.count - 1].append(section)
      } else {
        groups.append([section])
      }
    }
    // The year marker stays first in its group; only the months reverse — otherwise the
    // "2025" header would trail 2025's months in `oldestFirst` order.
    let orderedGroups: [[TimelineSourceSection]] =
      switch order {
      case .newestFirst: groups
      case .oldestFirst: groups.reversed().map { [$0[0]] + $0.dropFirst().reversed() }
      }
    var rows: [TimelineRow] = []
    rows.reserveCapacity(sections.reduce(0) { $0 + $1.rows.count })
    var built: [Section] = []
    for group in orderedGroups {
      for section in group {
        let start = rows.count
        if section.kind == .year, section.rows.isEmpty {
          built.append(Section(header: section.header, kind: .year, range: start..<start))
          continue
        }
        let orderedRows: [TimelineRow] =
          switch order {
          case .newestFirst: section.rows
          case .oldestFirst: section.rows.reversed()
          }
        for row in orderedRows where include(row) {
          rows.append(row)
        }
        if rows.count > start {
          built.append(Section(header: section.header, kind: section.kind, range: start..<rows.count))
        }
      }
    }
    return makeSnapshot(rows: rows, sections: built, generation: generation, revision: 0)
  }

  /// Returns a new snapshot with `transform` applied to `ids`, plus the flat indexes that
  /// changed (for `reloadItems`). Same `generation`, `revision + 1`.
  ///
  /// Counts and the index map are rebuilt (cheap integer passes); dayKeys are patched at
  /// the changed indexes and `dateRange` is carried over — so `transform` must not move
  /// rows or change their dates. Structural edits go through `removing`/`build`.
  public func patching(
    ids: Set<String>, _ transform: (inout TimelineRow) -> Void
  ) -> (TimelineGridSnapshot, changedIndexes: [Int]) {
    var patchedRows = rows
    var changed: [Int] = []
    for id in ids {
      guard let index = indexById[id] else { continue }
      transform(&patchedRows[index])
      changed.append(index)
    }
    changed.sort()
    var patchedDayKeys = dayKeys
    for index in changed {
      patchedDayKeys[index] = Self.dayKey(for: patchedRows[index].localDateTime)
    }
    let (photos, videos) = Self.counts(of: patchedRows)
    let snapshot = TimelineGridSnapshot(
      generation: generation, revision: revision + 1, rows: patchedRows, sections: sections,
      indexById: Self.indexMap(of: patchedRows), dayKeys: patchedDayKeys,
      photoCount: photos, videoCount: videos, dateRange: dateRange)
    return (snapshot, changed)
  }

  /// Returns a new snapshot without `ids` (favorite-toggle undo, trash, remove-from-album).
  /// Sections left empty are dropped, except a year marker is kept while any of its year's
  /// month sections survive. `dateRange`/counts/index/dayKeys are rebuilt.
  public func removing(ids: Set<String>, generation: Int) -> TimelineGridSnapshot {
    guard !ids.isEmpty else { return self }
    var keptRows: [TimelineRow] = []
    keptRows.reserveCapacity(rows.count)
    // Maps old flat index -> new flat index (nil when removed).
    var remap: [Int?] = Array(repeating: nil, count: rows.count)
    for (index, row) in rows.enumerated() where !ids.contains(row.id) {
      remap[index] = keptRows.count
      keptRows.append(row)
    }
    var keptSections: [Section] = []
    // A year marker heads the months that follow it, so it is emitted just before the
    // first surviving month — never after (a marker whose months are all gone is dropped).
    var pendingYear: Section?
    for section in sections {
      if section.kind == .year, section.range.isEmpty {
        // Rebased to the current tail (still empty — header only).
        pendingYear = Section(
          header: section.header, kind: .year, range: keptRows.count..<keptRows.count)
        continue
      }
      let kept = section.range.compactMap { remap[$0] }
      guard let first = kept.first, let last = kept.last else { continue }
      if let year = pendingYear {
        keptSections.append(year)
        pendingYear = nil
      }
      // `remap` preserves order, so kept indexes are contiguous.
      keptSections.append(Section(header: section.header, kind: section.kind, range: first..<(last + 1)))
    }
    return Self.makeSnapshot(
      rows: keptRows, sections: keptSections, generation: generation, revision: 0)
  }

  /// The (section, item) containing `forIndex` — binary search over section ranges, so
  /// header-only year sections (empty ranges) are never returned.
  public func sectionAndItem(forIndex: Int) -> (section: Int, item: Int) {
    precondition(forIndex >= 0 && forIndex < rows.count, "flat index out of range")
    var low = 0
    var high = sections.count
    while low < high {
      let mid = (low + high) / 2
      if sections[mid].range.upperBound <= forIndex {
        low = mid + 1
      } else if sections[mid].range.lowerBound > forIndex {
        high = mid
      } else {
        return (mid, forIndex - sections[mid].range.lowerBound)
      }
    }
    preconditionFailure("flat index \(forIndex) is inside no section")
  }

  /// The flat row index for `(section, item)`.
  public func flatIndex(section: Int, item: Int) -> Int {
    precondition(section >= 0 && section < sections.count, "section out of range")
    let range = sections[section].range
    precondition(item >= 0 && item < range.count, "item out of range")
    return range.lowerBound + item
  }

  // MARK: - private builders

  static func makeSnapshot(
    rows: [TimelineRow], sections: [Section], generation: Int, revision: Int
  ) -> TimelineGridSnapshot {
    // One fused pass — dayKeys, counts, index map and date range together, so `build`
    // stays a true single pass over the rows.
    var dayKeys: [String] = []
    dayKeys.reserveCapacity(rows.count)
    var indexById: [String: Int] = [:]
    indexById.reserveCapacity(rows.count)
    var photos = 0
    var videos = 0
    var earliest: Date?
    var latest: Date?
    for (index, row) in rows.enumerated() {
      dayKeys.append(dayKey(for: row.localDateTime))
      indexById[row.id] = index
      switch row.mediaKind {
      case .video: videos += 1
      default: photos += 1
      }
      if let date = row.localDateTime {
        if earliest == nil || date < earliest! { earliest = date }
        if latest == nil || date > latest! { latest = date }
      }
    }
    let range: ClosedRange<Date>?
    if let earliest, let latest { range = earliest...latest } else { range = nil }
    return TimelineGridSnapshot(
      generation: generation, revision: revision, rows: rows, sections: sections,
      indexById: indexById, dayKeys: dayKeys,
      photoCount: photos, videoCount: videos, dateRange: range)
  }

  private static func counts(of rows: [TimelineRow]) -> (photos: Int, videos: Int) {
    var photos = 0
    var videos = 0
    for row in rows {
      switch row.mediaKind {
      case .video: videos += 1
      default: photos += 1
      }
    }
    return (photos, videos)
  }

  private static func indexMap(of rows: [TimelineRow]) -> [String: Int] {
    var map: [String: Int] = [:]
    map.reserveCapacity(rows.count)
    for (index, row) in rows.enumerated() { map[row.id] = index }
    return map
  }

  /// "yyyy-MM-dd" in GMT: `localDateTime` is stored as local wall time in UTC (the Immich
  /// convention), so GMT components recover the wall clock. Pure integer civil-date math
  /// (no `Calendar`, no `DateFormatter` anywhere on this path — both cost microseconds per
  /// row, fatal at 102k rows). Matches `MacMainWindow.dateString` ("yyyy-MM-dd",
  /// en_US_POSIX) for viewers in GMT; elsewhere it intentionally reflects wall time, not zone.
  static func dayKey(for date: Date?) -> String {
    guard let date else { return "" }
    // Days since the Unix epoch, floored (pre-1970 dates floor toward -1, not 0).
    let days = Int(floor(date.timeIntervalSince1970 / 86_400))
    // Howard Hinnant's civil_from_days: proleptic Gregorian, valid for the full Int range.
    let shifted = days + 719_468
    let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
    let dayOfEra = shifted - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let year = yearOfEra + era * 400
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthPart = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthPart + 2) / 5 + 1
    let month = monthPart + (monthPart < 10 ? 3 : -9)
    let fullYear = year + (month <= 2 ? 1 : 0)
    return "\(pad(fullYear, to: 4))-\(pad(month, to: 2))-\(pad(day, to: 2))"
  }

  /// Zero-pads `value` to `width` digits (years can exceed 4 digits; never truncated).
  private static func pad(_ value: Int, to width: Int) -> String {
    var text = String(value)
    while text.count < width { text = "0" + text }
    return text
  }
}

/// Bucket-header titles — the fix for R5 (`MacGridView.bucketTitle` built a `DateFormatter`
/// per bucket and mutated `dateFormat` twice, an ICU reparse each time). Formatters are
/// `static let` (created once); results are memoized per key in a lock-guarded dictionary.
public enum TimelineBucketTitle {
  public enum Kind: Sendable {
    case month
    case day
    case year
  }

  /// Lock-guarded memo table. `@unchecked Sendable` is safe because every access holds
  /// `lock` (NSLock itself is thread-safe); the `static let` below is immutable after init.
  private final class TitleCache: @unchecked Sendable {
    private let lock = NSLock()
    private var titles: [String: String] = [:]

    func cached(_ key: String) -> String? {
      lock.withLock { titles[key] }
    }

    func store(_ title: String, for key: String) {
      lock.withLock { titles[key] = title }
    }
  }

  private static let cache = TitleCache()

  private static let monthParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }()

  private static let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"
    formatter.locale = Locale.current
    return formatter
  }()

  private static let dayParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }()

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d, yyyy"
    formatter.locale = Locale.current
    return formatter
  }()

  /// "2026-09" (.month) → "September 2026" (matches the old `MacGridView.bucketTitle`);
  /// "2026-09-16" (.day) → "Wednesday, September 16, 2026"; "2026" (.year) → "2026".
  /// Unparseable keys return the key itself (never a blank header).
  public static func title(forKey key: String, kind: Kind) -> String {
    let cacheKey = "\(key)|\(kind)"
    if let hit = cache.cached(cacheKey) { return hit }
    let titled: String =
      switch kind {
      case .month:
        monthParser.date(from: key).map { monthFormatter.string(from: $0) } ?? key
      case .day:
        dayParser.date(from: key).map { dayFormatter.string(from: $0) } ?? key
      case .year:
        key
      }
    cache.store(titled, for: cacheKey)
    return titled
  }
}
