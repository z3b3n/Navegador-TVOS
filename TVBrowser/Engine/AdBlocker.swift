import Foundation

final class AdBlocker {
    static let shared = AdBlocker()

    var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "tvbrowser_adblock_enabled")
        }
    }

    private let blockedHosts: Set<String> = [
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "adservice.google.com",
        "pagead2.googlesyndication.com",
        "adnxs.com",
        "adsrvr.org",
        "criteo.com",
        "outbrain.com",
        "taboola.com",
        "pubmatic.com",
        "rubiconproject.com",
        "openx.net",
        "popads.net",
        "popcash.net",
        "propellerads.com",
        "adsterra.com",
        "exoclick.com",
        "trafficjunky.net",
        "juicyads.com",
        "mgid.com",
        "revcontent.com",
        "zedo.com",
        "scorecardresearch.com",
        "quantserve.com",
        "amazon-adsystem.com",
        "media.net",
        "bidswitch.net",
        "casalemedia.com",
        "advertising.com",
        "admob.com"
    ]

    private init() {
        if UserDefaults.standard.object(forKey: "tvbrowser_adblock_enabled") != nil {
            isEnabled = UserDefaults.standard.bool(forKey: "tvbrowser_adblock_enabled")
        }
    }

    func shouldAllow(url: URL) -> Bool {
        guard isEnabled else { return true }
        guard let host = url.host?.lowercased() else { return true }

        if blockedHosts.contains(host) {
            return false
        }
        for blocked in blockedHosts where host.hasSuffix("." + blocked) {
            return false
        }
        return true
    }

    var cosmeticAndPopupScript: String {
        guard isEnabled else { return "" }
        return """
        (function() {
            if (window.__tvBrowserAdBlockApplied) return;
            window.__tvBrowserAdBlockApplied = true;

            // Block pop-ups via window.open
            window.open = function() { return null; };

            // Hide common ad containers
            var css = `
                ins.adsbygoogle,
                [id*="google_ads"],
                [id*="ad-container"],
                [id*="ad_container"],
                [class*="ad-banner"],
                [class*="ad_banner"],
                [class*="adsbox"],
                iframe[src*="doubleclick"],
                iframe[src*="googlesyndication"],
                .sponsored-content,
                .popup-overlay {
                    display: none !important;
                    visibility: hidden !important;
                    pointer-events: none !important;
                }
            `;
            var style = document.createElement('style');
            style.type = 'text/css';
            style.appendChild(document.createTextNode(css));
            (document.head || document.documentElement).appendChild(style);
        })();
        """
    }
}
