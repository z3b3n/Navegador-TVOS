import UIKit

final class TabsViewController: UIViewController {
    var tabs: [BrowserTab] = []
    var activeTabIndex: Int = 0
    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var collectionView: UICollectionView!
    private let titleLabel = UILabel()
    private let newTabButton = UIButton(type: .custom)
    private let closeViewButton = UIButton(type: .custom)
    private let topFocusGuide = UIFocusGuide()
    private let bottomFocusGuide = UIFocusGuide()

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [collectionView]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 0.98)
        setupHeader()
        setupCollectionView()
        setupFocusGuides()

        let menuTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menuTap)
    }

    private func setupHeader() {
        titleLabel.text = "Pestañas abiertas (\(tabs.count))"
        titleLabel.font = .systemFont(ofSize: 36, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        newTabButton.setTitle("+ Nueva pestaña", for: .normal)
        newTabButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .semibold)
        newTabButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        newTabButton.layer.cornerRadius = 14
        newTabButton.backgroundColor = UIColor.systemBlue
        newTabButton.setTitleColor(.white, for: .normal)
        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.addTarget(self, action: #selector(newTabTapped), for: .primaryActionTriggered)
        view.addSubview(newTabButton)

        closeViewButton.setTitle("Cerrar", for: .normal)
        closeViewButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .semibold)
        closeViewButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        closeViewButton.layer.cornerRadius = 14
        closeViewButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        closeViewButton.setTitleColor(.white, for: .normal)
        closeViewButton.translatesAutoresizingMaskIntoConstraints = false
        closeViewButton.addTarget(self, action: #selector(closeTapped), for: .primaryActionTriggered)
        view.addSubview(closeViewButton)

        let hintLabel = UILabel()
        hintLabel.text = "Selecciona una pestaña para cambiar · Pulsa Play/Pausa o mantén Seleccionar para cerrarla"
        hintLabel.font = .systemFont(ofSize: 20, weight: .regular)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 60),

            closeViewButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeViewButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -60),

            newTabButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            newTabButton.trailingAnchor.constraint(equalTo: closeViewButton.leadingAnchor, constant: -16),

            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            hintLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor)
        ])
    }

    private func setupCollectionView() {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.25), heightDimension: .absolute(220))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(236))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 48, bottom: 40, trailing: 48)

        let layout = UICollectionViewCompositionalLayout(section: section)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TabCardCell.self, forCellWithReuseIdentifier: TabCardCell.reuseId)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        collectionView.addGestureRecognizer(longPress)

        let playTap = UITapGestureRecognizer(target: self, action: #selector(handlePlayPauseOnCell(_:)))
        playTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        collectionView.addGestureRecognizer(playTap)

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 130),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupFocusGuides() {
        // Bridges UP from left-side tab cards directly to + Nueva pestaña / Cerrar
        view.addLayoutGuide(topFocusGuide)
        topFocusGuide.preferredFocusEnvironments = [newTabButton, closeViewButton]
        NSLayoutConstraint.activate([
            topFocusGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topFocusGuide.trailingAnchor.constraint(equalTo: newTabButton.leadingAnchor),
            topFocusGuide.bottomAnchor.constraint(equalTo: collectionView.topAnchor)
        ])

        view.addLayoutGuide(bottomFocusGuide)
        bottomFocusGuide.preferredFocusEnvironments = [collectionView]
        NSLayoutConstraint.activate([
            bottomFocusGuide.topAnchor.constraint(equalTo: newTabButton.bottomAnchor),
            bottomFocusGuide.leadingAnchor.constraint(equalTo: newTabButton.leadingAnchor),
            bottomFocusGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFocusGuide.bottomAnchor.constraint(equalTo: collectionView.topAnchor)
        ])
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations({
            for btn in [self.newTabButton, self.closeViewButton] {
                if context.nextFocusedView === btn {
                    btn.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
                    btn.backgroundColor = .white
                    btn.setTitleColor(.black, for: .normal)
                } else if context.previouslyFocusedView === btn {
                    btn.transform = .identity
                    btn.backgroundColor = (btn === self.newTabButton) ? .systemBlue : UIColor.white.withAlphaComponent(0.16)
                    btn.setTitleColor(.white, for: .normal)
                }
            }
        }, completion: nil)
    }

    @objc private func newTabTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onNewTab?()
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }

    @objc private func handlePlayPauseOnCell(_ gesture: UITapGestureRecognizer) {
        guard let cell = view.window?.windowScene?.focusSystem?.focusedItem as? UICollectionViewCell,
              let indexPath = collectionView.indexPath(for: cell),
              tabs.indices.contains(indexPath.item),
              tabs.count > 1 else { return }
        closeTabAt(indexPath.item)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let cell = view.window?.windowScene?.focusSystem?.focusedItem as? UICollectionViewCell,
              let indexPath = collectionView.indexPath(for: cell),
              tabs.indices.contains(indexPath.item) else { return }

        let tab = tabs[indexPath.item]
        let alert = UIAlertController(title: tab.title, message: tab.url?.absoluteString, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Abrir pestaña", style: .default) { [weak self] _ in
            self?.dismiss(animated: true) {
                self?.onSelectTab?(indexPath.item)
            }
        })
        if tabs.count > 1 {
            alert.addAction(UIAlertAction(title: "Cerrar pestaña", style: .destructive) { [weak self] _ in
                self?.closeTabAt(indexPath.item)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    private func closeTabAt(_ index: Int) {
        guard tabs.indices.contains(index), tabs.count > 1 else { return }
        onCloseTab?(index)
        tabs.remove(at: index)
        if activeTabIndex >= tabs.count { activeTabIndex = max(0, tabs.count - 1) }
        titleLabel.text = "Pestañas abiertas (\(tabs.count))"
        collectionView.reloadData()
    }
}

extension TabsViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        tabs.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabCardCell.reuseId, for: indexPath) as! TabCardCell
        let tab = tabs[indexPath.item]
        cell.configure(tab: tab, isActive: indexPath.item == activeTabIndex)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        dismiss(animated: true) { [weak self] in
            self?.onSelectTab?(indexPath.item)
        }
    }
}

private final class TabCardCell: UICollectionViewCell {
    static let reuseId = "TabCardCell"

    private let card = UIView()
    private let badgeLabel = UILabel()
    private let titleLabel = UILabel()
    private let urlLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.white.withAlphaComponent(0.11)
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 3
        card.layer.borderColor = UIColor.clear.cgColor
        contentView.addSubview(card)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: 16, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.layer.cornerRadius = 8
        badgeLabel.clipsToBounds = true
        badgeLabel.textAlignment = .center
        card.addSubview(badgeLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        card.addSubview(titleLabel)

        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = .systemFont(ofSize: 17, weight: .regular)
        urlLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        urlLabel.lineBreakMode = .byTruncatingMiddle
        card.addSubview(urlLabel)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            badgeLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            badgeLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            badgeLabel.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.topAnchor.constraint(equalTo: badgeLabel.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),

            urlLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            urlLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            urlLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(tab: BrowserTab, isActive: Bool) {
        titleLabel.text = tab.title.isEmpty ? "Nueva pestaña" : tab.title
        urlLabel.text = tab.url?.host ?? tab.url?.absoluteString ?? "Inicio"
        if tab.isAppMode {
            badgeLabel.text = "  WEBAPP  "
            badgeLabel.backgroundColor = .systemIndigo
        } else if isActive {
            badgeLabel.text = "  ACTIVA  "
            badgeLabel.backgroundColor = .systemBlue
        } else {
            badgeLabel.text = "  PESTAÑA  "
            badgeLabel.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations({
            if self.isFocused {
                self.card.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
                self.card.backgroundColor = .white
                self.card.layer.borderColor = UIColor.systemBlue.cgColor
                self.titleLabel.textColor = .black
                self.urlLabel.textColor = UIColor.black.withAlphaComponent(0.65)
            } else {
                self.card.transform = .identity
                self.card.backgroundColor = UIColor.white.withAlphaComponent(0.11)
                self.card.layer.borderColor = UIColor.clear.cgColor
                self.titleLabel.textColor = .white
                self.urlLabel.textColor = UIColor.white.withAlphaComponent(0.65)
            }
        }, completion: nil)
    }
}
