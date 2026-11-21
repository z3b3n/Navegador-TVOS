import UIKit
import AVKit
import AVFoundation

private final class FocusSinkView: UIView {
    override var canBecomeFocused: Bool { true }
}

final class BrowserViewController: UIViewController, UIGestureRecognizerDelegate {
    private var tabs: [BrowserTab] = []
    private var activeTabIndex: Int = 0
    private var activeTab: BrowserTab? {
        tabs.indices.contains(activeTabIndex) ? tabs[activeTabIndex] : nil
    }
    private var currentEngine: TVWebEngine? { activeTab?.engine }

    private let focusSinkView = FocusSinkView()
    private let webHostContainer = UIView()
    private let cursorView = VirtualCursorView()
    private let inputController = InputController()
    private var panGesture: UIPanGestureRecognizer?
    private let remoteServer = LocalExportServer()
    private var remoteServerURL: String?
    private var remoteServerRunning = false
    private var connectedRemoteClients = 0
    private weak var activeExportVC: ExportViewController?

    // Compact Safari-style Toolbar
    private let toolbarContainer = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let toolbarStack = UIStackView()
    private let backButton = UIButton(type: .custom)
    private let forwardButton = UIButton(type: .custom)
    private let homeButton = UIButton(type: .custom)
    private let urlButton = UIButton(type: .custom)
    private let zoomOutButton = UIButton(type: .custom)
    private let zoomLevelButton = UIButton(type: .custom)
    private let zoomInButton = UIButton(type: .custom)
    private let reloadButton = UIButton(type: .custom)
    private let bookmarkStarButton = UIButton(type: .custom)
    private let videoButton = UIButton(type: .custom)
    private let tabsButton = UIButton(type: .custom)
    private let moreButton = UIButton(type: .custom)
    private let hideToolbarButton = UIButton(type: .custom)

    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let linkPreviewLabel = UILabel()
    private let toastLabel = UILabel()
    private var toastHideWorkItem: DispatchWorkItem?

    private var toolbarVisible = false
    private var toolbarAutoHideWorkItem: DispatchWorkItem?
    private let toolbarInactivityTimeout: TimeInterval = 6.5
    private var suppressTopEdgeToolbarUntil: CFTimeInterval = 0
    private var lastScrolledDownTime: CFTimeInterval = 0
    private var hasPositionedInitialCursor = false
    private var lastPanPoint: CGPoint = .zero
    private var panStartPoint: CGPoint = .zero
    private var isWebInputFocused = false
    private var cachedCursorOverInnerScroll = false
    private var pendingScrollDelta: CGPoint = .zero
    private var innerScrollInFlight = false
    private var lastHoverCheckTime: CFTimeInterval = 0
    private var hoverCheckScheduled = false
    private var lastFailedURLByTab: [UUID: URL] = [:]

    private let homeSearchURL = URL(string: "https://www.google.com")!

    override var canBecomeFirstResponder: Bool { true }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if toolbarVisible {
            return [urlButton]
        }
        return [focusSinkView]
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "l", modifierFlags: .command, action: #selector(urlTapped)),
            UIKeyCommand(input: "t", modifierFlags: .command, action: #selector(shortcutNewTab)),
            UIKeyCommand(input: "w", modifierFlags: .command, action: #selector(shortcutCloseTab)),
            UIKeyCommand(input: "r", modifierFlags: .command, action: #selector(reloadTapped)),
            UIKeyCommand(input: "[", modifierFlags: .command, action: #selector(backTapped)),
            UIKeyCommand(input: "]", modifierFlags: .command, action: #selector(forwardTapped)),
            UIKeyCommand(input: "=", modifierFlags: .command, action: #selector(zoomInTapped)),
            UIKeyCommand(input: "-", modifierFlags: .command, action: #selector(zoomOutTapped)),
            UIKeyCommand(input: "0", modifierFlags: .command, action: #selector(zoomResetTapped)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(shortcutEscape))
        ]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupFocusSink()
        setupWebHost()
        setupToolbar()
        setupProgressAndOverlays()
        setupCursor()
        setupGestures()
        setupRemoteServer()

        view.layoutIfNeeded()

        inputController.delegate = self
        inputController.start()

        launchInitialTab()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restoreBrowserFocus()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !webHostContainer.bounds.isEmpty {
            for tab in tabs {
                applyViewportTransform(for: tab)
            }
        }
        if view.bounds.width > 100 && view.bounds.height > 100 {
            if !hasPositionedInitialCursor {
                cursorView.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
                hasPositionedInitialCursor = true
            } else {
                let cx = max(8, min(view.bounds.width - 8, cursorView.center.x))
                let cy = max(8, min(view.bounds.height - 8, cursorView.center.y))
                cursorView.center = CGPoint(x: cx, y: cy)
            }
        }
        if !toolbarVisible {
            view.bringSubviewToFront(cursorView)
        }
    }

    deinit {
        inputController.stop()
        remoteServer.stop()
    }

    private func setupFocusSink() {
        focusSinkView.translatesAutoresizingMaskIntoConstraints = false
        focusSinkView.backgroundColor = .clear
        view.addSubview(focusSinkView)
        NSLayoutConstraint.activate([
            focusSinkView.topAnchor.constraint(equalTo: view.topAnchor),
            focusSinkView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            focusSinkView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            focusSinkView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func restoreBrowserFocus() {
        let apply = { [weak self] in
            guard let self = self else { return }
            self.focusSinkView.isHidden = self.toolbarVisible
            self.panGesture?.isEnabled = !self.toolbarVisible && self.presentedViewController == nil
            self.becomeFirstResponder()
            self.setNeedsFocusUpdate()
            self.updateFocusIfNeeded()
            if !self.toolbarVisible {
                self.view.bringSubviewToFront(self.cursorView)
            } else if self.presentedViewController == nil {
                self.scheduleToolbarAutoHide()
            }
        }
        apply()
        DispatchQueue.main.async(execute: apply)
    }

    private func setupWebHost() {
        webHostContainer.translatesAutoresizingMaskIntoConstraints = false
        webHostContainer.backgroundColor = .black
        view.addSubview(webHostContainer)
        NSLayoutConstraint.activate([
            webHostContainer.topAnchor.constraint(equalTo: view.topAnchor),
            webHostContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webHostContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webHostContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupToolbar() {
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.layer.cornerRadius = 22
        toolbarContainer.layer.borderWidth = 1.5
        toolbarContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.20).cgColor
        toolbarContainer.clipsToBounds = true
        toolbarContainer.isHidden = true
        toolbarContainer.alpha = 0
        view.addSubview(toolbarContainer)

        toolbarStack.axis = .horizontal
        toolbarStack.spacing = 10
        toolbarStack.alignment = .center
        toolbarStack.distribution = .fill
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.contentView.addSubview(toolbarStack)

        NSLayoutConstraint.activate([
            toolbarContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            toolbarContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            toolbarContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            toolbarContainer.heightAnchor.constraint(equalToConstant: 98),

            toolbarStack.topAnchor.constraint(equalTo: toolbarContainer.contentView.topAnchor, constant: 12),
            toolbarStack.bottomAnchor.constraint(equalTo: toolbarContainer.contentView.bottomAnchor, constant: -12),
            toolbarStack.leadingAnchor.constraint(equalTo: toolbarContainer.contentView.leadingAnchor, constant: 16),
            toolbarStack.trailingAnchor.constraint(equalTo: toolbarContainer.contentView.trailingAnchor, constant: -16)
        ])

        configureButton(backButton, title: "◀", action: #selector(backTapped))
        configureButton(forwardButton, title: "▶", action: #selector(forwardTapped))
        configureButton(homeButton, title: "⌂ Inicio", action: #selector(homeTapped))

        configureButton(urlButton, title: "🔍 Buscar o escribir URL", action: #selector(urlTapped), accent: true)
        urlButton.contentHorizontalAlignment = .center
        urlButton.titleLabel?.lineBreakMode = .byTruncatingMiddle
        urlButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        urlButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        urlButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        configureButton(zoomOutButton, title: "A-", action: #selector(zoomOutTapped), horizontalInset: 14)
        configureButton(zoomLevelButton, title: "100%", action: #selector(presentZoomPresetPicker), horizontalInset: 14)
        configureButton(zoomInButton, title: "A+", action: #selector(zoomInTapped), horizontalInset: 14)

        configureButton(reloadButton, title: "↻", action: #selector(reloadTapped), horizontalInset: 14)
        configureButton(bookmarkStarButton, title: "☆", action: #selector(toggleBookmarkTapped), horizontalInset: 14)
        configureButton(videoButton, title: "📺 Vídeo", action: #selector(playDetectedVideoTapped), horizontalInset: 14)
        videoButton.isHidden = true

        configureButton(tabsButton, title: "❏ 1", action: #selector(tabsTapped), horizontalInset: 14)
        configureButton(moreButton, title: "⋯ Menú", action: #selector(moreTapped), horizontalInset: 14)
        configureButton(hideToolbarButton, title: "Listo", action: #selector(hideToolbarTapped), horizontalInset: 16)

        [
            backButton, forwardButton, homeButton,
            urlButton,
            zoomOutButton, zoomLevelButton, zoomInButton,
            reloadButton, bookmarkStarButton, videoButton,
            tabsButton, moreButton, hideToolbarButton
        ].forEach { toolbarStack.addArrangedSubview($0) }
    }

    private func configureButton(_ button: UIButton, title: String, action: Selector, accent: Bool = false, horizontalInset: CGFloat = 18) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 25, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: horizontalInset, bottom: 12, right: horizontalInset)
        button.layer.cornerRadius = 14
        button.backgroundColor = accent ? UIColor.systemBlue.withAlphaComponent(0.55) : UIColor.white.withAlphaComponent(0.14)
        button.setTitleColor(.white, for: .normal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(self, action: action, for: .primaryActionTriggered)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations({
            if let prev = context.previouslyFocusedView as? UIButton, prev.isDescendant(of: self.toolbarContainer) {
                prev.transform = .identity
                prev.backgroundColor = (prev == self.urlButton)
                    ? UIColor.systemBlue.withAlphaComponent(0.55)
                    : UIColor.white.withAlphaComponent(0.14)
                prev.setTitleColor(.white, for: .normal)
            }
            if let next = context.nextFocusedView as? UIButton, next.isDescendant(of: self.toolbarContainer) {
                next.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
                next.backgroundColor = .white
                next.setTitleColor(.black, for: .normal)
            }
        }, completion: nil)
        if toolbarVisible,
           presentedViewController == nil,
           let next = context.nextFocusedView,
           next.isDescendant(of: toolbarContainer) {
            scheduleToolbarAutoHide()
        }
    }

    private func setupProgressAndOverlays() {
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.progressTintColor = .systemBlue
        progressBar.trackTintColor = .clear
        progressBar.alpha = 0
        view.addSubview(progressBar)

        linkPreviewLabel.translatesAutoresizingMaskIntoConstraints = false
        linkPreviewLabel.backgroundColor = UIColor.black.withAlphaComponent(0.80)
        linkPreviewLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        linkPreviewLabel.font = .systemFont(ofSize: 19, weight: .medium)
        linkPreviewLabel.layer.cornerRadius = 10
        linkPreviewLabel.clipsToBounds = true
        linkPreviewLabel.lineBreakMode = .byTruncatingMiddle
        linkPreviewLabel.isHidden = true
        view.addSubview(linkPreviewLabel)

        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.84)
        toastLabel.textColor = .white
        toastLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        toastLabel.textAlignment = .center
        toastLabel.layer.cornerRadius = 16
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0
        view.addSubview(toastLabel)

        NSLayoutConstraint.activate([
            progressBar.topAnchor.constraint(equalTo: view.topAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 4),

            linkPreviewLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            linkPreviewLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            linkPreviewLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 820),
            linkPreviewLabel.heightAnchor.constraint(equalToConstant: 36),

            toastLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func setupCursor() {
        let fallbackBounds = view.bounds.isEmpty ? UIScreen.main.bounds : view.bounds
        cursorView.center = CGPoint(x: fallbackBounds.midX, y: fallbackBounds.midY)
        view.addSubview(cursorView)
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = self
        view.addGestureRecognizer(pan)
        panGesture = pan
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        !toolbarVisible && presentedViewController == nil
    }

    private func showToast(_ text: String, duration: TimeInterval = 1.6) {
        toastHideWorkItem?.cancel()
        toastLabel.text = "   \(text)   "
        UIView.animate(withDuration: 0.15) {
            self.toastLabel.alpha = 1
        }
        let item = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.25) {
                self?.toastLabel.alpha = 0
            }
        }
        toastHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    // MARK: - Tabs & Startup

    private func launchInitialTab() {
        if let autoApp = BrowserStore.shared.autoLaunchWebApp,
           let url = URL(string: autoApp.urlString) {
            openTab(url: url, webApp: autoApp, switchToIt: true)
            showToast("WebApp: \(autoApp.title) (Mantén OK o Menú para opciones)", duration: 3.0)
        } else {
            openTab(url: homeSearchURL, webApp: nil, switchToIt: true)
            showToast("Arriba: Buscar/Menú · Mantén OK: Menú rápido · Play: Cursor/Scroll", duration: 3.5)
        }
    }

    @discardableResult
    private func openTab(
        url: URL?,
        runtimeConfiguration: Any? = nil,
        webApp: WebAppItem? = nil,
        switchToIt: Bool = true
    ) -> BrowserTab {
        let initialFrame = webHostContainer.bounds.isEmpty
            ? (view.bounds.isEmpty ? UIScreen.main.bounds : view.bounds)
            : webHostContainer.bounds
        let tab = BrowserTab(
            frame: initialFrame,
            runtimeConfiguration: runtimeConfiguration,
            webApp: webApp,
            showingStartPage: false
        )
        tab.engine.delegate = self
        tab.engine.webView.isUserInteractionEnabled = false
        tab.engine.webView.autoresizingMask = []
        tab.engine.webView.isHidden = true
        webHostContainer.addSubview(tab.engine.webView)
        applyPageZoom(for: tab)

        applyAdBlockRuleList(to: tab)
        tabs.append(tab)

        if switchToIt {
            switchToTab(at: tabs.count - 1)
        } else {
            updateToolbarState()
        }

        if let url = url {
            load(url: url, in: tab)
        }
        return tab
    }

    private func switchToTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        isWebInputFocused = false
        cachedCursorOverInnerScroll = false
        cachedPageCanScrollUp = false

        for (i, tab) in tabs.enumerated() {
            tab.engine.webView.isHidden = (i != index)
        }

        if let tab = activeTab {
            if tab.isAppMode {
                setToolbarVisible(false)
            }
            applyPageZoom(for: tab)
        }
        updateToolbarState()
        updateProgressUI()
    }

    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let removed = tabs.remove(at: index)
        removed.engine.delegate = nil
        removed.engine.webView.removeFromSuperview()
        lastFailedURLByTab.removeValue(forKey: removed.id)

        if tabs.isEmpty {
            openTab(url: homeSearchURL, switchToIt: true)
            return
        }
        let nextIndex: Int
        if index < activeTabIndex {
            nextIndex = activeTabIndex - 1
        } else {
            nextIndex = min(activeTabIndex, tabs.count - 1)
        }
        switchToTab(at: nextIndex)
    }

    private func tab(for engine: TVWebEngine) -> BrowserTab? {
        tabs.first { $0.engine === engine }
    }

    private func applyAdBlockRuleList(to tab: BrowserTab) {
        if tab.adBlockEnabled, let json = AdBlocker.shared.contentRuleListJSON {
            tab.engine.installContentRuleList(withJSON: json)
        } else {
            tab.engine.installContentRuleList(withJSON: nil)
        }
    }

    // MARK: - Navigation & URL Handling

    func load(url: URL, in targetTab: BrowserTab? = nil) {
        guard let tab = targetTab ?? activeTab else { return }
        tab.url = url
        tab.detectedVideoURL = nil
        lastFailedURLByTab.removeValue(forKey: tab.id)
        isWebInputFocused = false
        cachedCursorOverInnerScroll = false
        cachedPageCanScrollUp = false
        tab.engine.load(url)
        if tab === activeTab {
            updateToolbarState()
        }
    }

    private func openInputURL(_ raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return }

        if let direct = URL(string: trimmed),
           let scheme = direct.scheme?.lowercased(),
           ["http", "https", "file", "about", "data"].contains(scheme) {
            load(url: direct)
        } else if trimmed.contains("."), !trimmed.contains(" "),
                  let httpsURL = URL(string: "https://" + trimmed) {
            load(url: httpsURL)
        } else if let searchURL = BrowserStore.shared.searchEngine.searchURL(for: trimmed) {
            load(url: searchURL)
        }
    }

    private func applyViewportTransform(for tab: BrowserTab) {
        let hostBounds = webHostContainer.bounds.isEmpty
            ? (view.bounds.isEmpty ? UIScreen.main.bounds : view.bounds)
            : webHostContainer.bounds
        guard !hostBounds.isEmpty else { return }

        let zoom = CGFloat(max(0.75, min(2.5, tab.zoom)))
        let targetBounds = CGRect(
            x: 0,
            y: 0,
            width: hostBounds.width / zoom,
            height: hostBounds.height / zoom
        )
        let targetCenter = CGPoint(x: hostBounds.midX, y: hostBounds.midY)
        let targetTransform = abs(zoom - 1.0) < 0.005
            ? CGAffineTransform.identity
            : CGAffineTransform(scaleX: zoom, y: zoom)

        let webView = tab.engine.webView
        if abs(webView.bounds.width - targetBounds.width) > 0.5 || abs(webView.bounds.height - targetBounds.height) > 0.5 {
            webView.bounds = targetBounds
        }
        if abs(webView.center.x - targetCenter.x) > 0.5 || abs(webView.center.y - targetCenter.y) > 0.5 {
            webView.center = targetCenter
        }
        if abs(webView.transform.a - targetTransform.a) > 0.002 ||
            abs(webView.transform.d - targetTransform.d) > 0.002 ||
            abs(webView.transform.tx) > 0.1 ||
            abs(webView.transform.ty) > 0.1 {
            webView.transform = targetTransform
        }
    }

    private func applyPageZoom(for tab: BrowserTab? = nil) {
        guard let targetTab = tab ?? activeTab else { return }
        applyViewportTransform(for: targetTab)
        let resetCSSZoomJS = """
        (function() {
            var root = document.documentElement;
            if (!root) return;
            if (root.style.zoom) root.style.zoom = '';
            if (root.style.width) root.style.width = '';
            if (root.style.overflowX) root.style.overflowX = '';
            if (root.style.transform) root.style.transform = '';
            if (root.style.transformOrigin) root.style.transformOrigin = '';
            root.style.webkitTextSizeAdjust = '100%';
        })();
        """
        targetTab.engine.evaluateJavaScript(resetCSSZoomJS, completion: nil)
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        cancelToolbarAutoHide()
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }

    private func scheduleToolbarAutoHide() {
        cancelToolbarAutoHide()
        guard toolbarVisible, presentedViewController == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self,
                  self.toolbarVisible,
                  self.presentedViewController == nil else { return }
            self.setToolbarVisible(false)
        }
        toolbarAutoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + toolbarInactivityTimeout, execute: work)
    }

    private func cancelToolbarAutoHide() {
        toolbarAutoHideWorkItem?.cancel()
        toolbarAutoHideWorkItem = nil
    }

    private func setToolbarVisible(_ visible: Bool) {
        guard toolbarVisible != visible else {
            if visible { scheduleToolbarAutoHide() }
            return
        }
        toolbarVisible = visible
        cursorView.isHidden = visible
        panGesture?.isEnabled = !visible && presentedViewController == nil
        focusSinkView.isHidden = visible
        if visible {
            linkPreviewLabel.isHidden = true
            updateToolbarState()
            toolbarContainer.isHidden = false
            view.bringSubviewToFront(toolbarContainer)
            scheduleToolbarAutoHide()
            UIView.animate(withDuration: 0.18) {
                self.toolbarContainer.alpha = 1
            } completion: { _ in
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
                self.scheduleToolbarAutoHide()
            }
        } else {
            cancelToolbarAutoHide()
            suppressTopEdgeToolbarUntil = CACurrentMediaTime() + 0.60
            if cursorView.center.y < 165 {
                cursorView.center.y = 165
            }
            UIView.animate(withDuration: 0.18, animations: {
                self.toolbarContainer.alpha = 0
            }) { _ in
                self.toolbarContainer.isHidden = true
                self.restoreBrowserFocus()
            }
        }
    }

    private func updateProgressUI() {
        guard let tab = activeTab else { return }
        if tab.isLoading {
            progressBar.setProgress(Float(max(0.1, tab.estimatedProgress)), animated: true)
            UIView.animate(withDuration: 0.15) { self.progressBar.alpha = 1 }
        } else {
            progressBar.setProgress(1.0, animated: true)
            UIView.animate(withDuration: 0.25, delay: 0.15, options: [], animations: {
                self.progressBar.alpha = 0
            }) { _ in
                self.progressBar.progress = 0
            }
        }
    }

    private func updateToolbarState() {
        let canBack = canNavigateBackOrCloseTab
        let canForward = currentEngine?.canGoForward ?? false
        backButton.isEnabled = canBack
        backButton.alpha = canBack ? 1.0 : 0.35
        forwardButton.isEnabled = canForward
        forwardButton.alpha = canForward ? 1.0 : 0.35

        let isLoading = currentEngine?.isLoading ?? activeTab?.isLoading ?? false
        reloadButton.setTitle(isLoading ? "✕" : "↻", for: .normal)
        tabsButton.setTitle("❏ \(tabs.count)", for: .normal)
        let zoomPct = Int(round((activeTab?.zoom ?? BrowserStore.shared.pageZoom) * 100))
        zoomLevelButton.setTitle("\(zoomPct)%", for: .normal)
        videoButton.isHidden = (activeTab?.detectedVideoURL == nil)

        if let currentURL = currentEngine?.currentURL ?? activeTab?.url {
            let schemePrefix = currentURL.scheme == "https" ? "🔒 " : ""
            let hostTitle = currentURL.host ?? currentURL.absoluteString
            let display = (activeTab?.title.isEmpty == false && activeTab?.title != "Nueva pestaña")
                ? "\(schemePrefix)\(hostTitle) — \(activeTab?.title ?? "")"
                : "\(schemePrefix)\(currentURL.absoluteString)"
            urlButton.setTitle(display, for: .normal)
            let isSaved = BrowserStore.shared.isBookmarked(urlString: currentURL.absoluteString)
            bookmarkStarButton.setTitle(isSaved ? "★" : "☆", for: .normal)
        } else {
            urlButton.setTitle("🔍 Buscar en \(BrowserStore.shared.searchEngine.displayName) o URL", for: .normal)
            bookmarkStarButton.setTitle("☆", for: .normal)
        }
    }

    // MARK: - Toolbar & Shortcut Actions

    @objc private func backTapped() {
        if currentEngine?.canGoBack == true {
            currentEngine?.goBack()
        } else if tabs.count > 1 {
            closeTab(at: activeTabIndex)
        }
        updateToolbarState()
        if toolbarVisible { scheduleToolbarAutoHide() }
    }

    @objc private func forwardTapped() {
        currentEngine?.goForward()
        updateToolbarState()
        if toolbarVisible { scheduleToolbarAutoHide() }
    }

    @objc private func homeTapped() {
        setToolbarVisible(false)
        presentStartPage()
    }

    @objc private func reloadTapped() {
        if currentEngine?.isLoading == true {
            currentEngine?.stopLoading()
        } else {
            currentEngine?.reload()
        }
        setToolbarVisible(false)
    }

    @objc private func toggleBookmarkTapped() {
        guard let url = currentEngine?.currentURL ?? activeTab?.url else { return }
        if BrowserStore.shared.isBookmarked(urlString: url.absoluteString) {
            BrowserStore.shared.removeBookmark(urlString: url.absoluteString)
            showToast("Marcador eliminado")
        } else {
            let title = currentEngine?.currentTitle ?? activeTab?.title ?? url.host ?? url.absoluteString
            BrowserStore.shared.addBookmark(title: title, urlString: url.absoluteString)
            showToast("Guardado en favoritos ★")
        }
        updateToolbarState()
        if toolbarVisible { scheduleToolbarAutoHide() }
    }

    private func setZoom(_ newZoom: Double, showNotice: Bool = true) {
        guard let tab = activeTab else { return }
        let clamped = max(0.75, min(2.5, newZoom))
        tab.zoom = clamped
        if let webApp = tab.webApp {
            BrowserStore.shared.updateWebAppZoom(id: webApp.id, zoom: clamped)
        } else {
            BrowserStore.shared.pageZoom = clamped
        }
        applyPageZoom(for: tab)
        updateToolbarState()
        if showNotice {
            showToast("Escala \(Int(round(clamped * 100)))%")
        }
        if toolbarVisible { scheduleToolbarAutoHide() }
    }

    @objc private func zoomOutTapped() {
        let current = activeTab?.zoom ?? BrowserStore.shared.pageZoom
        setZoom(current - 0.15)
    }

    @objc private func zoomInTapped() {
        let current = activeTab?.zoom ?? BrowserStore.shared.pageZoom
        setZoom(current + 0.15)
    }

    @objc private func zoomResetTapped() {
        setZoom(BrowserStore.defaultTVZoom)
    }

    @objc private func presentZoomPresetPicker() {
        let currentPct = Int(round((activeTab?.zoom ?? BrowserStore.shared.pageZoom) * 100))
        let alert = UIAlertController(
            title: "Escala / Zoom de pantalla (\(currentPct)%)",
            message: "Elige un tamaño cómodo para tu televisor. También puedes ajustar con A- / A+ en directo o pellizcando en el iPhone.",
            preferredStyle: .alert
        )
        let presets: [(String, Double)] = [
            ("100% (Original PC)", 1.0),
            ("120% (Suave)", 1.20),
            ("140% (Por defecto TV 55\")", 1.40),
            ("160% (Grande)", 1.60),
            ("180% (Muy grande)", 1.80),
            ("200% (Extra grande)", 2.0),
            ("225% (Gigante)", 2.25),
            ("250% (Máximo)", 2.50)
        ]
        for (title, factor) in presets {
            let pct = Int(round(factor * 100))
            let label = (abs(pct - currentPct) <= 2) ? "✓ \(title)" : title
            alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.setZoom(factor)
                self?.restoreBrowserFocus()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            self?.restoreBrowserFocus()
        })
        present(alert, animated: true)
    }

    @objc private func shortcutNewTab() {
        presentStartPage(createNewTab: true)
    }

    @objc private func shortcutCloseTab() {
        closeTab(at: activeTabIndex)
    }

    @objc private func shortcutEscape() {
        if toolbarVisible {
            setToolbarVisible(false)
        } else if isWebInputFocused {
            inputControllerDidSendKeyboardAction(.escape)
        } else {
            inputControllerDidPressBack()
        }
    }

    @objc private func urlTapped() {
        let engineName = BrowserStore.shared.searchEngine.displayName
        let alert = UIAlertController(
            title: "Buscar en \(engineName) o ir a URL",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { [weak self] tf in
            guard let self = self else { return }
            tf.placeholder = "ej: youtube.com o buscar..."
            tf.text = ""
            tf.keyboardType = .webSearch
            tf.returnKeyType = .go
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.clearButtonMode = .whileEditing
            self.attachSubmitOnReturn(tf, alert: alert) { [weak self] text in
                self?.setToolbarVisible(false)
                self?.openInputURL(text)
                self?.restoreBrowserFocus()
            }
        }
        let goAction = UIAlertAction(title: "Ir / Buscar", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let text = alert?.textFields?.first?.text else { return }
            self.setToolbarVisible(false)
            self.openInputURL(text)
            self.restoreBrowserFocus()
        }
        alert.addAction(goAction)
        alert.preferredAction = goAction

        if let current = (currentEngine?.currentURL ?? activeTab?.url)?.absoluteString {
            alert.addAction(UIAlertAction(title: "Editar URL actual", style: .default) { [weak self] _ in
                self?.openEditCurrentURL(current)
            })
        }
        alert.addAction(UIAlertAction(title: "Página de Inicio (Favoritos / WebApps)", style: .default) { [weak self] _ in
            self?.setToolbarVisible(false)
            self?.presentStartPage()
        })
        alert.addAction(UIAlertAction(title: "Ir a Google", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.setToolbarVisible(false)
            self.load(url: self.homeSearchURL)
            self.restoreBrowserFocus()
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            self?.restoreBrowserFocus()
        })
        present(alert, animated: true)
    }

    private func openEditCurrentURL(_ current: String) {
        let alert = UIAlertController(title: "Editar dirección", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] tf in
            guard let self = self else { return }
            tf.text = current
            tf.keyboardType = .URL
            tf.returnKeyType = .go
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.clearButtonMode = .whileEditing
            self.attachSubmitOnReturn(tf, alert: alert) { [weak self] text in
                self?.setToolbarVisible(false)
                self?.openInputURL(text)
                self?.restoreBrowserFocus()
            }
        }
        let goAction = UIAlertAction(title: "Ir", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let text = alert?.textFields?.first?.text else { return }
            self.setToolbarVisible(false)
            self.openInputURL(text)
            self.restoreBrowserFocus()
        }
        alert.addAction(goAction)
        alert.preferredAction = goAction
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            self?.restoreBrowserFocus()
        })
        present(alert, animated: true)
    }

    private func attachSubmitOnReturn(_ tf: UITextField, alert: UIAlertController, handler: @escaping (String) -> Void) {
        tf.addAction(UIAction { [weak alert, weak tf] _ in
            let text = tf?.text ?? ""
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            DispatchQueue.main.async {
                if let alert = alert, alert.presentingViewController != nil {
                    alert.dismiss(animated: true) { handler(text) }
                } else {
                    handler(text)
                }
            }
        }, for: .editingDidEndOnExit)
    }

    @objc private func tabsTapped() {
        let vc = TabsViewController()
        vc.tabs = tabs
        vc.activeTabIndex = activeTabIndex
        vc.onSelectTab = { [weak self] idx in
            self?.setToolbarVisible(false)
            self?.switchToTab(at: idx)
            self?.restoreBrowserFocus()
        }
        vc.onCloseTab = { [weak self] idx in
            self?.closeTab(at: idx)
        }
        vc.onNewTab = { [weak self] in
            self?.setToolbarVisible(false)
            self?.presentStartPage(createNewTab: true)
        }
        vc.onDismiss = { [weak self] in
            self?.restoreBrowserFocus()
        }
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    @objc private func moreTapped() {
        guard let tab = activeTab else { return }
        let zoomPct = Int(round(tab.zoom * 100))
        let uaName: String = {
            switch tab.userAgentMode {
            case .desktopMac: return "Escritorio Mac"
            case .iPad: return "iPad"
            case .iPhone: return "iPhone"
            @unknown default: return "Escritorio Mac"
            }
        }()
        let remoteSubtitle = remoteServerRunning ? "Activo (\(connectedRemoteClients) conectados)" : "Ratón y teclado Wi-Fi"

        let menuVC = BrowserMenuViewController()
        menuVC.modalPresentationStyle = .fullScreen
        menuVC.items = [
            BrowserMenuActionItem(
                id: "mode",
                icon: cursorView.mode == .pointer ? "⌖" : "↕",
                title: cursorView.mode == .pointer ? "Modo: Cursor" : "Modo: Scroll",
                subtitle: "Cambiar a \(cursorView.mode == .pointer ? "Scroll" : "Cursor")",
                accentColor: cursorView.mode == .pointer ? .systemBlue : .systemGreen
            ),
            BrowserMenuActionItem(
                id: "home",
                icon: "⌂",
                title: "Página de Inicio",
                subtitle: "WebApps, Favoritos e Historial",
                accentColor: .systemIndigo
            ),
            BrowserMenuActionItem(
                id: "tabs",
                icon: "❏",
                title: "Pestañas (\(tabs.count))",
                subtitle: "Ver o abrir nueva pestaña",
                accentColor: .systemTeal
            ),
            BrowserMenuActionItem(
                id: "remote",
                icon: "📱",
                title: "Control Remoto QR",
                subtitle: remoteSubtitle,
                accentColor: UIColor(red: 0.08, green: 0.68, blue: 0.90, alpha: 1.0)
            ),
            BrowserMenuActionItem(
                id: "zoomIn",
                icon: "A+",
                title: "Aumentar Escala",
                subtitle: "Actual: \(zoomPct)% → \(min(250, zoomPct + 15))%",
                accentColor: .systemBlue
            ),
            BrowserMenuActionItem(
                id: "zoomOut",
                icon: "A-",
                title: "Reducir Escala",
                subtitle: "Actual: \(zoomPct)% → \(max(75, zoomPct - 15))%",
                accentColor: .systemBlue
            ),
            BrowserMenuActionItem(
                id: "zoomPresets",
                icon: "\(zoomPct)%",
                title: "Elegir Escala (TV 55\")",
                subtitle: "Presets 100% – 250%",
                accentColor: .systemIndigo
            ),
            BrowserMenuActionItem(
                id: "video",
                icon: "▶",
                title: "Reproducir Vídeo TV",
                subtitle: "Abrir reproductor nativo",
                accentColor: .systemPurple
            ),
            BrowserMenuActionItem(
                id: "bookmarks",
                icon: "★",
                title: "Marcadores",
                subtitle: "\(BrowserStore.shared.bookmarks.count) guardados",
                accentColor: .systemOrange
            ),
            BrowserMenuActionItem(
                id: "history",
                icon: "🕒",
                title: "Historial",
                subtitle: "\(BrowserStore.shared.history.count) páginas",
                accentColor: .systemTeal
            ),
            BrowserMenuActionItem(
                id: "webapp",
                icon: "⊞",
                title: "Guardar WebApp",
                subtitle: "Fijar en pantalla completa",
                accentColor: .systemIndigo
            ),
            BrowserMenuActionItem(
                id: "userAgent",
                icon: "🖥",
                title: "User-Agent",
                subtitle: uaName,
                accentColor: .systemGray
            ),
            BrowserMenuActionItem(
                id: "adblock",
                icon: "🛡",
                title: "AdBlock: \(tab.adBlockEnabled ? "ON" : "OFF")",
                subtitle: "Bloqueador de anuncios",
                accentColor: tab.adBlockEnabled ? .systemGreen : .systemGray
            ),
            BrowserMenuActionItem(
                id: "searchEngine",
                icon: "🔍",
                title: "Buscador",
                subtitle: BrowserStore.shared.searchEngine.displayName,
                accentColor: .systemBlue
            ),
            BrowserMenuActionItem(
                id: "clearCache",
                icon: "🗑",
                title: "Borrar Caché",
                subtitle: "Limpiar caché y cookies",
                accentColor: .systemRed
            )
        ]

        menuVC.onSelectAction = { [weak self] actionId in
            guard let self = self else { return }
            switch actionId {
            case "mode":
                self.setToolbarVisible(false)
                self.modeTapped()
                self.restoreBrowserFocus()
            case "home":
                self.setToolbarVisible(false)
                self.presentStartPage()
            case "tabs":
                self.tabsTapped()
            case "remote":
                self.exportTapped()
            case "zoomIn":
                self.zoomInTapped()
                self.setToolbarVisible(false)
            case "zoomOut":
                self.zoomOutTapped()
                self.setToolbarVisible(false)
            case "zoomPresets":
                self.presentZoomPresetPicker()
            case "zoomReset":
                self.zoomResetTapped()
                self.setToolbarVisible(false)
            case "video":
                self.setToolbarVisible(false)
                self.detectAndPlayVideo()
            case "bookmarks":
                self.bookmarksTapped()
            case "history":
                self.historyTapped()
            case "webapp":
                self.promptSaveCurrentAsWebApp()
            case "userAgent":
                self.presentUserAgentPicker()
            case "adblock":
                guard let tab = self.activeTab else { return }
                tab.adBlockEnabled.toggle()
                if !tab.isAppMode { AdBlocker.shared.isEnabled = tab.adBlockEnabled }
                self.applyAdBlockRuleList(to: tab)
                tab.engine.reload()
                self.setToolbarVisible(false)
                self.showToast("AdBlock \(tab.adBlockEnabled ? "ON" : "OFF")")
            case "searchEngine":
                self.presentSearchEnginePicker()
            case "clearCache":
                self.setToolbarVisible(false)
                TVWebEngine.clearCacheAndCookies {
                    self.showToast("Caché y cookies borradas")
                    self.currentEngine?.reload()
                    self.restoreBrowserFocus()
                }
            default:
                self.restoreBrowserFocus()
            }
        }
        menuVC.onDismiss = { [weak self] in
            self?.restoreBrowserFocus()
        }
        present(menuVC, animated: true)
    }

    private func presentUserAgentPicker() {
        let alert = UIAlertController(title: "Identidad del navegador (User-Agent)", message: nil, preferredStyle: .alert)
        let choices: [(String, TVUserAgentMode)] = [
            ("Escritorio Mac (Safari macOS)", .desktopMac),
            ("iPad (Safari iPadOS)", .iPad),
            ("iPhone (Safari móvil)", .iPhone)
        ]
        for (title, mode) in choices {
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self, let tab = self.activeTab else { return }
                tab.userAgentMode = mode
                tab.engine.userAgentMode = mode
                if !tab.isAppMode { BrowserStore.shared.defaultUserAgentMode = mode }
                tab.engine.reload()
                self.setToolbarVisible(false)
                self.showToast("User-Agent: \(title)")
                self.restoreBrowserFocus()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            self?.restoreBrowserFocus()
        })
        present(alert, animated: true)
    }

    private func presentSearchEnginePicker() {
        let alert = UIAlertController(title: "Buscador predeterminado", message: nil, preferredStyle: .alert)
        for engine in SearchEngineOption.allCases {
            alert.addAction(UIAlertAction(title: engine.displayName, style: .default) { [weak self] _ in
                BrowserStore.shared.searchEngine = engine
                self?.updateToolbarState()
                self?.showToast("Buscador: \(engine.displayName)")
                self?.restoreBrowserFocus()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            self?.restoreBrowserFocus()
        })
        present(alert, animated: true)
    }

    private func promptSaveCurrentAsWebApp(prefillBookmark: BookmarkItem? = nil) {
        let urlStr = prefillBookmark?.urlString ?? (currentEngine?.currentURL ?? activeTab?.url)?.absoluteString ?? ""
        guard !urlStr.isEmpty else { return }
        let defaultTitle = prefillBookmark?.title ?? activeTab?.title ?? URL(string: urlStr)?.host ?? "WebApp"

        let alert = UIAlertController(
            title: "Guardar como WebApp",
            message: "Se abrirá en pantalla completa sin barras y conservará este zoom y User-Agent.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.text = defaultTitle
            tf.placeholder = "Nombre de la WebApp"
        }

        let saveNormal = UIAlertAction(title: "Guardar WebApp", style: .default) { [weak self, weak alert] _ in
            self?.finishSavingWebApp(title: alert?.textFields?.first?.text ?? defaultTitle, urlString: urlStr, autoLaunch: false)
            self?.restoreBrowserFocus()
        }
        let saveAuto = UIAlertAction(title: "Guardar y abrir al iniciar Platanet", style: .default) { [weak self, weak alert] _ in
            self?.finishSavingWebApp(title: alert?.textFields?.first?.text ?? defaultTitle, urlString: urlStr, autoLaunch: true)
            self?.restoreBrowserFocus()
        }
        alert.addAction(saveNormal)
        alert.addAction(saveAuto)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            self?.restoreBrowserFocus()
        })
        present(alert, animated: true)
    }

    private func finishSavingWebApp(title: String, urlString: String, autoLaunch: Bool) {
        let tab = activeTab
        let app = BrowserStore.shared.saveWebApp(
            title: title,
            urlString: urlString,
            userAgentMode: tab?.userAgentMode ?? BrowserStore.shared.defaultUserAgentMode,
            zoom: tab?.zoom ?? BrowserStore.shared.pageZoom,
            adBlockEnabled: tab?.adBlockEnabled ?? AdBlocker.shared.isEnabled,
            autoLaunch: autoLaunch
        )
        if tab?.url?.absoluteString == urlString {
            tab?.webApp = app
            setToolbarVisible(false)
        }
        showToast("WebApp '\(app.title)' guardada")
    }

    private func presentStartPage(createNewTab: Bool = false) {
        let vc = StartPageViewController()
        vc.modalPresentationStyle = .fullScreen
        vc.currentPageTitle = currentEngine?.currentTitle ?? activeTab?.title
        vc.currentPageURL = currentEngine?.currentURL ?? activeTab?.url
        vc.onSearchTapped = { [weak self] in
            vc.dismiss(animated: true) {
                if createNewTab {
                    self?.openTab(url: self?.homeSearchURL, switchToIt: true)
                }
                self?.urlTapped()
            }
        }
        vc.onSelectURL = { [weak self] url in
            vc.dismiss(animated: true) {
                if createNewTab {
                    self?.openTab(url: url, switchToIt: true)
                } else {
                    self?.activeTab?.webApp = nil
                    self?.load(url: url)
                }
                self?.restoreBrowserFocus()
            }
        }
        vc.onSelectWebApp = { [weak self] app in
            vc.dismiss(animated: true) {
                guard let url = URL(string: app.urlString) else { return }
                if let existingIdx = self?.tabs.firstIndex(where: { $0.webApp?.id == app.id }) {
                    self?.switchToTab(at: existingIdx)
                } else {
                    self?.openTab(url: url, webApp: app, switchToIt: true)
                }
                self?.showToast("WebApp: \(app.title) (Mantén Menú para salir)")
                self?.restoreBrowserFocus()
            }
        }
        vc.onClose = { [weak self] in
            vc.dismiss(animated: true) {
                self?.restoreBrowserFocus()
            }
        }
        present(vc, animated: true)
    }

    @objc private func bookmarksTapped() {
        let vc = BookmarksViewController()
        vc.modalPresentationStyle = .fullScreen
        vc.onSelectURL = { [weak self] url in
            self?.setToolbarVisible(false)
            self?.load(url: url)
            self?.restoreBrowserFocus()
        }
        vc.onSaveAsWebApp = { [weak self] item in
            self?.promptSaveCurrentAsWebApp(prefillBookmark: item)
        }
        vc.onDismiss = { [weak self] in
            self?.restoreBrowserFocus()
        }
        present(vc, animated: true)
    }

    @objc private func historyTapped() {
        let vc = HistoryViewController()
        vc.modalPresentationStyle = .fullScreen
        vc.onSelectURL = { [weak self] url in
            self?.setToolbarVisible(false)
            self?.load(url: url)
            self?.restoreBrowserFocus()
        }
        vc.onDismiss = { [weak self] in
            self?.restoreBrowserFocus()
        }
        present(vc, animated: true)
    }

    @objc private func exportTapped() {
        let presentExport = { [weak self] in
            guard let self = self else { return }
            let vc = ExportViewController()
            vc.modalPresentationStyle = .fullScreen
            vc.server = self.remoteServer
            vc.serverURLString = self.remoteServerURL
            vc.connectedClientsCount = self.connectedRemoteClients
            vc.onStopServerRequested = { [weak self] in
                self?.remoteServer.stop()
                self?.remoteServerRunning = false
                self?.remoteServerURL = nil
                self?.showToast("Control remoto apagado")
            }
            vc.onDismiss = { [weak self] in
                self?.restoreBrowserFocus()
            }
            self.activeExportVC = vc
            self.present(vc, animated: true)
        }

        if remoteServerRunning {
            presentExport()
        } else {
            remoteServerRunning = true
            remoteServer.start { [weak self] urlString in
                guard let self = self else { return }
                self.remoteServerURL = urlString
                self.activeExportVC?.updateStatus(urlString: urlString, clientsCount: self.connectedRemoteClients)
            }
            presentExport()
        }
    }

    @objc private func modeTapped() {
        cursorView.mode = (cursorView.mode == .pointer) ? .scroll : .pointer
        let modeName = cursorView.mode == .pointer ? "Modo Cursor" : "Modo Scroll"
        showToast(modeName)
    }

    private func presentQuickRemoteMenu() {
        let zoomPct = Int(round((activeTab?.zoom ?? BrowserStore.shared.pageZoom) * 100))
        let modeToggleTitle = cursorView.mode == .pointer ? "↕ Cambiar a Modo Scroll" : "🎯 Cambiar a Modo Cursor"

        let alert = UIAlertController(
            title: "Acciones rápidas del mando",
            message: "Escala actual: \(zoomPct)%",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "🔍 Buscar o escribir dirección (URL)", style: .default) { [weak self] _ in
            self?.urlTapped()
        })
        alert.addAction(UIAlertAction(title: "☰ Abrir barra completa de Safari", style: .default) { [weak self] _ in
            self?.setToolbarVisible(true)
        })
        alert.addAction(UIAlertAction(title: "🔎 Cambiar Escala / Zoom (\(zoomPct)%)", style: .default) { [weak self] _ in
            self?.presentZoomPresetPicker()
        })
        alert.addAction(UIAlertAction(title: modeToggleTitle, style: .default) { [weak self] _ in
            self?.modeTapped()
            self?.restoreBrowserFocus()
        })
        alert.addAction(UIAlertAction(title: "⌂ Ir a Página de Inicio", style: .default) { [weak self] _ in
            self?.presentStartPage()
        })
        alert.addAction(UIAlertAction(title: "❏ Pestañas (\(tabs.count))", style: .default) { [weak self] _ in
            self?.tabsTapped()
        })
        alert.addAction(UIAlertAction(title: "📱 Control Remoto desde iPhone", style: .default) { [weak self] _ in
            self?.exportTapped()
        })
        if currentEngine?.canGoBack == true {
            alert.addAction(UIAlertAction(title: "◀ Página anterior", style: .default) { [weak self] _ in
                self?.backTapped()
                self?.restoreBrowserFocus()
            })
        }
        alert.addAction(UIAlertAction(title: "↻ Recargar página", style: .default) { [weak self] _ in
            self?.currentEngine?.reload()
            self?.restoreBrowserFocus()
        })
        alert.addAction(UIAlertAction(title: "Cerrar", style: .cancel) { [weak self] _ in
            self?.restoreBrowserFocus()
        })
        present(alert, animated: true)
    }

    @objc private func hideToolbarTapped() {
        setToolbarVisible(false)
    }

    // MARK: - Native Video Handoff

    @objc private func playDetectedVideoTapped() {
        if let videoURL = activeTab?.detectedVideoURL {
            setToolbarVisible(false)
            presentNativeVideoPlayer(url: videoURL)
        } else {
            detectAndPlayVideo()
        }
    }

    private func detectAndPlayVideo() {
        let js = """
        (function() {
            var videos = Array.prototype.slice.call(document.querySelectorAll('video'));
            var best = null;
            for (var i = 0; i < videos.length; i++) {
                var v = videos[i];
                var src = v.currentSrc || v.src || '';
                if (!src) {
                    var s = v.querySelector('source[src]');
                    if (s) src = s.src || '';
                }
                if (src && src.indexOf('blob:') !== 0) { best = src; break; }
            }
            return best;
        })();
        """
        currentEngine?.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            if let str = result as? String, let url = URL(string: str) {
                DispatchQueue.main.async {
                    self.activeTab?.detectedVideoURL = url
                    self.updateToolbarState()
                    self.presentNativeVideoPlayer(url: url)
                }
            } else {
                DispatchQueue.main.async {
                    self.showToast("No se detectó flujo MP4/HLS directo (usa pantalla completa en la web)", duration: 2.5)
                }
            }
        }
    }

    private func presentNativeVideoPlayer(url: URL) {
        currentEngine?.evaluateJavaScript("document.querySelectorAll('video').forEach(function(v){ try{v.pause();}catch(e){} });", completion: nil)
        let player = AVPlayer(url: url)
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        present(playerVC, animated: true) {
            player.play()
        }
    }

    // MARK: - Remote Control Server (Phone / PC Trackpad, Mouse & Keyboard)

    private func setupRemoteServer() {
        remoteServer.currentZoomProvider = { [weak self] in
            self?.activeTab?.zoom ?? BrowserStore.shared.pageZoom
        }

        remoteServer.onClientCountChanged = { [weak self] count in
            guard let self = self else { return }
            self.connectedRemoteClients = count
            self.activeExportVC?.updateStatus(urlString: self.remoteServerURL, clientsCount: count)
        }

        remoteServer.onRemoteCommand = { [weak self] cmd in
            guard let self = self else { return }
            switch cmd {
            case .moveCursor(let dx, let dy):
                if self.toolbarVisible { self.setToolbarVisible(false) }
                self.moveCursor(by: CGPoint(x: dx, y: dy))
            case .scroll(let dx, let dy):
                if !self.toolbarVisible {
                    self.scrollWebView(by: CGPoint(x: dx, y: dy))
                }
            case .click:
                if !self.toolbarVisible {
                    self.performClickAtCursor()
                }
            case .back:
                self.inputControllerDidPressBack()
            case .typeText(let text):
                self.typeDirectlyIntoWebInput(text)
            case .key(let code):
                switch code {
                case "Enter": self.inputControllerDidSendKeyboardAction(.enter)
                case "Backspace": self.inputControllerDidSendKeyboardAction(.backspace)
                case "Tab": self.inputControllerDidSendKeyboardAction(.tab(shift: false))
                case "Escape": self.inputControllerDidSendKeyboardAction(.escape)
                default: break
                }
            case .openURL(let raw):
                self.setToolbarVisible(false)
                self.openInputURL(raw)
            case .setZoom(let zoom):
                self.setZoom(zoom)
            case .action(let name):
                switch name {
                case "back": self.backTapped()
                case "forward": self.forwardTapped()
                case "reload": self.currentEngine?.reload()
                case "home": self.presentStartPage()
                case "mode": self.modeTapped()
                case "toolbar": self.setToolbarVisible(!self.toolbarVisible)
                case "tabs": self.tabsTapped()
                case "video": self.detectAndPlayVideo()
                case "zoomIn": self.zoomInTapped()
                case "zoomOut": self.zoomOutTapped()
                case "zoomReset": self.zoomResetTapped()
                default: break
                }
            }
        }
    }

    // MARK: - Touchpad Pan & Press Handling

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !toolbarVisible, presentedViewController == nil else { return }
        let point = gesture.translation(in: view)

        switch gesture.state {
        case .began:
            inputController.cancelScrollInertia()
            lastPanPoint = point
            panStartPoint = point
        case .changed:
            let dx = point.x - lastPanPoint.x
            let dy = point.y - lastPanPoint.y
            lastPanPoint = point

            let totalDist = hypot(point.x - panStartPoint.x, point.y - panStartPoint.y)
            if totalDist > 10 {
                inputController.markSelectPanMoved()
            }
            if inputController.isSelectPressed && totalDist < 10 {
                return
            }

            if cursorView.mode == .pointer {
                moveCursor(by: CGPoint(x: dx * 1.20, y: dy * 1.20))
            } else {
                scrollWebView(by: CGPoint(x: -dx * 1.05, y: -dy * 1.05))
            }
        case .ended, .cancelled:
            if cursorView.mode == .scroll {
                let vel = gesture.velocity(in: view)
                inputController.applyScrollImpulse(velocity: CGPoint(x: -vel.x * 0.45, y: -vel.y * 0.45))
            }
            lastPanPoint = .zero
        default:
            lastPanPoint = .zero
        }
    }

    private var canNavigateBackOrCloseTab: Bool {
        (currentEngine?.canGoBack == true) || tabs.count > 1
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presentedViewController != nil {
            super.pressesBegan(presses, with: event)
            return
        }

        if toolbarVisible {
            if presses.contains(where: { $0.type == .menu || $0.type == .playPause }) {
                return
            }
            scheduleToolbarAutoHide()
            super.pressesBegan(presses, with: event)
            return
        }

        if inputController.handlePressesBegan(presses, allowToolbarToggle: true, interceptMenu: canNavigateBackOrCloseTab) {
            return
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presentedViewController != nil {
            super.pressesEnded(presses, with: event)
            return
        }

        if toolbarVisible {
            if presses.contains(where: { $0.type == .menu || $0.type == .playPause }) {
                setToolbarVisible(false)
                return
            }
            scheduleToolbarAutoHide()
            super.pressesEnded(presses, with: event)
            return
        }

        if inputController.handlePressesEnded(presses, interceptMenu: canNavigateBackOrCloseTab) {
            return
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        inputController.handlePressesCancelled(presses)
        super.pressesCancelled(presses, with: event)
    }

    // MARK: - Cursor, Hover & Scroll Logic

    private func moveCursor(by delta: CGPoint) {
        let bounds = view.bounds
        let nextX = max(8, min(bounds.width - 8, cursorView.center.x + delta.x))
        let nextY = max(8, min(bounds.height - 8, cursorView.center.y + delta.y))
        cursorView.center = CGPoint(x: nextX, y: nextY)

        let now = CACurrentMediaTime()
        let scrollView = currentEngine?.scrollView
        let topInset = scrollView?.adjustedContentInset.top ?? 0
        let currentOffsetY = (scrollView?.contentOffset.y ?? 0) + topInset
        let isAtTop = (currentOffsetY <= 6) && !cachedPageCanScrollUp

        if !isAtTop {
            lastScrolledDownTime = now
        }

        // Top edge:
        // - If the page is scrolled down, entering the top band gently scrolls the page back up.
        // - Once already at the top of the page, pushing against the top edge reveals the big Safari bar.
        let topEdgeTriggerY: CGFloat = 18
        let topScrollZoneY: CGFloat = 125
        if !isAtTop && nextY <= topScrollZoneY && delta.y < 0 {
            let t = min(1.0, (topScrollZoneY - nextY) / topScrollZoneY)
            let curve: CGFloat = 0.22 + 0.78 * (t * t)
            let step = max(-10.5, min(-1.6, delta.y * 0.90 * curve))
            scrollWebView(by: CGPoint(x: 0, y: step))
        } else if isAtTop,
                  nextY <= topEdgeTriggerY,
                  delta.y < -1.0,
                  activeTab?.isAppMode != true,
                  now >= suppressTopEdgeToolbarUntil,
                  (now - lastScrolledDownTime) >= 0.25 {
            setToolbarVisible(true)
            return
        }

        // Bottom edge: start gentle progressive scrolling ~150pt before the bottom so stopping is precise.
        let bottomZoneSpan: CGFloat = 150
        let bottomZoneStart = bounds.height - bottomZoneSpan
        if nextY >= bottomZoneStart && delta.y > 0 {
            let t = min(1.0, (nextY - bottomZoneStart) / bottomZoneSpan)
            let curve: CGFloat = 0.22 + 0.78 * (t * t)
            let step = min(10.5, max(1.6, delta.y * 0.90 * curve))
            scrollWebView(by: CGPoint(x: 0, y: step))
        }

        scheduleHoverUpdate()
    }

    private func scheduleHoverUpdate() {
        guard cursorView.mode == .pointer, !toolbarVisible else { return }
        let now = CACurrentMediaTime()
        if now - lastHoverCheckTime >= 0.055 {
            lastHoverCheckTime = now
            performHoverProbeAtCursor()
        } else if !hoverCheckScheduled {
            hoverCheckScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                guard let self = self else { return }
                self.hoverCheckScheduled = false
                self.lastHoverCheckTime = CACurrentMediaTime()
                self.performHoverProbeAtCursor()
            }
        }
    }

    private func performHoverProbeAtCursor() {
        guard let engine = currentEngine, cursorView.mode == .pointer, !toolbarVisible else { return }
        let pt = cursorView.center
        let viewW = max(1, view.bounds.width)
        let viewH = max(1, view.bounds.height)

        let js = """
        (function() {
            var vw = window.innerWidth || document.documentElement.clientWidth || \(viewW);
            var vh = window.innerHeight || document.documentElement.clientHeight || \(viewH);
            var x = \(pt.x) * (vw / \(viewW));
            var y = \(pt.y) * (vh / \(viewH));
            var doc = document;
            var localX = x, localY = y;

            function deepHit(d, px, py) {
                var node = d.elementFromPoint(px, py);
                while (node && node.shadowRoot && typeof node.shadowRoot.elementFromPoint === 'function') {
                    var inner = node.shadowRoot.elementFromPoint(px, py);
                    if (!inner || inner === node) break;
                    node = inner;
                }
                return node;
            }
            function tvClosest(node, sel) {
                var cur = node;
                while (cur) {
                    if (cur.matches && cur.matches(sel)) return cur;
                    if (cur.parentElement) { cur = cur.parentElement; continue; }
                    var root = cur.getRootNode ? cur.getRootNode() : null;
                    cur = (root && root.host) ? root.host : null;
                }
                return null;
            }

            var el = deepHit(doc, localX, localY);
            for (var depth = 0; depth < 4 && el && el.tagName && el.tagName.toLowerCase() === 'iframe'; depth++) {
                try {
                    var idoc = el.contentDocument || (el.contentWindow && el.contentWindow.document);
                    if (!idoc) break;
                    var r = el.getBoundingClientRect();
                    localX = localX - r.left;
                    localY = localY - r.top;
                    var inner = deepHit(idoc, localX, localY);
                    if (!inner) break;
                    el = inner;
                    doc = idoc;
                } catch (e) { break; }
            }
            if (!el) return null;

            if (window.__tvBrowserLastHover !== el) {
                try {
                    if (window.__tvBrowserLastHover && window.__tvBrowserLastHover.dispatchEvent) {
                        window.__tvBrowserLastHover.dispatchEvent(new MouseEvent('mouseout', { bubbles: true, clientX: localX, clientY: localY }));
                    }
                    el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true, clientX: localX, clientY: localY }));
                } catch (e) {}
                window.__tvBrowserLastHover = el;
            }
            try {
                el.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: localX, clientY: localY }));
            } catch (e) {}

            var tag = (el.tagName || '').toLowerCase();
            var nonText = ['submit','button','checkbox','radio','reset','file','image','range','color','hidden'];
            var isText = (tag === 'textarea') ||
                         (tag === 'input' && nonText.indexOf((el.getAttribute('type') || 'text').toLowerCase()) === -1) ||
                         !!el.isContentEditable;
            var link = tvClosest(el, 'a[href]');
            var clickable = link || tvClosest(el, 'a, button, select, label, summary, details, [role="button"], [role="link"], [role="tab"], [role="menuitem"], [role="option"], [role="switch"], [onclick], [tabindex]');
            var hasInnerScroll = false;
            var canScrollUp = (window.scrollY || document.documentElement.scrollTop || 0) > 4;
            var cur = el;
            for (var i = 0; cur && cur !== doc.body && cur !== doc.documentElement; i++) {
                try {
                    var st = getComputedStyle(cur);
                    if (!clickable && i < 4 && st.cursor === 'pointer') {
                        clickable = cur;
                    }
                    var canY = (st.overflowY === 'auto' || st.overflowY === 'scroll') && cur.scrollHeight > cur.clientHeight + 2;
                    var canX = (st.overflowX === 'auto' || st.overflowX === 'scroll') && cur.scrollWidth > cur.clientWidth + 2;
                    if (canY || canX) {
                        hasInnerScroll = true;
                        if (canY && cur.scrollTop > 4) canScrollUp = true;
                    }
                } catch (e) {}
                cur = cur.parentElement;
            }
            var href = null;
            if (link && link.href) {
                var rawHref = (link.getAttribute('href') || '').trim();
                if (rawHref.indexOf('javascript:') !== 0 && rawHref !== '#') href = link.href;
            }
            return JSON.stringify({
                hint: isText ? 'text' : (clickable ? 'clickable' : 'normal'),
                href: href,
                hasInnerScroll: hasInnerScroll,
                canScrollUp: canScrollUp
            });
        })();
        """

        engine.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self,
                  let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            let hintStr = obj["hint"] as? String ?? "normal"
            let hint: CursorVisualHint = hintStr == "text" ? .textInput : (hintStr == "clickable" ? .clickable : .normal)
            let hasInner = obj["hasInnerScroll"] as? Bool ?? false
            let canUp = obj["canScrollUp"] as? Bool ?? false
            DispatchQueue.main.async {
                self.cachedCursorOverInnerScroll = hasInner
                self.cachedPageCanScrollUp = canUp
                self.cursorView.visualHint = hint
                if let href = obj["href"] as? String, !href.isEmpty {
                    self.linkPreviewLabel.text = "  \(href)  "
                    self.linkPreviewLabel.isHidden = false
                } else {
                    self.linkPreviewLabel.isHidden = true
                }
            }
        }
    }

    private func scrollWebView(by delta: CGPoint) {
        guard let engine = currentEngine else { return }
        let zoom = max(0.75, CGFloat(activeTab?.zoom ?? BrowserStore.shared.pageZoom))
        let scaledDX = delta.x / zoom
        let scaledDY = delta.y / zoom

        if !cachedCursorOverInnerScroll {
            let sv = engine.scrollView
            let minX = -sv.adjustedContentInset.left
            let minY = -sv.adjustedContentInset.top
            let maxX = max(minX, sv.contentSize.width - sv.bounds.width + sv.adjustedContentInset.right)
            let maxY = max(minY, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)

            if maxY > minY + 1 || maxX > minX + 1 {
                let targetX = max(minX, min(maxX, sv.contentOffset.x + scaledDX))
                let targetY = max(minY, min(maxY, sv.contentOffset.y + scaledDY))
                let movedX = abs(targetX - sv.contentOffset.x) > 0.05
                let movedY = abs(targetY - sv.contentOffset.y) > 0.05
                if movedX || movedY {
                    sv.setContentOffset(CGPoint(x: targetX, y: targetY), animated: false)
                    return
                }
            }
        }

        pendingScrollDelta.x += scaledDX
        pendingScrollDelta.y += scaledDY

        if !innerScrollInFlight {
            flushScrollDelta(using: engine)
        }
    }

    private func flushScrollDelta(using engine: TVWebEngine) {
        let dx = pendingScrollDelta.x
        let dy = pendingScrollDelta.y
        guard abs(dx) > 0.1 || abs(dy) > 0.1 else {
            pendingScrollDelta = .zero
            return
        }
        pendingScrollDelta = .zero
        innerScrollInFlight = true

        let pt = cursorView.center
        let viewW = max(1, view.bounds.width)
        let viewH = max(1, view.bounds.height)

        let js = """
        (function() {
            var vw = window.innerWidth || document.documentElement.clientWidth || \(viewW);
            var vh = window.innerHeight || document.documentElement.clientHeight || \(viewH);
            var x = \(pt.x) * (vw / \(viewW));
            var y = \(pt.y) * (vh / \(viewH));
            var el = document.elementFromPoint(x, y);
            while (el && el !== document.body && el !== document.documentElement) {
                var st = getComputedStyle(el);
                var canY = (st.overflowY === 'auto' || st.overflowY === 'scroll') && el.scrollHeight > el.clientHeight + 2;
                var canX = (st.overflowX === 'auto' || st.overflowX === 'scroll') && el.scrollWidth > el.clientWidth + 2;
                if (canY || canX) {
                    var beforeY = el.scrollTop, beforeX = el.scrollLeft;
                    if (canY) el.scrollTop += \(dy);
                    if (canX) el.scrollLeft += \(dx);
                    if (el.scrollTop !== beforeY || el.scrollLeft !== beforeX) {
                        return JSON.stringify({ handled: true, canUp: el.scrollTop > 4 });
                    }
                }
                el = el.parentElement;
            }
            var docCanUp = (window.scrollY || document.documentElement.scrollTop || 0) > 4;
            return JSON.stringify({ handled: false, canUp: docCanUp });
        })();
        """

        engine.evaluateJavaScript(js) { [weak self, weak engine] result, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.innerScrollInFlight = false
                var handled = false
                if let jsonStr = result as? String,
                   let data = jsonStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    handled = (obj["handled"] as? Bool) ?? false
                    self.cachedPageCanScrollUp = (obj["canUp"] as? Bool) ?? false
                }
                if !handled {
                    if let scrollView = engine?.scrollView,
                       (scrollView.contentSize.height > scrollView.bounds.height + 2 ||
                        scrollView.contentSize.width > scrollView.bounds.width + 2) {
                        let minX = -scrollView.adjustedContentInset.left
                        let minY = -scrollView.adjustedContentInset.top
                        let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right)
                        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
                        let targetX = max(minX, min(maxX, scrollView.contentOffset.x + dx))
                        let targetY = max(minY, min(maxY, scrollView.contentOffset.y + dy))
                        scrollView.setContentOffset(CGPoint(x: targetX, y: targetY), animated: false)
                    } else {
                        engine?.evaluateJavaScript("window.scrollBy(\(dx), \(dy));", completion: nil)
                    }
                }
                if let current = self.currentEngine, (abs(self.pendingScrollDelta.x) > 0.5 || abs(self.pendingScrollDelta.y) > 0.5) {
                    self.flushScrollDelta(using: current)
                }
            }
        }
    }

    private func performClickAtCursor() {
        guard let engine = currentEngine else { return }
        cursorView.animateClick()
        let pt = cursorView.center
        let viewW = max(1, view.bounds.width)
        let viewH = max(1, view.bounds.height)
        let navCountBefore = engine.mainFrameNavigationCount
        let urlBefore = engine.currentURL
        let tabsCountBefore = tabs.count

        let js = """
        (function() {
            var vw = window.innerWidth || document.documentElement.clientWidth || \(viewW);
            var vh = window.innerHeight || document.documentElement.clientHeight || \(viewH);
            var x = \(pt.x) * (vw / \(viewW));
            var y = \(pt.y) * (vh / \(viewH));

            function deepHit(d, px, py) {
                var node = d.elementFromPoint(px, py);
                while (node && node.shadowRoot && typeof node.shadowRoot.elementFromPoint === 'function') {
                    var inner = node.shadowRoot.elementFromPoint(px, py);
                    if (!inner || inner === node) break;
                    node = inner;
                }
                return node;
            }
            function tvClosest(node, sel) {
                var cur = node;
                while (cur) {
                    if (cur.matches && cur.matches(sel)) return cur;
                    if (cur.parentElement) { cur = cur.parentElement; continue; }
                    var root = cur.getRootNode ? cur.getRootNode() : null;
                    cur = (root && root.host) ? root.host : null;
                }
                return null;
            }

            var doc = document;
            var win = window;
            var el = deepHit(doc, x, y);
            var localX = x, localY = y;
            for (var depth = 0; depth < 4 && el && el.tagName && el.tagName.toLowerCase() === 'iframe'; depth++) {
                var r = el.getBoundingClientRect();
                var nextX = localX - r.left;
                var nextY = localY - r.top;
                try {
                    var idoc = el.contentDocument || (el.contentWindow && el.contentWindow.document);
                    if (!idoc) {
                        if (el.contentWindow) {
                            window.__tvBrowserLastClick = Date.now();
                            el.contentWindow.postMessage({ __tvBrowserBridge: true, action: 'click', rx: nextX, ry: nextY }, '*');
                            return JSON.stringify({ kind: 'iframeForwarded' });
                        }
                        break;
                    }
                    localX = nextX;
                    localY = nextY;
                    var inner = deepHit(idoc, localX, localY);
                    if (!inner) break;
                    el = inner;
                    doc = idoc;
                    win = el.contentWindow || doc.defaultView || window;
                } catch (e) {
                    if (el.contentWindow) {
                        window.__tvBrowserLastClick = Date.now();
                        el.contentWindow.postMessage({ __tvBrowserBridge: true, action: 'click', rx: nextX, ry: nextY }, '*');
                        return JSON.stringify({ kind: 'iframeForwarded' });
                    }
                    break;
                }
            }
            if (!el) return null;
            window.__tvBrowserLastClick = Date.now();

            var nonText = ['submit','button','checkbox','radio','reset','file','image','range','color','hidden'];
            function isTextInput(n) {
                if (!n || !n.tagName) return false;
                var tag = n.tagName.toLowerCase();
                if (tag === 'textarea') return !n.disabled && !n.readOnly;
                if (tag === 'input') {
                    var t = (n.getAttribute('type') || 'text').toLowerCase();
                    return nonText.indexOf(t) === -1 && !n.disabled && !n.readOnly;
                }
                if (n.isContentEditable) return true;
                var role = (n.getAttribute && n.getAttribute('role')) || '';
                return role === 'textbox' || role === 'searchbox' || role === 'combobox';
            }

            var selectEl = (el.tagName && el.tagName.toLowerCase() === 'select') ? el : tvClosest(el, 'select');
            if (selectEl && !selectEl.disabled) {
                window.__tvBrowserActiveSelect = selectEl;
                var options = Array.prototype.slice.call(selectEl.options || []).map(function(o, idx) {
                    return { index: idx, text: o.text || o.value || ('Opción ' + (idx + 1)), selected: o.selected };
                });
                return JSON.stringify({
                    kind: 'select',
                    title: selectEl.getAttribute('aria-label') || selectEl.name || 'Seleccionar opción',
                    options: options
                });
            }

            var inputEl = null;
            if (isTextInput(el)) inputEl = el;
            if (!inputEl) {
                var c = tvClosest(el, 'input, textarea, [contenteditable=""], [contenteditable="true"], [contenteditable="plaintext-only"], [role="textbox"], [role="searchbox"]');
                if (isTextInput(c)) inputEl = c;
            }
            if (!inputEl && el.tagName && el.tagName.toLowerCase() === 'label' && el.control && isTextInput(el.control)) {
                inputEl = el.control;
            }
            if (!inputEl && el.querySelector && !tvClosest(el, 'button, a[href], [role="button"], [role="tab"]')) {
                var rect = el.getBoundingClientRect();
                if (rect.width < 900 && rect.height < 160) {
                    var innerInp = el.querySelector('input:not([type="hidden"]), textarea, [contenteditable="true"]');
                    if (isTextInput(innerInp)) inputEl = innerInp;
                }
            }

            if (inputEl) {
                var itype = (inputEl.getAttribute('type') || 'text').toLowerCase();
                window.__tvBrowserActiveInput = inputEl;
                try { inputEl.focus(); } catch (e) {}

                var formUsername = '';
                if (itype === 'password') {
                    var frm = inputEl.form || tvClosest(inputEl, 'form');
                    var scope = frm || doc;
                    var uField = scope.querySelector('input[type="email"], input[autocomplete="username"], input[name*="user" i], input[name*="mail" i], input[type="text"]');
                    if (uField && uField.value) formUsername = uField.value;
                }

                return JSON.stringify({
                    kind: 'input',
                    value: inputEl.isContentEditable ? (inputEl.innerText || '') : (inputEl.value || ''),
                    placeholder: inputEl.placeholder || inputEl.getAttribute('aria-label') || inputEl.getAttribute('title') || inputEl.name || 'Escribir texto',
                    isPassword: itype === 'password',
                    formUsername: formUsername
                });
            }

            window.__tvBrowserActiveInput = null;
            var target = tvClosest(el, 'a[href], a, button, input, select, textarea, label, summary, details, [role="button"], [role="link"], [role="tab"], [role="menuitem"], [role="option"], [role="switch"], [onclick], [tabindex]');
            if (!target) {
                var cur = el;
                for (var i = 0; i < 4 && cur; i++) {
                    try {
                        if (getComputedStyle(cur).cursor === 'pointer') { target = cur; break; }
                    } catch (e) {}
                    cur = cur.parentElement;
                }
            }
            if (!target) target = el;

            var opts = { bubbles: true, cancelable: true, view: win, clientX: localX, clientY: localY, screenX: localX, screenY: localY, button: 0, buttons: 1 };
            try {
                if (typeof PointerEvent === 'function') {
                    var popts = Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, opts);
                    target.dispatchEvent(new PointerEvent('pointerover', popts));
                    target.dispatchEvent(new PointerEvent('pointerdown', popts));
                }
            } catch (e) {}
            target.dispatchEvent(new MouseEvent('mouseover', opts));
            target.dispatchEvent(new MouseEvent('mousedown', opts));
            try { target.focus && target.focus(); } catch (e) {}
            try {
                if (typeof PointerEvent === 'function') {
                    target.dispatchEvent(new PointerEvent('pointerup', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, opts, { buttons: 0 })));
                }
            } catch (e) {}
            target.dispatchEvent(new MouseEvent('mouseup', Object.assign({}, opts, { buttons: 0 })));
            var notPrevented = target.dispatchEvent(new MouseEvent('click', Object.assign({}, opts, { buttons: 0, detail: 1 })));

            var link = tvClosest(el, 'a[href]');
            var href = null;
            var linkTarget = null;
            if (link && link.href) {
                var raw = (link.getAttribute('href') || '').trim();
                if (raw.indexOf('javascript:') !== 0 && raw.charAt(0) !== '#') {
                    href = link.href;
                    linkTarget = (link.getAttribute('target') || '').toLowerCase();
                }
            }
            return JSON.stringify({
                kind: 'clicked',
                href: href,
                target: linkTarget,
                prevented: !notPrevented
            });
        })();
        """

        engine.evaluateJavaScript(js) { [weak self, weak engine] result, _ in
            guard let self = self,
                  let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            let kind = obj["kind"] as? String
            DispatchQueue.main.async {
                if kind == "input" {
                    self.isWebInputFocused = true
                    let currentVal = obj["value"] as? String ?? ""
                    let placeholder = obj["placeholder"] as? String ?? "Escribir texto"
                    let isPassword = obj["isPassword"] as? Bool ?? false
                    let formUsername = obj["formUsername"] as? String ?? ""
                    self.promptWebTextInput(
                        title: placeholder,
                        currentValue: currentVal,
                        isPassword: isPassword,
                        detectedUsername: formUsername
                    )
                } else if kind == "select",
                          let title = obj["title"] as? String,
                          let options = obj["options"] as? [[String: Any]] {
                    self.isWebInputFocused = false
                    self.promptSelectOptions(title: title, options: options)
                } else {
                    self.isWebInputFocused = false
                    if kind == "clicked",
                       let href = obj["href"] as? String,
                       let url = URL(string: href),
                       let scheme = url.scheme?.lowercased(),
                       ["http", "https"].contains(scheme),
                       (obj["prevented"] as? Bool) != true {
                        let linkTarget = obj["target"] as? String ?? ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak engine] in
                            guard let self = self, let engine = engine, engine === self.currentEngine else { return }
                            let navigated = engine.mainFrameNavigationCount != navCountBefore
                            let urlChanged = engine.currentURL != urlBefore
                            let tabAdded = self.tabs.count != tabsCountBefore
                            let loadingStarted = engine.isLoading
                            if !navigated && !urlChanged && !tabAdded && !loadingStarted {
                                if linkTarget == "_blank" {
                                    self.openTab(url: url, switchToIt: true)
                                } else {
                                    self.load(url: url)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func promptSelectOptions(title: String, options: [[String: Any]]) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        for opt in options.prefix(24) {
            guard let idx = opt["index"] as? Int,
                  let text = opt["text"] as? String else { continue }
            let selected = (opt["selected"] as? Bool) == true
            let display = selected ? "✓ \(text)" : text
            alert.addAction(UIAlertAction(title: display, style: .default) { [weak self] _ in
                let js = """
                (function() {
                    var s = window.__tvBrowserActiveSelect;
                    if (!s) return;
                    s.selectedIndex = \(idx);
                    s.dispatchEvent(new Event('input', { bubbles: true }));
                    s.dispatchEvent(new Event('change', { bubbles: true }));
                })();
                """
                self?.currentEngine?.evaluateJavaScript(js, completion: nil)
                self?.restoreBrowserFocus()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            self?.restoreBrowserFocus()
        })
        present(alert, animated: true)
    }

    private func promptWebTextInput(title: String, currentValue: String, isPassword: Bool, detectedUsername: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] tf in
            guard let self = self else { return }
            tf.text = currentValue
            tf.isSecureTextEntry = isPassword
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.returnKeyType = isPassword ? .done : .search
            tf.clearButtonMode = .whileEditing
            self.attachSubmitOnReturn(tf, alert: alert) { [weak self] text in
                self?.handleEnteredText(text, isPassword: isPassword, detectedUsername: detectedUsername, submit: true)
                self?.restoreBrowserFocus()
            }
        }

        let submitAction = UIAlertAction(title: "Escribir y Enviar", style: .default) { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            self?.handleEnteredText(text, isPassword: isPassword, detectedUsername: detectedUsername, submit: true)
            self?.restoreBrowserFocus()
        }
        alert.addAction(submitAction)
        alert.addAction(UIAlertAction(title: "Solo escribir", style: .default) { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            self?.handleEnteredText(text, isPassword: isPassword, detectedUsername: detectedUsername, submit: false)
            self?.restoreBrowserFocus()
        })
        alert.preferredAction = submitAction

        if let host = currentEngine?.currentURL?.host {
            let saved = BrowserStore.shared.credentials(forHost: host)
            if let cred = saved.first {
                let label = isPassword ? "Autocompletar contraseña (\(cred.username))" : "Autocompletar (\(cred.username))"
                alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                    let value = isPassword ? cred.password : cred.username
                    self?.applyWebTextInput(value, submit: isPassword)
                    self?.restoreBrowserFocus()
                })
            }
        }

        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            self?.restoreBrowserFocus()
        })
        present(alert, animated: true)
    }

    private func handleEnteredText(_ text: String, isPassword: Bool, detectedUsername: String, submit: Bool) {
        applyWebTextInput(text, submit: submit)

        if isPassword, !text.isEmpty, let host = currentEngine?.currentURL?.host {
            let existing = BrowserStore.shared.credentials(forHost: host)
            let alreadySaved = existing.contains { $0.password == text && ($0.username == detectedUsername || detectedUsername.isEmpty) }
            if !alreadySaved {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self = self, self.presentedViewController == nil else { return }
                    self.offerToSavePassword(host: host, username: detectedUsername, password: text)
                }
            }
        }
    }

    private func offerToSavePassword(host: String, username: String, password: String) {
        let userDisplay = username.isEmpty ? "esta cuenta" : username
        let alert = UIAlertController(
            title: "¿Guardar contraseña?",
            message: "Guardar credenciales para \(host) (\(userDisplay)) en el llavero de Apple TV.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Guardar", style: .default) { [weak self] _ in
            BrowserStore.shared.saveCredential(host: host, username: username, password: password)
            self?.restoreBrowserFocus()
        })
        alert.addAction(UIAlertAction(title: "Ahora no", style: .cancel) { [weak self] _ in
            self?.restoreBrowserFocus()
        })
        present(alert, animated: true)
    }

    private func applyWebTextInput(_ text: String, submit: Bool) {
        let jsonData = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        let jsonArray = String(data: jsonData, encoding: .utf8) ?? "[\"\"]"

        let js = """
        (function() {
            var value = \(jsonArray)[0];
            var el = window.__tvBrowserActiveInput;
            if (!el || !el.isConnected) {
                el = document.activeElement;
                if (!el || el === document.body) return 'no-input';
            }
            try { el.focus(); } catch (e) {}

            if (el.isContentEditable) {
                el.innerText = value;
            } else {
                var proto = (el instanceof HTMLTextAreaElement) ? HTMLTextAreaElement.prototype
                          : (el instanceof HTMLInputElement) ? HTMLInputElement.prototype : null;
                var desc = proto ? Object.getOwnPropertyDescriptor(proto, 'value') : null;
                try {
                    if (desc && desc.set) { desc.set.call(el, value); } else { el.value = value; }
                } catch (e) {
                    el.value = value;
                }
            }

            var ev;
            try { ev = new InputEvent('input', { bubbles: true, cancelable: false, inputType: 'insertText', data: value }); }
            catch (e) { ev = new Event('input', { bubbles: true }); }
            el.dispatchEvent(ev);
            el.dispatchEvent(new Event('change', { bubbles: true }));

            if (\(submit ? "true" : "false")) {
                setTimeout(function() {
                    var handled = false;
                    ['keydown', 'keypress', 'keyup'].forEach(function(k) {
                        var kev = new KeyboardEvent(k, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, charCode: k === 'keypress' ? 13 : 0, bubbles: true, cancelable: true });
                        try {
                            Object.defineProperty(kev, 'keyCode', { get: function() { return 13; } });
                            Object.defineProperty(kev, 'which', { get: function() { return 13; } });
                        } catch (e) {}
                        if (!el.dispatchEvent(kev)) handled = true;
                    });
                    if (handled) return;
                    var form = el.form || (el.closest ? el.closest('form') : null);
                    if (!form) return;
                    if (typeof form.requestSubmit === 'function') {
                        try { form.requestSubmit(); return; } catch (e) {}
                    }
                    var btn = form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
                    if (btn) { btn.click(); } else { form.submit(); }
                }, 60);
            }
            return 'ok';
        })();
        """
        currentEngine?.evaluateJavaScript(js, completion: nil)
    }

    private func typeDirectlyIntoWebInput(_ text: String) {
        if let alert = topPresenter() as? UIAlertController, let tf = alert.textFields?.first {
            tf.text = (tf.text ?? "") + text
            tf.sendActions(for: .editingChanged)
            return
        }
        let jsonData = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        let jsonArray = String(data: jsonData, encoding: .utf8) ?? "[\"\"]"

        let js = """
        (function() {
            var ch = \(jsonArray)[0];
            var el = window.__tvBrowserActiveInput || document.activeElement;
            if (!el || el === document.body) {
                el = document.querySelector('input[type="search"], input[name="q"], textarea[name="q"], input[type="text"], textarea');
                if (!el) return;
                window.__tvBrowserActiveInput = el;
            }
            try { el.focus(); } catch (e) {}

            if (el.isContentEditable) {
                el.innerText = (el.innerText || '') + ch;
            } else {
                var cur = el.value || '';
                var start = (typeof el.selectionStart === 'number') ? el.selectionStart : cur.length;
                var end = (typeof el.selectionEnd === 'number') ? el.selectionEnd : cur.length;
                var nextVal = cur.slice(0, start) + ch + cur.slice(end);
                var proto = (el instanceof HTMLTextAreaElement) ? HTMLTextAreaElement.prototype
                          : (el instanceof HTMLInputElement) ? HTMLInputElement.prototype : null;
                var desc = proto ? Object.getOwnPropertyDescriptor(proto, 'value') : null;
                try {
                    if (desc && desc.set) { desc.set.call(el, nextVal); } else { el.value = nextVal; }
                } catch (e) { el.value = nextVal; }
                try { el.setSelectionRange(start + ch.length, start + ch.length); } catch (e) {}
            }
            var ev;
            try { ev = new InputEvent('input', { bubbles: true, inputType: 'insertText', data: ch }); }
            catch (e) { ev = new Event('input', { bubbles: true }); }
            el.dispatchEvent(ev);
        })();
        """
        currentEngine?.evaluateJavaScript(js, completion: nil)
    }

    private func renderErrorPage(error: NSError, failingURL: URL?, in tab: BrowserTab) {
        if let failingURL = failingURL {
            lastFailedURLByTab[tab.id] = failingURL
        }
        let host = failingURL?.host ?? failingURL?.absoluteString ?? "la página"
        let desc = error.localizedDescription
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let safeHost = host
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let html = """
        <!DOCTYPE html>
        <html lang="es">
        <head>
            <meta charset="utf-8">
            <style>
                body {
                    margin: 0; height: 100vh; display: flex; align-items: center; justify-content: center;
                    background: #0b1120; color: #f8fafc; font-family: -apple-system, sans-serif;
                }
                .box {
                    max-width: 720px; padding: 48px; border-radius: 28px;
                    background: #131c31; border: 1px solid #1e293b; text-align: center;
                }
                h1 { font-size: 38px; margin: 0 0 16px; }
                p { font-size: 24px; color: #94a3b8; line-height: 1.45; margin: 0 0 32px; }
                a.btn {
                    display: inline-block; background: #2563eb; color: #fff; text-decoration: none;
                    font-size: 24px; font-weight: 600; padding: 16px 36px; border-radius: 14px;
                }
            </style>
        </head>
        <body>
            <div class="box">
                <h1>Platanet no puede abrir \(safeHost)</h1>
                <p>\(desc)</p>
                <a class="btn" href="tvbrowser://retry">Reintentar</a>
            </div>
        </body>
        </html>
        """
        tab.engine.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - InputControllerDelegate

extension BrowserViewController: InputControllerDelegate {
    func inputControllerDidMoveCursor(delta: CGPoint) {
        guard !toolbarVisible, presentedViewController == nil else { return }
        if cursorView.mode == .scroll {
            scrollWebView(by: CGPoint(x: delta.x * 0.85, y: delta.y * 0.85))
        } else {
            moveCursor(by: delta)
        }
    }

    func inputControllerDidScroll(delta: CGPoint) {
        guard !toolbarVisible, presentedViewController == nil else { return }
        scrollWebView(by: delta)
    }

    func inputControllerDidClick() {
        guard !toolbarVisible, presentedViewController == nil else { return }
        performClickAtCursor()
    }

    func inputControllerDidLongPressSelect() {
        guard !toolbarVisible, presentedViewController == nil else { return }
        presentQuickRemoteMenu()
    }

    func inputControllerDidToggleMode() {
        guard !toolbarVisible, presentedViewController == nil else { return }
        modeTapped()
    }

    func inputControllerDidPressBack() {
        if toolbarVisible {
            setToolbarVisible(false)
        } else if currentEngine?.canGoBack == true {
            currentEngine?.goBack()
        } else if tabs.count > 1 {
            closeTab(at: activeTabIndex)
            showToast("Pestaña cerrada")
        }
    }

    func inputControllerDidPressForward() {
        guard !toolbarVisible, presentedViewController == nil else { return }
        currentEngine?.goForward()
    }

    func inputControllerDidToggleToolbar() {
        guard presentedViewController == nil else { return }
        setToolbarVisible(!toolbarVisible)
    }

    func inputControllerIsWebInputFocused() -> Bool {
        isWebInputFocused
    }

    func inputControllerDidTypeText(_ text: String) {
        typeDirectlyIntoWebInput(text)
    }

    func inputControllerDidSendKeyboardAction(_ action: WebKeyboardAction) {
        if let alert = topPresenter() as? UIAlertController, let tf = alert.textFields?.first {
            switch action {
            case .backspace:
                if var cur = tf.text, !cur.isEmpty {
                    cur.removeLast()
                    tf.text = cur
                    tf.sendActions(for: .editingChanged)
                }
                return
            case .enter:
                tf.sendActions(for: .editingDidEndOnExit)
                return
            case .escape:
                alert.dismiss(animated: true) { [weak self] in
                    self?.restoreBrowserFocus()
                }
                return
            default:
                return
            }
        }
        let js: String
        switch action {
        case .enter:
            js = """
            (function() {
                var el = window.__tvBrowserActiveInput || document.activeElement;
                if (!el) return;
                var handled = false;
                ['keydown', 'keypress', 'keyup'].forEach(function(k) {
                    var kev = new KeyboardEvent(k, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true });
                    if (!el.dispatchEvent(kev)) handled = true;
                });
                if (!handled) {
                    var form = el.form || (el.closest ? el.closest('form') : null);
                    if (form && typeof form.requestSubmit === 'function') { try { form.requestSubmit(); return; } catch(e){} }
                    if (form) {
                        var btn = form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
                        if (btn) btn.click(); else form.submit();
                    }
                }
            })();
            """
        case .backspace:
            js = """
            (function() {
                var el = window.__tvBrowserActiveInput || document.activeElement;
                if (!el || el === document.body) return;
                if (el.isContentEditable) {
                    var t = el.innerText || '';
                    el.innerText = t.slice(0, Math.max(0, t.length - 1));
                } else {
                    var cur = el.value || '';
                    var start = (typeof el.selectionStart === 'number') ? el.selectionStart : cur.length;
                    var end = (typeof el.selectionEnd === 'number') ? el.selectionEnd : cur.length;
                    var nextVal = (start !== end) ? (cur.slice(0, start) + cur.slice(end)) : (start > 0 ? cur.slice(0, start - 1) + cur.slice(start) : cur);
                    var nextPos = (start !== end) ? start : Math.max(0, start - 1);
                    var proto = (el instanceof HTMLTextAreaElement) ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
                    var desc = Object.getOwnPropertyDescriptor(proto, 'value');
                    try { if (desc && desc.set) desc.set.call(el, nextVal); else el.value = nextVal; } catch(e) { el.value = nextVal; }
                    try { el.setSelectionRange(nextPos, nextPos); } catch(e) {}
                }
                el.dispatchEvent(new Event('input', { bubbles: true }));
            })();
            """
        case .tab(let shift):
            js = """
            (function() {
                var list = Array.prototype.slice.call(document.querySelectorAll('input:not([type="hidden"]):not([disabled]), textarea:not([disabled]), select:not([disabled]), button:not([disabled]), a[href]'));
                if (!list.length) return;
                var idx = list.indexOf(document.activeElement);
                var nextIdx = \(shift ? "-1" : "1");
                var target = list[(idx + nextIdx + list.length) % list.length];
                if (target) {
                    target.focus();
                    window.__tvBrowserActiveInput = target;
                }
            })();
            """
        case .escape:
            isWebInputFocused = false
            js = "(function(){ var el = document.activeElement; if (el && el.blur) el.blur(); window.__tvBrowserActiveInput = null; })();"
        case .arrowUp:
            scrollWebView(by: CGPoint(x: 0, y: -120))
            return
        case .arrowDown:
            scrollWebView(by: CGPoint(x: 0, y: 120))
            return
        case .arrowLeft:
            scrollWebView(by: CGPoint(x: -120, y: 0))
            return
        case .arrowRight:
            scrollWebView(by: CGPoint(x: 120, y: 0))
            return
        }
        currentEngine?.evaluateJavaScript(js, completion: nil)
    }
}

// MARK: - TVWebEngineDelegate

extension BrowserViewController: TVWebEngineDelegate {
    func webEngineDidStartLoading(_ engine: TVWebEngine) {
        guard let tab = tab(for: engine) else { return }
        tab.isLoading = true
        if tab === activeTab {
            isWebInputFocused = false
            cachedCursorOverInnerScroll = false
            cachedPageCanScrollUp = false
            updateProgressUI()
            updateToolbarState()
        }
    }

    func webEngineDidFinishLoading(_ engine: TVWebEngine) {
        guard let tab = tab(for: engine) else { return }
        tab.isLoading = false
        tab.estimatedProgress = 1.0
        applyPageZoom(for: tab)
        if tab.adBlockEnabled {
            let adScript = AdBlocker.shared.cosmeticAndPopupScript
            if !adScript.isEmpty {
                engine.evaluateJavaScript(adScript, completion: nil)
            }
        }
        if tab === activeTab {
            updateProgressUI()
            updateToolbarState()
        }
    }

    @objc(webEngine:didFailWithError:failingURL:)
    func webEngine(_ engine: TVWebEngine, didFailWithError error: Error, failing failingURL: URL?) {
        guard let tab = tab(for: engine) else { return }
        tab.isLoading = false
        if tab === activeTab {
            updateProgressUI()
            updateToolbarState()
        }
        renderErrorPage(error: error as NSError, failingURL: failingURL ?? tab.url, in: tab)
    }

    @objc(webEngine:didUpdateURL:title:)
    func webEngine(_ engine: TVWebEngine, didUpdate url: URL?, title: String?) {
        guard let tab = tab(for: engine) else { return }
        if let url = url, url.scheme != "about" {
            tab.url = url
            BrowserStore.shared.recordHistory(title: title ?? url.host ?? url.absoluteString, urlString: url.absoluteString)
        }
        if let title = title, !title.isEmpty {
            tab.title = title
        } else if let host = url?.host {
            tab.title = host
        }
        if tab === activeTab {
            updateToolbarState()
        }
    }

    @objc(webEngine:didUpdateProgress:)
    func webEngine(_ engine: TVWebEngine, didUpdateProgress progress: Double) {
        guard let tab = tab(for: engine) else { return }
        tab.estimatedProgress = progress
        if tab === activeTab {
            updateProgressUI()
        }
    }

    @objc(webEngine:didUpdateNavigationStateCanGoBack:canGoForward:isLoading:)
    func webEngine(_ engine: TVWebEngine, didUpdateNavigationStateCanGoBack canGoBack: Bool, canGoForward: Bool, isLoading: Bool) {
        guard let tab = tab(for: engine) else { return }
        tab.isLoading = isLoading
        if tab === activeTab {
            updateToolbarState()
            updateProgressUI()
        }
    }

    @objc(webEngine:shouldAllowURL:)
    func webEngine(_ engine: TVWebEngine, shouldAllow url: URL) -> Bool {
        if url.scheme == "tvbrowser" && url.host == "retry" {
            if let tab = tab(for: engine), let retryURL = lastFailedURLByTab[tab.id] {
                DispatchQueue.main.async { [weak self] in
                    self?.load(url: retryURL, in: tab)
                }
            }
            return false
        }
        guard let tab = tab(for: engine) else { return AdBlocker.shared.shouldAllow(url: url) }
        return tab.adBlockEnabled ? AdBlocker.shared.shouldAllow(url: url) : true
    }

    @objc(webEngine:createPopupEngineWithConfiguration:forURL:)
    func webEngine(_ engine: TVWebEngine, createPopupEngineWithConfiguration configuration: Any?, for url: URL?) -> TVWebEngine? {
        let popupTab = openTab(url: nil, runtimeConfiguration: configuration, webApp: nil, switchToIt: true)
        if let url = url {
            popupTab.url = url
            updateToolbarState()
        }
        return popupTab.engine
    }

    func webEngineDidRequestClose(_ engine: TVWebEngine) {
        guard let idx = tabs.firstIndex(where: { $0.engine === engine }) else { return }
        closeTab(at: idx)
    }

    func webEngineWebContentProcessDidTerminate(_ engine: TVWebEngine) {
        guard let tab = tab(for: engine) else { return }
        if tab === activeTab {
            showToast("WebKit se recuperó tras reiniciar el proceso", duration: 2.0)
        }
        engine.reload()
    }

    private func topPresenter() -> UIViewController {
        var vc: UIViewController = self
        while let presented = vc.presentedViewController, !presented.isBeingDismissed {
            vc = presented
        }
        return vc
    }

    @objc(webEngine:runJavaScriptAlert:completion:)
    func webEngine(_ engine: TVWebEngine, runJavaScriptAlert message: String, completion: @escaping () -> Void) {
        let presenter = topPresenter()
        let alert = UIAlertController(title: currentEngine?.currentURL?.host ?? "Aviso", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak self] _ in
            completion()
            self?.restoreBrowserFocus()
        })
        presenter.present(alert, animated: true)
    }

    @objc(webEngine:runJavaScriptConfirm:completion:)
    func webEngine(_ engine: TVWebEngine, runJavaScriptConfirm message: String, completion: @escaping (Bool) -> Void) {
        let presenter = topPresenter()
        let alert = UIAlertController(title: currentEngine?.currentURL?.host ?? "Confirmar", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak self] _ in
            completion(true)
            self?.restoreBrowserFocus()
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            completion(false)
            self?.restoreBrowserFocus()
        })
        presenter.present(alert, animated: true)
    }

    @objc(webEngine:runJavaScriptPrompt:defaultText:completion:)
    func webEngine(_ engine: TVWebEngine, runJavaScriptPrompt prompt: String, defaultText: String?, completion: @escaping (String?) -> Void) {
        let presenter = topPresenter()
        let alert = UIAlertController(title: currentEngine?.currentURL?.host ?? "Entrada", message: prompt, preferredStyle: .alert)
        alert.addTextField { tf in tf.text = defaultText }
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak self, weak alert] _ in
            completion(alert?.textFields?.first?.text)
            self?.restoreBrowserFocus()
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            completion(nil)
            self?.restoreBrowserFocus()
        })
        presenter.present(alert, animated: true)
    }

    @objc(webEngine:didReceiveScriptMessageName:body:)
    func webEngine(_ engine: TVWebEngine, didReceiveScriptMessageName name: String, body: Any?) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return }
        if type == "inputFocus" {
            if tab(for: engine) === activeTab {
                isWebInputFocused = (dict["focused"] as? Bool) == true
            }
        } else if type == "videoDetected", let src = dict["src"] as? String, let url = URL(string: src) {
            if let tab = tab(for: engine) {
                tab.detectedVideoURL = url
                if tab === activeTab {
                    updateToolbarState()
                }
            }
        }
    }
}
