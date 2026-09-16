import AppKit
import CoreModel

/// Section header for the timeline grid (WP3 §2): "September 2025" at 17 pt
/// semibold for months, "2025" at 28 pt bold for years. Frame-based layout, no
/// Auto Layout. The `headerView` material shows only while the layout reports the
/// header as pinned; otherwise the view is transparent.
final class MacGridHeaderView: NSView, NSCollectionViewElement {
  static let identifier = NSUserInterfaceItemIdentifier("MacGridHeaderView")
  /// Matches the grid's leading inset so titles align with the first column.
  static let leadingInset: CGFloat = 8

  private let effectView: NSVisualEffectView = {
    let view = NSVisualEffectView()
    view.material = .headerView
    view.state = .active
    view.isHidden = true
    return view
  }()

  private let label: NSTextField = {
    let field = NSTextField(labelWithString: "")
    field.isEditable = false
    field.isSelectable = false
    field.backgroundColor = .clear
    field.lineBreakMode = .byTruncatingTail
    return field
  }()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = nil  // Transparent unless pinned; never a fill color.
    addSubview(effectView)
    addSubview(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Title + emphasis from the snapshot section. Called by the coordinator (slice 2).
  func configure(title: String, kind: TimelineSectionKind) {
    label.stringValue = title
    // Year markers read as separators; month headers stay quiet.
    label.font =
      kind == .year
      ? .systemFont(ofSize: 28, weight: .bold)
      : .systemFont(ofSize: 17, weight: .semibold)
    needsLayout = true
  }

  /// Material background only while stuck to the viewport top.
  var isPinned = false {
    didSet {
      guard isPinned != oldValue else { return }
      effectView.isHidden = !isPinned
    }
  }

  override func layout() {
    super.layout()
    effectView.frame = bounds
    // Vertically centered text with the grid's leading inset; the field sizes to
    // its content height so larger year type stays centered too.
    let availableWidth = max(0, bounds.width - Self.leadingInset * 2)
    let height = label.attributedStringValue.size().height
    let rowHeight = ceil(max(height, 0))
    label.frame = NSRect(
      x: Self.leadingInset,
      y: floor((bounds.height - rowHeight) / 2),
      width: availableWidth,
      height: rowHeight)
  }

  // MARK: - NSCollectionViewElement

  func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes?) {
    guard let layoutAttributes else { return }
    frame = layoutAttributes.frame
    if let header = layoutAttributes as? MacTimelineHeaderAttributes {
      isPinned = header.isPinned
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    label.stringValue = ""
    isPinned = false
  }
}
