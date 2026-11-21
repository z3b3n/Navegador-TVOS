import UIKit

private final class HistorySubtitleCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class HistoryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onSelectURL: ((URL) -> Void)?
    var onDismiss: (() -> Void)?

    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let clearButton = UIButton(type: .custom)
    private let closeButton = UIButton(type: .custom)
    private let emptyLabel = UILabel()
    private let topFocusGuide = UIFocusGuide()
    private let bottomFocusGuide = UIFocusGuide()

    private let formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        BrowserStore.shared.history.isEmpty ? [closeButton] : [tableView]
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
        titleLabel.text = "Historial"
        titleLabel.font = .systemFont(ofSize: 38, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        clearButton.setTitle("Borrar todo", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .semibold)
        clearButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        clearButton.layer.cornerRadius = 14
        clearButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.32)
        clearButton.setTitleColor(.white, for: .normal)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearTapped), for: .primaryActionTriggered)
        view.addSubview(clearButton)

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

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -72),

            clearButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -16)
        ])
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(HistorySubtitleCell.self, forCellReuseIdentifier: "HistoryCell")
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "El historial está vacío."
        emptyLabel.font = .systemFont(ofSize: 26, weight: .medium)
        emptyLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        emptyLabel.textAlignment = .center
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 118),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 48),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -48),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupFocusGuides() {
        view.addLayoutGuide(topFocusGuide)
        topFocusGuide.preferredFocusEnvironments = [clearButton, closeButton]
        NSLayoutConstraint.activate([
            topFocusGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topFocusGuide.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor),
            topFocusGuide.bottomAnchor.constraint(equalTo: tableView.topAnchor)
        ])

        view.addLayoutGuide(bottomFocusGuide)
        bottomFocusGuide.preferredFocusEnvironments = [tableView]
        NSLayoutConstraint.activate([
            bottomFocusGuide.topAnchor.constraint(equalTo: closeButton.bottomAnchor),
            bottomFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomFocusGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFocusGuide.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func updateEmptyState() {
        let isEmpty = BrowserStore.shared.history.isEmpty
        emptyLabel.isHidden = !isEmpty
        clearButton.isEnabled = !isEmpty
        clearButton.alpha = isEmpty ? 0.35 : 1.0
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations({
            for btn in [self.clearButton, self.closeButton] {
                if context.nextFocusedView === btn {
                    btn.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
                    btn.backgroundColor = .white
                    btn.setTitleColor(.black, for: .normal)
                } else if context.previouslyFocusedView === btn {
                    btn.transform = .identity
                    btn.backgroundColor = (btn === self.clearButton)
                        ? UIColor.systemRed.withAlphaComponent(0.32)
                        : UIColor.white.withAlphaComponent(0.16)
                    btn.setTitleColor(.white, for: .normal)
                }
            }
        }, completion: nil)
    }

    @objc private func clearTapped() {
        let alert = UIAlertController(
            title: "¿Borrar todo el historial?",
            message: "Esta acción no se puede deshacer.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Borrar", style: .destructive) { [weak self] _ in
            BrowserStore.shared.clearHistory()
            self?.tableView.reloadData()
            self?.updateEmptyState()
            self?.setNeedsFocusUpdate()
            self?.updateFocusIfNeeded()
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        BrowserStore.shared.history.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath)
        let item = BrowserStore.shared.history[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = "\(item.urlString) · \(formatter.string(from: item.visitedAt))"
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = BrowserStore.shared.history[indexPath.row]
        if let url = URL(string: item.urlString) {
            dismiss(animated: true) { [weak self] in
                self?.onSelectURL?(url)
            }
        }
    }
}
