import CoreModel
import LocalStore
import Media
import UIKit

// MARK: - grid cell (WP1 §6: manual layout, off-main thumbhash, SF Symbol badges)

/// Builds the minimal `Asset` a `TimelineRow` stands in for on the thumbnail path: the
/// media pipeline only reads id/thumbhash/file name, fixture art only id/size.
func gridStubAsset(id: String, row: TimelineRow?) -> Asset {
  let height = 1000
  let width = max(1, Int((row?.aspectRatio ?? 1) * Double(height)))
  return Asset(
    id: id, ownerId: row?.ownerId ?? "", originalFileName: row?.originalFileName ?? "",
    thumbhash: row?.thumbhash, checksum: "",
    localDateTime: row?.localDateTime, durationSeconds: row?.durationSeconds,
    type: row?.mediaKind == .video ? .video : .image,
    isFavorite: row?.isFavorite ?? false, width: width, height: height,
    isEdited: row?.isEdited ?? false)
}

/// One square grid cell. Manual `layoutSubviews`, no Auto Layout: image layers fill the
/// bounds, badges sit in the native corners (spec `device-native-02`, audit L13), and the
/// selection affordance renders above the image (audit L3).
///
/// Image stack, bottom to top: neutral `fillView` (`secondarySystemFill`, audit L15 —
/// never white/black with orphan badges), thumbhash `thumbView`, `photoView`, then a
/// light `dimView` for selection. `thumbView`/`photoView` crossfade implicitly: the
/// thumbhash appears first (cache hit sets it synchronously, miss decodes off-main),
/// the thumbnail replaces it when its load lands.
final class PhotoGridCell: UICollectionViewCell {
  static let reuseId = "PhotoGridCell"

  let fillView = UIView()
  let thumbView = UIImageView()
  let photoView = UIImageView()
  let dimView = UIView()
  let heartView = UIImageView()
  let durationLabel = UILabel()
  let sharedView = UIImageView()
  let selectBadge = UIImageView()

  /// The asset id this cell currently represents; async work checks it before touching UI.
  private(set) var representedId: String?
  private var workTask: Task<Void, Never>?
  private var isEditingMode = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    fillView.backgroundColor = .secondarySystemFill
    thumbView.contentMode = .scaleAspectFill
    thumbView.clipsToBounds = true
    photoView.contentMode = .scaleAspectFill
    photoView.clipsToBounds = true
    dimView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.35)
    dimView.isHidden = true
    heartView.tintColor = .white
    heartView.contentMode = .scaleAspectFit
    sharedView.tintColor = .white
    sharedView.contentMode = .scaleAspectFit
    selectBadge.tintColor = .white
    selectBadge.contentMode = .scaleAspectFit
    selectBadge.isHidden = true
    durationLabel.font = .systemFont(ofSize: 10, weight: .semibold)
    durationLabel.textColor = .white
    durationLabel.shadowColor = .black
    durationLabel.shadowOffset = CGSize(width: 0, height: 1)
    durationLabel.textAlignment = .right
    for view in [fillView, thumbView, photoView, dimView, heartView, durationLabel, sharedView, selectBadge] {
      view.autoresizingMask = []
      contentView.addSubview(view)
    }
    // Drop shadows read on bright photos; the views themselves carry no shadow layers.
    heartView.layer.shadowColor = UIColor.black.cgColor
    heartView.layer.shadowOffset = CGSize(width: 0, height: 1)
    heartView.layer.shadowOpacity = 0.8
    sharedView.layer.shadowColor = UIColor.black.cgColor
    sharedView.layer.shadowOffset = CGSize(width: 0, height: 1)
    sharedView.layer.shadowOpacity = 0.8
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    let bounds = contentView.bounds
    fillView.frame = bounds
    thumbView.frame = bounds
    photoView.frame = bounds
    dimView.frame = bounds
    heartView.frame = CGRect(x: 5, y: bounds.height - 19, width: 15, height: 14)
    durationLabel.frame = CGRect(x: bounds.width - 55, y: bounds.height - 20, width: 51, height: 15)
    sharedView.frame = CGRect(x: bounds.width - 21, y: 5, width: 16, height: 13)
    selectBadge.frame = CGRect(x: bounds.width - 27, y: bounds.height - 27, width: 22, height: 22)
    // Explicit shadow paths: layer shadows without a path force an offscreen render
    // pass per badge per frame while scrolling.
    heartView.layer.shadowPath = CGPath(rect: heartView.bounds, transform: nil)
    sharedView.layer.shadowPath = CGPath(rect: sharedView.bounds, transform: nil)
  }

  override var isSelected: Bool {
    didSet { updateSelectionVisuals() }
  }

  // Shared symbol images — rasterized once, never per cell configuration. A fling
  // materializes dozens of cells in one runloop turn; per-cell `UIImage(systemName:)`
  // creation summed to ~105 ms main-thread bursts.
  private static let heartConfig = UIImage.SymbolConfiguration(pointSize: 13)
  private static let sharedConfig = UIImage.SymbolConfiguration(pointSize: 12)
  private static let selectConfig = UIImage.SymbolConfiguration(pointSize: 20)
  private static let heartImage = UIImage(systemName: "heart.fill", withConfiguration: heartConfig)
  private static let sharedImage = UIImage(
    systemName: "person.2.fill", withConfiguration: sharedConfig)
  private static let circleImage = UIImage(
    systemName: "circle", withConfiguration: selectConfig)
  private static let checkImage = UIImage(
    systemName: "checkmark.circle.fill", withConfiguration: selectConfig)

  /// Edit-mode affordance: every cell shows an empty circle, selected cells a filled
  /// check plus a light dim (spec `device-native-09`).
  func applyMode(editing: Bool, selected: Bool) {
    isEditingMode = editing
    if editing {
      selectBadge.isHidden = false
      selectBadge.image = selected ? Self.checkImage : Self.circleImage
    } else {
      selectBadge.isHidden = true
    }
    if selected != isSelected {
      // Drive through the collection view's state so delegate callbacks stay truthful.
      isSelected = selected
    } else {
      updateSelectionVisuals()
    }
  }

  private func updateSelectionVisuals() {
    dimView.isHidden = !(isEditingMode && isSelected)
    if isEditingMode {
      selectBadge.isHidden = false
      selectBadge.image = isSelected ? Self.checkImage : Self.circleImage
    }
  }

  /// Native badges from the row + index flags: `heart.fill` bottom-left, duration
  /// bottom-right (`m:ss` / `h:mm:ss` via the shared formatter), `person.2.fill`
  /// top-right for shared containers. No per-call formatter allocation.
  func configureBadges(row: TimelineRow?, flags: PhotosLocalStore.TimelineIndexFlags) {
    if row?.isFavorite == true {
      heartView.isHidden = false
      heartView.image = Self.heartImage
    } else {
      heartView.isHidden = true
      heartView.image = nil
    }
    if row?.mediaKind == .video, let seconds = row?.durationSeconds {
      durationLabel.isHidden = false
      durationLabel.text = VideoDurationFormat.string(seconds: seconds)
    } else {
      durationLabel.isHidden = true
      durationLabel.text = nil
    }
    if flags.contains(.sharedContainer) {
      sharedView.isHidden = false
      sharedView.image = Self.sharedImage
    } else {
      sharedView.isHidden = true
      sharedView.image = nil
    }
  }

  /// Starts (or reuses) the thumbnail content for `id`. Cache hits apply synchronously;
  /// everything else runs in one cancellable task: thumbhash decode off-main first, then
  /// the pipeline thumbnail. Fixture assets render generated art without network.
  func setThumbnail(
    id: String, row: TimelineRow?, pipeline: MediaPipeline?, aspectFit: Bool,
    cache: ThumbhashCache = .shared
  ) {
    representedId = id
    workTask?.cancel()
    photoView.contentMode = aspectFit ? .scaleAspectFit : .scaleAspectFill
    thumbView.image = cache.image(for: id)
    photoView.image = nil
    let stub = gridStubAsset(id: id, row: row)
    guard let pipeline else {
      // No pipeline (previews): fixture art below needs it only for cache warming.
      if FixtureArtwork.isFixtureAsset(id) {
        workTask = Task { [weak self] in
          let art = await Task.detached(priority: .userInitiated) {
            FixtureArtwork.image(for: stub)
          }.value
          guard let self, self.representedId == id, !Task.isCancelled else { return }
          self.photoView.image = art
        }
      }
      return
    }
    // `MediaMemoryCache` is NSCache-backed and thread-safe: read it here on the
    // main thread so only the Sendable cache crosses the detached boundary below.
    let memory = pipeline.memory
    workTask = Task { [weak self] in
      // Fixture assets render generated art without network — off-main like every
      // other decode (synchronous renders here stalled first-swipe by ~110 ms).
      if FixtureArtwork.isFixtureAsset(id) {
        let art = await Task.detached(priority: .userInitiated) {
          FixtureArtwork.image(for: stub)
        }.value
        guard let self, self.representedId == id, !Task.isCancelled else { return }
        if let art, let cgImage = art.cgImage {
          // Warm every tier through the real pipeline path (covers + viewer read
          // these) off the main thread: a fling lands hundreds of completions per
          // second and the triple store showed up as steady-state scroll stalls.
          await Task.detached(priority: .utility) {
            memory.store(cgImage, id: id, tier: .thumbnail, edited: false)
            memory.store(cgImage, id: id, tier: .preview, edited: false)
            memory.store(cgImage, id: id, tier: .fullsize, edited: false)
          }.value
          guard self.representedId == id, !Task.isCancelled else { return }
          self.photoView.image = art
        }
        return
      }
      if self?.thumbView.image == nil {
        let thumb = await cache.decode(id: id, thumbhash: row?.thumbhash)
        guard let self, self.representedId == id, !Task.isCancelled else { return }
        // A thumbnail that landed first wins — never paint the placeholder over it.
        if self.photoView.image == nil { self.thumbView.image = thumb }
      }
      do {
        let loaded = try await pipeline.load(asset: stub, tier: .thumbnail)
        guard let self, self.representedId == id, !Task.isCancelled else { return }
        let image: UIImage? = switch loaded.content {
        case .placeholder(let img): img
        case .tier(_, let img, _): img
        }
        self.photoView.image = image
        if image != nil { self.thumbView.image = nil }
      } catch {
        // Offline with nothing cached: the neutral fill + badges stay. CancellationError
        // is never an error for the user.
      }
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    workTask?.cancel()
    workTask = nil
    representedId = nil
    thumbView.image = nil
    photoView.image = nil
    heartView.image = nil
    durationLabel.text = nil
    sharedView.image = nil
    dimView.isHidden = true
    selectBadge.isHidden = true
    isEditingMode = false
  }
}
