import UIKit

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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HistoryCell")

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
        BrowserStore.shared.clearHistory()
        tableView.reloadData()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        BrowserStore.shared.history.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "HistoryCell")
        let item = BrowserStore.shared.history[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = "\(item.urlString) · \(formatter.string(from: item.visitedAt))"
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = BrowserStore.shared.history[indexPath.row]
        if let url = URL(string: item.urlString) {
            dismiss(animated: true) {
                self.onSelectURL?(url)
            }
        }
    }
}
