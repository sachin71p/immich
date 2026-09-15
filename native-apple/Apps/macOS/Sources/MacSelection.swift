import Foundation

/// Grid selection state: marquee + ⌘/⇧ selection, full keyboard navigation, type-to-jump by date
/// (brief task 2). Pure value type over row ids so it unit-tests without AppKit.
public struct GridSelectionModel: Sendable, Hashable {
  public var orderedIds: [String]
  public var selected: Set<String>
  public var anchorIndex: Int?

  public init(orderedIds: [String] = [], selected: Set<String> = [], anchorIndex: Int? = nil) {
    self.orderedIds = orderedIds
    self.selected = selected
    self.anchorIndex = anchorIndex
  }

  public var anchorId: String? {
    guard let anchorIndex, orderedIds.indices.contains(anchorIndex) else { return nil }
    return orderedIds[anchorIndex]
  }

  /// Selection in display order (stable for viewer paging + bulk actions).
  public var selectedInOrder: [String] { orderedIds.filter { selected.contains($0) } }

  public mutating func retarget(to ids: [String]) {
    orderedIds = ids
    selected = selected.intersection(ids)
    if let anchorIndex, !orderedIds.indices.contains(anchorIndex) {
      self.anchorIndex = nil
    }
  }

  /// Plain click / return-to-single: collapse to one id.
  public mutating func selectSingle(id: String) {
    selected = [id]
    anchorIndex = orderedIds.firstIndex(of: id)
  }

  /// ⌘-click: toggle one id, move the anchor there.
  public mutating func toggle(id: String) {
    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    anchorIndex = orderedIds.firstIndex(of: id)
  }

  /// ⇧-click / ⇧-arrows: extend from the anchor (or the first selected) to `id`.
  public mutating func extend(to id: String) {
    guard let end = orderedIds.firstIndex(of: id) else { return }
    let start = anchorIndex ?? orderedIds.firstIndex(where: { selected.contains($0) }) ?? end
    let range = min(start, end)...max(start, end)
    selected = Set(orderedIds[range])
  }

  /// Marquee drag: replace the selection with an index range.
  public mutating func marquee(from start: Int, to end: Int) {
    guard !orderedIds.isEmpty else { return }
    let lo = max(0, min(start, end))
    let hi = min(orderedIds.count - 1, max(start, end))
    guard lo <= hi else { return }
    selected = Set(orderedIds[lo...hi])
    anchorIndex = end
  }

  public mutating func selectAll() {
    selected = Set(orderedIds)
    anchorIndex = orderedIds.isEmpty ? nil : 0
  }

  public mutating func clear() {
    selected = []
    anchorIndex = nil
  }

  public enum ArrowDirection: Sendable { case left, right, up, down }

  /// Arrow-key navigation. Returns the newly focused id (selection follows focus unless
  /// `extending`, which mirrors ⇧-arrow range extension).
  @discardableResult
  public mutating func move(_ direction: ArrowDirection, columns: Int, extending: Bool) -> String? {
    guard !orderedIds.isEmpty else { return nil }
    let columns = max(1, columns)
    let current = anchorIndex ?? 0
    let next: Int
    switch direction {
    case .left: next = max(0, current - 1)
    case .right: next = min(orderedIds.count - 1, current + 1)
    case .up: next = max(0, current - columns)
    case .down: next = min(orderedIds.count - 1, current + columns)
    }
    let id = orderedIds[next]
    if extending {
      extend(to: id)
    } else {
      selectSingle(id: id)
    }
    anchorIndex = next
    return id
  }

  /// Type-to-jump: typed digits resolve against bucket keys (`yyyy`, `yyyy-MM`, `yyyy-MM-dd`).
  /// Returns the first row index whose bucket key starts with the buffer, or nil.
  public static func jumpIndex(prefix: String, bucketKeys: [String]) -> Int? {
    guard !prefix.isEmpty else { return nil }
    var offset = 0
    for key in bucketKeys {
      if key.hasPrefix(prefix) { return offset }
      offset += 1
    }
    return nil
  }
}
