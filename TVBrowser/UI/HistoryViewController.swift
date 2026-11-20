import UIKit

private final class HistorySubtitleCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class HistoryViewController: UITableViewController {
    var onSelectURL: ((URL) -> Void)?

    private let formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Historial"
        tableView.register(HistorySubtitleCell.self, forCellReuseIdentifier: "HistoryCell")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Borrar todo",
            style: .plain,
            target: self,
            action: #selector(clearTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Cerrar",
            style: .done,
            target: self,
            action: #selector(closeTapped)
        )
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
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        BrowserStore.shared.history.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath)
        let item = BrowserStore.shared.history[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = "\(item.urlString) · \(formatter.string(from: item.visitedAt))"
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = BrowserStore.shared.history[indexPath.row]
        if let url = URL(string: item.urlString) {
            dismiss(animated: true) { [weak self] in
                self?.onSelectURL?(url)
            }
        }
    }
}
