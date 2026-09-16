import AppKit
import CoreModel
import Media

// MARK: - container (hit-testing only; hover comes from the collection view)

/// The cell's root view. Owns no tracking areas (WP3 §3: one area lives on the
/// collection view) — just explicit hit-testing for the favorite badge, keeping the
/// approach from the old cell: NSCollectionView's click machinery swallows clicks
/// meant for subviews, so the heart frame is tested here and everything else falls
/// through to `super` for native plain/shift/command selection.
final class MacThumbnailContainerView: NSView {
  /// Heart-badge frame in container coordinates, refreshed by the cell's layout.
  var favoriteFrame: CGRect = .zero
  var onFavoriteHit: (() -> Void)?
  /// Frame layout + appearance refresh live on the view (`NSCollectionViewItem` has
  /// neither `layout()` nor `viewDidChangeEffectiveAppearance()`); the cell assigns
  /// both and does the real work.
  var onLayout: ((CGRect) -> Void)?
  var onAppearanceChange: (() -> Void)?

  override func layout() {
    super.layout()
    onLayout?(bounds)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    onAppearanceChange?()
  }

  override func mouseDown(with event: NSEvent) {
    if !favoriteFrame.isNull, !favoriteFrame.isEmpty {
      let point = convert(event.locationInWindow, from: nil)
      if favoriteFrame.contains(point) {
        onFavoriteHit?()
        return
      }
    }
    super.mouseDown(with: event)
  }
}

// MARK: - cell (WP3 §4 rewrite: the black-border fix)

/// Frame-based grid cell. The R10 black-border root cause was `prepareForReuse`
/// assigning `layer.borderColor = nil` while `borderWidth = 4` (CALayer paints nil as
/// opaque black) plus an early-returning `isSelected` didSet that never repaired it.
/// This rewrite removes the mechanism: no borders anywhere (`borderWidth = 0`
/// always), selection drawn by a dedicated overlay layer with always-non-nil colors,
/// and didSets without early returns.
final class MacGridCell: NSCollectionViewItem {
  static let identifier = NSUserInterfaceItemIdentifier("MacGridCell")

  /// In-flight progressive load, cancelled on reuse/scroll-away.
  var loadTask: Task<Void, Never>?
  /// Row this cell is configured for; image sets apply only on match.
  var representedId: String?
  var onFavorite: (() -> Void)?

  private var row: TimelineRow?
  private var aspectFit = false
  private var selectionMode = false
  private var hovered = false

  private let imageLayer = CALayer()
  private let selectionLayer = CALayer()
  private let durationLayer = CATextLayer()
  private let scrimLayer = CAGradientLayer()
  private let liveLayer = CALayer()
  private let heartLayer = CALayer()
  private let checkLayer = CALayer()

  // MARK: cached text/symbol resources (badges stay lightweight layers)

  private static let badgeFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
  private static let symbolLock = NSLock()
  private static var symbolCache: [String: CGImage] = [:]
  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  /// Template SF Symbol rasterized once per name+color+scale and cached. Must run on
  /// the main thread (lockFocus); all callers are main-actor cell configuration.
  private static func symbolImage(named name: String, color: NSColor, scale: CGFloat) -> CGImage? {
    let key = name + "|" + String(describing: color) + "@" + String(describing: scale)
    if let hit = symbolLock.withLock({ symbolCache[key] }) { return hit }
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let side = ceil(20 * scale)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    symbol.draw(in: rect)
    color.set()
    rect.fill(using: .sourceAtop)
    image.unlockFocus()
    var proposed = rect
    guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
    symbolLock.withLock { symbolCache[key] = cg }
    return cg
  }

  static func durationText(_ seconds: Int) -> String {
    String(seconds / 60) + ":" + String(format: "%02d", seconds % 60)
  }

  // MARK: view setup (no Auto Layout; everything is frame-laid in `layout()`)

  override func loadView() {
    let container = MacThumbnailContainerView()
    container.wantsLayer = true
    container.layerContentsRedrawPolicy = .never
    // The actual fix: borders are gone, not just transparent. borderWidth stays 0
    // forever, so no nil-color path can ever paint a black frame again.
    container.layer?.borderWidth = 0
    container.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    guard let root = container.layer else {
      view = container
      return
    }
    imageLayer.masksToBounds = true
    imageLayer.cornerRadius = 0
    // No implicit fade/slide when the stream swaps placeholder → thumbnail.
    imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    root.addSublayer(imageLayer)

    selectionLayer.borderWidth = 3
    selectionLayer.isHidden = true
    selectionLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    root.addSublayer(selectionLayer)

    scrimLayer.isHidden = true
    root.addSublayer(scrimLayer)

    durationLayer.font = Self.badgeFont
    durationLayer.fontSize = 11
    durationLayer.foregroundColor = NSColor.white.cgColor
    durationLayer.alignmentMode = .right
    durationLayer.isHidden = true
    root.addSublayer(durationLayer)

    liveLayer.isHidden = true
    root.addSublayer(liveLayer)
    heartLayer.isHidden = true
    root.addSublayer(heartLayer)
    checkLayer.isHidden = true
    root.addSublayer(checkLayer)

    container.onFavoriteHit = { [weak self] in self?.toggleFavorite() }
    container.onLayout = { [weak self] bounds in self?.layoutSublayers(in: bounds) }
    container.onAppearanceChange = { [weak self] in self?.updateSelectionOverlay() }
    view = container
  }

  // MARK: selection (no early returns — every state change repaints)

  override var isSelected: Bool {
    didSet { updateSelectionOverlay() }
  }

  override var highlightState: NSCollectionViewItem.HighlightState {
    didSet { updateSelectionOverlay() }
  }

  private func updateSelectionOverlay() {
    // Accent CGColors are re-resolved on every update (never stored, never nil), so
    // Dark Mode / accent changes can't strand a stale or missing color.
    let accent = NSColor.controlAccentColor
    selectionLayer.borderColor = accent.cgColor
    selectionLayer.backgroundColor = accent.withAlphaComponent(0.12).cgColor
    selectionLayer.isHidden = !(isSelected || highlightState == .forSelection)
    updateCheckBadge()
  }

  // MARK: hover + selection mode (coordinator-driven)

  /// Called by the coordinator's single collection-view tracking area. Drives the
  /// hover-only outline heart; the filled favorite heart is always visible.
  func setHover(_ hovering: Bool) {
    hovered = hovering
    updateHeartBadge()
  }

  /// Selection-mode checkmark (WP3 §3: `isSelectionMode` is badge-only). Refreshed
  /// for visible cells when the mode flips, without a reload.
  func setSelectionMode(_ mode: Bool) {
    selectionMode = mode
    updateCheckBadge()
  }

  // MARK: configure (WP3 §4 order: cache → placeholder → streamed tiers)

  /// - Parameters:
  ///   - aspectFit: `.resizeAspect` letterbox on quaternary (zoomed-out mode) vs
  ///     `.resizeAspectFill` square crop (Photos default).
  ///   - itemSide/scale: thumbnail `pixelSize = min(512, ceil(side*scale/64)*64)`,
  ///     or tier `.preview` once `side*scale > 512`.
  func configure(
    row: TimelineRow, aspectFit: Bool, selectionMode: Bool,
    itemSide: CGFloat, pipeline: MediaPipeline
  ) {
    loadTask?.cancel()
    loadTask = nil
    self.row = row
    self.aspectFit = aspectFit
    self.selectionMode = selectionMode
    representedId = row.id
    representedObject = row.id

    imageLayer.contentsGravity = aspectFit ? .resizeAspect : .resizeAspectFill
    updateBadges()
    updateSelectionOverlay()
    view.setAccessibilityIdentifier("grid-cell-" + row.id)
    if row.mediaKind == .video, let seconds = row.durationSeconds {
      view.setAccessibilityLabel("Video, " + Self.durationText(seconds))
    } else if let date = row.localDateTime {
      view.setAccessibilityLabel("Photo, " + Self.dateFormatter.string(from: date))
    } else {
      view.setAccessibilityLabel("Photo")
    }
    view.needsLayout = true

    // 1. Synchronous memory-cache hit: the cell never sits blank when we've
    // already decoded this thumbnail (R9: no sync hit existed before WP1).
    if let hit = pipeline.cachedImage(id: row.id, tier: .thumbnail) {
      imageLayer.contents = hit
      return
    }
    // 2. Thumbhash placeholder already decoded.
    if let placeholder = pipeline.cachedPlaceholder(id: row.id) {
      imageLayer.contents = placeholder
    }
    // 3. Progressive task: decode the placeholder if needed, then stream tiers.
    let id = row.id
    let thumbhash = row.thumbhash
    let edited = row.isEdited
    let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    let pixels = itemSide * scale
    let tier: MediaTier = pixels > 512 ? .preview : .thumbnail
    let pixelSize: Int? = tier == .thumbnail ? min(512, Int(ceil(pixels / 64)) * 64) : nil
    loadTask = Task { [weak self] in
      if self?.imageLayer.contents == nil {
        if let decoded = await pipeline.placeholder(id: id, thumbhash: thumbhash) {
          guard let self, self.representedId == id else { return }
          self.imageLayer.contents = decoded
        }
      }
      do {
        for try await step in await pipeline.stream(
          id: id, thumbhash: thumbhash, tier: tier, edited: edited, pixelSize: pixelSize)
        {
          let cgImage: CGImage?
          switch step.content {
          case .placeholder:
            continue  // Already showing the decoded placeholder from step 3.
          case .tier(_, let loaded, _):
            cgImage = loaded.cgImage(forProposedRect: nil, context: nil, hints: nil)
          }
          guard let self, self.representedId == id else { return }
          if let cgImage { self.imageLayer.contents = cgImage }
          if Task.isCancelled { return }
        }
      } catch {
        // Same contract as the old cell: per-cell failures are cosmetic and keep the
        // placeholder; systemic failures surface through the loader, not the grid.
      }
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    loadTask?.cancel()
    loadTask = nil
    representedId = nil
    representedObject = nil
    row = nil
    hovered = false
    imageLayer.contents = nil
    // Hide, never nil: selection/border colors stay non-nil for the next occupant.
    selectionLayer.isHidden = true
    durationLayer.isHidden = true
    scrimLayer.isHidden = true
    liveLayer.isHidden = true
    heartLayer.isHidden = true
    checkLayer.isHidden = true
  }

  @objc private func toggleFavorite() { onFavorite?() }

  // MARK: badges

  private func updateBadges() {
    guard let row else { return }
    if let seconds = row.durationSeconds {
      durationLayer.string = Self.durationText(seconds)
      durationLayer.isHidden = false
      scrimLayer.isHidden = false
      scrimLayer.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.45).cgColor]
    } else {
      durationLayer.isHidden = true
      scrimLayer.isHidden = true
    }
    liveLayer.isHidden = row.mediaKind != .livePhoto
    updateHeartBadge()
    updateCheckBadge()
  }

  private func updateHeartBadge() {
    guard let row else {
      heartLayer.isHidden = true
      return
    }
    let scale = view.window?.backingScaleFactor ?? 2
    if row.isFavorite {
      heartLayer.contents = Self.symbolImage(
        named: "heart.fill", color: .systemRed, scale: scale)
      heartLayer.isHidden = false
    } else if hovered {
      heartLayer.contents = Self.symbolImage(named: "heart", color: .white, scale: scale)
      heartLayer.isHidden = false
    } else {
      heartLayer.isHidden = true
    }
  }

  private func updateCheckBadge() {
    guard selectionMode, isSelected else {
      checkLayer.isHidden = true
      return
    }
    let scale = view.window?.backingScaleFactor ?? 2
    checkLayer.contents = Self.symbolImage(
      named: "checkmark.circle.fill", color: .controlAccentColor, scale: scale)
    checkLayer.isHidden = false
  }

  // MARK: frame layout (no Auto Layout inside the cell)

  private func layoutSublayers(in bounds: CGRect) {
    guard !bounds.isEmpty else { return }
    let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    for layer in [imageLayer, selectionLayer] {
      layer.frame = bounds
      layer.contentsScale = scale
    }
    for layer in [durationLayer, scrimLayer, liveLayer, heartLayer, checkLayer] {
      layer.contentsScale = scale
    }
    let inset: CGFloat = 6
    // Bottom-right duration with a subtle scrim so white text reads on bright photos.
    if !durationLayer.isHidden, let text = durationLayer.string as? String {
      let size = (text as NSString).size(withAttributes: [.font: Self.badgeFont])
      let labelFrame = CGRect(
        x: bounds.maxX - inset - size.width - 4,
        y: bounds.minY + inset,
        width: size.width + 4,
        height: ceil(size.height))
      durationLayer.frame = labelFrame
      scrimLayer.startPoint = CGPoint(x: 0.5, y: 0)
      scrimLayer.endPoint = CGPoint(x: 0.5, y: 1)
      scrimLayer.frame = labelFrame.insetBy(dx: -6, dy: -3)
    }
    // Top-left Live Photo glyph (20 pt; backing scale handled via contentsScale).
    let badgeSide: CGFloat = 20
    liveLayer.frame = CGRect(
      x: bounds.minX + inset, y: bounds.maxY - inset - badgeSide,
      width: badgeSide, height: badgeSide)
    // Bottom-left heart (favorite target; the container hit-tests this frame).
    let heartSide: CGFloat = 24
    let heartFrame = CGRect(
      x: bounds.minX + inset, y: bounds.minY + inset,
      width: heartSide, height: heartSide)
    heartLayer.frame = heartFrame
    (view as? MacThumbnailContainerView)?.favoriteFrame = heartFrame
    // Top-right selection-mode checkmark.
    let checkSide: CGFloat = 22
    checkLayer.frame = CGRect(
      x: bounds.maxX - inset - checkSide, y: bounds.maxY - inset - checkSide,
      width: checkSide, height: checkSide)
  }
}
