import Foundation
import Security

struct BookmarkItem: Codable, Equatable {
    let title: String
    let urlString: String
}

struct HistoryItem: Codable, Equatable {
    let title: String
    let urlString: String
    let visitedAt: Date
}

struct SavedCredential: Codable, Equatable {
    let host: String
    let username: String
    let password: String
    let updatedAt: Date
}

final class BrowserStore {
    static let shared = BrowserStore()

    private let bookmarksKey = "tvbrowser_bookmarks_v1"
    private let historyKey = "tvbrowser_history_v1"
    private let zoomKey = "tvbrowser_zoom_v1"
    private let keychainService = "com.local.tvbrowser.credentials"
    private let keychainAccount = "saved_credentials_json"
    private let maxHistoryCount = 100

    private(set) var bookmarks: [BookmarkItem] = []
    private(set) var history: [HistoryItem] = []
    private(set) var credentials: [SavedCredential] = []

    var pageZoom: Double {
        get {
            let val = UserDefaults.standard.double(forKey: zoomKey)
            return val > 0 ? val : 1.3
        }
        set {
            let clamped = max(0.8, min(2.2, newValue))
            UserDefaults.standard.set(clamped, forKey: zoomKey)
        }
    }

    private init() {
        load()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: bookmarksKey),
           let decoded = try? JSONDecoder().decode([BookmarkItem].self, from: data) {
            bookmarks = decoded
        } else {
            bookmarks = [
                BookmarkItem(title: "Google", urlString: "https://www.google.com"),
                BookmarkItem(title: "Cuenta de Google", urlString: "https://accounts.google.com"),
                BookmarkItem(title: "DuckDuckGo", urlString: "https://duckduckgo.com"),
                BookmarkItem(title: "YouTube", urlString: "https://www.youtube.com"),
                BookmarkItem(title: "Wikipedia", urlString: "https://es.wikipedia.org")
            ]
            saveBookmarks()
        }

        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            history = decoded
        }

        credentials = loadCredentialsFromKeychain()
    }

    // MARK: - Bookmarks

    func addBookmark(title: String, urlString: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = cleanTitle.isEmpty ? urlString : cleanTitle
        if let idx = bookmarks.firstIndex(where: { $0.urlString == urlString }) {
            bookmarks.remove(at: idx)
        }
        bookmarks.insert(BookmarkItem(title: displayTitle, urlString: urlString), at: 0)
        saveBookmarks()
    }

    func removeBookmark(at index: Int) {
        guard bookmarks.indices.contains(index) else { return }
        bookmarks.remove(at: index)
        saveBookmarks()
    }

    func isBookmarked(urlString: String) -> Bool {
        bookmarks.contains { $0.urlString == urlString }
    }

    // MARK: - History

    func recordHistory(title: String, urlString: String) {
        guard !urlString.isEmpty, urlString != "about:blank" else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = cleanTitle.isEmpty ? urlString : cleanTitle

        if history.first?.urlString == urlString {
            history[0] = HistoryItem(title: displayTitle, urlString: urlString, visitedAt: Date())
        } else {
            history.insert(HistoryItem(title: displayTitle, urlString: urlString, visitedAt: Date()), at: 0)
        }
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    // MARK: - Credentials (Keychain)

    func saveCredential(host: String, username: String, password: String) {
        let cleanHost = host.lowercased()
        if let idx = credentials.firstIndex(where: { $0.host == cleanHost && $0.username == username }) {
            credentials.remove(at: idx)
        }
        credentials.insert(SavedCredential(host: cleanHost, username: username, password: password, updatedAt: Date()), at: 0)
        saveCredentialsToKeychain(credentials)
    }

    func credentials(forHost host: String) -> [SavedCredential] {
        let h = host.lowercased()
        return credentials.filter { h == $0.host || h.hasSuffix("." + $0.host) || $0.host.hasSuffix("." + h) }
    }

    func removeCredential(at index: Int) {
        guard credentials.indices.contains(index) else { return }
        credentials.remove(at: index)
        saveCredentialsToKeychain(credentials)
    }

    // MARK: - Export Formats

    func exportBookmarksHTML() -> String {
        var lines = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Marcadores TVBrowser</TITLE>",
            "<H1>Marcadores TVBrowser</H1>",
            "<DL><p>"
        ]
        for b in bookmarks {
            let safeTitle = b.title
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let safeURL = b.urlString.replacingOccurrences(of: "\"", with: "%22")
            lines.append("    <DT><A HREF=\"\(safeURL)\">\(safeTitle)</A>")
        }
        lines.append("</DL><p>")
        return lines.joined(separator: "\n")
    }

    func exportBookmarksJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(bookmarks), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }

    func exportCredentialsCSV() -> String {
        var rows = ["name,url,username,password"]
        for c in credentials {
            let esc: (String) -> String = { s in
                "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            rows.append("\(esc(c.host)),\(esc("https://" + c.host)),\(esc(c.username)),\(esc(c.password))")
        }
        return rows.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func saveCredentialsToKeychain(_ items: [SavedCredential]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadCredentialsFromKeychain() -> [SavedCredential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let decoded = try? JSONDecoder().decode([SavedCredential].self, from: data) else {
            return []
        }
        return decoded
    }
}
