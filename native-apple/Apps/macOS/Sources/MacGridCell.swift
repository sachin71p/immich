import AppKit
import CoreModel
import LocalStore
import Media
import Rules
import SwiftUI
// MARK: - NSCollectionView grid

final class MacThumbnailContainerView: NSView {
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
    // Never `nil`: with `borderWidth = 4`, CALayer paints an opaque black frame when
    // `borderColor` is unset (R10). WP3 redoes the cell properly.
    (view as? MacThumbnailContainerView)?.layer?.borderColor = NSColor.clear.cgColor
  }
}
