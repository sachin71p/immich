import AppKit
import CoreModel

/// Layout attributes carrying the pinned state for section headers, so
/// `MacGridHeaderView` can switch its material without knowing the viewport.
final class MacTimelineHeaderAttributes: NSCollectionViewLayoutAttributes {
  /// True while the header is stuck to the top of the viewport.
  var isPinned = false

  override func copy(with zone: NSZone? = nil) -> Any {
    let clone = super.copy(with: zone) as! MacTimelineHeaderAttributes
    clone.isPinned = isPinned
    return clone
  }
}

/// Custom grid layout for the timeline (WP3 §1). Geometry comes from WP1's
/// `TimelineGridGeometry` — pure math, O(sections) to build, arithmetic queries —
/// so `prepare()` only rebuilds when the width, zoom size or snapshot generation
/// changes, and element queries stay O(visible).
@MainActor
final class MacTimelineLayout: NSCollectionViewLayout {
  /// Set by the coordinator from the zoom slider and pinch. Clamped to 64…400.
  var targetItemSide: CGFloat = 180
  /// Set by the coordinator; drives section/item counts and geometry rebuilds.
  var snapshot: TimelineGridSnapshot = .empty

  /// Kill-switch for sticky headers: if WP7 measures any pinning hitch ≥ 50 ms,
  /// set this false (headers then scroll with their section) and report.
  static let pinsHeaders = true

  /// Zoom bounds both the slider and pinch feed through.
  static let minItemSide: CGFloat = 64
  static let maxItemSide: CGFloat = 400
  /// Pinch deltas below this are ignored so continuous gestures don't thrash layout.
  static let pinchQuantum: CGFloat = 4

  /// Clamp a requested zoom size into the supported range.
  static func clampedItemSide(_ side: CGFloat) -> CGFloat {
    min(maxItemSide, max(minItemSide, side))
  }

  /// Quantize a pinch update: returns `proposed` only when it moved at least one
  /// quantum from `current`, otherwise `current` (caller skips the invalidate).
  static func quantizedPinch(from current: CGFloat, to proposed: CGFloat) -> CGFloat {
    abs(proposed - current) >= pinchQuantum ? clampedItemSide(proposed) : current
  }

  private var geometry: TimelineGridGeometry?
  private var lastWidth: CGFloat = -1
  private var lastItemSide: CGFloat = -1
  private var lastGeneration = -1
  private var lastBoundsMinY: CGFloat = 0
  /// Reusable attribute objects, cleared on every geometry rebuild.
  private var itemCache: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
  private var headerCache: [Int: MacTimelineHeaderAttributes] = [:]

  override class var layoutAttributesClass: AnyClass { MacTimelineHeaderAttributes.self }

  // MARK: - prepare

  override func prepare() {
    super.prepare()
    guard let collectionView else { return }
    let width = collectionView.bounds.width
    guard width > 0 else { return }
    let side = Self.clampedItemSide(targetItemSide)
    let generation = snapshot.generation
    guard geometry == nil || width != lastWidth || side != lastItemSide
      || generation != lastGeneration
    else { return }
    let config = TimelineGridGeometry.Config(width: width, targetItemSide: side)
    geometry = TimelineGridGeometry(
      config: config,
      sections: snapshot.sections.map { (count: $0.range.count, kind: $0.kind) })
    lastWidth = width
    lastItemSide = side
    lastGeneration = generation
    lastBoundsMinY = collectionView.bounds.minY
    itemCache.removeAll(keepingCapacity: true)
    headerCache.removeAll(keepingCapacity: true)
  }

  // MARK: - queries (O(visible))

  override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
    guard let geometry else { return [] }
    var result: [NSCollectionViewLayoutAttributes] = []
    let visible = collectionView?.visibleRect ?? rect
    let pinnedSection = Self.pinsHeaders ? pinnedSection(for: visible, in: geometry) : nil
    for section in geometry.sections(intersecting: rect) {
      if let header = headerAttributes(for: section, in: geometry, visible: visible,
        pinnedSection: pinnedSection)
      {
        result.append(header)
      }
      for item in geometry.items(in: section, intersecting: rect) {
        result.append(itemAttributes(section: section, item: item, in: geometry))
      }
    }
    return result
  }

  override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
    guard let geometry else { return nil }
    guard snapshot.sections.indices.contains(indexPath.section),
      indexPath.section < geometry.sectionCount,
      snapshot.sections[indexPath.section].range.count > indexPath.item,
      indexPath.item >= 0
    else { return nil }
    return itemAttributes(section: indexPath.section, item: indexPath.item, in: geometry)
  }

  override func layoutAttributesForSupplementaryView(
    ofKind elementKind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath
  ) -> NSCollectionViewLayoutAttributes? {
    guard elementKind == NSCollectionView.elementKindSectionHeader,
      let geometry
    else { return nil }
    let visible = collectionView?.visibleRect ?? .zero
    let pinnedSection = Self.pinsHeaders ? pinnedSection(for: visible, in: geometry) : nil
    return headerAttributes(
      for: indexPath.section, in: geometry, visible: visible, pinnedSection: pinnedSection)
  }

  override var collectionViewContentSize: NSSize {
    guard let geometry else { return .zero }
    return NSSize(width: max(0, geometry.config.width), height: geometry.contentHeight)
  }

  // MARK: - invalidation

  /// True on width changes (needs a geometry rebuild in `prepare`) and on vertical
  /// scrolls while pinning is on (headers slide; geometry is untouched).
  override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
    guard let collectionView else { return false }
    let widthChanged = newBounds.width != collectionView.bounds.width
    let scrolled = Self.pinsHeaders && newBounds.minY != lastBoundsMinY
    lastBoundsMinY = newBounds.minY
    return widthChanged || scrolled
  }

  /// Scroll invalidation touches supplementary (header) elements only — items keep
  /// their cached attributes and the geometry is not re-prepared.
  override func invalidationContext(
    forBoundsChange newBounds: NSRect
  ) -> NSCollectionViewLayoutInvalidationContext {
    let context = super.invalidationContext(forBoundsChange: newBounds)
    guard let geometry, !newBounds.size.equalTo(.zero) else { return context }
    if newBounds.width != lastWidth {
      return context  // Full invalidate; prepare() rebuilds the geometry.
    }
    // NB: unlike UICollectionView, AppKit's context has no invalidateEverything /
    // invalidateDataSourceCounts setters — invalidating only the supplementary
    // elements below is what scopes the work. `prepare()` also early-returns when
    // width/side/generation are unchanged, so the geometry is never rebuilt here.
    let visible = NSRect(origin: newBounds.origin, size: newBounds.size)
    let paths = geometry.sections(intersecting: visible).compactMap { section -> IndexPath? in
      guard geometry.headerFrame(section: section) != nil else { return nil }
      return IndexPath(item: 0, section: section)
    }
    if !paths.isEmpty {
      context.invalidateSupplementaryElements(
        ofKind: NSCollectionView.elementKindSectionHeader, at: Set(paths))
    }
    return context
  }

  // MARK: - zoom anchoring (used by the coordinator, slice 2)

  /// Anchor for a zoom change: the item at the top of the viewport plus its offset
  /// from `visibleRect.minY`, so the coordinator can restore it post-invalidate.
  func anchorForZoomChange() -> (indexPath: IndexPath, topOffset: CGFloat)? {
    guard let geometry, let visible = collectionView?.visibleRect else { return nil }
    guard let nearest = geometry.indexPathNearest(y: visible.minY + 1) else { return nil }
    let top = geometry.originY(section: nearest.section, item: nearest.item)
    return (IndexPath(item: nearest.item, section: nearest.section), top - visible.minY)
  }

  /// Content offset that puts an anchor item back at its pre-zoom offset.
  func contentOffset(forAnchor indexPath: IndexPath, topOffset: CGFloat) -> CGFloat {
    guard let geometry, indexPath.section < geometry.sectionCount,
      snapshot.sections.indices.contains(indexPath.section),
      indexPath.item < snapshot.sections[indexPath.section].range.count
    else { return topOffset }
    return geometry.originY(section: indexPath.section, item: indexPath.item) - topOffset
  }

  // MARK: - private

  private func itemAttributes(
    section: Int, item: Int, in geometry: TimelineGridGeometry
  ) -> NSCollectionViewLayoutAttributes {
    let key = IndexPath(item: item, section: section)
    if let cached = itemCache[key] { return cached }
    let attrs = NSCollectionViewLayoutAttributes(forItemWith: key)
    attrs.frame = geometry.itemFrame(section: section, item: item)
    itemCache[key] = attrs
    return attrs
  }

  private func headerAttributes(
    for section: Int, in geometry: TimelineGridGeometry, visible: NSRect, pinnedSection: Int?
  ) -> MacTimelineHeaderAttributes? {
    guard let frame = geometry.headerFrame(section: section),
      snapshot.sections.indices.contains(section)
    else { return nil }
    let sectionKind = snapshot.sections[section].kind
    let stuck = pinnedFrame(
      frame, section: section, kind: sectionKind, in: geometry, visible: visible,
      pinnedSection: pinnedSection)
    let pinned = stuck.minY != frame.minY
    if let cached = headerCache[section] {
      cached.frame = stuck
      cached.isPinned = pinned
      return cached
    }
    let attrs = MacTimelineHeaderAttributes(
      forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
      with: IndexPath(item: 0, section: section))
    attrs.frame = stuck
    attrs.isPinned = pinned
    attrs.zIndex = 1024  // Pinned headers float above cells.
    headerCache[section] = attrs
    return attrs
  }

  /// Photos-style sticky month header: the header of the section at the top of the
  /// viewport sticks at `clamp(visibleMinY, sectionTop, sectionBottom − headerH)`.
  /// Year markers also stick (they separate years); `.none` sections have no header.
  private func pinnedFrame(
    _ frame: NSRect, section: Int, kind: TimelineSectionKind,
    in geometry: TimelineGridGeometry, visible: NSRect, pinnedSection: Int?
  ) -> NSRect {
    guard Self.pinsHeaders, pinnedSection == section, kind != .none else { return frame }
    guard let bottom = sectionBottom(section, in: geometry) else { return frame }
    var stuck = frame
    stuck.origin.y = min(max(visible.minY, frame.minY), max(frame.minY, bottom - frame.height))
    return stuck
  }

  /// Section whose header should stick: the visible section containing the top of
  /// the viewport (binary search + short scan, via the geometry).
  private func pinnedSection(for visible: NSRect, in geometry: TimelineGridGeometry) -> Int? {
    let range = geometry.sections(intersecting: visible)
    guard !range.isEmpty else { return nil }
    return range.lowerBound
  }

  /// Bottom of a section = top of the next section with a known top, else the
  /// content height. Tops come from header frames, falling back to first-item tops.
  private func sectionBottom(_ section: Int, in geometry: TimelineGridGeometry) -> CGFloat? {
    guard let geometryCount = collectionViewSectionCount(), section < geometryCount else {
      return nil
    }
    var next = section + 1
    while next < geometryCount {
      if let top = sectionTop(next, in: geometry) { return top }
      next += 1
    }
    return geometry.contentHeight
  }

  private func sectionTop(_ section: Int, in geometry: TimelineGridGeometry) -> CGFloat? {
    guard snapshot.sections.indices.contains(section) else { return nil }
    if let header = geometry.headerFrame(section: section) { return header.minY }
    let count = snapshot.sections[section].range.count
    guard count > 0 else { return nil }
    return geometry.originY(section: section, item: 0)
  }

  private func collectionViewSectionCount() -> Int? {
    guard let geometry else { return nil }
    return geometry.sectionCount
  }
}
