import Foundation

struct BookmarkItem: Codable, Equatable {
    let title: String
    let urlString: String
}

struct HistoryItem: Codable, Equatable {
    let title: String
    let urlString: String
    let visitedAt: Date
}

final class BrowserStore {
    static let shared = BrowserStore()

    private let bookmarksKey = "tvbrowser_bookmarks_v1"
    private let historyKey = "tvbrowser_history_v1"
    private let maxHistoryCount = 100

    private(set) var bookmarks: [BookmarkItem] = []
    private(set) var history: [HistoryItem] = []

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
                BookmarkItem(title: "DuckDuckGo", urlString: "https://duckduckgo.com"),
                BookmarkItem(title: "YouTube", urlString: "https://www.youtube.com"),
                BookmarkItem(title: "Wikipedia", urlString: "https://es.wikipedia.org"),
                BookmarkItem(title: "GitHub", urlString: "https://github.com")
            ]
            saveBookmarks()
        }

        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            history = decoded
        }
    }

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
}
