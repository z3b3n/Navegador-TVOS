import Foundation

final class AdBlocker {
    static let shared = AdBlocker()

    var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "tvbrowser_adblock_enabled")
        }
    }

    private let allowedAuthHosts: Set<String> = [
        "accounts.google.com",
        "accounts.youtube.com",
        "myaccount.google.com",
        "apis.google.com",
        "ssl.gstatic.com",
        "www.gstatic.com",
        "ogs.google.com"
    ]

    private let blockedHosts: [String] = [
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
        "admob.com",
        "taboola.com",
        "moatads.com",
        "adsafeprotected.com",
        "2mdn.net",
        "yieldmo.com",
        "sharethrough.com",
        "smartadserver.com",
        "adform.net",
        "popunder.net"
    ]

    private let blockedHostSet: Set<String>

    private init() {
        blockedHostSet = Set(blockedHosts)
        if UserDefaults.standard.object(forKey: "tvbrowser_adblock_enabled") != nil {
            isEnabled = UserDefaults.standard.bool(forKey: "tvbrowser_adblock_enabled")
        }
    }

    func shouldAllow(url: URL) -> Bool {
        guard isEnabled else { return true }
        guard let host = url.host?.lowercased() else { return true }

        if allowedAuthHosts.contains(host) {
            return true
        }
        if blockedHostSet.contains(host) {
            return false
        }
        for blocked in blockedHostSet where host.hasSuffix("." + blocked) {
            return false
        }
        return true
    }

    /// Generates Safari-compatible WKContentRuleList JSON for network-level blocking.
    var contentRuleListJSON: String? {
        guard isEnabled else { return nil }
        var rules: [[String: Any]] = []
        for host in blockedHostSet.sorted() {
            let escaped = NSRegularExpression.escapedPattern(for: host)
            rules.append([
                "trigger": [
                    "url-filter": "^https?://([^/]+\\.)?\(escaped)(:|/|$)",
                    "load-type": ["third-party"]
                ],
                "action": ["type": "block"]
            ])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    var cosmeticAndPopupScript: String {
        guard isEnabled else { return "" }
        return """
        (function() {
            if (window.__tvBrowserAdBlockApplied) return;
            window.__tvBrowserAdBlockApplied = true;

            var host = (window.location && window.location.hostname || '').toLowerCase();
            var isAuthHost = host.indexOf('accounts.google.') !== -1 ||
                             host.indexOf('myaccount.google.') !== -1 ||
                             host.indexOf('login.microsoftonline.') !== -1 ||
                             host.indexOf('github.com') !== -1;

            if (!isAuthHost && window.open) {
                var origOpen = window.open.bind(window);
                window.open = function(url, target, features) {
                    var lastClick = window.__tvBrowserLastClick || 0;
                    try {
                        if (!lastClick && window.top && window.top.__tvBrowserLastClick) {
                            lastClick = window.top.__tvBrowserLastClick;
                        }
                    } catch (e) {}
                    var recentClick = lastClick && (Date.now() - lastClick) < 3000;
                    if (recentClick) {
                        return origOpen(url, target, features);
                    }
                    if (typeof url === 'string' && url.indexOf('accounts.google.com') !== -1) {
                        return origOpen(url, target, features);
                    }
                    return null;
                };
            }

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
                .sponsored-content {
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
