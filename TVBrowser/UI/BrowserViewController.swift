import UIKit

final class BrowserViewController: UIViewController {
    private var webEngine: TVWebEngine!
    private let cursorView = VirtualCursorView()
    private let inputController = InputController()

    private let toolbarContainer = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let toolbarStack = UIStackView()
    private let urlButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let bookmarkAddButton = UIButton(type: .system)
    private let bookmarksButton = UIButton(type: .system)
    private let historyButton = UIButton(type: .system)
    private let adBlockButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let hideToolbarButton = UIButton(type: .system)

    private let statusBadge = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private var toolbarVisible = false
    private var lastPanPoint: CGPoint = .zero
    private let homeURL = URL(string: "https://www.google.com")!

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if toolbarVisible {
            return [urlButton]
        }
        return [view]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupWebEngine()
        setupToolbar()
        setupStatusBadge()
        setupCursor()
        setupGestures()

        inputController.delegate = self
        inputController.start()

        load(url: homeURL)
    }

    deinit {
        inputController.stop()
    }

    private func setupWebEngine() {
        webEngine = TVWebEngine(frame: view.bounds)
        webEngine.delegate = self
        webEngine.webView.isUserInteractionEnabled = false
        view.addSubview(webEngine.webView)
    }

    private func setupToolbar() {
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.layer.cornerRadius = 18
        toolbarContainer.clipsToBounds = true
        toolbarContainer.isHidden = true
        toolbarContainer.alpha = 0
        view.addSubview(toolbarContainer)

        toolbarStack.axis = .horizontal
        toolbarStack.spacing = 14
        toolbarStack.alignment = .center
        toolbarStack.distribution = .fill
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.contentView.addSubview(toolbarStack)

        NSLayoutConstraint.activate([
            toolbarContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            toolbarContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            toolbarContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            toolbarContainer.heightAnchor.constraint(equalToConstant: 84),

            toolbarStack.topAnchor.constraint(equalTo: toolbarContainer.contentView.topAnchor, constant: 10),
            toolbarStack.bottomAnchor.constraint(equalTo: toolbarContainer.contentView.bottomAnchor, constant: -10),
            toolbarStack.leadingAnchor.constraint(equalTo: toolbarContainer.contentView.leadingAnchor, constant: 20),
            toolbarStack.trailingAnchor.constraint(equalTo: toolbarContainer.contentView.trailingAnchor, constant: -20)
        ])

        configureButton(backButton, title: "◀", action: #selector(backTapped))
        configureButton(forwardButton, title: "▶", action: #selector(forwardTapped))
        configureButton(reloadButton, title: "↻", action: #selector(reloadTapped))

        configureButton(urlButton, title: "https://www.google.com", action: #selector(urlTapped))
        urlButton.contentHorizontalAlignment = .left
        urlButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        urlButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true

        configureButton(bookmarkAddButton, title: "★+", action: #selector(addBookmarkTapped))
        configureButton(bookmarksButton, title: "Marcadores", action: #selector(bookmarksTapped))
        configureButton(historyButton, title: "Historial", action: #selector(historyTapped))
        configureButton(adBlockButton, title: "AdBlock: ON", action: #selector(adBlockTapped))
        configureButton(modeButton, title: "Modo: Cursor", action: #selector(modeTapped))
        configureButton(hideToolbarButton, title: "Navegar", action: #selector(hideToolbarTapped))

        [
            backButton, forwardButton, reloadButton,
            urlButton,
            bookmarkAddButton, bookmarksButton, historyButton,
            adBlockButton, modeButton, hideToolbarButton
        ].forEach { toolbarStack.addArrangedSubview($0) }

        updateToolbarState()
    }

    private func configureButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 22, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        button.layer.cornerRadius = 10
        button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        button.setTitleColor(.white, for: .normal)
        button.addTarget(self, action: action, for: .primaryActionTriggered)
    }

    private func setupStatusBadge() {
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        statusBadge.textColor = .white
        statusBadge.font = .systemFont(ofSize: 20, weight: .medium)
        statusBadge.textAlignment = .center
        statusBadge.layer.cornerRadius = 12
        statusBadge.clipsToBounds = true
        statusBadge.text = "  Cursor · Play/Pausa: Scroll · Menú: Atrás / Barra  "
        view.addSubview(statusBadge)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            statusBadge.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            statusBadge.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusBadge.heightAnchor.constraint(equalToConstant: 38),

            loadingIndicator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            loadingIndicator.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28)
        ])
    }

    private func setupCursor() {
        cursorView.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        view.addSubview(cursorView)
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(pan)

        let playPauseTap = UITapGestureRecognizer(target: self, action: #selector(modeTapped))
        playPauseTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        view.addGestureRecognizer(playPauseTap)
    }

    // MARK: - Navigation & Actions

    func load(url: URL) {
        urlButton.setTitle(url.absoluteString, for: .normal)
        webEngine.load(url)
    }

    private func openInputURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let direct = URL(string: trimmed), direct.scheme != nil {
            load(url: direct)
        } else if trimmed.contains("."), !trimmed.contains(" "),
                  let httpsURL = URL(string: "https://" + trimmed) {
            load(url: httpsURL)
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            if let searchURL = URL(string: "https://www.google.com/search?q=" + encoded) {
                load(url: searchURL)
            }
        }
    }

    private func setToolbarVisible(_ visible: Bool) {
        guard toolbarVisible != visible else { return }
        toolbarVisible = visible
        cursorView.isHidden = visible

        if visible {
            updateToolbarState()
            toolbarContainer.isHidden = false
            UIView.animate(withDuration: 0.2) {
                self.toolbarContainer.alpha = 1
            } completion: { _ in
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
            }
        } else {
            UIView.animate(withDuration: 0.2, animations: {
                self.toolbarContainer.alpha = 0
            }) { _ in
                self.toolbarContainer.isHidden = true
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
            }
        }
    }

    private func updateToolbarState() {
        backButton.isEnabled = webEngine.canGoBack
        backButton.alpha = webEngine.canGoBack ? 1.0 : 0.4
        forwardButton.isEnabled = webEngine.canGoForward
        forwardButton.alpha = webEngine.canGoForward ? 1.0 : 0.4

        let adState = AdBlocker.shared.isEnabled ? "ON" : "OFF"
        adBlockButton.setTitle("AdBlock: \(adState)", for: .normal)

        let modeName = cursorView.mode == .pointer ? "Cursor" : "Scroll"
        modeButton.setTitle("Modo: \(modeName)", for: .normal)
        statusBadge.text = "  \(modeName) · Play/Pausa: Cambiar · Menú: Atrás/Barra  "

        if let urlStr = webEngine.currentURL?.absoluteString {
            urlButton.setTitle(urlStr, for: .normal)
            let isSaved = BrowserStore.shared.isBookmarked(urlString: urlStr)
            bookmarkAddButton.setTitle(isSaved ? "★" : "★+", for: .normal)
        }
    }

    @objc private func backTapped() {
        webEngine.goBack()
        updateToolbarState()
    }

    @objc private func forwardTapped() {
        webEngine.goForward()
        updateToolbarState()
    }

    @objc private func reloadTapped() {
        webEngine.reload()
        setToolbarVisible(false)
    }

    @objc private func urlTapped() {
        let alert = UIAlertController(
            title: "Ir a dirección o buscar",
            message: "Escribe una URL o término de búsqueda",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.text = self.webEngine.currentURL?.absoluteString ?? "https://"
            tf.keyboardType = .URL
            tf.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Ir", style: .default) { _ in
            if let text = alert.textFields?.first?.text {
                self.setToolbarVisible(false)
                self.openInputURL(text)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func addBookmarkTapped() {
        guard let url = webEngine.currentURL else { return }
        let title = webEngine.currentTitle ?? url.host ?? url.absoluteString
        BrowserStore.shared.addBookmark(title: title, urlString: url.absoluteString)
        updateToolbarState()
    }

    @objc private func bookmarksTapped() {
        let vc = BookmarksViewController(style: .grouped)
        vc.onSelectURL = { [weak self] url in
            self?.setToolbarVisible(false)
            self?.load(url: url)
        }
        present(UINavigationController(rootViewController: vc), animated: true)
    }

    @objc private func historyTapped() {
        let vc = HistoryViewController(style: .grouped)
        vc.onSelectURL = { [weak self] url in
            self?.setToolbarVisible(false)
            self?.load(url: url)
        }
        present(UINavigationController(rootViewController: vc), animated: true)
    }

    @objc private func adBlockTapped() {
        AdBlocker.shared.isEnabled.toggle()
        updateToolbarState()
        webEngine.reload()
    }

    @objc private func modeTapped() {
        cursorView.mode = (cursorView.mode == .pointer) ? .scroll : .pointer
        updateToolbarState()
    }

    @objc private func hideToolbarTapped() {
        setToolbarVisible(false)
    }

    // MARK: - Touchpad Pan & Press Handling

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !toolbarVisible else { return }
        let point = gesture.translation(in: view)

        switch gesture.state {
        case .began:
            lastPanPoint = point
        case .changed:
            let dx = point.x - lastPanPoint.x
            let dy = point.y - lastPanPoint.y
            lastPanPoint = point

            if cursorView.mode == .pointer {
                moveCursor(by: CGPoint(x: dx * 1.35, y: dy * 1.35))
            } else {
                scrollWebView(by: CGPoint(x: -dx * 1.5, y: -dy * 1.5))
            }
        default:
            lastPanPoint = .zero
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if toolbarVisible {
            if presses.contains(where: { $0.type == .menu }) {
                setToolbarVisible(false)
                return
            }
            super.pressesBegan(presses, with: event)
            return
        }

        if inputController.handlePressesBegan(presses) {
            return
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if toolbarVisible {
            super.pressesEnded(presses, with: event)
            return
        }
        if inputController.handlePressesEnded(presses) {
            return
        }
        super.pressesEnded(presses, with: event)
    }

    // MARK: - Cursor & Scroll Logic

    private func moveCursor(by delta: CGPoint) {
        let bounds = view.bounds
        let nextX = max(8, min(bounds.width - 8, cursorView.center.x + delta.x))
        let nextY = max(8, min(bounds.height - 8, cursorView.center.y + delta.y))
        cursorView.center = CGPoint(x: nextX, y: nextY)

        // Edge scrolling when cursor reaches top or bottom
        if nextY <= 12 && delta.y < 0 {
            scrollWebView(by: CGPoint(x: 0, y: delta.y * 2.2))
        } else if nextY >= bounds.height - 12 && delta.y > 0 {
            scrollWebView(by: CGPoint(x: 0, y: delta.y * 2.2))
        }
    }

    private func scrollWebView(by delta: CGPoint) {
        if let scrollView = webEngine.scrollView {
            let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let targetX = max(0, min(maxX, scrollView.contentOffset.x + delta.x))
            let targetY = max(0, min(maxY, scrollView.contentOffset.y + delta.y))
            scrollView.setContentOffset(CGPoint(x: targetX, y: targetY), animated: false)
        } else {
            let js = "window.scrollBy(\(delta.x), \(delta.y));"
            webEngine.evaluateJavaScript(js, completion: nil)
        }
    }

    private func performClickAtCursor() {
        cursorView.animateClick()
        let pt = cursorView.center
        let js = """
        (function() {
            var el = document.elementFromPoint(\(pt.x), \(pt.y));
            if (!el) return null;
            var tag = (el.tagName || '').toLowerCase();
            if (tag === 'input' || tag === 'textarea' || el.isContentEditable) {
                var type = (el.getAttribute('type') || 'text').toLowerCase();
                if (type !== 'submit' && type !== 'button' && type !== 'checkbox' && type !== 'radio') {
                    window.__tvBrowserActiveInput = el;
                    return JSON.stringify({
                        kind: 'input',
                        value: el.value || el.innerText || '',
                        placeholder: el.placeholder || el.name || 'Texto',
                        isPassword: type === 'password'
                    });
                }
            }
            el.focus && el.focus();
            ['mouseover', 'mousedown', 'mouseup', 'click'].forEach(function(evt) {
                el.dispatchEvent(new MouseEvent(evt, {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    clientX: \(pt.x),
                    clientY: \(pt.y)
                }));
            });
            if (typeof el.click === 'function') { el.click(); }
            return JSON.stringify({ kind: 'clicked' });
        })();
        """

        webEngine.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self,
                  let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["kind"] as? String == "input" else {
                return
            }

            let currentVal = obj["value"] as? String ?? ""
            let placeholder = obj["placeholder"] as? String ?? "Texto"
            let isPassword = obj["isPassword"] as? Bool ?? false

            DispatchQueue.main.async {
                self.promptWebTextInput(title: placeholder, currentValue: currentVal, isPassword: isPassword)
            }
        }
    }

    private func promptWebTextInput(title: String, currentValue: String, isPassword: Bool) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = currentValue
            tf.isSecureTextEntry = isPassword
            tf.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in
            let text = alert.textFields?.first?.text ?? ""
            self.applyWebTextInput(text, submit: false)
        })
        alert.addAction(UIAlertAction(title: "Aceptar y Enviar", style: .default) { _ in
            let text = alert.textFields?.first?.text ?? ""
            self.applyWebTextInput(text, submit: true)
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    private func applyWebTextInput(_ text: String, submit: Bool) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let submitJS = submit ? """
        if (el.form) {
            el.form.submit();
        } else {
            el.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
            el.dispatchEvent(new KeyboardEvent('keypress', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
            el.dispatchEvent(new KeyboardEvent('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
        }
        """ : ""

        let js = """
        (function() {
            var el = window.__tvBrowserActiveInput;
            if (!el) return;
            if (el.isContentEditable) {
                el.innerText = "\(escaped)";
            } else {
                var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set
                          || Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set;
                if (setter) {
                    setter.call(el, "\(escaped)");
                } else {
                    el.value = "\(escaped)";
                }
            }
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            \(submitJS)
        })();
        """
        webEngine.evaluateJavaScript(js, completion: nil)
    }
}

// MARK: - InputControllerDelegate

extension BrowserViewController: InputControllerDelegate {
    func inputControllerDidMoveCursor(delta: CGPoint) {
        guard !toolbarVisible else { return }
        if cursorView.mode == .scroll {
            scrollWebView(by: CGPoint(x: delta.x * 1.5, y: delta.y * 1.5))
        } else {
            moveCursor(by: delta)
        }
    }

    func inputControllerDidScroll(delta: CGPoint) {
        guard !toolbarVisible else { return }
        scrollWebView(by: delta)
    }

    func inputControllerDidClick() {
        guard !toolbarVisible else { return }
        performClickAtCursor()
    }

    func inputControllerDidToggleMode() {
        guard !toolbarVisible else { return }
        modeTapped()
    }

    func inputControllerDidPressBack() {
        if toolbarVisible {
            setToolbarVisible(false)
        } else if webEngine.canGoBack {
            webEngine.goBack()
        } else {
            setToolbarVisible(true)
        }
    }

    func inputControllerDidPressForward() {
        guard !toolbarVisible else { return }
        webEngine.goForward()
    }

    func inputControllerDidToggleToolbar() {
        setToolbarVisible(!toolbarVisible)
    }
}

// MARK: - TVWebEngineDelegate

extension BrowserViewController: TVWebEngineDelegate {
    func webEngineDidStartLoading(_ engine: TVWebEngine) {
        loadingIndicator.startAnimating()
    }

    func webEngineDidFinishLoading(_ engine: TVWebEngine) {
        loadingIndicator.stopAnimating()
        let adScript = AdBlocker.shared.cosmeticAndPopupScript
        if !adScript.isEmpty {
            engine.evaluateJavaScript(adScript, completion: nil)
        }
        updateToolbarState()
    }

    func webEngine(_ engine: TVWebEngine, didFailWithError error: Error) {
        loadingIndicator.stopAnimating()
        updateToolbarState()
    }

    func webEngine(_ engine: TVWebEngine, didUpdate url: URL?, title: String?) {
        if let url = url {
            BrowserStore.shared.recordHistory(title: title ?? url.host ?? url.absoluteString, urlString: url.absoluteString)
        }
        updateToolbarState()
    }

    func webEngine(_ engine: TVWebEngine, shouldAllow url: URL) -> Bool {
        AdBlocker.shared.shouldAllow(url: url)
    }
}
