import AppKit
import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI
final class MacKeyCollectionView: NSCollectionView {
  var onKeyDown: (@MainActor (NSEvent) -> Bool)?
  var onSelectAllAction: (@MainActor () -> Void)?
  var onDoubleClick: (@MainActor (IndexPath) -> Void)?

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
}

struct MacCollectionGridView: NSViewRepresentable {
  var sections: [MacGridSection]
  var assetsById: [String: Asset]
  /// `yyyy-MM-dd` capture-date strings parallel to the flattened rows (`""` when unknown).
  var rowDates: [String]
  var pipeline: MediaPipeline
  var exporter: MacExporter?
  var itemSize: CGFloat
  var usesSquareThumbnails = false
  /// Normal clicks open an asset. Selection is an explicit mode, as in the macOS Photos app.
  var isSelectionMode: Bool = false
  @Binding var selectedIds: Set<String>
  var onSelectionChange: ([String]) -> Void
  var onOpen: (String) -> Void
  var onPreview: (String) -> Void
  var onToggleFavorite: (String) -> Void
  var onMagnify: (CGFloat) -> Void

  func makeNSView(context: Context) -> NSScrollView {
    let layout = NSCollectionViewFlowLayout()
    layout.minimumInteritemSpacing = 8
    layout.minimumLineSpacing = 8
    layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    // NB: `estimatedItemSize` was tried here to avoid a full-dataset layout pass on launch, but
    // on this library's scale (100k+ items, aspect-ratio-varied heights via sizeForItemAt) it
    // instead sent NSCollectionViewFlowLayout into a self-reinvalidating layout loop —
    // `_updateVisibleCellsNow:` recursing into itself indefinitely, a full hang that is strictly
    // worse than the multi-second synchronous layout it was meant to avoid. Reverted; the
    // underlying scale problem needs a real fix (e.g. paginating the query) rather than this.
    let collectionView = MacKeyCollectionView()
    collectionView.collectionViewLayout = layout
    collectionView.isSelectable = true
    collectionView.allowsMultipleSelection = true
    collectionView.allowsEmptySelection = true
    collectionView.register(MacGridCell.self, forItemWithIdentifier: MacGridCell.identifier)
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
    let magnify = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnify(_:)))
    collectionView.addGestureRecognizer(magnify)
    let scrollView = NSScrollView()
    scrollView.documentView = collectionView
    scrollView.hasVerticalScroller = true
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
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.reloadIfNeeded(sections: sections)
    context.coordinator.applyItemSize(itemSize)
    context.coordinator.syncSelection(selectedIds: selectedIds)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  @MainActor
  final class Coordinator: NSObject, @MainActor NSCollectionViewDataSource,
    @MainActor NSCollectionViewDelegateFlowLayout
  {
    var parent: MacCollectionGridView
    weak var collectionView: MacKeyCollectionView?
    private var flatIds: [String] = []
    private var sectionOffsets: [Int] = []
    private var typedBuffer = ""
    private var typedReset: Task<Void, Never>?
    private var suppressSelectionCallback = false

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

    // MARK: data

    func reloadIfNeeded(sections: [MacGridSection]) {
      let ids = sections.flatMap { $0.rows.map(\.id) }
      guard ids != flatIds else { return }
      flatIds = ids
      sectionOffsets = []
      var offset = 0
      for section in sections {
        sectionOffsets.append(offset)
        offset += section.rows.count
      }
      collectionView?.reloadData()
    }

    func applyItemSize(_ size: CGFloat) {
      guard let layout = collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout,
        layout.itemSize.width != size
      else { return }
      layout.itemSize = NSSize(width: size, height: size)
      layout.invalidateLayout()
    }

    /// Edit > Select All: extend the native selection, then push ids back out.
    func selectAll() {
      guard let collectionView, !flatIds.isEmpty else { return }
      collectionView.selectionIndexPaths = Set(
        flatIds.indices.map { IndexPath(item: $0, section: 0) })
      pushSelection()
    }

    var selectAllObserver: NSObjectProtocol?

    func syncSelection(selectedIds: Set<String>) {
      guard let collectionView else { return }
      let wanted = Set(flatIds.indices.filter { selectedIds.contains(flatIds[$0]) }.map {
        IndexPath(item: $0, section: 0)
      })
      let current = collectionView.selectionIndexPaths
      guard wanted != current else { return }
      suppressSelectionCallback = true
      defer { suppressSelectionCallback = false }
      collectionView.selectionIndexPaths = wanted
    }

    // MARK: NSCollectionViewDataSource

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
      flatIds.count
    }

    func collectionView(
      _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
      let item = collectionView.makeItem(withIdentifier: MacGridCell.identifier, for: indexPath)
      guard let cell = item as? MacGridCell else { return item }
      let id = flatIds[indexPath.item]
      cell.representedObject = id
      cell.view.setAccessibilityIdentifier("grid-cell-\(id)")
      cell.view.setAccessibilityLabel("Photo \(id)")
    cell.setFavorite(parent.assetsById[id]?.isFavorite ?? false)
    cell.onFavorite = { [weak self] in self?.parent.onToggleFavorite(id) }
      if let asset = parent.assetsById[id] {
        cell.photoView.image = nil
        cell.loadTask?.cancel()
        let pipeline = parent.pipeline
        let box = WeakCellBox(cell)
        cell.loadTask = Task {
          do {
            for try await step in await pipeline.stream(asset: asset, tier: .thumbnail) {
              let image: NSImage?
              switch step.content {
              case .placeholder(let placeholder): image = placeholder
              case .tier(_, let loaded, _): image = loaded
              }
              await MainActor.run {
                box.setImage(image, ifRepresentedObjectIs: id)
              }
              if Task.isCancelled { return }
            }
          } catch {
            // Per-cell load failures (cancellation from fast scrolling, a single corrupt
            // asset) are expected and cosmetic — the cell just keeps its blurhash placeholder.
            // Systemic failures (wrong server URL, auth, network) surface via `lastSyncError`.
          }
        }
      }
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
      guard let id = flatIds[safe: indexPath.item] else { return }
      parent.onOpen(id)
    }

    @objc func handleMagnify(_ recognizer: NSMagnificationGestureRecognizer) {
      guard recognizer.state == .changed else { return }
      parent.onMagnify(recognizer.magnification)
      recognizer.magnification = 0
    }

    func collectionView(
      _ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>
    ) {
      pushSelection()
    }

    private func pushSelection() {
      guard !suppressSelectionCallback, let collectionView else { return }
      let ids = collectionView.selectionIndexPaths.compactMap { flatIds[safe: $0.item] }
      parent.onSelectionChange(ids)
    }

    func collectionView(
      _ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
      sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
      guard !parent.usesSquareThumbnails,
        let id = flatIds[safe: indexPath.item],
        let asset = parent.assetsById[id],
        let width = asset.width, width > 0,
        let height = asset.height, height > 0
      else {
        return NSSize(width: parent.itemSize, height: parent.itemSize)
      }
      // The cell and thumbnail now have the same aspect ratio, so AppKit never stretches a
      // portrait into a square. Clamp very tall screenshots and panoramas to keep timeline
      // scanning practical at every +/- and pinch grid size.
      let ratio = CGFloat(height) / CGFloat(width)
      let boundedHeight = min(parent.itemSize * 1.6, max(parent.itemSize * 0.62, parent.itemSize * ratio))
      return NSSize(width: parent.itemSize, height: boundedHeight)
    }

    // MARK: drag out (brief task 5: export originals to Finder via file promises)

    func collectionView(
      _ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
      guard let id = flatIds[safe: indexPath.item] else { return nil }
      let item = NSPasteboardItem()
      item.setString(id, forType: .init("com.immich.heirloom.asset-id"))
      // Plain-text mirror so the SwiftUI sidebar drop targets (and Finder-adjacent
      // handlers) can read the dragged ids through NSItemProvider.
      item.setString(id, forType: .string)
      return item
    }

    /// Prefetch originals when a drag begins so the promised-files write at drop time is local.
    func collectionView(
      _ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
      willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>
    ) {
      guard let exporter = parent.exporter else { return }
      let box = dragState
      box.reset()
      for indexPath in indexPaths {
        guard let id = flatIds[safe: indexPath.item],
          let asset = parent.assetsById[id]
        else { continue }
        box.prefetch(asset: asset, with: exporter)
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
        guard let id = flatIds[safe: indexPath.item],
          let asset = parent.assetsById[id]
        else { continue }
        names.append(asset.originalFileName)
        let destination = dropURL.appendingPathComponent(asset.originalFileName)
        if let temp = dragState.stagedFile(for: id) {
          try? FileManager.default.copyItem(at: temp, to: destination)
        } else if let exporter = parent.exporter {
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

    // MARK: keyboard (brief task 2)

    // Navigation keys only (return/space/type-to-jump; arrows are native). Asset actions
    // (favorite/rotate/delete/move/info) live in the menus and route through the focused
    // value, so there is exactly one shortcut owner and no double-fire with the viewer.
    func handleKey(_ event: NSEvent) -> Bool {
      let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
      let currentId: String? = {
        guard let collectionView else { return nil }
        let sorted = collectionView.selectionIndexPaths.sorted { $0.item < $1.item }
        return sorted.last.flatMap { flatIds[safe: $0.item] }
      }()

      switch event.keyCode {
      case 36:  // return = open
        if let currentId { parent.onOpen(currentId); return true }
        return false
      case 49:  // space = Quick Look-style preview
        if flags.isEmpty, let currentId { parent.onPreview(currentId); return true }
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
      let dates = parent.rowDates
      guard dates.count == flatIds.count,
        let index = dates.firstIndex(where: { !$0.isEmpty && $0.hasPrefix(prefix) })
      else { return }
      let indexPath = IndexPath(item: index, section: 0)
      collectionView.selectionIndexPaths = [indexPath]
      collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
      pushSelection()
    }
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

/// Main-thread-confined cell reference carried across the image-load suspension.
private final class WeakCellBox: @unchecked Sendable {
  weak var cell: MacGridCell?
  init(_ cell: MacGridCell) { self.cell = cell }

  @MainActor
  func setImage(_ image: NSImage?, ifRepresentedObjectIs id: String) {
    guard let cell, cell.representedObject as? String == id else { return }
    cell.photoView.image = image
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
