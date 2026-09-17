import Foundation
import LocalStore

// MARK: - immutable grid snapshot (WP1 §3)

/// Everything the collection view needs for one render pass: sectioned id lists, an id
/// lookup and a generation counter. A reference type by design: publishing a new snapshot
/// is O(1) (no 100k-struct `==` on the main actor), and all stored state is a `let`, so
/// the class is `Sendable` without locks. Built off-main in a detached task.
final class GridSnapshot: Sendable {
  struct Section: Sendable {
    /// Bucket key (`yyyy`, `yyyy-MM`, `yyyy-MM-dd`) or `"results"` for flat id sources.
    var key: String
    var title: String
    var ids: [String]
    var startDate: Date?
    var endDate: Date?
  }

  /// Bumped whenever section membership or order changes. The VC applies a snapshot only
  /// when its generation differs from the applied one, via diffable-data-source diffs —
  /// a sync update never tears the grid down.
  let generation: Int
  let sections: [Section]
  /// Flat id → position lookup for selection diffing, scrubbing and viewer routing.
  let indexById: [String: IndexPath]
  /// Every id in display order (newest first). Resolved into the viewer route on open —
  /// never copied per SwiftUI update.
  let allIds: [String]

  static let empty = GridSnapshot(generation: 0, sections: [], indexById: [:], allIds: [])

  var isEmpty: Bool { allIds.isEmpty }
  var count: Int { allIds.count }
  var dateRange: (start: Date, end: Date)? {
    let dates = sections.compactMap(\.startDate) + sections.compactMap(\.endDate)
    guard let min = dates.min(), let max = dates.max() else { return nil }
    return (min, max)
  }

  init(generation: Int, sections: [Section], indexById: [String: IndexPath], allIds: [String]) {
    self.generation = generation
    self.sections = sections
    self.indexById = indexById
    self.allIds = allIds
  }

  /// Groups flat index entries into bucket sections. Runs off-main: bucket keys come from
  /// integer calendar components in UTC (matching the SQL `strftime` on stored wall-time
  /// text) and titles from a static month-name table — never a `DateFormatter` per row.
  nonisolated static func build(
    entries: [PhotosLocalStore.TimelineIndexEntry],
    granularity: PhotosLocalStore.Granularity,
    generation: Int
  ) -> GridSnapshot {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
    var order: [String] = []
    var grouped: [String: [PhotosLocalStore.TimelineIndexEntry]] = [:]
    for entry in entries {
      let key = bucketKey(for: entry.localDateTime, granularity: granularity, calendar: calendar)
      if grouped[key] == nil {
        grouped[key] = []
        order.append(key)
      }
      grouped[key]?.append(entry)
    }
    var sections: [Section] = []
    var indexById: [String: IndexPath] = [:]
    var allIds: [String] = []
    indexById.reserveCapacity(entries.count)
    allIds.reserveCapacity(entries.count)
    for (sectionOffset, key) in order.enumerated() {
      let members = grouped[key] ?? []
      let ids = members.map(\.id)
      let dates = members.compactMap(\.localDateTime)
      for (itemOffset, id) in ids.enumerated() {
        indexById[id] = IndexPath(item: itemOffset, section: sectionOffset)
      }
      allIds.append(contentsOf: ids)
      sections.append(
        Section(
          key: key, title: title(for: key, granularity: granularity), ids: ids,
          startDate: dates.min(), endDate: dates.max()))
    }
    return GridSnapshot(
      generation: generation, sections: sections, indexById: indexById, allIds: allIds)
  }

  /// A flat single-section snapshot preserving the caller's order (search results).
  nonisolated static func flat(ids: [String], title: String, generation: Int) -> GridSnapshot {
    var indexById: [String: IndexPath] = [:]
    indexById.reserveCapacity(ids.count)
    for (offset, id) in ids.enumerated() { indexById[id] = IndexPath(item: offset, section: 0) }
    let section = Section(
      key: "results", title: title, ids: ids, startDate: nil, endDate: nil)
    return GridSnapshot(
      generation: generation, sections: ids.isEmpty ? [] : [section], indexById: indexById,
      allIds: ids)
  }

  // MARK: - bucket keys + titles (integer math, no formatters)

  private static let monthNames = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ]
  private static let monthFullNames = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ]

  nonisolated static func bucketKey(
    for date: Date?, granularity: PhotosLocalStore.Granularity, calendar: Calendar
  ) -> String {
    guard let date else { return "unknown" }
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    let year = parts.year ?? 0
    switch granularity {
    case .year:
      return String(format: "%04d", year)
    case .month:
      return String(format: "%04d-%02d", year, parts.month ?? 0)
    case .day:
      return String(format: "%04d-%02d-%02d", year, parts.month ?? 0, parts.day ?? 0)
    }
  }

  /// Section titles: "2024", "June 2024", "3 June 2024". Also used for year-bucket keys
  /// (`"2024"` formats back to itself).
  nonisolated static func title(for key: String, granularity: PhotosLocalStore.Granularity) -> String {
    let fields = key.split(separator: "-").compactMap { Int($0) }
    switch granularity {
    case .year:
      return key
    case .month:
      guard fields.count == 2, (1...12).contains(fields[1]) else { return key }
      return "\(monthFullNames[fields[1] - 1]) \(fields[0])"
    case .day:
      guard fields.count == 3, (1...12).contains(fields[1]) else { return key }
      return "\(fields[2]) \(monthFullNames[fields[1] - 1]) \(fields[0])"
    }
  }

  /// The fast-scroller bubble label ("Sep 2018") for a date, from the static name table.
  nonisolated static func bubbleTitle(for date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
    let parts = calendar.dateComponents([.year, .month], from: date)
    guard let month = parts.month, (1...12).contains(month) else { return "" }
    return "\(monthNames[month - 1]) \(parts.year ?? 0)"
  }
}
