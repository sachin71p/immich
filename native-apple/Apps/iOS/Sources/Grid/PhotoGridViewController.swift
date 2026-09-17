import CoreModel
import LocalStore
import Media
import UIKit

@MainActor
final class PhotoGridViewController: UIViewController {
  typealias DataSource = UICollectionViewDiffableDataSource<String, String>

  var collectionView: UICollectionView!
  var dataSource: DataSource!
  var onTap: ((String) -> Void)?
  var onSelectionChange: ((Set<String>) -> Void)?
  var onPrefetch: (([String]) -> Void)?
  var onPinchColumns: ((Int) -> Void)?
  /// S1: pull-to-refresh handler (wired to `refreshAll` by the Library screen). Runs in a `Task`;
  /// the control always ends refreshing afterwards, even in fixture mode where sync is nil.
  var onRefresh: (() async -> Void)?
  /// Visible-window paging: ids around the viewport missing cached rows.
  var onNeedRows: (([String]) -> Void)?
  /// First/last visible dates for the Library subtitle (WP2).
  var onVisibleRange: ((Date?, Date?) -> Void)?
  /// Fires once, on the first non-empty snapshot apply (perf gate).
  var onFirstPaint: (() -> Void)?

  /// Row/flag/date lookups into the loader's cache (O(1), main-thread safe).
  var rowProvider: ((String) -> TimelineRow?)?
  var flagsProvider: ((String) -> PhotosLocalStore.TimelineIndexFlags)?
  var dateProvider: ((String) -> Date?)?
  var pipeline: MediaPipeline?
  var monitor: GridStallMonitor?

  /// No section headers (All view, search results); the snapshot stays sectioned for
  /// diffing, scrubbing and the visible range.
  var showsHeaders = true

  private(set) var currentSnapshot = GridSnapshot.empty
  private var appliedGeneration = -1
  private var currentColumns = 5
  private var currentAspectFit = false
  private var currentEditMode = false
  private var selectedIds = Set<String>()
  private var lastFiredRange: String = ""
  private var lastScrubSection = -1
  private var firstPaintFired = false
  private var didApplyNonEmpty = false
  private var lastSummaryUpdate = Date.distantPast
  private var scroller: FastScroller!
  private let perfLabel = UILabel()

  // MARK: - cheap setters (WP1 §5: compare-then-act, never redundant work)

  /// Applies a snapshot only when its generation is new, via a diffable-data-source diff —
  /// identical sync re-queries are a no-op here. Never tears the grid down.
  func applySnapshot(_ snapshot: GridSnapshot, animating: Bool = true) {
    guard snapshot.generation != appliedGeneration else { return }
    monitor?.currentPhase = "apply"
    appliedGeneration = snapshot.generation
    currentSnapshot = snapshot
    // Animated diffs of thousands of items wedge the main thread for minutes (the
    // 100k first paint never finished): animate only small updates to a live grid.
    let animated = animating && didApplyNonEmpty && snapshot.allIds.count <= 2000
    let start = Date()
    var diff = NSDiffableDataSourceSnapshot<String, String>()
    for section in snapshot.sections {
      diff.appendSections([section.key])
      diff.appendItems(section.ids, toSection: section.key)
    }
    dataSource.apply(diff, animatingDifferences: animated)
    if !snapshot.isEmpty { didApplyNonEmpty = true }
    monitor?.snapshotApplyMs = Date().timeIntervalSince(start) * 1000
    restoreSelection()
    pageVisibleRows()
    fireVisibleRange()
    if !firstPaintFired, !snapshot.isEmpty {
      firstPaintFired = true
      onFirstPaint?()
    }
    updatePerfSummary(force: true)
  }

  /// Rebuilds the fixed square layout only when the column count changed, keeping the
  /// pinch anchor item at its viewport position.
  func setColumns(_ columns: Int, animated: Bool = true) {
    let clamped = min(13, max(1, columns))
    guard clamped != currentColumns else { return }
    let anchor = anchorId()
    let anchorTop = anchor.flatMap { anchorTopOffset(for: $0) }
    currentColumns = clamped
    let start = Date()
    HeirloomSignpost.interval(HeirloomSignpost.layoutPrepare) {
      collectionView.setCollectionViewLayout(makeLayout(), animated: animated)
    }
    monitor?.layoutPrepareMs = Date().timeIntervalSince(start) * 1000
    if let anchor, let indexPath = dataSource.indexPath(for: anchor) {
      collectionView.layoutIfNeeded()
      let rect = collectionView.layoutAttributesForItem(at: indexPath)?.frame
      let y = (rect?.minY ?? 0) - (anchorTop ?? 0)
      collectionView.setContentOffset(
        CGPoint(x: 0, y: max(0, y)), animated: false)
    }
  }

  /// Aspect-fit flips image content modes in place — square cells stay, no layout reset.
  func setAspectFit(_ aspectFit: Bool) {
    guard aspectFit != currentAspectFit else { return }
    currentAspectFit = aspectFit
    reconfigureVisibleRows()
  }

  /// Edit mode never resets snapshot or layout (L4): visible cells + headers reconfigure.
  func setEditMode(_ editMode: Bool) {
    guard editMode != currentEditMode else { return }
    currentEditMode = editMode
    collectionView.allowsMultipleSelection = editMode
    if !editMode {
      selectedIds = []
      for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
        collectionView.deselectItem(at: indexPath, animated: false)
      }
    }
    reconfigureVisibleRows()
    reconfigureVisibleHeaders()
  }

  /// Diffs against the collection view's own selection — never loops over all rows (P3).
  func setSelection(_ ids: Set<String>) {
    let current = Set(collectionView.indexPathsForSelectedItems ?? [])
    var want: Set<IndexPath> = []
    want.reserveCapacity(ids.count)
    for id in ids {
      if let indexPath = currentSnapshot.indexById[id] { want.insert(indexPath) }
    }
    for indexPath in current.subtracting(want) {
      collectionView.deselectItem(at: indexPath, animated: false)
    }
    for indexPath in want.subtracting(current) {
      collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
    }
    selectedIds = ids
  }

  /// Visible headers don't refresh on their own — reconfigure their Select buttons.
  private func reconfigureVisibleHeaders() {
    for section in 0..<currentSnapshot.sections.count {
      guard let header = collectionView.supplementaryView(
        forElementKind: UICollectionView.elementKindSectionHeader,
        at: IndexPath(item: 0, section: section)) as? BucketHeaderView
      else { continue }
      header.showsSelectButton = currentEditMode
    }
  }

  /// In-place visible-cell refresh for flag-only updates (same snapshot generation).
  func reconfigureVisibleRows() {
    monitor?.currentPhase = "reconfigure"
    for indexPath in collectionView.indexPathsForVisibleItems {
      guard let id = dataSource.itemIdentifier(for: indexPath),
        let cell = collectionView.cellForItem(at: indexPath) as? PhotoGridCell
      else { continue }
      configure(cell, id: id)
    }
  }

  func scrollToSection(_ section: Int, animated: Bool = true) {
    guard section != lastScrubSection else { return }
    lastScrubSection = section
    guard section < currentSnapshot.sections.count, !currentSnapshot.sections.isEmpty else {
      return
    }
    collectionView.scrollToItem(
      at: IndexPath(item: 0, section: section), at: .top, animated: animated)
  }

  func scrollToId(_ id: String, animated: Bool = false) {
    guard let indexPath = currentSnapshot.indexById[id] else { return }
    collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
  }

  // MARK: - lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
    collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    collectionView.backgroundColor = .systemBackground
    collectionView.register(PhotoGridCell.self, forCellWithReuseIdentifier: PhotoGridCell.reuseId)
    collectionView.register(
      BucketHeaderView.self,
      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
      withReuseIdentifier: BucketHeaderView.reuseId)
    collectionView.delegate = self
    collectionView.prefetchDataSource = self
    collectionView.allowsMultipleSelection = false
    collectionView.alwaysBounceVertical = true
    collectionView.accessibilityValue = "idle"
    let refresh = UIRefreshControl()
    refresh.isAccessibilityElement = true
    refresh.accessibilityIdentifier = "pull-to-refresh"
    refresh.accessibilityValue = "idle"
    refresh.addTarget(self, action: #selector(didPullToRefresh(_:)), for: .valueChanged)
    collectionView.refreshControl = refresh
    view.addSubview(collectionView)

    dataSource = DataSource(collectionView: collectionView) { [weak self] cv, indexPath, id in
      guard let self else { return nil }
      let cell = cv.dequeueReusableCell(
        withReuseIdentifier: PhotoGridCell.reuseId, for: indexPath) as! PhotoGridCell
      self.configure(cell, id: id)
      return cell
    }
    dataSource.supplementaryViewProvider = { [weak self] cv, kind, indexPath in
      guard let self, self.showsHeaders,
        let header = cv.dequeueReusableSupplementaryView(
          ofKind: kind, withReuseIdentifier: BucketHeaderView.reuseId, for: indexPath) as? BucketHeaderView
      else { return nil }
      let section = self.currentSnapshot.sections[indexPath.section]
      header.titleLabel.text = section.title
      header.showsSelectButton = self.currentEditMode
      header.onSelectAll = { [weak self] in self?.selectAll(in: indexPath.section) }
      return header
    }

    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(didPinch(_:)))
    collectionView.addGestureRecognizer(pinch)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(didPanSelect(_:)))
    pan.delegate = self
    collectionView.addGestureRecognizer(pan)

    scroller = FastScroller(frame: scrollerFrame())
    scroller.autoresizingMask = [.flexibleHeight, .flexibleLeftMargin]
    scroller.onScrub = { [weak self] fraction in self?.scrubToFraction(fraction) }
    view.addSubview(scroller)

    // Perf-gate hook: a 1px label carrying the stall summary for the UI test. The
    // summary goes in `text` (what XCUI `value` returns for static texts) as well as
    // `accessibilityValue` — value-only was invisible to the test harness.
    perfLabel.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    perfLabel.alpha = 0.01
    perfLabel.isAccessibilityElement = true
    perfLabel.accessibilityIdentifier = "grid-perf-summary"
    perfLabel.text = "idle"
    perfLabel.accessibilityValue = "idle"
    view.addSubview(perfLabel)
    if GridStallMonitor.runsInThisProcess {
      monitor = GridStallMonitor()
      monitor?.start()
    }
  }

  private func scrollerFrame() -> CGRect {
    CGRect(x: view.bounds.width - 20, y: 0, width: 20, height: view.bounds.height)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    scroller.frame = scrollerFrame()
  }

  // MARK: - layout (WP1 §4: always fixed square, 1 pt spacing, no estimates)

  private func makeLayout() -> UICollectionViewLayout {
    let count = CGFloat(max(1, currentColumns))
    // Square cells at 1/count width AND height, 0.5 pt insets → 1 pt gaps like native.
    let itemSize = NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1.0 / count),
      heightDimension: .fractionalWidth(1.0 / count))
    let item = NSCollectionLayoutItem(layoutSize: itemSize)
    item.contentInsets = NSDirectionalEdgeInsets(top: 0.5, leading: 0.5, bottom: 0.5, trailing: 0.5)
    let groupSize = NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1.0),
      heightDimension: .fractionalWidth(1.0 / count))
    let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
    let section = NSCollectionLayoutSection(group: group)
    if showsHeaders {
      let headerSize = NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(36))
      section.boundarySupplementaryItems = [
        NSCollectionLayoutBoundarySupplementaryItem(
          layoutSize: headerSize, elementKind: UICollectionView.elementKindSectionHeader,
          alignment: .top)
      ]
    }
    return UICollectionViewCompositionalLayout(section: section)
  }

  /// Rebuilds layout when `showsHeaders` flips (All vs Months) — the only path that
  /// resets layout besides column changes.
  func setShowsHeaders(_ shows: Bool) {
    guard shows != showsHeaders else { return }
    showsHeaders = shows
    collectionView.setCollectionViewLayout(makeLayout(), animated: false)
  }

  // MARK: - cells

  private func configure(_ cell: PhotoGridCell, id: String) {
    monitor?.currentPhase = "configure"
    let row = rowProvider?(id)
    let flags = flagsProvider?(id) ?? []
    cell.configureBadges(row: row, flags: flags)
    cell.applyMode(editing: currentEditMode, selected: selectedIds.contains(id))
    cell.setThumbnail(id: id, row: row, pipeline: pipeline, aspectFit: currentAspectFit)
  }

  private func restoreSelection() {
    guard !selectedIds.isEmpty else { return }
    for id in selectedIds {
      if let indexPath = dataSource.indexPath(for: id) {
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
      }
    }
  }

  private func anchorId() -> String? {
    let visible = collectionView.indexPathsForVisibleItems.sorted()
    guard let first = visible.first else { return nil }
    return dataSource.itemIdentifier(for: first)
  }

  private func anchorTopOffset(for id: String) -> CGFloat? {
    guard let indexPath = dataSource.indexPath(for: id),
      let rect = collectionView.layoutAttributesForItem(at: indexPath)?.frame
    else { return nil }
    return rect.minY - collectionView.contentOffset.y
  }

  private func selectAll(in section: Int) {
    guard section < currentSnapshot.sections.count else { return }
    for id in currentSnapshot.sections[section].ids {
      selectedIds.insert(id)
      if let indexPath = dataSource.indexPath(for: id) {
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
      }
    }
    onSelectionChange?(selectedIds)
  }

  // MARK: - visible window: paging, range, scroller

  /// Pages rows for the visible window plus one screen ahead when the cache misses.
  private func pageVisibleRows() {
    let visible = collectionView.indexPathsForVisibleItems.sorted()
    guard !visible.isEmpty else { return }
    var ids: [String] = []
    ids.reserveCapacity(visible.count + 100)
    for indexPath in visible {
      if let id = dataSource.itemIdentifier(for: indexPath) { ids.append(id) }
    }
    // One screen ahead in the scroll direction (approx: next 100 items in section order).
    if let last = visible.last {
      var ahead = IndexPath(item: last.item + 1, section: last.section)
      while ids.count < visible.count + 100 {
        guard ahead.section < currentSnapshot.sections.count,
          ahead.item < currentSnapshot.sections[ahead.section].ids.count
        else {
          ahead = IndexPath(item: 0, section: ahead.section + 1)
          if ahead.section >= currentSnapshot.sections.count { break }
          continue
        }
        ids.append(currentSnapshot.sections[ahead.section].ids[ahead.item])
        ahead = IndexPath(item: ahead.item + 1, section: ahead.section)
      }
    }
    let missing = ids.filter { rowProvider?($0) == nil }
    if !missing.isEmpty { onNeedRows?(missing) }
  }

  private func fireVisibleRange() {
    let visible = collectionView.indexPathsForVisibleItems.sorted()
    guard let first = visible.first, let last = visible.last,
      let firstId = dataSource.itemIdentifier(for: first),
      let lastId = dataSource.itemIdentifier(for: last)
    else { return }
    // Day-granularity key: the subtitle shows a date range, so per-id changes inside
    // the same days must not invalidate SwiftUI (a fling would re-render dozens of
    // times per second for an identical subtitle).
    let firstDate = dateProvider?(firstId)
    let lastDate = dateProvider?(lastId)
    let key = "\(dayIndex(firstDate))-\(dayIndex(lastDate))"
    guard key != lastFiredRange else { return }
    lastFiredRange = key
    onVisibleRange?(firstDate, lastDate)
  }

  private func dayIndex(_ date: Date?) -> Int {
    guard let date else { return Int.min }
    return Int(date.timeIntervalSince1970 / 86_400)
  }

  private func updateScroller() {
    let content = collectionView.contentSize.height
    let bounds = collectionView.bounds.height
    guard content > bounds, bounds > 0 else {
      scroller.hideHandle()
      return
    }
    let top = collectionView.contentOffset.y / (content - bounds)
    scroller.update(fractionVisible: bounds / content, topFraction: top)
    // Bubble text from the middle visible item's date.
    let visible = collectionView.indexPathsForVisibleItems.sorted()
    if let middle = visible.dropFirst(visible.count / 2).first,
      let id = dataSource.itemIdentifier(for: middle),
      let date = dateProvider?(id)
    {
      scroller.setBubble(dateText: GridSnapshot.bubbleTitle(for: date))
    }
  }

  private func scrubToFraction(_ fraction: CGFloat) {
    let content = collectionView.contentSize.height
    let bounds = collectionView.bounds.height
    guard content > bounds else { return }
    let y = fraction * (content - bounds)
    collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
    updateScroller()
    let hostHeight = view.bounds.height
    scroller.showBubble(atY: min(hostHeight - 40, max(40, fraction * hostHeight)))
    pageVisibleRows()
    fireVisibleRange()
  }

  private func updatePerfSummary(force: Bool = false) {
    guard let monitor else { return }
    let now = Date()
    guard force || now.timeIntervalSince(lastSummaryUpdate) > 0.5 else { return }
    lastSummaryUpdate = now
    let summary = monitor.summary()
    perfLabel.text = summary
    perfLabel.accessibilityValue = summary
    // Nudge the AX tree so test reads see the new value instead of a cached one —
    // but never mid-fling: the post makes the AX server re-snapshot a 110k-item
    // tree against the main thread, the very stalls this hook measures. The test
    // only reads at settle and final (quiescent), where force posts still fire.
    // The monitor (and this hook) exist only under `-gridPerfRun`, never in production.
    if force || (!collectionView.isDragging && !collectionView.isDecelerating) {
      UIAccessibility.post(notification: .layoutChanged, argument: perfLabel)
    }
  }

  // MARK: - actions

  @objc private func didPullToRefresh(_ sender: UIRefreshControl) {
    sender.accessibilityValue = "refreshing"
    collectionView.accessibilityValue = "refreshing"
    Task { @MainActor in
      await onRefresh?()
      sender.accessibilityValue = "idle"
      collectionView.accessibilityValue = "idle"
      sender.endRefreshing()
    }
  }

  @objc private func didPinch(_ gesture: UIPinchGestureRecognizer) {
    guard gesture.state == .ended else { return }
    // WP1 §4 pinch steps, animated with the anchor kept in place by setColumns.
    let steps = [1, 3, 5, 9, 13]
    let current = currentColumns
    if gesture.scale > 1.3, let next = steps.last(where: { $0 < current }) {
      onPinchColumns?(next)
    } else if gesture.scale < 0.77, let next = steps.first(where: { $0 > current }) {
      onPinchColumns?(next)
    }
  }

  /// Drag-to-select: in edit mode a pan across cells adds them to the selection.
  @objc private func didPanSelect(_ gesture: UIPanGestureRecognizer) {
    guard currentEditMode else { return }
    let point = gesture.location(in: collectionView)
    guard let indexPath = collectionView.indexPathForItem(at: point),
      let id = dataSource.itemIdentifier(for: indexPath),
      !selectedIds.contains(id)
    else { return }
    selectedIds.insert(id)
    collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
    onSelectionChange?(selectedIds)
  }
}

extension PhotoGridViewController: UICollectionViewDelegate {
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
    if currentEditMode {
      selectedIds.insert(id)
      onSelectionChange?(selectedIds)
    } else {
      collectionView.deselectItem(at: indexPath, animated: false)
      onTap?(id)
    }
  }

  func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
    guard currentEditMode, let id = dataSource.itemIdentifier(for: indexPath) else { return }
    selectedIds.remove(id)
    onSelectionChange?(selectedIds)
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    monitor?.currentPhase = "scroll"
    updateScroller()
    updatePerfSummary()
    // Keep prefetch work to the visible window as it moves.
    if let pipeline {
      let ids = Set(
        collectionView.indexPathsForVisibleItems.compactMap {
          dataSource.itemIdentifier(for: $0)
        })
      pipeline.cancelPrefetch(keeping: ids)
    }
    // Page + range fire only when the visible set actually changed (gated inside).
    pageVisibleRows()
    fireVisibleRange()
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    updatePerfSummary(force: true)
  }

  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    if !decelerate { updatePerfSummary(force: true) }
  }
}

extension PhotoGridViewController: UICollectionViewDataSourcePrefetching {
  func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
    monitor?.currentPhase = "prefetch"
    // Priority by visibility using index distance only — never `layoutAttributesForItem`
    // (layout resolution per path costs milliseconds under fling volume). Fan-out is
    // capped: the pipeline dedups and the next event re-prioritizes anyway.
    let visible = collectionView.indexPathsForVisibleItems
    let edge = visible.max()
    let ids = indexPaths
      .compactMap { path -> (String, Int)? in
        guard let id = dataSource.itemIdentifier(for: path) else { return nil }
        let distance: Int
        if let edge {
          distance =
            abs(path.section - edge.section) * 10_000 + abs(path.item - edge.item)
        } else {
          distance = 0
        }
        return (id, distance)
      }
      .sorted { $0.1 < $1.1 }
      .prefix(60)
      .map(\.0)
    guard !ids.isEmpty else { return }
    let missing = ids.filter { rowProvider?($0) == nil }
    if !missing.isEmpty { onNeedRows?(missing) }
    onPrefetch?(ids)
  }
}

extension PhotoGridViewController: UIGestureRecognizerDelegate {
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool {
    gestureRecognizer is UIPanGestureRecognizer
  }
}
