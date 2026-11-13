import UIKit

final class BrowserViewController: UIViewController {
    private var webEngine: TVWebEngine!
    private let cursorView = VirtualCursorView()
    private let inputController = InputController()

    private let toolbarContainer = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let toolbarStack = UIStackView()
    private let searchButton = UIButton(type: .system)
    private let urlButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let zoomOutButton = UIButton(type: .system)
    private let zoomInButton = UIButton(type: .system)
    private let bookmarkAddButton = UIButton(type: .system)
    private let bookmarksButton = UIButton(type: .system)
    private let historyButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let adBlockButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let hideToolbarButton = UIButton(type: .system)

    private let statusBadge = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    private var toolbarVisible = false
    private var lastPanPoint: CGPoint = .zero
    private var lastUsernameEntered: String = ""
    private var isLoadingPage = false
    private let homeURL = URL(string: "https://www.google.com")!

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if toolbarVisible {
            return [searchButton]
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
        toolbarContainer.layer.cornerRadius = 22
        toolbarContainer.layer.borderWidth = 1.5
        toolbarContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        toolbarContainer.clipsToBounds = true
        toolbarContainer.isHidden = true
        toolbarContainer.alpha = 0
        view.addSubview(toolbarContainer)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        toolbarContainer.contentView.addSubview(scroll)

        toolbarStack.axis = .horizontal
        toolbarStack.spacing = 14
        toolbarStack.alignment = .center
        toolbarStack.distribution = .fill
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(toolbarStack)

        NSLayoutConstraint.activate([
            toolbarContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            toolbarContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            toolbarContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            toolbarContainer.heightAnchor.constraint(equalToConstant: 100),

            scroll.topAnchor.constraint(equalTo: toolbarContainer.contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: toolbarContainer.contentView.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: toolbarContainer.contentView.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: toolbarContainer.contentView.trailingAnchor, constant: -18),

            toolbarStack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 12),
            toolbarStack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -12),
            toolbarStack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            toolbarStack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            toolbarStack.heightAnchor.constraint(equalTo: scroll.heightAnchor, constant: -24)
        ])

        configureButton(searchButton, title: "🔍 Buscar / URL", action: #selector(urlTapped), accent: true)
        configureButton(backButton, title: "◀", action: #selector(backTapped))
        configureButton(forwardButton, title: "▶", action: #selector(forwardTapped))
        configureButton(reloadButton, title: "↻", action: #selector(reloadTapped))

        configureButton(urlButton, title: "https://www.google.com", action: #selector(urlTapped))
        urlButton.contentHorizontalAlignment = .left
        urlButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        urlButton.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true

        configureButton(zoomOutButton, title: "A-", action: #selector(zoomOutTapped))
        configureButton(zoomInButton, title: "A+", action: #selector(zoomInTapped))
        configureButton(bookmarkAddButton, title: "★+", action: #selector(addBookmarkTapped))
        configureButton(bookmarksButton, title: "Marcadores", action: #selector(bookmarksTapped))
        configureButton(historyButton, title: "Historial", action: #selector(historyTapped))
        configureButton(exportButton, title: "Exportar", action: #selector(exportTapped))
        configureButton(adBlockButton, title: "AdBlock: ON", action: #selector(adBlockTapped))
        configureButton(modeButton, title: "Modo: Cursor", action: #selector(modeTapped))
        configureButton(hideToolbarButton, title: "Navegar", action: #selector(hideToolbarTapped))

        [
            searchButton, backButton, forwardButton, reloadButton,
            urlButton,
            zoomOutButton, zoomInButton,
            bookmarkAddButton, bookmarksButton, historyButton, exportButton,
            adBlockButton, modeButton, hideToolbarButton
        ].forEach { toolbarStack.addArrangedSubview($0) }

        updateToolbarState()
    }

    private func configureButton(_ button: UIButton, title: String, action: Selector, accent: Bool = false) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 25, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        button.layer.cornerRadius = 14
        button.backgroundColor = accent ? UIColor.systemBlue.withAlphaComponent(0.75) : UIColor.white.withAlphaComponent(0.14)
        button.setTitleColor(.white, for: .normal)
        button.addTarget(self, action: action, for: .primaryActionTriggered)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations({
            if let prev = context.previouslyFocusedView as? UIButton, prev.isDescendant(of: self.toolbarContainer) {
                prev.transform = .identity
                prev.backgroundColor = (prev == self.searchButton)
                    ? UIColor.systemBlue.withAlphaComponent(0.75)
                    : UIColor.white.withAlphaComponent(0.14)
                prev.setTitleColor(.white, for: .normal)
            }
            if let next = context.nextFocusedView as? UIButton, next.isDescendant(of: self.toolbarContainer) {
                next.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
                next.backgroundColor = .white
                next.setTitleColor(.black, for: .normal)
            }
        }, completion: nil)
    }

    private func setupStatusBadge() {
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        statusBadge.textColor = .white
        statusBadge.font = .systemFont(ofSize: 23, weight: .medium)
        statusBadge.textAlignment = .center
        statusBadge.layer.cornerRadius = 14
        statusBadge.clipsToBounds = true
        view.addSubview(statusBadge)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            statusBadge.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            statusBadge.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusBadge.heightAnchor.constraint(equalToConstant: 44),

            loadingIndicator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            loadingIndicator.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28)
        ])
    }

    private func setupCursor() {
        cursorView.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        view.addSubview(cursorView)
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
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

    private func applyPageZoom() {
        let zoom = BrowserStore.shared.pageZoom
        let js = """
        (function() {
            if (document.documentElement) {
                document.documentElement.style.zoom = '\(zoom)';
                document.documentElement.style.webkitTextSizeAdjust = '\(Int(zoom * 100))%';
            }
        })();
        """
        webEngine.evaluateJavaScript(js, completion: nil)
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

        let zoomPct = Int(round(BrowserStore.shared.pageZoom * 100))
        let modeName = cursorView.mode == .pointer ? "Cursor" : "Scroll"
        modeButton.setTitle("Modo: \(modeName)", for: .normal)
        statusBadge.text = "  \(modeName) · Zoom \(zoomPct)% · Play/Pausa: Modo · Menú: Atrás/Barra  "

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

    @objc private func zoomOutTapped() {
        BrowserStore.shared.pageZoom -= 0.15
        applyPageZoom()
        updateToolbarState()
    }

    @objc private func zoomInTapped() {
        BrowserStore.shared.pageZoom += 0.15
        applyPageZoom()
        updateToolbarState()
    }

    @objc private func urlTapped() {
        let alert = UIAlertController(
            title: "Buscar en Google o ir a URL",
            message: "Escribe lo que quieras buscar o una dirección web",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "ej: youtube.com o noticias hoy"
            tf.text = ""
            tf.keyboardType = .URL
            tf.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Ir / Buscar", style: .default) { _ in
            if let text = alert.textFields?.first?.text {
                self.setToolbarVisible(false)
                self.openInputURL(text)
            }
        })
        if let current = webEngine.currentURL?.absoluteString {
            alert.addAction(UIAlertAction(title: "Editar URL actual", style: .default) { _ in
                self.openEditCurrentURL(current)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    private func openEditCurrentURL(_ current: String) {
        let alert = UIAlertController(title: "Editar dirección", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = current
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

    @objc private func exportTapped() {
        let vc = ExportViewController()
        present(vc, animated: true)
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
                moveCursor(by: CGPoint(x: dx * 1.45, y: dy * 1.45))
            } else {
                scrollWebView(by: CGPoint(x: -dx * 1.6, y: -dy * 1.6))
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

        if nextY <= 12 && delta.y < 0 {
            scrollWebView(by: CGPoint(x: 0, y: delta.y * 2.2))
        } else if nextY >= bounds.height - 12 && delta.y > 0 {
            scrollWebView(by: CGPoint(x: 0, y: delta.y * 2.2))
        }
    }

    private func scrollWebView(by delta: CGPoint) {
        if let scrollView = webEngine.scrollView, scrollView.contentSize.height > scrollView.bounds.height {
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
        let viewW = max(1, view.bounds.width)
        let viewH = max(1, view.bounds.height)

        let js = """
        (function() {
            var vw = window.innerWidth || document.documentElement.clientWidth || \(viewW);
            var vh = window.innerHeight || document.documentElement.clientHeight || \(viewH);
            var x = \(pt.x) * (vw / \(viewW));
            var y = \(pt.y) * (vh / \(viewH));
            var el = document.elementFromPoint(x, y);
            if (!el) {
                var z = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
                if (z !== 1) {
                    x = x / z;
                    y = y / z;
                    el = document.elementFromPoint(x, y);
                }
            }
            if (!el) return null;

            var inputEl = el.closest ? el.closest('input, textarea, [contenteditable="true"], [role="textbox"], [role="searchbox"]') : null;
            if (!inputEl && el.querySelector) {
                var childInput = el.querySelector('input:not([type="hidden"]), textarea');
                if (childInput) inputEl = childInput;
            }
            if (inputEl) {
                var tag = (inputEl.tagName || '').toLowerCase();
                var type = (inputEl.getAttribute('type') || 'text').toLowerCase();
                if (type !== 'submit' && type !== 'button' && type !== 'checkbox' && type !== 'radio' && type !== 'reset') {
                    window.__tvBrowserActiveInput = inputEl;
                    inputEl.focus && inputEl.focus();
                    return JSON.stringify({
                        kind: 'input',
                        value: inputEl.value || inputEl.innerText || '',
                        placeholder: inputEl.placeholder || inputEl.getAttribute('aria-label') || inputEl.name || 'Escribir texto',
                        isPassword: type === 'password'
                    });
                }
            }

            var target = (el.closest && el.closest('a[href], button, [role="button"], [role="link"]')) || el;
            target.focus && target.focus();
            ['mouseover', 'mousedown', 'mouseup', 'click'].forEach(function(evt) {
                target.dispatchEvent(new MouseEvent(evt, {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    clientX: x,
                    clientY: y
                }));
            });
            if (typeof target.click === 'function') { target.click(); }

            var link = el.closest ? el.closest('a[href]') : null;
            var href = (link && link.href && link.href.indexOf('javascript:') !== 0) ? link.href : null;
            return JSON.stringify({ kind: 'clicked', href: href });
        })();
        """

        webEngine.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self,
                  let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            let kind = obj["kind"] as? String
            if kind == "input" {
                let currentVal = obj["value"] as? String ?? ""
                let placeholder = obj["placeholder"] as? String ?? "Escribir texto"
                let isPassword = obj["isPassword"] as? Bool ?? false

                DispatchQueue.main.async {
                    self.promptWebTextInput(title: placeholder, currentValue: currentVal, isPassword: isPassword)
                }
            } else if kind == "clicked", let href = obj["href"] as? String, let url = URL(string: href) {
                // Fallback if the click didn't trigger navigation (e.g. target=_blank or intercepted link)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if !self.isLoadingPage && self.webEngine.currentURL?.absoluteString != href {
                        self.load(url: url)
                    }
                }
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
            self.handleEnteredText(text, isPassword: isPassword, submit: false)
        })
        alert.addAction(UIAlertAction(title: "Aceptar y Enviar", style: .default) { _ in
            let text = alert.textFields?.first?.text ?? ""
            self.handleEnteredText(text, isPassword: isPassword, submit: true)
        })

        if let host = webEngine.currentURL?.host {
            let saved = BrowserStore.shared.credentials(forHost: host)
            if let cred = saved.first {
                let label = isPassword ? "Autocompletar contraseña (\(cred.username))" : "Autocompletar (\(cred.username))"
                alert.addAction(UIAlertAction(title: label, style: .default) { _ in
                    let value = isPassword ? cred.password : cred.username
                    self.applyWebTextInput(value, submit: isPassword)
                })
            }
        }

        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    private func handleEnteredText(_ text: String, isPassword: Bool, submit: Bool) {
        if !isPassword && !text.isEmpty {
            lastUsernameEntered = text
        }
        applyWebTextInput(text, submit: submit)

        if isPassword, !text.isEmpty, let host = webEngine.currentURL?.host {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.offerToSavePassword(host: host, username: self.lastUsernameEntered, password: text)
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
        alert.addAction(UIAlertAction(title: "Guardar", style: .default) { _ in
            BrowserStore.shared.saveCredential(host: host, username: username, password: password)
        })
        alert.addAction(UIAlertAction(title: "Ahora no", style: .cancel))
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
            ['keydown', 'keypress', 'keyup'].forEach(function(k) {
                el.dispatchEvent(new KeyboardEvent(k, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
            });
        }
        """ : ""

        let js = """
        (function() {
            var el = window.__tvBrowserActiveInput;
            if (!el) return;
            el.focus && el.focus();
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
        isLoadingPage = true
        loadingIndicator.startAnimating()
    }

    func webEngineDidFinishLoading(_ engine: TVWebEngine) {
        isLoadingPage = false
        loadingIndicator.stopAnimating()
        applyPageZoom()
        let adScript = AdBlocker.shared.cosmeticAndPopupScript
        if !adScript.isEmpty {
            engine.evaluateJavaScript(adScript, completion: nil)
        }
        updateToolbarState()
    }

    func webEngine(_ engine: TVWebEngine, didFailWithError error: Error) {
        isLoadingPage = false
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
