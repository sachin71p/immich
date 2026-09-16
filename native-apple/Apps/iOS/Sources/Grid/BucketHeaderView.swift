import UIKit

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
