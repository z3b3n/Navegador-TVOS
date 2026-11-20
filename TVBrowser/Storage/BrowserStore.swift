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

enum SearchEngineOption: String, Codable, CaseIterable {
    case google
    case duckDuckGo
    case bing

    var displayName: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing: return "Bing"
        }
    }

    func searchURL(for query: String) -> URL? {
        let base: String
        switch self {
        case .google: base = "https://www.google.com/search"
        case .duckDuckGo: base = "https://duckduckgo.com/"
        case .bing: base = "https://www.bing.com/search"
        }
        var comps = URLComponents(string: base)
        comps?.queryItems = [URLQueryItem(name: "q", value: query)]
        return comps?.url
    }
}

struct WebAppItem: Codable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var userAgentModeRaw: Int
    var zoom: Double
    var adBlockEnabled: Bool
    var autoLaunch: Bool
    let createdAt: Date

    var userAgentMode: TVUserAgentMode {
        get { TVUserAgentMode(rawValue: userAgentModeRaw) ?? .desktopMac }
        set { userAgentModeRaw = newValue.rawValue }
    }
}

final class BrowserStore {
    static let shared = BrowserStore()

    private let bookmarksKey = "tvbrowser_bookmarks_v1"
    private let historyKey = "tvbrowser_history_v1"
    private let webAppsKey = "tvbrowser_webapps_v1"
    private let zoomKey = "tvbrowser_zoom_v1"
    private let userAgentKey = "tvbrowser_ua_mode_v1"
    private let searchEngineKey = "tvbrowser_search_engine_v1"
    private let keychainService = "com.local.tvbrowser.credentials"
    private let keychainAccount = "saved_credentials_json"
    private let maxHistoryCount = 150

    private(set) var bookmarks: [BookmarkItem] = []
    private(set) var history: [HistoryItem] = []
    private(set) var webApps: [WebAppItem] = []
    private(set) var credentials: [SavedCredential] = []

    var pageZoom: Double {
        get {
            let val = UserDefaults.standard.double(forKey: zoomKey)
            return val > 0 ? val : 1.25
        }
        set {
            let clamped = max(0.75, min(2.2, newValue))
            UserDefaults.standard.set(clamped, forKey: zoomKey)
        }
    }

    var defaultUserAgentMode: TVUserAgentMode {
        get {
            let raw = UserDefaults.standard.object(forKey: userAgentKey) as? Int ?? 0
            return TVUserAgentMode(rawValue: raw) ?? .desktopMac
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userAgentKey)
        }
    }

    var searchEngine: SearchEngineOption {
        get {
            guard let raw = UserDefaults.standard.string(forKey: searchEngineKey),
                  let val = SearchEngineOption(rawValue: raw) else {
                return .google
            }
            return val
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: searchEngineKey)
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
                BookmarkItem(title: "YouTube", urlString: "https://www.youtube.com"),
                BookmarkItem(title: "DuckDuckGo", urlString: "https://duckduckgo.com"),
                BookmarkItem(title: "Wikipedia", urlString: "https://es.wikipedia.org"),
                BookmarkItem(title: "GitHub", urlString: "https://github.com")
            ]
            saveBookmarks()
        }

        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            history = decoded
        }

        if let data = UserDefaults.standard.data(forKey: webAppsKey),
           let decoded = try? JSONDecoder().decode([WebAppItem].self, from: data) {
            webApps = decoded
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

    func removeBookmark(urlString: String) {
        bookmarks.removeAll { $0.urlString == urlString }
        saveBookmarks()
    }

    func isBookmarked(urlString: String) -> Bool {
        bookmarks.contains { $0.urlString == urlString }
    }

    @discardableResult
    func importBookmarksHTML(_ html: String) -> Int {
        let pattern = #"<A[^>]*HREF\s*=\s*"([^"]+)"[^>]*>(.*?)</A>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return 0
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)
        var added = 0
        for m in matches {
            guard let hrefRange = Range(m.range(at: 1), in: html),
                  let titleRange = Range(m.range(at: 2), in: html) else { continue }
            let rawURL = String(html[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme) else { continue }
            let rawTitle = String(html[titleRange])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !isBookmarked(urlString: url.absoluteString) {
                bookmarks.append(BookmarkItem(title: rawTitle.isEmpty ? (url.host ?? url.absoluteString) : rawTitle, urlString: url.absoluteString))
                added += 1
            }
        }
        if added > 0 { saveBookmarks() }
        return added
    }

    // MARK: - WebApps

    var autoLaunchWebApp: WebAppItem? {
        webApps.first { $0.autoLaunch }
    }

    func saveWebApp(
        title: String,
        urlString: String,
        userAgentMode: TVUserAgentMode,
        zoom: Double,
        adBlockEnabled: Bool,
        autoLaunch: Bool
    ) -> WebAppItem {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? (URL(string: urlString)?.host ?? urlString) : cleanTitle
        if autoLaunch {
            for i in webApps.indices { webApps[i].autoLaunch = false }
        }
        if let idx = webApps.firstIndex(where: { $0.urlString == urlString }) {
            var existing = webApps[idx]
            existing.title = finalTitle
            existing.userAgentMode = userAgentMode
            existing.zoom = zoom
            existing.adBlockEnabled = adBlockEnabled
            existing.autoLaunch = autoLaunch
            webApps[idx] = existing
            saveWebApps()
            return existing
        }
        let item = WebAppItem(
            id: UUID(),
            title: finalTitle,
            urlString: urlString,
            userAgentModeRaw: userAgentMode.rawValue,
            zoom: zoom,
            adBlockEnabled: adBlockEnabled,
            autoLaunch: autoLaunch,
            createdAt: Date()
        )
        webApps.insert(item, at: 0)
        saveWebApps()
        return item
    }

    func toggleAutoLaunch(webAppID: UUID) {
        guard let targetIdx = webApps.firstIndex(where: { $0.id == webAppID }) else { return }
        let nextState = !webApps[targetIdx].autoLaunch
        for i in webApps.indices { webApps[i].autoLaunch = false }
        webApps[targetIdx].autoLaunch = nextState
        saveWebApps()
    }

    func removeWebApp(id: UUID) {
        webApps.removeAll { $0.id == id }
        saveWebApps()
    }

    // MARK: - History

    func recordHistory(title: String, urlString: String) {
        guard !urlString.isEmpty,
              urlString != "about:blank",
              !urlString.hasPrefix("data:") else { return }
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

    func recentUniqueHistory(limit: Int = 8) -> [HistoryItem] {
        var seen = Set<String>()
        var result: [HistoryItem] = []
        for item in history {
            if !seen.contains(item.urlString) {
                seen.insert(item.urlString)
                result.append(item)
                if result.count >= limit { break }
            }
        }
        return result
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

    private func saveWebApps() {
        if let data = try? JSONEncoder().encode(webApps) {
            UserDefaults.standard.set(data, forKey: webAppsKey)
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
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
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
