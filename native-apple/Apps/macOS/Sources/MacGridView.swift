import AppKit
import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI

/// One grid section: an optional bucket header plus its rows.
struct MacGridSection: Sendable, Hashable {
  var header: String?
  var rows: [TimelineRow]
}

/// Loads grid content from the local store (A0 Architecture: the DB is the UI's only data source).
@MainActor
@Observable
final class MacGridLoader {
  var sections: [MacGridSection] = []
  var assetsById: [String: Asset] = [:]
  var isLoading = false
  var error: String?

  var allRowIds: [String] { sections.flatMap { $0.rows.map(\.id) } }

  func load(
    store: PhotosLocalStore, userId: String, destination: SidebarDestination,
    grouping: TimelineGrouping, switcher: LibraryFilterOption
  ) async {
    isLoading = true
    error = nil
    defer { isLoading = false }
    do {
      sections = try await Self.fetch(
        store: store, userId: userId, destination: destination,
        grouping: grouping, switcher: switcher
      )
      assetsById = try await Self.assetsById(store: store, ids: allRowIds)
    } catch {
      self.error = error.localizedDescription
      sections = []
    }
  }

  // MARK: - fetch

  private static func scope(
    store: PhotosLocalStore, userId: String, purpose: TimelinePurpose,
    filter: ExplicitContainerFilter?
  ) async throws -> ContainerScope {
    let ctx = try await store.timelineContext(for: userId, explicitFilter: filter)
    return TimelineScope.resolve(purpose: purpose, context: ctx)
  }

  static func fetch(
    store: PhotosLocalStore, userId: String, destination: SidebarDestination,
    grouping: TimelineGrouping, switcher: LibraryFilterOption
  ) async throws -> [MacGridSection] {
    let override = switcher.explicitFilter
    switch destination.query {
    case .timeline(let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      return try await bucketed(store: store, scope: s, grouping: grouping)
    case .favorites(let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      let rows = try await store.favoriteAssets(scope: s, limit: 1000)
      return [MacGridSection(header: nil, rows: rows)]
    case .recents, .imports:
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override)
      let rows = try await store.recentAssets(scope: s, limit: 1000)
      return [MacGridSection(header: nil, rows: rows)]
    case .media(let kind, let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      let rows = try await store.assets(scope: s, mediaKind: kind, limit: 1000)
      return [MacGridSection(header: nil, rows: rows)]
    case .album(let id):
      let ids = try await store.assetIds(inAlbum: id)
      let assets = try await store.assets(ids: ids)
      let byId = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
      let sorted = assets.sorted { (byId[$0.id] ?? 0) < (byId[$1.id] ?? 0) }
      return [MacGridSection(header: nil, rows: sorted.map(TimelineRow.init(asset:)))]
    case .trash:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [MacGridSection(header: nil, rows: try await store.trashedAssets(scope: s, limit: 1000))]
    case .hidden:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [MacGridSection(header: nil, rows: try await store.hiddenAssets(scope: s).map(TimelineRow.init(asset:)))]
    case .archive:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [MacGridSection(header: nil, rows: try await store.archivedAssets(scope: s).map(TimelineRow.init(asset:)))]
    case .locked:
      return [MacGridSection(header: nil, rows: try await store.lockedAssets(currentUserId: userId, limit: 1000))]
    case .map, .people, .memories, .search:
      return []
    }
  }

  private static func bucketed(
    store: PhotosLocalStore, scope: ContainerScope, grouping: TimelineGrouping
  ) async throws -> [MacGridSection] {
    let buckets = try await store.timelineBuckets(scope: scope, granularity: .month)
    if grouping == .all {
      // All Photos: flatten buckets newest-first, capped for memory.
      var rows: [TimelineRow] = []
      for bucket in buckets.prefix(12) {
        rows += try await store.timelineAssets(scope: scope, bucketKey: bucket.key, granularity: .month, limit: 200)
        if rows.count >= 1000 { break }
      }
      return [MacGridSection(header: nil, rows: rows)]
    }
    var sections: [MacGridSection] = []
    var lastYear: String?
    for bucket in buckets.prefix(36) {
      let rows = try await store.timelineAssets(scope: scope, bucketKey: bucket.key, granularity: .month, limit: 200)
      guard !rows.isEmpty else { continue }
      if grouping.groupsByYear {
        let year = String(bucket.key.prefix(4))
        if year != lastYear {
          sections.append(MacGridSection(header: year, rows: []))
          lastYear = year
        }
      }
      sections.append(MacGridSection(header: Self.bucketTitle(bucket.key), rows: rows))
    }
    return sections
  }

  private static func bucketTitle(_ key: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    if let date = formatter.date(from: key) {
      formatter.dateFormat = "MMMM yyyy"
      return formatter.string(from: date)
    }
    return key
  }

  private static func assetsById(store: PhotosLocalStore, ids: [String]) async throws -> [String: Asset] {
    var result: [String: Asset] = [:]
    for chunk in ids.chunked(into: 400) {
      for asset in try await store.assets(ids: chunk) { result[asset.id] = asset }
    }
    return result
  }
}

extension TimelineRow {
  /// Client-side mirror of the store's row projection (LocalStore+Timeline `rowSelectSQL`), for
  /// album/utility queries that return full `Asset`s instead of `TimelineRow`s.
  init(asset: Asset) {
    let ratio: Double
    if let w = asset.width, let h = asset.height, h > 0 { ratio = Double(w) / Double(h) } else { ratio = 1 }
    let kind: TimelineMediaKind
    if asset.livePhotoVideoId != nil { kind = .livePhoto }
    else if asset.type == .video { kind = .video }
    else if asset.originalFileName.hasPrefix("Screenshot") || asset.originalFileName.hasPrefix("screenshot") {
      kind = .screenshot
    } else { kind = .photo }
    self.init(
      id: asset.id, thumbhash: asset.thumbhash, aspectRatio: ratio, mediaKind: kind,
      isFavorite: asset.isFavorite, isTrashed: asset.deletedAt != nil,
      isArchived: asset.visibility == .archive, localDateTime: asset.localDateTime
    )
  }
}

extension Array {
  func chunked(into size: Int) -> [[Element]] {
    guard size > 0 else { return [self] }
    return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
}

// MARK: - NSCollectionView grid

final class MacGridCell: NSCollectionViewItem {
  static let identifier = NSUserInterfaceItemIdentifier("MacGridCell")
  var loadTask: Task<Void, Never>?
  let spinner = NSProgressIndicator()

  override func loadView() {
    let imageView = NSImageView()
    imageView.imageScaling = .scaleAxesIndependently
    imageView.wantsLayer = true
    view = imageView
  }

  var photoView: NSImageView { view as! NSImageView }

  override func prepareForReuse() {
    super.prepareForReuse()
    loadTask?.cancel()
    loadTask = nil
    photoView.image = nil
  }
}

final class MacKeyCollectionView: NSCollectionView {
  var onKeyDown: (@MainActor (NSEvent) -> Bool)?
  var onSelectAllAction: (@MainActor () -> Void)?

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
}

struct MacCollectionGridView: NSViewRepresentable {
  var sections: [MacGridSection]
  var assetsById: [String: Asset]
  /// `yyyy-MM-dd` capture-date strings parallel to the flattened rows (`""` when unknown).
  var rowDates: [String]
  var pipeline: MediaPipeline
  var exporter: MacExporter?
  var itemSize: CGFloat
  @Binding var selectedIds: Set<String>
  var onSelectionChange: ([String]) -> Void
  var onOpen: (String) -> Void
  var onPreview: (String) -> Void

  func makeNSView(context: Context) -> NSScrollView {
    let layout = NSCollectionViewFlowLayout()
    layout.minimumInteritemSpacing = 2
    layout.minimumLineSpacing = 2
    layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
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
          } catch {}
        }
      }
      return cell
    }

    // MARK: delegate

    func collectionView(
      _ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
      pushSelection()
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
      NSSize(width: parent.itemSize, height: parent.itemSize)
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

