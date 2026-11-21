import UIKit

final class StartPageViewController: UIViewController {
    var onSearchTapped: (() -> Void)?
    var onSelectURL: ((URL) -> Void)?
    var onSelectWebApp: ((WebAppItem) -> Void)?
    var onClose: (() -> Void)?

    private enum Section: Int {
        case webApps
        case favorites
        case recent
    }

    private var activeSections: [Section] = []
    private var collectionView: UICollectionView!
    private let searchBarButton = UIButton(type: .custom)
    private let closeButton = UIButton(type: .custom)
    private let topFocusGuide = UIFocusGuide()
    private let gridFocusGuide = UIFocusGuide()

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [searchBarButton]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 1.0)
        rebuildSections()
        setupHeader()
        setupCollectionView()
        setupFocusGuides()

        let menuTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menuTap)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuildSections()
        collectionView.reloadData()
    }

    private func rebuildSections() {
        var next: [Section] = []
        if !BrowserStore.shared.webApps.isEmpty { next.append(.webApps) }
        if !BrowserStore.shared.bookmarks.isEmpty { next.append(.favorites) }
        if !recentItems().isEmpty { next.append(.recent) }
        activeSections = next
    }

    private func setupHeader() {
        let titleLabel = UILabel()
        titleLabel.text = "TVBrowser · Inicio"
        titleLabel.font = .systemFont(ofSize: 38, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        closeButton.setTitle("Volver al navegador", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .semibold)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 26, bottom: 12, right: 26)
        closeButton.layer.cornerRadius = 14
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .primaryActionTriggered)
        view.addSubview(closeButton)

        searchBarButton.setTitle("🔍   Buscar en \(BrowserStore.shared.searchEngine.displayName) o escribir dirección web...", for: .normal)
        searchBarButton.titleLabel?.font = .systemFont(ofSize: 28, weight: .medium)
        searchBarButton.contentHorizontalAlignment = .center
        searchBarButton.contentEdgeInsets = UIEdgeInsets(top: 20, left: 32, bottom: 20, right: 32)
        searchBarButton.layer.cornerRadius = 20
        searchBarButton.layer.borderWidth = 1.5
        searchBarButton.layer.borderColor = UIColor.white.withAlphaComponent(0.20).cgColor
        searchBarButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        searchBarButton.setTitleColor(UIColor.white.withAlphaComponent(0.95), for: .normal)
        searchBarButton.translatesAutoresizingMaskIntoConstraints = false
        searchBarButton.addTarget(self, action: #selector(searchTapped), for: .primaryActionTriggered)
        view.addSubview(searchBarButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 60),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -60),

            searchBarButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            searchBarButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searchBarButton.widthAnchor.constraint(equalToConstant: 1180),
            searchBarButton.heightAnchor.constraint(equalToConstant: 78)
        ])
    }

    private func setupCollectionView() {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.2), heightDimension: .absolute(150))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(166))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 50, bottom: 24, trailing: 50)
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(44))
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            return section
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(StartPageTileCell.self, forCellWithReuseIdentifier: StartPageTileCell.reuseId)
        collectionView.register(StartPageHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: StartPageHeaderView.reuseId)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        collectionView.addGestureRecognizer(longPress)

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: searchBarButton.bottomAnchor, constant: 24),
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
            topFocusGuide.bottomAnchor.constraint(equalTo: searchBarButton.topAnchor)
        ])

        view.addLayoutGuide(gridFocusGuide)
        gridFocusGuide.preferredFocusEnvironments = [collectionView]
        NSLayoutConstraint.activate([
            gridFocusGuide.topAnchor.constraint(equalTo: searchBarButton.bottomAnchor),
            gridFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridFocusGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridFocusGuide.bottomAnchor.constraint(equalTo: collectionView.topAnchor)
        ])
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations({
            for btn in [self.searchBarButton, self.closeButton] {
                if context.nextFocusedView === btn {
                    btn.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
                    btn.backgroundColor = .white
                    btn.setTitleColor(.black, for: .normal)
                } else if context.previouslyFocusedView === btn {
                    btn.transform = .identity
                    btn.backgroundColor = UIColor.white.withAlphaComponent(btn === self.searchBarButton ? 0.12 : 0.14)
                    btn.setTitleColor(.white, for: .normal)
                }
            }
        }, completion: nil)
    }

    @objc private func searchTapped() {
        onSearchTapped?()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let focusedCell = view.window?.windowScene?.focusSystem?.focusedItem as? UICollectionViewCell,
              let indexPath = collectionView.indexPath(for: focusedCell),
              activeSections.indices.contains(indexPath.section) else { return }

        switch activeSections[indexPath.section] {
        case .webApps:
            let app = BrowserStore.shared.webApps[indexPath.item]
            let alert = UIAlertController(title: app.title, message: app.urlString, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Abrir WebApp", style: .default) { [weak self] _ in
                self?.onSelectWebApp?(app)
            })
            let autoTitle = app.autoLaunch ? "Quitar inicio automático" : "Abrir automáticamente al iniciar TVBrowser"
            alert.addAction(UIAlertAction(title: autoTitle, style: .default) { [weak self] _ in
                BrowserStore.shared.toggleAutoLaunch(webAppID: app.id)
                self?.rebuildSections()
                self?.collectionView.reloadData()
            })
            alert.addAction(UIAlertAction(title: "Eliminar WebApp", style: .destructive) { [weak self] _ in
                BrowserStore.shared.removeWebApp(id: app.id)
                self?.rebuildSections()
                self?.collectionView.reloadData()
            })
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
            present(alert, animated: true)

        case .favorites:
            let bm = BrowserStore.shared.bookmarks[indexPath.item]
            let alert = UIAlertController(title: bm.title, message: bm.urlString, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Abrir", style: .default) { [weak self] _ in
                if let url = URL(string: bm.urlString) { self?.onSelectURL?(url) }
            })
            alert.addAction(UIAlertAction(title: "Guardar como WebApp (Pantalla completa)", style: .default) { [weak self] _ in
                _ = BrowserStore.shared.saveWebApp(
                    title: bm.title,
                    urlString: bm.urlString,
                    userAgentMode: BrowserStore.shared.defaultUserAgentMode,
                    zoom: BrowserStore.shared.pageZoom,
                    adBlockEnabled: AdBlocker.shared.isEnabled,
                    autoLaunch: false
                )
                self?.rebuildSections()
                self?.collectionView.reloadData()
            })
            alert.addAction(UIAlertAction(title: "Eliminar favorito", style: .destructive) { [weak self] _ in
                BrowserStore.shared.removeBookmark(at: indexPath.item)
                self?.rebuildSections()
                self?.collectionView.reloadData()
            })
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
            present(alert, animated: true)

        case .recent:
            break
        }
    }

    private func recentItems() -> [HistoryItem] {
        BrowserStore.shared.recentUniqueHistory(limit: 10)
    }
}

extension StartPageViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        activeSections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch activeSections[section] {
        case .webApps: return BrowserStore.shared.webApps.count
        case .favorites: return BrowserStore.shared.bookmarks.count
        case .recent: return recentItems().count
        }
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: StartPageHeaderView.reuseId, for: indexPath) as! StartPageHeaderView
        switch activeSections[indexPath.section] {
        case .webApps:
            header.titleLabel.text = "WebApps (Pantalla completa) · Mantén pulsado Seleccionar para opciones"
        case .favorites:
            header.titleLabel.text = "Favoritos"
        case .recent:
            header.titleLabel.text = "Visitados recientemente"
        }
        return header
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StartPageTileCell.reuseId, for: indexPath) as! StartPageTileCell
        switch activeSections[indexPath.section] {
        case .webApps:
            let app = BrowserStore.shared.webApps[indexPath.item]
            let badge = app.autoLaunch ? "AUTO" : "APP"
            cell.configure(title: app.title, urlString: app.urlString, badge: badge, tint: .systemIndigo)
        case .favorites:
            let bm = BrowserStore.shared.bookmarks[indexPath.item]
            cell.configure(title: bm.title, urlString: bm.urlString, badge: nil, tint: .systemBlue)
        case .recent:
            let hist = recentItems()[indexPath.item]
            cell.configure(title: hist.title, urlString: hist.urlString, badge: nil, tint: .systemTeal)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch activeSections[indexPath.section] {
        case .webApps:
            let app = BrowserStore.shared.webApps[indexPath.item]
            onSelectWebApp?(app)
        case .favorites:
            let bm = BrowserStore.shared.bookmarks[indexPath.item]
            if let url = URL(string: bm.urlString) { onSelectURL?(url) }
        case .recent:
            let hist = recentItems()[indexPath.item]
            if let url = URL(string: hist.urlString) { onSelectURL?(url) }
        }
    }
}

private final class StartPageHeaderView: UICollectionReusableView {
    static let reuseId = "StartPageHeaderView"
    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class StartPageTileCell: UICollectionViewCell {
    static let reuseId = "StartPageTileCell"

    private let card = UIView()
    private let iconBadge = UILabel()
    private let tagLabel = UILabel()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 2.5
        card.layer.borderColor = UIColor.clear.cgColor
        contentView.addSubview(card)

        iconBadge.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.font = .systemFont(ofSize: 26, weight: .bold)
        iconBadge.textColor = .white
        iconBadge.textAlignment = .center
        iconBadge.layer.cornerRadius = 14
        iconBadge.clipsToBounds = true
        card.addSubview(iconBadge)

        tagLabel.translatesAutoresizingMaskIntoConstraints = false
        tagLabel.font = .systemFont(ofSize: 15, weight: .bold)
        tagLabel.textColor = .white
        tagLabel.backgroundColor = UIColor.systemIndigo
        tagLabel.layer.cornerRadius = 8
        tagLabel.clipsToBounds = true
        tagLabel.textAlignment = .center
        card.addSubview(tagLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        card.addSubview(titleLabel)

        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        hostLabel.font = .systemFont(ofSize: 17, weight: .regular)
        hostLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        hostLabel.lineBreakMode = .byTruncatingTail
        card.addSubview(hostLabel)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            iconBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            iconBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconBadge.widthAnchor.constraint(equalToConstant: 48),
            iconBadge.heightAnchor.constraint(equalToConstant: 48),

            tagLabel.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            tagLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            tagLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            tagLabel.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.topAnchor.constraint(equalTo: iconBadge.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            hostLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            hostLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            hostLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, urlString: String, badge: String?, tint: UIColor) {
        let host = URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
        let letter = String((host.first ?? title.first ?? "W")).uppercased()
        iconBadge.text = letter
        iconBadge.backgroundColor = tint
        titleLabel.text = title
        hostLabel.text = host
        if let badge = badge {
            tagLabel.isHidden = false
            tagLabel.text = " \(badge) "
        } else {
            tagLabel.isHidden = true
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations({
            if self.isFocused {
                self.card.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
                self.card.backgroundColor = .white
                self.card.layer.borderColor = UIColor.systemBlue.cgColor
                self.titleLabel.textColor = .black
                self.hostLabel.textColor = UIColor.black.withAlphaComponent(0.65)
            } else {
                self.card.transform = .identity
                self.card.backgroundColor = UIColor.white.withAlphaComponent(0.10)
                self.card.layer.borderColor = UIColor.clear.cgColor
                self.titleLabel.textColor = .white
                self.hostLabel.textColor = UIColor.white.withAlphaComponent(0.6)
            }
        }, completion: nil)
    }
}
