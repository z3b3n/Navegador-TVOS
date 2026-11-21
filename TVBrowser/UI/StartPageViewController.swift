import UIKit

final class StartPageViewController: UIViewController {
    var onSearchTapped: (() -> Void)?
    var onSelectURL: ((URL) -> Void)?
    var onSelectWebApp: ((WebAppItem) -> Void)?
    var onClose: (() -> Void)?

    var currentPageTitle: String?
    var currentPageURL: URL?

    private enum Section: Int {
        case webApps
        case favorites
        case recent
    }

    private var activeSections: [Section] = []
    private var isEditingShortcuts = false
    private var collectionView: UICollectionView!
    private let searchBarButton = UIButton(type: .custom)
    private let addShortcutButton = UIButton(type: .custom)
    private let editShortcutsButton = UIButton(type: .custom)
    private let closeButton = UIButton(type: .custom)
    private let headerButtonsStack = UIStackView()
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

        let menuTap = UITapGestureRecognizer(target: self, action: #selector(menuButtonPressed))
        menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menuTap)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadStartPageData()
    }

    private func reloadStartPageData() {
        rebuildSections()
        updateEditButtonAppearance()
        collectionView.reloadData()
    }

    private func rebuildSections() {
        var next: [Section] = []
        if !BrowserStore.shared.webApps.isEmpty { next.append(.webApps) }
        next.append(.favorites)
        if !recentItems().isEmpty { next.append(.recent) }
        activeSections = next
    }

    private func setupHeader() {
        let titleLabel = UILabel()
        titleLabel.text = "Platanet · Inicio"
        titleLabel.font = .systemFont(ofSize: 38, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        configureHeaderButton(addShortcutButton, title: "+ Añadir acceso", tint: UIColor.systemBlue.withAlphaComponent(0.55), action: #selector(addShortcutTapped))
        configureHeaderButton(editShortcutsButton, title: "Editar", tint: UIColor.white.withAlphaComponent(0.14), action: #selector(toggleEditTapped))
        configureHeaderButton(closeButton, title: "Volver al navegador", tint: UIColor.white.withAlphaComponent(0.14), action: #selector(closeTapped))

        headerButtonsStack.axis = .horizontal
        headerButtonsStack.spacing = 14
        headerButtonsStack.alignment = .center
        headerButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        [addShortcutButton, editShortcutsButton, closeButton].forEach { headerButtonsStack.addArrangedSubview($0) }
        view.addSubview(headerButtonsStack)

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

            headerButtonsStack.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            headerButtonsStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -60),

            searchBarButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            searchBarButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searchBarButton.widthAnchor.constraint(equalToConstant: 1180),
            searchBarButton.heightAnchor.constraint(equalToConstant: 78)
        ])
    }

    private func configureHeaderButton(_ button: UIButton, title: String, tint: UIColor, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 22, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 22, bottom: 12, right: 22)
        button.layer.cornerRadius = 14
        button.backgroundColor = tint
        button.setTitleColor(.white, for: .normal)
        button.addTarget(self, action: action, for: .primaryActionTriggered)
    }

    private func headerButtonDefaultBackground(_ button: UIButton) -> UIColor {
        if button === addShortcutButton {
            return UIColor.systemBlue.withAlphaComponent(0.55)
        }
        if button === editShortcutsButton && isEditingShortcuts {
            return UIColor.systemRed.withAlphaComponent(0.75)
        }
        if button === searchBarButton {
            return UIColor.white.withAlphaComponent(0.12)
        }
        return UIColor.white.withAlphaComponent(0.14)
    }

    private func updateEditButtonAppearance() {
        editShortcutsButton.setTitle(isEditingShortcuts ? "✓ Listo" : "Editar accesos", for: .normal)
        if !editShortcutsButton.isFocused {
            editShortcutsButton.backgroundColor = headerButtonDefaultBackground(editShortcutsButton)
        }
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
        topFocusGuide.preferredFocusEnvironments = [addShortcutButton]
        NSLayoutConstraint.activate([
            topFocusGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topFocusGuide.trailingAnchor.constraint(equalTo: headerButtonsStack.leadingAnchor),
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
            for btn in [self.searchBarButton, self.addShortcutButton, self.editShortcutsButton, self.closeButton] {
                if context.nextFocusedView === btn {
                    btn.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
                    btn.backgroundColor = .white
                    btn.setTitleColor(.black, for: .normal)
                } else if context.previouslyFocusedView === btn {
                    btn.transform = .identity
                    btn.backgroundColor = self.headerButtonDefaultBackground(btn)
                    btn.setTitleColor(.white, for: .normal)
                }
            }
        }, completion: nil)
    }

    @objc private func searchTapped() {
        onSearchTapped?()
    }

    @objc private func addShortcutTapped() {
        presentAddShortcutMenu()
    }

    @objc private func toggleEditTapped() {
        isEditingShortcuts.toggle()
        reloadStartPageData()
    }

    @objc private func menuButtonPressed() {
        if isEditingShortcuts {
            isEditingShortcuts = false
            reloadStartPageData()
        } else {
            onClose?()
        }
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let focusedCell = view.window?.windowScene?.focusSystem?.focusedItem as? UICollectionViewCell,
              let indexPath = collectionView.indexPath(for: focusedCell),
              activeSections.indices.contains(indexPath.section) else { return }

        presentOptionsForItem(at: indexPath)
    }

    private func presentOptionsForItem(at indexPath: IndexPath) {
        guard activeSections.indices.contains(indexPath.section) else { return }
        switch activeSections[indexPath.section] {
        case .webApps:
            presentWebAppOptions(at: indexPath.item)
        case .favorites:
            if indexPath.item >= BrowserStore.shared.bookmarks.count {
                presentAddShortcutMenu()
            } else {
                presentFavoriteOptions(at: indexPath.item)
            }
        case .recent:
            let recents = recentItems()
            guard recents.indices.contains(indexPath.item) else { return }
            let hist = recents[indexPath.item]
            let alert = UIAlertController(title: hist.title, message: hist.urlString, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Abrir página", style: .default) { [weak self] _ in
                if let url = URL(string: hist.urlString) { self?.onSelectURL?(url) }
            })
            alert.addAction(UIAlertAction(title: "★ Añadir a Favoritos", style: .default) { [weak self] _ in
                BrowserStore.shared.addBookmark(title: hist.title, urlString: hist.urlString)
                self?.reloadStartPageData()
            })
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
            present(alert, animated: true)
        }
    }

    private func presentWebAppOptions(at index: Int) {
        guard BrowserStore.shared.webApps.indices.contains(index) else { return }
        let app = BrowserStore.shared.webApps[index]
        let alert = UIAlertController(title: app.title, message: app.urlString, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Abrir WebApp", style: .default) { [weak self] _ in
            self?.onSelectWebApp?(app)
        })
        let autoTitle = app.autoLaunch ? "Quitar inicio automático" : "Abrir automáticamente al iniciar Platanet"
        alert.addAction(UIAlertAction(title: autoTitle, style: .default) { [weak self] _ in
            BrowserStore.shared.toggleAutoLaunch(webAppID: app.id)
            self?.reloadStartPageData()
        })
        alert.addAction(UIAlertAction(title: "✕ Eliminar WebApp", style: .destructive) { [weak self] _ in
            BrowserStore.shared.removeWebApp(id: app.id)
            self?.reloadStartPageData()
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    private func presentFavoriteOptions(at index: Int) {
        guard BrowserStore.shared.bookmarks.indices.contains(index) else { return }
        let bm = BrowserStore.shared.bookmarks[index]
        let alert = UIAlertController(title: bm.title, message: bm.urlString, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "↗ Abrir página", style: .default) { [weak self] _ in
            if let url = URL(string: bm.urlString) { self?.onSelectURL?(url) }
        })
        alert.addAction(UIAlertAction(title: "✎ Editar nombre o URL", style: .default) { [weak self] _ in
            self?.presentBookmarkEditor(editingIndex: index, initialTitle: bm.title, initialURL: bm.urlString)
        })
        if index > 0 {
            alert.addAction(UIAlertAction(title: "⬆ Mover al principio", style: .default) { [weak self] _ in
                BrowserStore.shared.moveBookmarkToFront(at: index)
                self?.reloadStartPageData()
            })
        }
        alert.addAction(UIAlertAction(title: "⊞ Guardar como WebApp (Pantalla completa)", style: .default) { [weak self] _ in
            _ = BrowserStore.shared.saveWebApp(
                title: bm.title,
                urlString: bm.urlString,
                userAgentMode: BrowserStore.shared.defaultUserAgentMode,
                zoom: BrowserStore.shared.pageZoom,
                adBlockEnabled: AdBlocker.shared.isEnabled,
                autoLaunch: false
            )
            self?.reloadStartPageData()
        })
        alert.addAction(UIAlertAction(title: "✕ Eliminar favorito", style: .destructive) { [weak self] _ in
            BrowserStore.shared.removeBookmark(at: index)
            self?.reloadStartPageData()
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    private func presentAddShortcutMenu() {
        let alert = UIAlertController(
            title: "Añadir acceso directo",
            message: "Guarda una página en Favoritos para abrirla con un clic desde Inicio.",
            preferredStyle: .alert
        )

        if let currentURL = currentPageURL,
           let scheme = currentURL.scheme?.lowercased(),
           (scheme == "http" || scheme == "https") {
            let host = currentURL.host?.replacingOccurrences(of: "www.", with: "") ?? currentURL.absoluteString
            let suggestedTitle = (currentPageTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? (currentPageTitle ?? host)
                : host
            alert.addAction(UIAlertAction(title: "★ Añadir página actual (\(host))", style: .default) { [weak self] _ in
                BrowserStore.shared.addBookmark(title: suggestedTitle, urlString: currentURL.absoluteString)
                self?.reloadStartPageData()
            })
        }

        alert.addAction(UIAlertAction(title: "✎ Escribir nombre y URL...", style: .default) { [weak self] _ in
            self?.presentBookmarkEditor(editingIndex: nil, initialTitle: "", initialURL: "https://")
        })

        let recents = recentItems()
        if !recents.isEmpty {
            alert.addAction(UIAlertAction(title: "🕒 Elegir de visitados recientemente...", style: .default) { [weak self] _ in
                self?.presentRecentToBookmarkPicker(items: recents)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    private func presentRecentToBookmarkPicker(items: [HistoryItem]) {
        let alert = UIAlertController(
            title: "Añadir desde historial reciente",
            message: "Pulsa una página para fijarla en Favoritos.",
            preferredStyle: .alert
        )
        for item in items.prefix(8) {
            let host = URL(string: item.urlString)?.host?.replacingOccurrences(of: "www.", with: "") ?? item.urlString
            let label = item.title.isEmpty ? host : "\(item.title) (\(host))"
            alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                BrowserStore.shared.addBookmark(title: item.title.isEmpty ? host : item.title, urlString: item.urlString)
                self?.reloadStartPageData()
            })
        }
        alert.addAction(UIAlertAction(title: "Volver", style: .cancel))
        present(alert, animated: true)
    }

    private func presentBookmarkEditor(editingIndex: Int?, initialTitle: String, initialURL: String) {
        let isEditing = (editingIndex != nil)
        let alert = UIAlertController(
            title: isEditing ? "Editar acceso directo" : "Nuevo acceso directo",
            message: "Introduce el nombre visible y la dirección web.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Nombre (ej. YouTube, Marca, Netflix...)"
            tf.text = initialTitle
            tf.autocapitalizationType = .words
        }
        alert.addTextField { tf in
            tf.placeholder = "https://www.ejemplo.com"
            tf.text = initialURL
            tf.keyboardType = .URL
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Guardar", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let fields = alert?.textFields else { return }
            let rawTitle = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var rawURL = fields[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawURL.isEmpty, rawURL != "https://", rawURL != "http://" else { return }
            if !rawURL.lowercased().hasPrefix("http://") && !rawURL.lowercased().hasPrefix("https://") {
                rawURL = "https://" + rawURL
            }
            let hostFallback = URL(string: rawURL)?.host?.replacingOccurrences(of: "www.", with: "") ?? rawURL
            let finalTitle = rawTitle.isEmpty ? hostFallback : rawTitle
            if let idx = editingIndex {
                BrowserStore.shared.updateBookmark(at: idx, title: finalTitle, urlString: rawURL)
            } else {
                BrowserStore.shared.addBookmark(title: finalTitle, urlString: rawURL)
            }
            self.reloadStartPageData()
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
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
        case .favorites: return BrowserStore.shared.bookmarks.count + 1
        case .recent: return recentItems().count
        }
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: StartPageHeaderView.reuseId, for: indexPath) as! StartPageHeaderView
        switch activeSections[indexPath.section] {
        case .webApps:
            header.titleLabel.text = isEditingShortcuts
                ? "WebApps · Pulsa cualquiera para eliminarla o configurar auto-inicio"
                : "WebApps (Pantalla completa) · Mantén OK para opciones"
        case .favorites:
            header.titleLabel.text = isEditingShortcuts
                ? "Modo Edición · Pulsa un favorito para editarlo, moverlo o eliminarlo"
                : "Favoritos · Accesos directos (Mantén OK o pulsa 'Editar accesos')"
        case .recent:
            header.titleLabel.text = "Visitados recientemente (Mantén OK para guardar en Favoritos)"
        }
        return header
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StartPageTileCell.reuseId, for: indexPath) as! StartPageTileCell
        switch activeSections[indexPath.section] {
        case .webApps:
            let app = BrowserStore.shared.webApps[indexPath.item]
            let badge = isEditingShortcuts ? "✕ EDITAR" : (app.autoLaunch ? "AUTO" : "APP")
            let badgeColor: UIColor = isEditingShortcuts ? .systemRed : .systemIndigo
            cell.configure(title: app.title, urlString: app.urlString, badge: badge, badgeColor: badgeColor, tint: .systemIndigo)
        case .favorites:
            if indexPath.item >= BrowserStore.shared.bookmarks.count {
                cell.configureAddTile()
            } else {
                let bm = BrowserStore.shared.bookmarks[indexPath.item]
                let badge = isEditingShortcuts ? "✕ EDITAR" : nil
                cell.configure(title: bm.title, urlString: bm.urlString, badge: badge, badgeColor: .systemRed, tint: .systemBlue)
            }
        case .recent:
            let hist = recentItems()[indexPath.item]
            cell.configure(title: hist.title, urlString: hist.urlString, badge: nil, badgeColor: .systemTeal, tint: .systemTeal)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch activeSections[indexPath.section] {
        case .webApps:
            if isEditingShortcuts {
                presentWebAppOptions(at: indexPath.item)
            } else {
                let app = BrowserStore.shared.webApps[indexPath.item]
                onSelectWebApp?(app)
            }
        case .favorites:
            if indexPath.item >= BrowserStore.shared.bookmarks.count {
                presentAddShortcutMenu()
            } else if isEditingShortcuts {
                presentFavoriteOptions(at: indexPath.item)
            } else {
                let bm = BrowserStore.shared.bookmarks[indexPath.item]
                if let url = URL(string: bm.urlString) { onSelectURL?(url) }
            }
        case .recent:
            let hist = recentItems()[indexPath.item]
            if isEditingShortcuts {
                presentOptionsForItem(at: indexPath)
            } else if let url = URL(string: hist.urlString) {
                onSelectURL?(url)
            }
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
    private var unfocusedCardBackground = UIColor.white.withAlphaComponent(0.10)

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = unfocusedCardBackground
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

    func configure(title: String, urlString: String, badge: String?, badgeColor: UIColor, tint: UIColor) {
        let host = URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
        let letter = String((host.first ?? title.first ?? "W")).uppercased()
        unfocusedCardBackground = UIColor.white.withAlphaComponent(0.10)
        iconBadge.text = letter
        iconBadge.backgroundColor = tint
        titleLabel.text = title
        hostLabel.text = host
        if let badge = badge {
            tagLabel.isHidden = false
            tagLabel.backgroundColor = badgeColor
            tagLabel.text = " \(badge) "
        } else {
            tagLabel.isHidden = true
        }
        if !isFocused {
            card.backgroundColor = unfocusedCardBackground
        }
    }

    func configureAddTile() {
        unfocusedCardBackground = UIColor.systemBlue.withAlphaComponent(0.18)
        iconBadge.text = "+"
        iconBadge.backgroundColor = .systemBlue
        titleLabel.text = "Añadir acceso"
        hostLabel.text = "Página actual o URL"
        tagLabel.isHidden = false
        tagLabel.backgroundColor = .systemBlue
        tagLabel.text = " NUEVO "
        if !isFocused {
            card.backgroundColor = unfocusedCardBackground
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
                self.card.backgroundColor = self.unfocusedCardBackground
                self.card.layer.borderColor = UIColor.clear.cgColor
                self.titleLabel.textColor = .white
                self.hostLabel.textColor = UIColor.white.withAlphaComponent(0.6)
            }
        }, completion: nil)
    }
}
