import UIKit

struct BrowserMenuActionItem {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: UIColor
}

final class BrowserMenuViewController: UIViewController {
    var items: [BrowserMenuActionItem] = []
    var onSelectAction: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private var collectionView: UICollectionView!
    private let closeButton = UIButton(type: .custom)
    private let topFocusGuide = UIFocusGuide()
    private let bottomFocusGuide = UIFocusGuide()

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        items.isEmpty ? [closeButton] : [collectionView]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.04, green: 0.06, blue: 0.11, alpha: 0.96)

        setupHeader()
        setupCollectionView()
        setupFocusGuides()

        let menuTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menuTap)
    }

    private func setupHeader() {
        let titleLabel = UILabel()
        titleLabel.text = "Menú de TVBrowser"
        titleLabel.font = .systemFont(ofSize: 38, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Navega con las flechas o el touchpad y pulsa Seleccionar"
        subtitleLabel.font = .systemFont(ofSize: 21, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)

        closeButton.setTitle("Cerrar", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .semibold)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 30, bottom: 14, right: 30)
        closeButton.layer.cornerRadius = 16
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .primaryActionTriggered)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 72),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -72)
        ])
    }

    private func setupCollectionView() {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.25), heightDimension: .absolute(152))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(172))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 60, bottom: 40, trailing: 60)

        let layout = UICollectionViewCompositionalLayout(section: section)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(BrowserMenuCardCell.self, forCellWithReuseIdentifier: BrowserMenuCardCell.reuseId)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 132),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupFocusGuides() {
        view.addLayoutGuide(topFocusGuide)
        topFocusGuide.preferredFocusEnvironments = [closeButton]
        NSLayoutConstraint.activate([
            topFocusGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topFocusGuide.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor),
            topFocusGuide.bottomAnchor.constraint(equalTo: collectionView.topAnchor)
        ])

        view.addLayoutGuide(bottomFocusGuide)
        bottomFocusGuide.preferredFocusEnvironments = [collectionView]
        NSLayoutConstraint.activate([
            bottomFocusGuide.topAnchor.constraint(equalTo: closeButton.bottomAnchor),
            bottomFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomFocusGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFocusGuide.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations({
            if context.nextFocusedView === self.closeButton {
                self.closeButton.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
                self.closeButton.backgroundColor = .white
                self.closeButton.setTitleColor(.black, for: .normal)
            } else if context.previouslyFocusedView === self.closeButton {
                self.closeButton.transform = .identity
                self.closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
                self.closeButton.setTitleColor(.white, for: .normal)
            }
        }, completion: nil)
    }

    @objc private func closeTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }
}

extension BrowserMenuViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BrowserMenuCardCell.reuseId, for: indexPath) as! BrowserMenuCardCell
        cell.configure(items[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let actionId = items[indexPath.item].id
        dismiss(animated: true) { [weak self] in
            self?.onSelectAction?(actionId)
        }
    }
}

private final class BrowserMenuCardCell: UICollectionViewCell {
    static let reuseId = "BrowserMenuCardCell"

    private let card = UIView()
    private let iconLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var baseTint: UIColor = .systemBlue

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 3
        card.layer.borderColor = UIColor.clear.cgColor
        contentView.addSubview(card)

        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.font = .systemFont(ofSize: 30, weight: .bold)
        iconLabel.textAlignment = .center
        iconLabel.textColor = .white
        iconLabel.layer.cornerRadius = 14
        iconLabel.clipsToBounds = true
        card.addSubview(iconLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 23, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        card.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.68)
        subtitleLabel.numberOfLines = 1
        card.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            iconLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            iconLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            iconLabel.widthAnchor.constraint(equalToConstant: 52),
            iconLabel.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: BrowserMenuActionItem) {
        baseTint = item.accentColor
        iconLabel.text = item.icon
        iconLabel.backgroundColor = item.accentColor
        titleLabel.text = item.title
        subtitleLabel.text = item.subtitle
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations({
            if self.isFocused {
                self.card.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
                self.card.backgroundColor = .white
                self.card.layer.borderColor = self.baseTint.cgColor
                self.titleLabel.textColor = .black
                self.subtitleLabel.textColor = UIColor.black.withAlphaComponent(0.68)
            } else {
                self.card.transform = .identity
                self.card.backgroundColor = UIColor.white.withAlphaComponent(0.10)
                self.card.layer.borderColor = UIColor.clear.cgColor
                self.titleLabel.textColor = .white
                self.subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.68)
            }
        }, completion: nil)
    }
}
