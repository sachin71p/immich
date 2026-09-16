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
  /// This is an in-process UI safety net, not normal pagination. It comfortably exceeds the
  /// largest library we support in the desktop timeline, so list views and their footer counts
  /// never silently describe only the first page.
  private static let completeViewLimit = 250_000
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
      let rows = try await store.favoriteAssets(scope: s, limit: completeViewLimit)
      return [MacGridSection(header: nil, rows: rows)]
    case .recents, .imports:
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override)
      let rows = try await store.recentAssets(scope: s, limit: completeViewLimit)
      return [MacGridSection(header: nil, rows: rows)]
    case .media(let kind, let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      let rows = try await store.assets(scope: s, mediaKind: kind, limit: completeViewLimit)
      return [MacGridSection(header: nil, rows: rows)]
    case .mediaCollection(let collection, let baseFilter):
      let s = try await scope(store: store, userId: userId, purpose: .timeline, filter: override ?? baseFilter)
      return [MacGridSection(header: nil, rows: try await store.mediaAssets(scope: s, collection: collection, limit: completeViewLimit))]
    case .album(let id):
      let ids = try await store.assetIds(inAlbum: id)
      let assets = try await store.assets(ids: ids)
      let byId = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
      let sorted = assets.sorted { (byId[$0.id] ?? 0) < (byId[$1.id] ?? 0) }
      return [MacGridSection(header: nil, rows: sorted.map(TimelineRow.init(asset:)))]
    case .trash:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [MacGridSection(header: nil, rows: try await store.trashedAssets(scope: s, limit: completeViewLimit))]
    case .hidden:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [MacGridSection(header: nil, rows: try await store.hiddenAssets(scope: s).map(TimelineRow.init(asset:)))]
    case .archive:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      return [MacGridSection(header: nil, rows: try await store.archivedAssets(scope: s).map(TimelineRow.init(asset:)))]
    case .locked:
      return [MacGridSection(header: nil, rows: try await store.lockedAssets(currentUserId: userId, limit: completeViewLimit))]
    case .capturedByMe:
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      let assets = try await store.capturedByUser(userId, scope: s, limit: completeViewLimit)
      return [MacGridSection(header: nil, rows: assets.map(TimelineRow.init(asset:)))]
    case .camera(let category):
      let s = try await scope(store: store, userId: userId, purpose: .manage, filter: nil)
      // Category destinations deliberately resolve their member EXIF models at query time. This
      // keeps "Phone" and "DSLR" complete as new models arrive in a subsequent sync.
      let models = try await store.cameraModels(scope: s)
        .filter { $0.category == category }
        .map(\.model)
      var assets: [Asset] = []
      for model in models {
        assets += try await store.assets(cameraModel: model, scope: s, limit: completeViewLimit)
      }
      assets.sort { ($0.localDateTime ?? .distantPast) > ($1.localDateTime ?? .distantPast) }
      return [MacGridSection(header: nil, rows: assets.map(TimelineRow.init(asset:)))]
    case .map, .people, .memories, .search:
      return []
    }
  }

  private static func bucketed(
    store: PhotosLocalStore, scope: ContainerScope, grouping: TimelineGrouping
  ) async throws -> [MacGridSection] {
    let buckets = try await store.timelineBuckets(scope: scope, granularity: .month)
    if grouping == .all {
      // All Photos is the complete local timeline, not merely the first screenful. Images are
      // still loaded lazily per visible cell; only lightweight row metadata is retained here.
      var rows: [TimelineRow] = []
      for bucket in buckets {
        rows += try await store.timelineAssets(
          scope: scope, bucketKey: bucket.key, granularity: .month, limit: bucket.count)
      }
      return [MacGridSection(header: nil, rows: rows)]
    }
    var sections: [MacGridSection] = []
    var lastYear: String?
    for bucket in buckets {
      let rows = try await store.timelineAssets(
        scope: scope, bucketKey: bucket.key, granularity: .month, limit: bucket.count)
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

extension Array {
  func chunked(into size: Int) -> [[Element]] {
    guard size > 0 else { return [self] }
    return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
}

// MARK: - NSCollectionView grid

private final class MacThumbnailContainerView: NSView {
  var onHover: ((Bool) -> Void)?
  /// Explicit hit-testing for the favorite button, rather than relying on AppKit routing the
  /// click to the button subview: NSCollectionViewItem's custom-built view sits inside
  /// NSCollectionView's own click/selection machinery, which in practice swallows clicks meant
  /// for a subview button — a long-documented AppKit gotcha, not something fixable by adjusting
  /// the button's own configuration. Checking the button's frame here and consuming the event
  /// ourselves sidesteps that entirely; every other point still falls through to `super` so
  /// plain, shift, and command clicks keep AppKit's native selection handling untouched.
  var favoriteButton: NSButton?
  var onFavoriteHit: (() -> Void)?
  private var trackingArea: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
      owner: self, userInfo: nil
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) { onHover?(true) }
  override func mouseExited(with event: NSEvent) { onHover?(false) }

  override func mouseDown(with event: NSEvent) {
    if let favoriteButton, favoriteButton.alphaValue > 0 {
      let point = convert(event.locationInWindow, from: nil)
      if favoriteButton.frame.contains(point) {
        onFavoriteHit?()
        return
      }
    }
    super.mouseDown(with: event)
  }
}

final class MacGridCell: NSCollectionViewItem {
  static let identifier = NSUserInterfaceItemIdentifier("MacGridCell")
  var loadTask: Task<Void, Never>?
  let spinner = NSProgressIndicator()
  var onFavorite: (() -> Void)?
  private let favoriteButton = NSButton()

  // NSCollectionViewItem's automatic selection highlight only applies to its default nib-based
  // imageView/textField outlets; this cell builds its view by hand in loadView(), so without this
  // override, AppKit was already tracking selection correctly (didSelectItemsAt fires, the
  // selection model updates) but nothing on screen ever showed it — indistinguishable, from the
  // user's side, from a click doing nothing at all.
  override var isSelected: Bool {
    didSet {
      guard oldValue != isSelected else { return }
      (view as? MacThumbnailContainerView)?.layer?.borderColor =
        isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
    }
  }

  override func loadView() {
    let container = MacThumbnailContainerView()
    container.wantsLayer = true
    container.layer?.cornerRadius = 8
    container.layer?.borderWidth = 4
    // CALayer.borderColor paints opaque black when never explicitly set — leaving this out
    // drew a thick black border around every cell, selected or not.
    container.layer?.borderColor = NSColor.clear.cgColor
    let imageView = NSImageView()
    // Preserve the photo's aspect ratio. The previous independent-axis scaling stretched people
    // and landscapes to the square cell; native Photos never distorts a thumbnail.
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = 8
    imageView.layer?.masksToBounds = true
    imageView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(imageView)
    favoriteButton.bezelStyle = .inline
    favoriteButton.isBordered = false
    favoriteButton.target = self
    favoriteButton.action = #selector(toggleFavorite)
    // Favorite is an affordance, not permanent thumbnail chrome. It becomes visible only
    // while this item is hovered, matching Photos and keeping dense grids visually calm.
    favoriteButton.alphaValue = 0
    favoriteButton.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(favoriteButton)
    NSLayoutConstraint.activate([
      imageView.topAnchor.constraint(equalTo: container.topAnchor), imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor), imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      favoriteButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
      favoriteButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
      // Explicit size, not left to intrinsic content size: an inline/borderless NSButton's
      // intrinsic size is unreliable, and a near-zero hit target would make the button
      // effectively unclickable even with a correctly visible heart icon.
      favoriteButton.widthAnchor.constraint(equalToConstant: 28),
      favoriteButton.heightAnchor.constraint(equalToConstant: 28),
    ])
    container.onHover = { [weak self] hovering in
      self?.favoriteButton.animator().alphaValue = hovering ? 1 : 0
    }
    container.favoriteButton = favoriteButton
    container.onFavoriteHit = { [weak self] in self?.toggleFavorite() }
    view = container
  }

  var photoView: NSImageView { view.subviews.first as! NSImageView }

  func setFavorite(_ isFavorite: Bool) {
    favoriteButton.image = NSImage(systemSymbolName: isFavorite ? "heart.fill" : "heart", accessibilityDescription: "Favorite")
    favoriteButton.contentTintColor = isFavorite ? .systemRed : .white
    favoriteButton.toolTip = isFavorite ? "Remove from Favorites" : "Add to Favorites"
  }

  @objc private func toggleFavorite() { onFavorite?() }

  override func prepareForReuse() {
    super.prepareForReuse()
    loadTask?.cancel()
    loadTask = nil
    photoView.image = nil
    favoriteButton.alphaValue = 0
    (view as? MacThumbnailContainerView)?.layer?.borderColor = nil
  }
}

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
