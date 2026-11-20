import UIKit

final class BrowserTab {
    let id = UUID()
    let engine: TVWebEngine
    var webApp: WebAppItem?
    var title: String
    var url: URL?
    var isLoading = false
    var estimatedProgress: Double = 0
    var userAgentMode: TVUserAgentMode
    var zoom: Double
    var adBlockEnabled: Bool
    var detectedVideoURL: URL?
    var showingStartPage: Bool

    var isAppMode: Bool { webApp != nil }

    init(
        frame: CGRect,
        runtimeConfiguration: Any? = nil,
        webApp: WebAppItem? = nil,
        showingStartPage: Bool = false
    ) {
        self.webApp = webApp
        self.showingStartPage = showingStartPage
        self.userAgentMode = webApp?.userAgentMode ?? BrowserStore.shared.defaultUserAgentMode
        self.zoom = webApp?.zoom ?? BrowserStore.shared.pageZoom
        self.adBlockEnabled = webApp?.adBlockEnabled ?? AdBlocker.shared.isEnabled
        self.title = webApp?.title ?? (showingStartPage ? "Inicio" : "Nueva pestaña")

        if let config = runtimeConfiguration {
            self.engine = TVWebEngine(frame: frame, runtimeConfiguration: config)
        } else {
            self.engine = TVWebEngine(frame: frame)
        }
        self.engine.userAgentMode = self.userAgentMode
    }
}
