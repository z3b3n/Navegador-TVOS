import UIKit

private final class BookmarkSubtitleCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class BookmarksViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onSelectURL: ((URL) -> Void)?
    var onSaveAsWebApp: ((BookmarkItem) -> Void)?
    var onDismiss: (() -> Void)?

    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let closeButton = UIButton(type: .custom)
    private let emptyLabel = UILabel()
    private let topFocusGuide = UIFocusGuide()
    private let bottomFocusGuide = UIFocusGuide()

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        BrowserStore.shared.bookmarks.isEmpty ? [closeButton] : [tableView]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1.0)

        setupHeader()
        setupTableView()
        setupFocusGuides()
        updateEmptyState()

        let menuTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menuTap)
    }

    private func setupHeader() {
        let titleLabel = UILabel()
        titleLabel.text = "Marcadores"
        titleLabel.font = .systemFont(ofSize: 38, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let hintLabel = UILabel()
        hintLabel.text = "Selecciona para abrir · Mantén pulsado Seleccionar para opciones"
        hintLabel.font = .systemFont(ofSize: 20, weight: .regular)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        closeButton.setTitle("Cerrar", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .semibold)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 26, bottom: 12, right: 26)
        closeButton.layer.cornerRadius = 14
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .primaryActionTriggered)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 72),

            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            hintLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -72)
        ])
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(BookmarkSubtitleCell.self, forCellReuseIdentifier: "BookmarkCell")

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        tableView.addGestureRecognizer(longPress)

        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No tienes marcadores guardados todavía."
        emptyLabel.font = .systemFont(ofSize: 26, weight: .medium)
        emptyLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        emptyLabel.textAlignment = .center
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 126),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 48),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -48),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupFocusGuides() {
        view.addLayoutGuide(topFocusGuide)
        topFocusGuide.preferredFocusEnvironments = [closeButton]
        NSLayoutConstraint.activate([
            topFocusGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topFocusGuide.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor),
            topFocusGuide.bottomAnchor.constraint(equalTo: tableView.topAnchor)
        ])

        view.addLayoutGuide(bottomFocusGuide)
        bottomFocusGuide.preferredFocusEnvironments = [tableView]
        NSLayoutConstraint.activate([
            bottomFocusGuide.topAnchor.constraint(equalTo: closeButton.bottomAnchor),
            bottomFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomFocusGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFocusGuide.bottomAnchor.constraint(equalTo: tableView.topAnchor)
        ])
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !BrowserStore.shared.bookmarks.isEmpty
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

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let cell = view.window?.windowScene?.focusSystem?.focusedItem as? UITableViewCell,
              let indexPath = tableView.indexPath(for: cell),
              BrowserStore.shared.bookmarks.indices.contains(indexPath.row) else { return }

        let item = BrowserStore.shared.bookmarks[indexPath.row]
        let alert = UIAlertController(title: item.title, message: item.urlString, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Abrir", style: .default) { [weak self] _ in
            if let url = URL(string: item.urlString) {
                self?.dismiss(animated: true) {
                    self?.onSelectURL?(url)
                }
            }
        })
        alert.addAction(UIAlertAction(title: "Guardar como WebApp", style: .default) { [weak self] _ in
            self?.dismiss(animated: true) {
                self?.onSaveAsWebApp?(item)
            }
        })
        alert.addAction(UIAlertAction(title: "Eliminar marcador", style: .destructive) { [weak self] _ in
            BrowserStore.shared.removeBookmark(at: indexPath.row)
            self?.tableView.deleteRows(at: [indexPath], with: .automatic)
            self?.updateEmptyState()
            if BrowserStore.shared.bookmarks.isEmpty {
                self?.setNeedsFocusUpdate()
                self?.updateFocusIfNeeded()
            }
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        BrowserStore.shared.bookmarks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BookmarkCell", for: indexPath)
        let item = BrowserStore.shared.bookmarks[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.urlString
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = BrowserStore.shared.bookmarks[indexPath.row]
        if let url = URL(string: item.urlString) {
            dismiss(animated: true) { [weak self] in
                self?.onSelectURL?(url)
            }
        }
    }
}
