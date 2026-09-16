import AppKit
import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI
import os

final class MacKeyCollectionView: NSCollectionView {
  var onKeyDown: (@MainActor (NSEvent) -> Bool)?
  var onSelectAllAction: (@MainActor () -> Void)?
  var onDoubleClick: (@MainActor (IndexPath) -> Void)?
  var onHoverMove: (@MainActor (NSEvent) -> Void)?
  var onContextMenu: (@MainActor (NSEvent) -> NSMenu?)?

  override func keyDown(with event: NSEvent) {
    if onKeyDown?(event) == true { return }
    super.keyDown(with: event)
  }

  // SwiftUI's default Edit menu already binds ⌘A to the standard `selectAll:` responder
  // action; MacMenus' custom View > Select All binds the same shortcut via notification.
  // Whichever menu item AppKit routes the physical keystroke to, this override makes sure
  // the real selection logic runs either way.
  override func selectAll(_ sender: Any?) {
    if let onSelectAllAction {
      onSelectAllAction()
    } else {
      super.selectAll(sender)
    }
  }

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      let point = convert(event.locationInWindow, from: nil)
      if let indexPath = indexPathForItem(at: point) {
        onDoubleClick?(indexPath)
        return
      }
    }
    super.mouseDown(with: event)
  }

  // The collection view owns the single hover tracking area (WP3 §3); mouse-moved
  // events land here and forward to the coordinator, which toggles at most two cells.
  override func mouseMoved(with event: NSEvent) {
    onHoverMove?(event)
  }

  // WP3 §3 context menu: the coordinator builds it (select-first, then MacAssetActions).
  override func menu(for event: NSEvent) -> NSMenu? {
    if let custom = onContextMenu?(event) { return custom }
    return super.menu(for: event)
  }
}

struct MacCollectionGridView: NSViewRepresentable {
  /// The grid's single source of truth (reference type: publishing a new snapshot is an
  /// O(1) identity comparison, never a value diff over 102k rows).
  var snapshot: TimelineGridSnapshot
  /// Patch cursor from the loader: when only this changes, reload just those indexes.
  var lastPatch: (revision: Int, indexes: [Int])
  var pipeline: MediaPipeline
  /// Used only to resolve `Asset`s for drag-out file names (cells load from rows alone).
  var store: PhotosLocalStore
  var exporter: MacExporter?
  var itemSize: CGFloat
  var usesSquareThumbnails = false
  /// Selection-mode badge only (checkmark on selected cells, Photos-style). Click
  /// selection itself is always native; this flag never gates selectability.
  var isSelectionMode: Bool = false
  /// Context-menu source (WP3 §3). Nil (default) means no menu; the pane passes the
  /// focused `gridActions` so menu items act on the current selection.
  var actions: MacAssetActions? = nil
  @Binding var selectedIds: Set<String>
  var onSelectionChange: ([String]) -> Void
  var onOpen: (String) -> Void
  var onPreview: (String) -> Void
  var onToggleFavorite: (String) -> Void
  var onMagnify: (CGFloat) -> Void

  func makeNSView(context: Context) -> NSScrollView {
    let layout = MacTimelineLayout()
    layout.snapshot = snapshot
    layout.targetItemSide = MacTimelineLayout.clampedItemSide(itemSize)
    let collectionView = MacKeyCollectionView()
    collectionView.collectionViewLayout = layout
    collectionView.isSelectable = true
    collectionView.allowsMultipleSelection = true
    collectionView.allowsEmptySelection = true
    collectionView.register(MacGridCell.self, forItemWithIdentifier: MacGridCell.identifier)
    collectionView.register(
      MacGridHeaderView.self,
      forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
      withIdentifier: MacGridHeaderView.identifier)
    collectionView.dataSource = context.coordinator
    collectionView.delegate = context.coordinator
    collectionView.onKeyDown = { [weak coordinator = context.coordinator] event in
      coordinator?.handleKey(event) ?? false
    }
    collectionView.onSelectAllAction = { [weak coordinator = context.coordinator] in
      coordinator?.selectAll()
    }
    context.coordinator.collectionView = collectionView
    collectionView.onDoubleClick = { [weak coordinator = context.coordinator] indexPath in
      coordinator?.open(indexPath)
    }
    collectionView.onHoverMove = { [weak coordinator = context.coordinator] event in
      coordinator?.hoverMoved(event)
    }
    collectionView.onContextMenu = { [weak coordinator = context.coordinator] event in
      coordinator?.contextMenu(for: event)
    }
    // Single hover tracking area for the whole grid (WP3 §3). Per-cell areas were
    // removed from MacThumbnailContainerView: 102k cells each installing an area is
    // pure overhead, and one `.inVisibleRect` area covers every cell.
    let hoverArea = NSTrackingArea(
      rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
      owner: collectionView, userInfo: nil)
    collectionView.addTrackingArea(hoverArea)
    let magnify = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnify(_:)))
    collectionView.addGestureRecognizer(magnify)
    let scrollView = NSScrollView()
    scrollView.documentView = collectionView
    scrollView.hasVerticalScroller = true
    context.coordinator.installPrefetchObserver(scrollView: scrollView)
    // Edit > Select All (menus own the shortcut — brief task 4). The box keeps the
    // @Sendable observer closure from capturing the non-Sendable coordinator.
    let selectAllBox = WeakCoordinatorBox(context.coordinator)
    context.coordinator.selectAllObserver = NotificationCenter.default.addObserver(
      forName: .macSelectAll, object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated {
        selectAllBox.value?.selectAll()
      }
    }
    return scrollView
  }

  static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
    if let observer = coordinator.selectAllObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = coordinator.prefetchObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    coordinator.cancelPrefetchTasks()
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    let coordinator = context.coordinator
    if snapshot.generation != coordinator.generation {
      coordinator.generation = snapshot.generation
      coordinator.appliedPatchRevision = lastPatch.revision
      if let layout = coordinator.collectionView?.collectionViewLayout as? MacTimelineLayout {
        layout.snapshot = snapshot
      }
      coordinator.hoveredIndexPath = nil
      coordinator.lastAppliedSelection = []
      coordinator.collectionView?.reloadData()
    } else if lastPatch.revision != coordinator.appliedPatchRevision {
      coordinator.appliedPatchRevision = lastPatch.revision
      // Patch path stays O(patch + visible): only patched indexes that are on screen
      // reload; the rest configure fresh when scrolled into view.
      if let cv = coordinator.collectionView, !lastPatch.indexes.isEmpty {
        let wanted = Set(lastPatch.indexes.compactMap { coordinator.indexPath(forFlat: $0) })
        let reload = wanted.intersection(cv.indexPathsForVisibleItems())
        if !reload.isEmpty {
          cv.reloadItems(at: reload)
        }
      }
    }
    coordinator.applyItemSize(itemSize)
    coordinator.syncSelection(selectedIds: selectedIds, snapshot: snapshot)
    coordinator.syncSelectionMode(isSelectionMode)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  @MainActor
  final class Coordinator: NSObject, @MainActor NSCollectionViewDataSource,
    @MainActor NSCollectionViewDelegate
  {
    var parent: MacCollectionGridView
    weak var collectionView: MacKeyCollectionView?
    /// Last snapshot generation fully loaded. A new generation means rows moved, so the
    /// whole list reloads; otherwise only `lastPatch` indexes refresh.
    var generation = -1
    var appliedPatchRevision = 0
    /// Last selection pushed into the collection view, so re-renders with an unchanged
    /// selection skip the `selectionIndexPaths` write (which would scroll/flicker).
    var lastAppliedSelection = Set<String>()
    /// Last `isSelectionMode` pushed to visible cells (checkmark badge only).
    var lastSelectionMode = false
    /// Index path under the cursor (single collection-view tracking area, WP3 §3).
    var hoveredIndexPath: IndexPath?
    private var typedBuffer = ""
    private var typedReset: Task<Void, Never>?
    private var suppressSelectionCallback = false
    /// Drag-out file names + assets, resolved from the store when the drag begins
    /// (cells no longer carry full `Asset`s).
    private var dragNames: [String: String] = [:]
    private var dragAssets: [String: Asset] = [:]
    /// Pinch state: raw magnification accumulates until it moves the grid a full
    /// quantum (4 pt), so continuous gestures don't thrash layout (WP3 §1).
    private var pinchAccumulator: CGFloat = 0
    // MARK: prefetch (WP3 §3)
    var prefetchObserver: NSObjectProtocol?
    private var lastPrefetchFire = Date.distantPast
    private var pendingPrefetch: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var lastBoundsY: CGFloat?
    private var lastBoundsTime: Date?
    /// Screens/second; > 4 means placeholders only, no network.
    private var scrollVelocity: CGFloat = 0
    /// +1 scrolling down/forward, −1 up/back.
    private var scrollDirection: CGFloat = 1
    /// `Prefetch` interval signposts for the WP0/WP7 harness. A local signposter (same
    /// subsystem/category as `HeirloomSignpost`) rather than extending PhotosCore's
    /// closed interval set, which WP1 owns.
    private let prefetchSignposter = OSSignposter(
      subsystem: "com.immich.heirloom", category: "timeline")

    init(parent: MacCollectionGridView) {
      self.parent = parent
      weakSelf = WeakCoordinatorBox(nil)
      super.init()
      weakSelf.value = self
    }

    private let weakSelf: WeakCoordinatorBox

    fileprivate func clearTypedBuffer() {
      typedBuffer = ""
    }

    func cancelPrefetchTasks() {
      pendingPrefetch?.cancel()
      settleTask?.cancel()
      pendingPrefetch = nil
      settleTask = nil
    }

    // MARK: snapshot mapping (section-aware; the single-section flat path is gone)

    /// Row for an index path via the snapshot's section ranges (empty `.year` sections
    /// hold no items, so `range.count == 0` correctly yields nil here).
    private func row(at indexPath: IndexPath) -> TimelineRow? {
      let snapshot = parent.snapshot
      guard snapshot.sections.indices.contains(indexPath.section),
        indexPath.item >= 0,
        indexPath.item < snapshot.sections[indexPath.section].range.count
      else { return nil }
      let flat = snapshot.flatIndex(section: indexPath.section, item: indexPath.item)
      guard snapshot.rows.indices.contains(flat) else { return nil }
      return snapshot.rows[flat]
    }

    private func flatIndex(at indexPath: IndexPath) -> Int? {
      let snapshot = parent.snapshot
      guard snapshot.sections.indices.contains(indexPath.section),
        indexPath.item >= 0,
        indexPath.item < snapshot.sections[indexPath.section].range.count
      else { return nil }
      let flat = snapshot.flatIndex(section: indexPath.section, item: indexPath.item)
      return snapshot.rows.indices.contains(flat) ? flat : nil
    }

    func indexPath(forFlat flat: Int) -> IndexPath? {
      let snapshot = parent.snapshot
      guard snapshot.rows.indices.contains(flat) else { return nil }
      let (section, item) = snapshot.sectionAndItem(forIndex: flat)
      guard section >= 0, item >= 0,
        snapshot.sections.indices.contains(section),
        item < snapshot.sections[section].range.count
      else { return nil }
      return IndexPath(item: item, section: section)
    }

    private var rowCount: Int { parent.snapshot.rows.count }

    /// Zoom path (WP3 §1): anchor the top-of-viewport item, invalidate, then restore
    /// the anchor offset so pinch and +/− feel continuous instead of jumping.
    func applyItemSize(_ size: CGFloat) {
      guard let cv = collectionView,
        let layout = cv.collectionViewLayout as? MacTimelineLayout
      else { return }
      let side = MacTimelineLayout.clampedItemSide(size)
      guard side != MacTimelineLayout.clampedItemSide(layout.targetItemSide) else { return }
      let anchor = layout.anchorForZoomChange()
      layout.targetItemSide = side
      layout.invalidateLayout()
      cv.layoutSubtreeIfNeeded()
      if let anchor {
        let y = layout.contentOffset(forAnchor: anchor.indexPath, topOffset: anchor.topOffset)
        if let clip = cv.enclosingScrollView?.contentView {
          clip.setBoundsOrigin(NSPoint(x: 0, y: y))
          cv.enclosingScrollView?.reflectScrolledClipView(clip)
        }
      }
    }

    /// Edit > Select All: extend the native selection, then push ids back out.
    func selectAll() {
      guard let collectionView, rowCount > 0 else { return }
      // Section-aware: every item of every section (O(rows), but user-invoked, never
      // on the update path).
      var paths = Set<IndexPath>()
      for (section, info) in parent.snapshot.sections.enumerated() {
        for item in 0..<info.range.count {
          paths.insert(IndexPath(item: item, section: section))
        }
      }
      collectionView.selectionIndexPaths = paths
      pushSelection()
    }

    var selectAllObserver: NSObjectProtocol?

    /// Selection diff through `indexById` (O(selection), never O(rows)).
    func syncSelection(selectedIds: Set<String>, snapshot: TimelineGridSnapshot) {
      guard let collectionView else { return }
      guard selectedIds != lastAppliedSelection else { return }
      lastAppliedSelection = selectedIds
      let wanted = Set(selectedIds.compactMap { snapshot.indexById[$0] }.compactMap {
        indexPath(forFlat: $0)
      })
      let current = collectionView.selectionIndexPaths
      guard wanted != current else { return }
      suppressSelectionCallback = true
      defer { suppressSelectionCallback = false }
      collectionView.selectionIndexPaths = wanted
    }

    /// Pushes a mode flip to visible cells without a reload (badge-only change).
    func syncSelectionMode(_ mode: Bool) {
      guard let cv = collectionView, mode != lastSelectionMode else { return }
      lastSelectionMode = mode
      for path in cv.indexPathsForVisibleItems() {
        (cv.item(at: path) as? MacGridCell)?.setSelectionMode(mode)
      }
    }

    // MARK: NSCollectionViewDataSource (all counts/views come from the snapshot)

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
      parent.snapshot.sections.count
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
      guard parent.snapshot.sections.indices.contains(section) else { return 0 }
      return parent.snapshot.sections[section].range.count
    }

    func collectionView(
      _ collectionView: NSCollectionView,
      viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
      at indexPath: IndexPath
    ) -> NSView {
      let view = collectionView.makeSupplementaryView(
        ofKind: kind, withIdentifier: MacGridHeaderView.identifier, for: indexPath)
      if kind == NSCollectionView.elementKindSectionHeader,
        let header = view as? MacGridHeaderView,
        parent.snapshot.sections.indices.contains(indexPath.section)
      {
        let section = parent.snapshot.sections[indexPath.section]
        header.configure(title: section.header ?? "", kind: section.kind)
      }
      return view
    }

    func collectionView(
      _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
      let item = collectionView.makeItem(withIdentifier: MacGridCell.identifier, for: indexPath)
      guard let cell = item as? MacGridCell else { return item }
      guard let row = row(at: indexPath) else { return cell }
      cell.onFavorite = { [weak self] in self?.parent.onToggleFavorite(row.id) }
      // WP3 S4 configure order (cache -> placeholder -> stream) lives in the cell;
      // the coordinator only supplies the row, the mode flags and the pipeline.
      cell.configure(
        row: row,
        aspectFit: !parent.usesSquareThumbnails,
        selectionMode: lastSelectionMode,
        itemSide: parent.itemSize,
        pipeline: parent.pipeline)
      cell.setHover(indexPath == hoveredIndexPath)
      return cell
    }

    // MARK: delegate

    func collectionView(
      _ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
      // A plain click only selects, matching native Photos — opening the viewer is reserved
      // for an explicit double-click, handled by MacKeyCollectionView.onDoubleClick -> open(_:).
      pushSelection()
    }

    func open(_ indexPath: IndexPath) {
      guard let id = row(at: indexPath)?.id else { return }
      parent.onOpen(id)
    }

    @objc func handleMagnify(_ recognizer: NSMagnificationGestureRecognizer) {
      switch recognizer.state {
      case .changed:
        // Accumulate raw magnification and only forward whole quanta: the pane steps
        // zoom discretely, and sub-quantum forwards would invalidate layout per event.
        pinchAccumulator += recognizer.magnification
        recognizer.magnification = 0
        if abs(pinchAccumulator * parent.itemSize) >= MacTimelineLayout.pinchQuantum {
          parent.onMagnify(pinchAccumulator)
          pinchAccumulator = 0
        }
      case .ended, .cancelled, .failed:
        pinchAccumulator = 0
      default:
        break
      }
    }

    func collectionView(
      _ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>
    ) {
      pushSelection()
    }

    /// Ordered ids (display order), so `onSelectionChange` keeps its contract even
    /// though `selectionIndexPaths` is an unordered set.
    private func pushSelection() {
      guard !suppressSelectionCallback, let collectionView else { return }
      let ordered = collectionView.selectionIndexPaths.sorted {
        ($0.section, $0.item) < ($1.section, $1.item)
      }
      let ids = ordered.compactMap { row(at: $0)?.id }
      lastAppliedSelection = Set(ids)
      parent.onSelectionChange(ids)
    }

    // MARK: hover (one collection-view tracking area)

    func hoverMoved(_ event: NSEvent) {
      guard let cv = collectionView else { return }
      let point = cv.convert(event.locationInWindow, from: nil)
      let path = cv.indexPathForItem(at: point)
      guard path != hoveredIndexPath else { return }
      if let old = hoveredIndexPath, let cell = cv.item(at: old) as? MacGridCell {
        cell.setHover(false)
      }
      hoveredIndexPath = path
      if let path, let cell = cv.item(at: path) as? MacGridCell {
        cell.setHover(true)
      }
    }

    // MARK: prefetch (clip-view bounds observer, throttled)

    func installPrefetchObserver(scrollView: NSScrollView) {
      let clip = scrollView.contentView
      clip.postsBoundsChangedNotifications = true
      let box = WeakCoordinatorBox(nil)
      // `weakSelf`-style box can't be used here: the coordinator exists already, so
      // point the box at it directly. The box (not the coordinator) is captured by the
      // @Sendable observer, keeping teardown safe.
      box.value = self
      prefetchObserver = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
      ) { _ in
        MainActor.assumeIsolated {
          box.value?.scrollBoundsDidChange()
        }
      }
    }

    func scrollBoundsDidChange() {
      updateScrollVelocity()
      let now = Date()
      guard now.timeIntervalSince(lastPrefetchFire) >= 0.05 else {
        // Throttled: coalesce into one deferred pass 50 ms out.
        if pendingPrefetch == nil {
          pendingPrefetch = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self, !Task.isCancelled else { return }
            self.pendingPrefetch = nil
            self.lastPrefetchFire = Date()
            self.prefetchPass()
            self.scheduleSettlePass()
          }
        }
        return
      }
      lastPrefetchFire = now
      prefetchPass()
      scheduleSettlePass()
    }

    private func updateScrollVelocity() {
      guard let clip = collectionView?.enclosingScrollView?.contentView else { return }
      let y = clip.bounds.minY
      let now = Date()
      defer {
        lastBoundsY = y
        lastBoundsTime = now
      }
      guard let lastY = lastBoundsY, let lastT = lastBoundsTime else { return }
      let dt = now.timeIntervalSince(lastT)
      guard dt > 0 else { return }
      let height = max(1, clip.bounds.height)
      let dy = y - lastY
      if dy != 0 { scrollDirection = dy > 0 ? 1 : -1 }
      scrollVelocity = abs(dy) / CGFloat(dt) / height
    }

    /// When scrolling stops, run one full prefetch pass so the cells around the
    /// resting viewport are always network-warm even if every live pass deferred.
    private func scheduleSettlePass() {
      settleTask?.cancel()
      settleTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(120))
        guard let self, !Task.isCancelled else { return }
        self.prefetchPass(settled: true)
      }
    }

    private func prefetchPass(settled: Bool = false) {
      guard let cv = collectionView else { return }
      let snapshot = parent.snapshot
      guard !snapshot.rows.isEmpty else { return }
      let visible = cv.indexPathsForVisibleItems().compactMap { flatIndex(at: $0) }
      guard !visible.isEmpty else { return }
      let lo = visible.min()!
      let hi = visible.max()!
      let perScreen = max(1, visible.count)
      let forward = scrollDirection >= 0
      if scrollVelocity > 4, !settled {
        // Fast fling: placeholders only for the upcoming screen, no network. The
        // settle pass (or a slow pass) backfills real thumbnails afterwards.
        let upcoming: [TimelineRow]
        if forward {
          let end = min(snapshot.rows.count, hi + 1 + perScreen)
          upcoming = (hi + 1..<end).map { snapshot.rows[$0] }
        } else {
          let start = max(0, lo - perScreen)
          upcoming = (start..<lo).map { snapshot.rows[$0] }
        }
        guard !upcoming.isEmpty else { return }
        let pipeline = parent.pipeline
        let state = prefetchSignposter.beginInterval("Prefetch")
        Task {
          for row in upcoming {
            if Task.isCancelled { break }
            _ = await pipeline.placeholder(id: row.id, thumbhash: row.thumbhash)
          }
          self.prefetchSignposter.endInterval("Prefetch", state)
        }
        return
      }
      // Slow scroll or settled: thumbnail prefetch for the window (1.5 screens ahead
      // in scroll direction, 0.5 behind), and cancel anything outside it.
      let ahead = Int((forward ? 1.5 : 0.5) * CGFloat(perScreen))
      let behind = Int((forward ? 0.5 : 1.5) * CGFloat(perScreen))
      let winLo = max(0, lo - behind)
      let winHi = min(snapshot.rows.count - 1, hi + ahead)
      guard winLo <= winHi else { return }
      let window = (winLo...winHi).map { snapshot.rows[$0] }
      let items = window.map { (id: $0.id, thumbhash: $0.thumbhash) }
      let keep = Set(window.map(\.id))
      let pipeline = parent.pipeline
      let state = prefetchSignposter.beginInterval("Prefetch")
      Task {
        await pipeline.prefetch(items, tier: .thumbnail)
        await pipeline.cancelPrefetch(keeping: keep)
        self.prefetchSignposter.endInterval("Prefetch", state)
      }
    }

    // MARK: context menu (from MacAssetActions)

    func contextMenu(for event: NSEvent) -> NSMenu? {
      guard let cv = collectionView, let actions = parent.actions else { return nil }
      // Right-click on an unselected item selects it first, Photos-style.
      let point = cv.convert(event.locationInWindow, from: nil)
      if let path = cv.indexPathForItem(at: point), !cv.selectionIndexPaths.contains(path) {
        suppressSelectionCallback = true
        cv.selectionIndexPaths = [path]
        suppressSelectionCallback = false
        pushSelection()
      }
      menuActions = actions
      let menu = NSMenu()
      menu.addItem(withTitle: "Open", action: #selector(menuOpenViewer(_:)), keyEquivalent: "")
        .target = self
      menu.addItem(withTitle: "Quick Look", action: #selector(menuPreview(_:)), keyEquivalent: "")
        .target = self
      menu.addItem(withTitle: "Get Info", action: #selector(menuToggleInspector(_:)), keyEquivalent: "")
        .target = self
      // Favorite title follows the first selected row; menu acts on the selection,
      // which is fresh by invoke time (select-first pushed through the binding before
      // the menu tracks).
      let firstFavorite: Bool? = {
        guard let first = cv.selectionIndexPaths.sorted(by: { ($0.section, $0.item) < ($1.section, $1.item) }).first else { return nil }
        return row(at: first)?.isFavorite
      }()
      menu.addItem(
        withTitle: (firstFavorite ?? false) ? "Unfavorite" : "Favorite",
        action: #selector(menuFavorite(_:)), keyEquivalent: "")
        .target = self
      // Rotate persists via the WP4 path (`gridActions.rotate` → `rotate(ids:)`).
      let rotateItem = NSMenuItem(
        title: "Rotate Clockwise", action: #selector(menuRotate(_:)), keyEquivalent: "")
      rotateItem.target = self
      menu.addItem(rotateItem)
      menu.addItem(withTitle: "Add to Album…", action: #selector(menuAddToAlbum(_:)), keyEquivalent: "")
        .target = self
      menu.addItem(withTitle: "Move to…", action: #selector(menuMove(_:)), keyEquivalent: "")
        .target = self
      menu.addItem(.separator())
      let trash = menu.addItem(
        withTitle: "Delete", action: #selector(menuTrash(_:)), keyEquivalent: "")
      trash.target = self
      return menu
    }

    private var menuActions: MacAssetActions?

    @objc private func menuOpenViewer(_ sender: Any?) { menuActions?.openViewer() }
    @objc private func menuPreview(_ sender: Any?) { menuActions?.preview() }
    @objc private func menuToggleInspector(_ sender: Any?) { menuActions?.toggleInspector() }
    @objc private func menuFavorite(_ sender: Any?) { menuActions?.favorite() }
    @objc private func menuRotate(_ sender: Any?) { menuActions?.rotate() }
    @objc private func menuAddToAlbum(_ sender: Any?) { menuActions?.addToAlbum() }
    @objc private func menuMove(_ sender: Any?) { menuActions?.move() }
    @objc private func menuTrash(_ sender: Any?) { menuActions?.trash() }

    // MARK: drag out (brief task 5: export originals to Finder via file promises)

    func collectionView(
      _ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
      guard let id = row(at: indexPath)?.id else { return nil }
      let item = NSPasteboardItem()
      item.setString(id, forType: .init("com.immich.heirloom.asset-id"))
      // Plain-text mirror so the SwiftUI sidebar drop targets (and Finder-adjacent
      // handlers) can read the dragged ids through NSItemProvider.
      item.setString(id, forType: .string)
      return item
    }

    /// Prefetch originals when a drag begins so the promised-files write at drop time is local.
    /// `Asset`s (for `originalFileName` + prefetch) resolve here because cells no longer
    /// carry them; the drop callback reads the maps this task fills.
    func collectionView(
      _ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
      willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>
    ) {
      guard parent.exporter != nil else { return }
      let ids = indexPaths.compactMap { row(at: $0)?.id }
      dragState.reset()
      dragNames = [:]
      dragAssets = [:]
      let store = parent.store
      let exporter = parent.exporter
      let box = dragState
      Task { @MainActor [weak self] in
        guard let assets = try? await store.assets(ids: ids) else { return }
        guard let self else { return }
        for asset in assets {
          self.dragNames[asset.id] = asset.originalFileName
          self.dragAssets[asset.id] = asset
          if let exporter { box.prefetch(asset: asset, with: exporter) }
        }
      }
    }

    /// Finder drop endpoint of the promised-files flow: materialize prefetched originals (or
    /// fall back to a bounded synchronous download) at the destination.
    func collectionView(
      _ collectionView: NSCollectionView,
      namesOfPromisedFilesDroppedAtDestination dropURL: URL,
      forDraggedItemsAt indexPaths: Set<IndexPath>
    ) -> [String] {
      var names: [String] = []
      for indexPath in indexPaths {
        guard let id = row(at: indexPath)?.id else { continue }
        let name = dragNames[id] ?? id
        names.append(name)
        let destination = dropURL.appendingPathComponent(name)
        if let temp = dragState.stagedFile(for: id) {
          try? FileManager.default.copyItem(at: temp, to: destination)
        } else if let asset = dragAssets[id], let exporter = parent.exporter {
          // Drag outran the prefetch: bounded synchronous fallback (30s per file).
          let box = LockBox<Data?>(nil)
          let semaphore = DispatchSemaphore(value: 0)
          let task = Task {
            box.value = try? await exporter.downloadOriginal(asset: asset)
            semaphore.signal()
          }
          if semaphore.wait(timeout: .now() + 30) == .success, let downloaded = box.value {
            try? downloaded.write(to: destination, options: .atomic)
          } else {
            task.cancel()
          }
        }
      }
      return names
    }

    private let dragState = MacDragPrefetchState()

    /// Lock-guarded box for passing one value across the sync/async fallback boundary.
    private final class LockBox<T>: @unchecked Sendable {
      private let lock = NSLock()
      private var stored: T
      init(_ value: T) { stored = value }
      var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
      }
    }

    // MARK: keyboard (brief task 2 + WP3 §3 selection keys)

    // Navigation keys only (return/space/type-to-jump; arrows are native). Asset actions
    // (favorite/rotate/delete/move/info) live in the menus and route through the focused
    // value, so there is exactly one shortcut owner and no double-fire with the viewer.
    func handleKey(_ event: NSEvent) -> Bool {
      let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
      let currentId: String? = {
        guard let collectionView else { return nil }
        let sorted = collectionView.selectionIndexPaths.sorted { ($0.section, $0.item) < ($1.section, $1.item) }
        return sorted.last.flatMap { row(at: $0)?.id }
      }()

      switch event.keyCode {
      case 36:  // return = open
        if let currentId { parent.onOpen(currentId); return true }
        return false
      case 49:  // space = Quick Look-style preview
        if flags.isEmpty, let currentId { parent.onPreview(currentId); return true }
        return false
      case 53:  // esc = clear selection
        if flags.isEmpty, let collectionView, !collectionView.selectionIndexPaths.isEmpty {
          collectionView.selectionIndexPaths = []
          pushSelection()
          return true
        }
        return false
      default:
        break
      }

      guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return false }
      // Type-to-jump by date: accumulate digits and dashes, jump to the first row whose
      // capture date starts with the buffer (e.g. "2024" or "2024-06").
      if flags.isEmpty, chars.allSatisfy({ $0.isNumber || $0 == "-" }) {
        typedBuffer += chars
        typedReset?.cancel()
        let selfBox = weakSelf
        typedReset = Task { @MainActor in
          try? await Task.sleep(for: .seconds(1))
          selfBox.clearTypedBuffer()
        }
        jumpToDate(prefix: typedBuffer)
        return true
      }
      return false
    }

    private func jumpToDate(prefix: String) {
      guard let collectionView, !prefix.isEmpty else { return }
      let snapshot = parent.snapshot
      // `dayKeys` parallel `rows` (WP1 contract); linear scan is keypress-rate, not
      // scroll-rate, so no perf concern.
      guard snapshot.dayKeys.count == snapshot.rows.count,
        let flat = snapshot.dayKeys.firstIndex(where: { !$0.isEmpty && $0.hasPrefix(prefix) }),
        let indexPath = indexPath(forFlat: flat)
      else { return }
      collectionView.selectionIndexPaths = [indexPath]
      collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
      pushSelection()
    }
  }
}

/// Main-thread-confined coordinator reference for the @Sendable select-all observer.
private final class WeakCoordinatorBox: @unchecked Sendable {
  weak var value: MacCollectionGridView.Coordinator?
  init(_ value: MacCollectionGridView.Coordinator?) { self.value = value }

  @MainActor
  func clearTypedBuffer() {
    // No-op when the view is torn down (weak).
    value?.clearTypedBuffer()
  }
}
