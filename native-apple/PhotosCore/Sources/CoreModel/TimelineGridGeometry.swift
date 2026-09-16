import CoreGraphics
import Foundation

/// Pure-math square grid geometry for WP3's custom `NSCollectionViewLayout` — the fix for R3.
///
/// Photos uses square cells in both modes ("aspect ratio grid" only changes how the image
/// fits inside the square), so the geometry is always square: **no per-item storage and no
/// per-item work in prepare.** Construction is O(sections); all queries are arithmetic or
/// binary search. Item `(r, c)` in a section sits at
/// `x = left + c * (itemSide + spacing)`, `y = sectionOrigin + headerH + r * (itemSide + spacing)`.
public struct TimelineGridGeometry: Sendable, Equatable {
  /// `NSEdgeInsets`-like insets as a `Sendable` value (AppKit insets are not `Sendable`).
  public struct Insets: Sendable, Equatable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat = 8, left: CGFloat = 8, bottom: CGFloat = 8, right: CGFloat = 8) {
      self.top = top
      self.left = left
      self.bottom = bottom
      self.right = right
    }
  }

  public struct Config: Sendable, Equatable {
    public var width: CGFloat
    /// From the zoom slider, 64…400.
    public var targetItemSide: CGFloat
    public var spacing: CGFloat = 2
    public var insets = Insets()
    public var yearHeaderHeight: CGFloat = 56
    public var monthHeaderHeight: CGFloat = 40

    public init(
      width: CGFloat, targetItemSide: CGFloat, spacing: CGFloat = 2,
      insets: Insets = Insets(), yearHeaderHeight: CGFloat = 56,
      monthHeaderHeight: CGFloat = 40
    ) {
      self.width = width
      self.targetItemSide = targetItemSide
      self.spacing = spacing
      self.insets = insets
      self.yearHeaderHeight = yearHeaderHeight
      self.monthHeaderHeight = monthHeaderHeight
    }
  }

  /// Per-section layout — O(sections) storage, never per-item.
  struct SectionLayout: Sendable, Equatable {
    /// Y of the section top (header top, or first row when headerless), including top inset
    /// for section 0.
    var originY: CGFloat
    var headerHeight: CGFloat
    var rowCount: Int
    var itemCount: Int
    var kind: TimelineSectionKind
  }

  public let config: Config
  public let columns: Int
  /// Cell side, floored to whole pixels so columns fill the width exactly.
  public let itemSide: CGFloat
  public let contentHeight: CGFloat
  let sectionLayouts: [SectionLayout]

  /// Number of sections (== `sections.count` passed to `init`).
  public var sectionCount: Int { sectionLayouts.count }

  /// - Parameter sections: `(count, kind)` per snapshot section, in order. `count` is the
  ///   item count (0 for header-only year markers).
  public init(config: Config, sections: [(count: Int, kind: TimelineSectionKind)]) {
    self.config = config
    let contentWidth = max(0, config.width - config.insets.left - config.insets.right)
    let columns = max(
      1, Int(floor((contentWidth + config.spacing) / (config.targetItemSide + config.spacing))))
    self.columns = columns
    let itemSide =
      columns > 0
      ? floor((contentWidth - CGFloat(columns - 1) * config.spacing) / CGFloat(columns)) : 0
    self.itemSide = max(0, itemSide)
    var layouts: [SectionLayout] = []
    layouts.reserveCapacity(sections.count)
    var y = config.insets.top
    for section in sections {
      let headerHeight: CGFloat =
        switch section.kind {
        case .none: 0
        case .year: config.yearHeaderHeight
        case .month: config.monthHeaderHeight
        }
      let rowCount =
        section.count > 0 ? Int(ceil(Double(section.count) / Double(columns))) : 0
      layouts.append(
        SectionLayout(
          originY: y, headerHeight: headerHeight, rowCount: rowCount,
          itemCount: max(0, section.count), kind: section.kind))
      y += headerHeight + CGFloat(rowCount) * (self.itemSide + config.spacing)
      // No trailing spacing after the last row — rows are top-packed with `spacing`
      // *between* them; then every section takes the same bottom gap.
      if rowCount > 0 { y -= config.spacing }
      y += config.spacing * 4
    }
    self.sectionLayouts = layouts
    // Content height keeps the last section's bottom gap plus the bottom inset, so the
    // grid's tail overscroll matches the inter-section rhythm instead of ending flush.
    self.contentHeight = y + config.insets.bottom
  }

  // MARK: - frames

  /// Header frame, or `nil` for `kind == .none` (and for out-of-range sections).
  public func headerFrame(section: Int) -> CGRect? {
    guard sectionLayouts.indices.contains(section) else { return nil }
    let layout = sectionLayouts[section]
    guard layout.kind != .none else { return nil }
    return CGRect(
      x: config.insets.left, y: layout.originY,
      width: max(0, config.width - config.insets.left - config.insets.right),
      height: layout.headerHeight)
  }

  /// Square frame for `(section, item)`.
  public func itemFrame(section: Int, item: Int) -> CGRect {
    let layout = sectionLayouts[section]
    let row = item / columns
    let column = item % columns
    return CGRect(
      x: config.insets.left + CGFloat(column) * (itemSide + config.spacing),
      y: layout.originY + layout.headerHeight + CGFloat(row) * (itemSide + config.spacing),
      width: itemSide,
      height: itemSide)
  }

  /// Y of the top of `(section, item)`'s row.
  public func originY(section: Int, item: Int) -> CGFloat {
    let layout = sectionLayouts[section]
    return layout.originY + layout.headerHeight + CGFloat(item / columns) * (itemSide + config.spacing)
  }

  // MARK: - range queries

  /// Sections overlapping `rect` — binary search on section origins, then a short linear
  /// scan (only visible sections). Empty when nothing overlaps (`insertionPoint..<insertionPoint`).
  public func sections(intersecting rect: CGRect) -> Range<Int> {
    var low = 0
    var high = sectionLayouts.count
    while low < high {
      let mid = (low + high) / 2
      if sectionEnd(mid) <= rect.minY {
        low = mid + 1
      } else {
        high = mid
      }
    }
    var end = low
    while end < sectionLayouts.count && sectionLayouts[end].originY < rect.maxY {
      end += 1
    }
    return low..<end
  }

  /// Items of `section` overlapping `rect` — arithmetic on the row index, with each
  /// candidate row/column verified against its true band so the result agrees exactly
  /// with brute-force frame intersection.
  public func items(in section: Int, intersecting rect: CGRect) -> Range<Int> {
    let layout = sectionLayouts[section]
    guard layout.itemCount > 0, layout.rowCount > 0 else { return 0..<0 }
    let headerEnd = layout.originY + layout.headerHeight
    let pitch = itemSide + config.spacing
    guard pitch > 0 else { return 0..<layout.itemCount }
    // Candidate rows covering the rect, then exact band verification (the spacing gutter
    // between rows belongs to no item).
    let firstRow = max(0, Int(floor((rect.minY - headerEnd) / pitch)))
    let lastRow = min(layout.rowCount - 1, Int(floor((rect.maxY - headerEnd) / pitch)))
    guard firstRow <= lastRow else { return 0..<0 }
    var matchedFirst: Int?
    var matchedLast = 0
    for row in firstRow...lastRow {
      let top = headerEnd + CGFloat(row) * pitch
      guard top < rect.maxY, top + itemSide > rect.minY else { continue }
      // Columns are uniform, so verify the horizontal band once per row.
      let firstCol = max(0, Int(floor((rect.minX - config.insets.left) / pitch)))
      let lastCol = min(columns - 1, Int(floor((rect.maxX - config.insets.left) / pitch)))
      var rowFirst: Int?
      var rowLast = 0
      if firstCol <= lastCol {
        for col in firstCol...lastCol {
          let left = config.insets.left + CGFloat(col) * pitch
          guard left < rect.maxX, left + itemSide > rect.minX else { continue }
          let item = row * columns + col
          guard item < layout.itemCount else { continue }
          if rowFirst == nil { rowFirst = item }
          rowLast = item
        }
      }
      if let rowFirst {
        if matchedFirst == nil { matchedFirst = rowFirst }
        matchedLast = rowLast
      }
    }
    guard let matchedFirst else { return 0..<0 }
    return matchedFirst..<(matchedLast + 1)
  }

  /// The item a zoom should anchor on at vertical position `y`: the containing section's
  /// row at `y` (first item of that row… see below). Header-only sections are skipped
  /// toward the nearest section with items. `nil` only when every section is empty.
  public func indexPathNearest(y: CGFloat) -> (section: Int, item: Int)? {
    guard !sectionLayouts.isEmpty else { return nil }
    let clamped = min(max(y, 0), max(contentHeight, 0))
    var section = 0
    for (index, layout) in sectionLayouts.enumerated() {
      if layout.originY <= clamped { section = index } else { break }
    }
    // `y` may sit in a header-only marker or the trailing gap — prefer the nearest
    // section with items, scanning outward from the containing section.
    if sectionLayouts[section].itemCount == 0 {
      var forward = section
      var backward = section
      var found: Int?
      while forward < sectionLayouts.count || backward >= 0 {
        if forward < sectionLayouts.count, sectionLayouts[forward].itemCount > 0 {
          found = forward
          break
        }
        if backward >= 0, sectionLayouts[backward].itemCount > 0 {
          found = backward
          break
        }
        forward += 1
        backward -= 1
      }
      guard let found else { return nil }
      section = found
    }
    let layout = sectionLayouts[section]
    let headerEnd = layout.originY + layout.headerHeight
    let pitch = itemSide + config.spacing
    let row =
      pitch > 0
      ? min(max(Int(floor((clamped - headerEnd) / pitch)), 0), layout.rowCount - 1) : 0
    return (section, min(max(row, 0) * columns, layout.itemCount - 1))
  }

  // MARK: - private

  private func sectionEnd(_ section: Int) -> CGFloat {
    let layout = sectionLayouts[section]
    var end = layout.originY + layout.headerHeight
    if layout.rowCount > 0 {
      end += CGFloat(layout.rowCount) * (itemSide + config.spacing) - config.spacing
    }
    return end + config.spacing * 4
  }
}
