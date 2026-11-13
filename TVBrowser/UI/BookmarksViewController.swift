import UIKit

final class BookmarksViewController: UITableViewController {
    var onSelectURL: ((URL) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Marcadores"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BookmarkCell")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Cerrar",
            style: .done,
            target: self,
            action: #selector(closeTapped)
        )
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        BrowserStore.shared.bookmarks.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "BookmarkCell")
        let item = BrowserStore.shared.bookmarks[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.urlString
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = BrowserStore.shared.bookmarks[indexPath.row]
        if let url = URL(string: item.urlString) {
            dismiss(animated: true) {
                self.onSelectURL?(url)
            }
        }
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            BrowserStore.shared.removeBookmark(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
}
