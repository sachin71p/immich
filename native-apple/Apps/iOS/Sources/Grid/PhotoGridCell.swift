import UIKit

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
    // L3 interim: the selection overlay sits ABOVE the image. (`selectedBackgroundView`
    // renders behind `contentView`, which the image fills, so selection was invisible.)
    // WP1 replaces this with the native circle/check badges.
    selectionOverlay.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
    selectionOverlay.layer.borderColor = UIColor.systemBlue.cgColor
    selectionOverlay.layer.borderWidth = 3
    selectionOverlay.isHidden = true
    selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(selectionOverlay)
    NSLayoutConstraint.activate([
      selectionOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
      selectionOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      selectionOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      selectionOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
    ])
  }

  /// L3 interim selection veil, above `imageView` and the badges.
  let selectionOverlay = UIView()

  override var isSelected: Bool {
    didSet { selectionOverlay.isHidden = !isSelected }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func prepareForReuse() {
    super.prepareForReuse()
    loadTask?.cancel()
    loadTask = nil
    imageView.image = nil
    selectionOverlay.isHidden = true
  }
}
