import UIKit

// MARK: - fast scroller (WP1 §7: UIKit handle + glass date bubble)

/// The native-style scroll handle: a slim pill on the right edge that appears while
/// scrolling and can be dragged; while dragging, a floating glass bubble shows the date
/// ("Sep 2018") at the handle position. Replaces the rotated `Slider` (audit L12).
final class FastScroller: UIView {
  /// Fraction 0...1 while dragging (top → bottom of content).
  var onScrub: ((CGFloat) -> Void)?

  private let pill = UIView()
  private let bubble: UIVisualEffectView = {
    let blur = UIBlurEffect(style: .systemMaterial)
    return UIVisualEffectView(effect: blur)
  }()
  private let bubbleLabel = UILabel()
  private var hideWork: DispatchWorkItem?
  private var dragging = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    pill.backgroundColor = .tertiaryLabel
    pill.layer.cornerRadius = 2.5
    pill.isHidden = true
    addSubview(pill)
    bubble.layer.cornerRadius = 12
    bubble.clipsToBounds = true
    bubble.isHidden = true
    bubble.contentView.addSubview(bubbleLabel)
    bubbleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    bubbleLabel.textAlignment = .center
    // The bubble floats left of the handle, clear of the thumb.
    if let host = superview { host.addSubview(bubble) } else { addSubview(bubble) }
    let pan = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
    pill.addGestureRecognizer(pan)
    pill.isUserInteractionEnabled = true
  }

  /// Only the pill is touchable — every other point falls through to the grid.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    if pill.frame.contains(point) { return pill.hitTest(convert(point, to: pill), with: event) }
    return nil
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    // The bubble must sit above scrolling content, not inside this overlay.
    if bubble.superview == self, let host = superview {
      bubble.removeFromSuperview()
      host.addSubview(bubble)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    pill.frame = CGRect(x: bounds.width - 9, y: 0, width: 5, height: bounds.height)
  }

  /// Shows the handle for the visible fraction of content; call from `scrollViewDidScroll`.
  /// `fractionVisible` is viewport/content height (clamped); `topFraction` the viewport top.
  func update(fractionVisible: CGFloat, topFraction: CGFloat) {
    guard !dragging else { return }
    let visible = min(1, max(0.02, fractionVisible))
    let top = min(1 - visible, max(0, topFraction))
    pill.isHidden = false
    pill.layer.cornerRadius = 2.5
    var frame = pill.frame
    frame.origin.y = top * bounds.height
    frame.size.height = max(44, visible * bounds.height)
    pill.frame = frame
    scheduleHide()
  }

  func setBubble(dateText: String) {
    bubbleLabel.text = dateText
    bubbleLabel.sizeToFit()
    let size = CGSize(width: bubbleLabel.bounds.width + 28, height: 36)
    bubble.bounds = CGRect(origin: .zero, size: size)
    bubbleLabel.frame = CGRect(
      x: 14, y: 0, width: size.width - 28, height: size.height)
  }

  /// Positions the bubble left of the handle at the drag point and shows it.
  func showBubble(atY y: CGFloat) {
    guard let host = superview else { return }
    bubble.isHidden = false
    bubble.center = CGPoint(x: host.bounds.width - bubble.bounds.width / 2 - 16, y: y)
  }

  func hideBubble() {
    bubble.isHidden = true
  }

  func hideHandle() {
    pill.isHidden = true
    bubble.isHidden = true
  }

  private func scheduleHide() {
    hideWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.dragging else { return }
      self.pill.isHidden = true
      self.bubble.isHidden = true
    }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
  }

  @objc private func didPan(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      dragging = true
      hideWork?.cancel()
      pill.isHidden = false
    case .changed:
      let y = gesture.location(in: self).y
      onScrub?(min(1, max(0, y / bounds.height)))
    case .ended, .cancelled, .failed:
      dragging = false
      hideBubble()
      scheduleHide()
    default:
      break
    }
  }
}
