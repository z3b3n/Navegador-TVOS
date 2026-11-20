import UIKit

private final class BookmarkSubtitleCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class BookmarksViewController: UITableViewController {
    var onSelectURL: ((URL) -> Void)?
    var onSaveAsWebApp: ((BookmarkItem) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Marcadores"
        tableView.register(BookmarkSubtitleCell.self, forCellReuseIdentifier: "BookmarkCell")

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        tableView.addGestureRecognizer(longPress)

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

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let cell = UIScreen.main.focusedView as? UITableViewCell,
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
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        BrowserStore.shared.bookmarks.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BookmarkCell", for: indexPath)
        let item = BrowserStore.shared.bookmarks[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.urlString
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = BrowserStore.shared.bookmarks[indexPath.row]
        if let url = URL(string: item.urlString) {
            dismiss(animated: true) { [weak self] in
                self?.onSelectURL?(url)
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
