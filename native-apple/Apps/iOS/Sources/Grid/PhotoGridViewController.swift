import CoreModel
import LocalStore
import Media
import UIKit

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
    // S1 test hook: the UI test polls this value — "refreshing" while `onRefresh` runs.
    // (The UIRefreshControl itself never appears in the XCUI tree, even as an AX element.)
    collectionView.accessibilityValue = "idle"
    let refresh = UIRefreshControl()
    // UIRefreshControl isn't exposed to the accessibility tree by default; the UI test needs it.
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
