import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI
import UIKit

// MARK: - zoom levels (brief task 1)

/// Apple-style grid zoom: Years → Months → Days → All Photos. Each level maps to a bucket
/// granularity (backed by `PhotosLocalStore.timelineBuckets`) and a default column count; pinch
/// moves between column counts within and across levels.
enum LibraryZoomLevel: String, CaseIterable, Identifiable {
  case years, months, days, all

  var id: String { rawValue }
  var title: String {
    switch self {
    case .years: return "Years"
    case .months: return "Months"
    case .days: return "Days"
    case .all: return "All Photos"
    }
  }

  var granularity: PhotosLocalStore.Granularity {
    switch self {
    case .years, .months: return .month
    case .days, .all: return .day
    }
  }

  var defaultColumns: Int {
    switch self {
    case .years: return 2
    case .months: return 3
    case .days: return 5
    case .all: return 7
    }
  }
}

/// The timeline source picked in the library switcher (brief task 2, DECISIONS §9 explicit filter).
/// `all` is the preference-driven timeline (Both/all sources); the rest are access-checked explicit
/// filters resolved through `Rules.TimelineScope`.
enum LibrarySource: Hashable {
  case all
  case personal
  case space(String)
  case library(String)

  var filter: ExplicitContainerFilter? {
    switch self {
    case .all: return nil
    case .personal: return .personalOnly
    case .space(let id): return .space(id)
    case .library(let id): return .library(id)
    }
  }
}

// MARK: - grid model

/// Everything the UIKit grid needs for one render pass: bucket headers, row ids per bucket, and
/// the hydrated assets behind the visible rows (badges need duration/container/favorite).
struct LibraryGridModel {
  var buckets: [TimelineBucket] = []
  var rowIdsByBucket: [String: [String]] = [:]
  var rowsById: [String: TimelineRow] = [:]
  var assetsById: [String: Asset] = [:]

  var allRowIds: [String] { buckets.flatMap { rowIdsByBucket[$0.key] ?? [] } }
}

@MainActor
final class LibraryGridLoader: ObservableObject {
  @Published var model = LibraryGridModel()
  @Published var isLoading = false

  /// Loads one granularity pass for `scope`: bucket headers, then the first page of every bucket,
  /// then the assets behind those rows for badges. Pagination within a bucket stays a scroll-driven
  /// follow-up (`loadMore`) so first paint never waits on the whole library.
  func load(scope: ContainerScope, granularity: PhotosLocalStore.Granularity, store: PhotosLocalStore) async {
    isLoading = true
    defer { isLoading = false }
    do {
      let buckets = try await store.timelineBuckets(scope: scope, granularity: granularity)
      var rowIdsByBucket: [String: [String]] = [:]
      var rowsById: [String: TimelineRow] = [:]
      for bucket in buckets {
        let rows = try await store.timelineAssets(scope: scope, bucketKey: bucket.key, granularity: granularity)
        rowIdsByBucket[bucket.key] = rows.map(\.id)
        for row in rows { rowsById[row.id] = row }
      }
      let assets = try await store.assets(ids: Array(rowsById.keys))
      model = LibraryGridModel(
        buckets: buckets, rowIdsByBucket: rowIdsByBucket, rowsById: rowsById,
        assetsById: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }))
    } catch {
      model = LibraryGridModel()
    }
  }
}

// MARK: - UIKit grid (brief task 1: UICollectionView, compositional layout, 120 Hz scrolling)

final class PhotoGridCell: UICollectionViewCell {
  static let reuseId = "PhotoGridCell"
  let imageView = UIImageView()
  let badgeLabel = UILabel()
  let favoriteBadge = UILabel()
  let containerBadge = UILabel()
  var loadTask: Task<Void, Never>?

  override init(frame: CGRect) {
    super.init(frame: frame)
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(imageView)
    NSLayoutConstraint.activate([
      imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
      imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
    ])
    for (label, size): (UILabel, CGFloat) in [(badgeLabel, 10), (favoriteBadge, 12), (containerBadge, 10)] {
      label.font = .systemFont(ofSize: size, weight: .semibold)
      label.textColor = .white
      label.shadowColor = .black
      label.shadowOffset = CGSize(width: 0, height: 1)
      label.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(label)
    }
    NSLayoutConstraint.activate([
      badgeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
      badgeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
      favoriteBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
      favoriteBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
      containerBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
      containerBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
    ])
    // Selected state for multi-select (brief task 5).
    selectedBackgroundView = UIView()
    selectedBackgroundView?.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.35)
    selectedBackgroundView?.layer.borderColor = UIColor.systemBlue.cgColor
    selectedBackgroundView?.layer.borderWidth = 3
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func prepareForReuse() {
    super.prepareForReuse()
    loadTask?.cancel()
    loadTask = nil
    imageView.image = nil
  }
}

final class BucketHeaderView: UICollectionReusableView {
  static let reuseId = "BucketHeaderView"
  let titleLabel = UILabel()
  var onSelectAll: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    titleLabel.font = .boldSystemFont(ofSize: 17)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(titleLabel)
    let button = UIButton(type: .system)
    button.setTitle("Select", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(selectTapped), for: .touchUpInside)
    button.tag = 1
    addSubview(button)
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      button.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  var showsSelectButton = false {
    didSet { viewWithTag(1)?.isHidden = !showsSelectButton }
  }

  @objc private func selectTapped() { onSelectAll?() }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class PhotoGridViewController: UIViewController {
  typealias DataSource = UICollectionViewDiffableDataSource<String, String>

  var collectionView: UICollectionView!
  var dataSource: DataSource!
  var model = LibraryGridModel()
  var columns = 3
  var squareCells = false
  var editMode = false
  var pipeline: MediaPipeline?
  var onTap: ((String) -> Void)?
  var onSelectionChange: ((Set<String>) -> Void)?
  var onPrefetch: (([String]) -> Void)?
  var onPinchColumns: ((Int) -> Void)?
  /// S1: pull-to-refresh handler (wired to `refreshAll` by the Library screen). Runs in a `Task`;
  /// the control always ends refreshing afterwards, even in fixture mode where sync is nil.
  var onRefresh: (() async -> Void)?

  private var selectedIds = Set<String>()
  private var appliedSignature = ""
  private var lastScrubSection = -1

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
    // S1: a working pull-to-refresh — `alwaysBounceVertical` keeps the gesture available on an
    // empty grid, where SwiftUI's `.refreshable` (List/ScrollView only) never fires.
    collectionView.alwaysBounceVertical = true
    let refresh = UIRefreshControl()
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
      guard let self,
        let header = cv.dequeueReusableSupplementaryView(
          ofKind: kind, withReuseIdentifier: BucketHeaderView.reuseId, for: indexPath) as? BucketHeaderView
      else { return nil }
      let key = self.model.buckets[indexPath.section].key
      header.titleLabel.text = Self.bucketTitle(key)
      header.showsSelectButton = self.editMode
      header.onSelectAll = { [weak self] in self?.selectAll(in: indexPath.section) }
      return header
    }

    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(didPinch(_:)))
    collectionView.addGestureRecognizer(pinch)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(didPanSelect(_:)))
    pan.delegate = self
    collectionView.addGestureRecognizer(pan)
  }

  static func bucketTitle(_ key: String) -> String {
    let inFmt = DateFormatter()
    let outFmt = DateFormatter()
    if key.count == 7 {
      inFmt.dateFormat = "yyyy-MM"
      outFmt.dateFormat = "MMMM yyyy"
    } else {
      inFmt.dateFormat = "yyyy-MM-dd"
      outFmt.dateFormat = "d MMMM yyyy"
    }
    if let date = inFmt.date(from: key) { return outFmt.string(from: date) }
    return key
  }

  func render() {
    collectionView.allowsMultipleSelection = editMode
    collectionView.setCollectionViewLayout(makeLayout(), animated: false)
    let signature = "\(model.buckets.map(\.key).joined())|\(columns)|\(squareCells)|\(editMode)"
    guard signature != appliedSignature else { return }
    appliedSignature = signature
    var snapshot = NSDiffableDataSourceSnapshot<String, String>()
    for bucket in model.buckets {
      snapshot.appendSections([bucket.key])
      snapshot.appendItems(model.rowIdsByBucket[bucket.key] ?? [], toSection: bucket.key)
    }
    dataSource.apply(snapshot, animatingDifferences: false)
    // Restore selection after snapshot changes.
    for id in selectedIds {
      if let indexPath = dataSource.indexPath(for: id) {
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
      }
    }
  }

  func setSelected(_ ids: Set<String>) {
    selectedIds = ids
    for section in 0..<model.buckets.count {
      let count = model.rowIdsByBucket[model.buckets[section].key]?.count ?? 0
      for item in 0..<count {
        let indexPath = IndexPath(item: item, section: section)
        let id = model.rowIdsByBucket[model.buckets[section].key]?[item]
        let shouldSelect = id.map { ids.contains($0) } ?? false
        if shouldSelect && collectionView.indexPathsForSelectedItems?.contains(indexPath) != true {
          collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        } else if !shouldSelect
          && collectionView.indexPathsForSelectedItems?.contains(indexPath) == true
        {
          collectionView.deselectItem(at: indexPath, animated: false)
        }
      }
    }
  }

  func scrollToScrubSection(_ section: Int) {
    guard section != lastScrubSection else { return }
    lastScrubSection = section
    guard section < model.buckets.count, !model.buckets.isEmpty else { return }
    collectionView.scrollToItem(
      at: IndexPath(item: 0, section: section), at: .top, animated: true)
  }

  private func makeLayout() -> UICollectionViewLayout {
    let count = CGFloat(max(1, columns))
    let itemSize: NSCollectionLayoutSize
    if squareCells {
      itemSize = NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0 / count),
        heightDimension: .fractionalWidth(1.0 / count))
    } else {
      itemSize = NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0 / count),
        heightDimension: .estimated(120))
    }
    let item = NSCollectionLayoutItem(layoutSize: itemSize)
    item.contentInsets = NSDirectionalEdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
    let groupSize = NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1.0),
      heightDimension: squareCells ? .fractionalWidth(1.0 / count) : .estimated(120))
    let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
    let section = NSCollectionLayoutSection(group: group)
    let headerSize = NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(36))
    section.boundarySupplementaryItems = [
      NSCollectionLayoutBoundarySupplementaryItem(
        layoutSize: headerSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
    ]
    return UICollectionViewCompositionalLayout(section: section)
  }

  private func configure(_ cell: PhotoGridCell, id: String) {
    let row = model.rowsById[id]
    let asset = model.assetsById[id]
    // Badges (brief task 1): video duration, live, favorite, container icon.
    if let asset, asset.type == .video, let duration = asset.durationSeconds {
      cell.badgeLabel.text = Self.formatDuration(duration)
    } else if row?.mediaKind == .livePhoto {
      cell.badgeLabel.text = "LIVE"
    } else {
      cell.badgeLabel.text = nil
    }
    cell.favoriteBadge.text = (row?.isFavorite == true) ? "♥" : nil
    if let asset {
      switch asset.container {
      case .personal: cell.containerBadge.text = nil
      case .space: cell.containerBadge.text = "⌂"
      case .library: cell.containerBadge.text = "▤"
      }
    } else {
      cell.containerBadge.text = nil
    }
    // Thumbhash placeholder renders instantly; the A2 pipeline upgrades thumbnail → preview.
    if let thumbhash = asset?.thumbhash,
      let decoded = try? ThumbHash.decode(base64: thumbhash),
      let placeholder = decoded.makePlatformImage()
    {
      cell.imageView.image = placeholder
    }
    guard let asset, let pipeline else { return }
    cell.loadTask = Task { [weak cell] in
      do {
        let loaded = try await pipeline.load(asset: asset, tier: .thumbnail)
        guard !Task.isCancelled else { return }
        let image: UIImage? = switch loaded.content {
        case .placeholder(let img): img
        case .tier(_, let img, _): img
        }
        cell?.imageView.image = image
      } catch {
        // Offline with nothing cached (or a fixture asset with no bytes): the placeholder stays.
      }
    }
  }

  static func formatDuration(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func selectAll(in section: Int) {
    guard section < model.buckets.count else { return }
    for id in model.rowIdsByBucket[model.buckets[section].key] ?? [] {
      selectedIds.insert(id)
      if let indexPath = dataSource.indexPath(for: id) {
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
      }
    }
    onSelectionChange?(selectedIds)
  }

  @objc private func didPullToRefresh(_ sender: UIRefreshControl) {
    sender.accessibilityValue = "refreshing"
    Task { @MainActor in
      await onRefresh?()
      sender.accessibilityValue = "idle"
      sender.endRefreshing()
    }
  }

  @objc private func didPinch(_ gesture: UIPinchGestureRecognizer) {
    guard gesture.state == .ended else { return }
    let steps = [2, 3, 5, 7, 10]
    let current = columns
    if gesture.scale > 1.3, let next = steps.last(where: { $0 < current }) {
      onPinchColumns?(next)
    } else if gesture.scale < 0.77, let next = steps.first(where: { $0 > current }) {
      onPinchColumns?(next)
    }
  }

  /// Drag-to-select (brief task 5): in edit mode a pan across cells adds them to the selection.
  @objc private func didPanSelect(_ gesture: UIPanGestureRecognizer) {
    guard editMode else { return }
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
    if editMode {
      selectedIds.insert(id)
      onSelectionChange?(selectedIds)
    } else {
      collectionView.deselectItem(at: indexPath, animated: false)
      onTap?(id)
    }
  }

  func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
    guard editMode, let id = dataSource.itemIdentifier(for: indexPath) else { return }
    selectedIds.remove(id)
    onSelectionChange?(selectedIds)
  }
}

extension PhotoGridViewController: UICollectionViewDataSourcePrefetching {
  func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
    // A2 prefetcher at the lowest priority keeps 120 Hz scrolling smooth.
    let ids = indexPaths.compactMap { dataSource.itemIdentifier(for: $0) }
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

// MARK: - SwiftUI host

struct PhotoGridView: UIViewControllerRepresentable {
  var model: LibraryGridModel
  var columns: Int
  var squareCells: Bool
  var editMode: Bool
  var selectedIds: Set<String>
  var pipeline: MediaPipeline?
  var onTap: (String) -> Void
  var onSelectionChange: (Set<String>) -> Void
  var onPrefetch: ([String]) -> Void
  var onPinchColumns: (Int) -> Void
  /// S1: pull-to-refresh handler. Defaulted to nil so non-Library grids (e.g. Search results)
  /// keep compiling unchanged and get no refresh control behavior.
  var onRefresh: (() async -> Void)? = nil
  /// Date-scrubber section index; the VC scrolls only when this value changes.
  var scrubSection: Int

  func makeUIViewController(context: Context) -> PhotoGridViewController {
    let vc = PhotoGridViewController()
    vc.onTap = { onTap($0) }
    vc.onSelectionChange = { onSelectionChange($0) }
    vc.onPrefetch = { onPrefetch($0) }
    vc.onPinchColumns = { onPinchColumns($0) }
    vc.onRefresh = onRefresh
    return vc
  }

  func updateUIViewController(_ vc: PhotoGridViewController, context: Context) {
    vc.model = model
    vc.columns = columns
    vc.squareCells = squareCells
    vc.editMode = editMode
    vc.pipeline = pipeline
    vc.onRefresh = onRefresh
    vc.render()
    vc.setSelected(selectedIds)
    vc.scrollToScrubSection(scrubSection)
  }
}

// MARK: - library screen (grid + switcher + zoom + scrubber + selection)

struct LibraryView: View {
  @EnvironmentObject var session: AppSession
  @StateObject private var loader = LibraryGridLoader()
  @State private var source: LibrarySource = .all
  @State private var zoom: LibraryZoomLevel = .months
  @State private var columns: Int = 3
  @State private var squareCells = false
  @State private var editMode = false
  @State private var selectedIds = Set<String>()
  @State private var scrubIndex = 0
  @State private var viewerRequest: ViewerRequest?
  @State private var showMoveSheet = false
  @State private var showSourcesSheet = false
  @State private var actionError: String?

  var body: some View {
    NavigationStack {
      ZStack(alignment: .trailing) {
        PhotoGridView(
          model: loader.model, columns: columns, squareCells: squareCells, editMode: editMode,
          selectedIds: selectedIds, pipeline: session.pipeline,
          onTap: { id in
            viewerRequest = ViewerRequest(ids: loader.model.allRowIds, initialId: id)
          },
          onSelectionChange: { selectedIds = $0 },
          onPrefetch: { ids in
            Task { await session.pipeline?.prefetch(ids: ids, tier: .thumbnail) }
          },
          onPinchColumns: { columns = $0 },
          onRefresh: { await refreshAll() },
          scrubSection: scrubIndex
        )
        .accessibilityIdentifier("library-grid")
        .ignoresSafeArea(edges: .bottom)
        // Date scrubber (brief task 1).
        if loader.model.buckets.count > 1 {
          Slider(value: Binding(
            get: { Double(scrubIndex) },
            set: { scrubIndex = Int($0) }
          ), in: 0...Double(max(0, loader.model.buckets.count - 1)), step: 1)
          .rotationEffect(.degrees(-90))
          .frame(width: 160)
          .offset(x: 56)
          .accessibilityIdentifier("date-scrubber")
        }
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          // Library switcher (brief task 2, Apple-style menu).
          Menu {
            Button("Both Libraries") { pickSource(.all) }
            Button("Personal Library") { pickSource(.personal) }
            ForEach(session.spaces) { space in
              Button(space.name) { pickSource(.space(space.id)) }
            }
            ForEach(session.libraries) { library in
              Button(library.name) { pickSource(.library(library.id)) }
            }
            Divider()
            Button("Show in Timeline…") { showSourcesSheet = true }
          } label: {
            Label(sourceTitle, systemImage: "photo.stack")
          }
          .accessibilityIdentifier("library-switcher")
        }
        ToolbarItem(placement: .principal) {
          VStack(spacing: 0) {
            Text("Library").font(.headline)
            Text(libraryDateRange).font(.caption2).foregroundStyle(.secondary)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: 10) {
            Button { columns = max(2, columns - 1) } label: { Image(systemName: "minus") }
            Button { columns = min(10, columns + 1) } label: { Image(systemName: "plus") }
            Button(editMode ? "Done" : "Select") {
              editMode.toggle()
              if !editMode { selectedIds = [] }
            }
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 4) {
          if editMode {
            SelectionActionBar(
              selectedIds: selectedIds,
              onClear: { selectedIds = [] },
              onMove: { showMoveSheet = true },
              onError: { actionError = $0 }
            )
          }
          Picker("Zoom", selection: $zoom) {
            ForEach(LibraryZoomLevel.allCases) { level in
              Text(level.title).tag(level)
            }
          }
          .pickerStyle(.segmented)
          .padding(.horizontal)
          Toggle("Square", isOn: $squareCells)
            .font(.caption)
            .padding(.horizontal)
        }
        .background(.thinMaterial)
      }
      // S1: re-keyed on `timelineVersion` so rows appear once a sync lands, without waiting
      // for a source/zoom change.
      .task(id: "\(sourceKey)-\(session.timelineVersion)") { await reload() }
      .onChange(of: zoom) { _, new in
        columns = new.defaultColumns
        Task { await reload() }
      }
      .fullScreenCover(item: $viewerRequest) { request in
        ViewerView(ids: request.ids, initialId: request.initialId)
      }
      .sheet(isPresented: $showMoveSheet) {
        MoveSheet(selectedIds: Array(selectedIds)) {
          selectedIds = []
          editMode = false
          Task { await refreshAll() }
        }
        .environmentObject(session)
      }
      .sheet(isPresented: $showSourcesSheet) {
        TimelineSourcesSheet()
          .environmentObject(session)
      }
      .alert("Action failed", isPresented: Binding(
        get: { actionError != nil }, set: { if !$0 { actionError = nil } })
      ) {
        Button("OK") { actionError = nil }
      } message: {
        Text(actionError ?? "")
      }
    }
  }

  private var sourceKey: String {
    switch source {
    case .all: return "all"
    case .personal: return "personal"
    case .space(let id): return "space-\(id)"
    case .library(let id): return "library-\(id)"
    }
  }

  private var sourceTitle: String {
    switch source {
    case .all: return "Library"
    case .personal: return "Personal"
    case .space(let id): return session.spaces.first { $0.id == id }?.name ?? "Shared Library"
    case .library(let id): return session.libraries.first { $0.id == id }?.name ?? "Library"
    }
  }

  private var libraryDateRange: String {
    let dates = loader.model.rowsById.values.compactMap(\.localDateTime).sorted()
    guard let first = dates.first, let last = dates.last else { return "No Photos" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
  }

  private func pickSource(_ new: LibrarySource) {
    source = new
    selectedIds = []
    editMode = false
    scrubIndex = 0
  }

  private func reload() async {
    guard let store = session.store else { return }
    do {
      let scope = try await session.timelineScope(explicit: source.filter)
      await loader.load(scope: scope, granularity: zoom.granularity, store: store)
    } catch {
      session.lastError = error.localizedDescription
    }
  }

  func refreshAll() async {
    await session.syncNow()
    await reload()
  }
}

/// Viewer launch request (full-screen cover item).
struct ViewerRequest: Identifiable {
  var ids: [String]
  var initialId: String?
  var id: String { initialId ?? ids.joined(separator: ",") }
}
