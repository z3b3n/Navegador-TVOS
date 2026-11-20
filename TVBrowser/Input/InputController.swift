import UIKit
import GameController

enum WebKeyboardAction {
    case enter
    case backspace
    case tab(shift: Bool)
    case escape
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
}

protocol InputControllerDelegate: AnyObject {
    func inputControllerDidMoveCursor(delta: CGPoint)
    func inputControllerDidScroll(delta: CGPoint)
    func inputControllerDidClick()
    func inputControllerDidToggleMode()
    func inputControllerDidPressBack()
    func inputControllerDidPressForward()
    func inputControllerDidToggleToolbar()
    func inputControllerIsWebInputFocused() -> Bool
    func inputControllerDidTypeText(_ text: String)
    func inputControllerDidSendKeyboardAction(_ action: WebKeyboardAction)
}

final class InputController {
    weak var delegate: InputControllerDelegate?

    private var displayLink: CADisplayLink?
    private var activeDirections: Set<UIPress.PressType> = []
    private var dpadHoldDuration: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval = 0

    // Scroll inertia velocity (points / second)
    private var scrollVelocity: CGPoint = .zero

    // Press tracking for short vs long press & click-on-release
    private var playPauseLongTimer: Timer?
    private var playPauseLongFired = false
    private var menuLongTimer: Timer?
    private var menuLongFired = false
    private var selectPressActive = false
    private var selectPannedSignificantly = false

    // Debounce flags for gamepad buttons
    private var lastButtonA = false
    private var lastButtonB = false
    private var lastButtonX = false
    private var lastButtonY = false
    private var lastLeftShoulder = false
    private var lastRightShoulder = false

    private let longPressThreshold: TimeInterval = 0.45

    var isSelectPressed: Bool { selectPressActive }

    func markSelectPanMoved() {
        if selectPressActive {
            selectPannedSignificantly = true
        }
    }

    func applyScrollImpulse(velocity: CGPoint) {
        // Clamp extreme flick velocities while preserving snappy inertia
        let maxV: CGFloat = 3400
        let vx = max(-maxV, min(maxV, velocity.x))
        let vy = max(-maxV, min(maxV, velocity.y))
        scrollVelocity = CGPoint(x: vx, y: vy)
    }

    func cancelScrollInertia() {
        scrollVelocity = .zero
    }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mouseDidBecomeCurrent(_:)),
            name: .GCMouseDidBecomeCurrent,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mouseDidStopBeingCurrent(_:)),
            name: .GCMouseDidStopBeingCurrent,
            object: nil
        )
        GCController.startWirelessControllerDiscovery(completionHandler: nil)

        if let currentMouse = GCMouse.current {
            configureMouse(currentMouse)
        }

        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    func stop() {
        invalidateTimers()
        displayLink?.invalidate()
        displayLink = nil
        GCController.stopWirelessControllerDiscovery()
        NotificationCenter.default.removeObserver(self)
    }

    private func invalidateTimers() {
        playPauseLongTimer?.invalidate()
        playPauseLongTimer = nil
        menuLongTimer?.invalidate()
        menuLongTimer = nil
    }

    @objc private func controllerDidDisconnect(_ note: Notification) {
        lastButtonA = false
        lastButtonB = false
        lastButtonX = false
        lastButtonY = false
        lastLeftShoulder = false
        lastRightShoulder = false
    }

    @objc private func mouseDidBecomeCurrent(_ note: Notification) {
        guard let mouse = note.object as? GCMouse else { return }
        configureMouse(mouse)
    }

    @objc private func mouseDidStopBeingCurrent(_ note: Notification) {
        if let mouse = note.object as? GCMouse {
            mouse.mouseInput?.mouseMovedHandler = nil
            mouse.mouseInput?.scroll.valueChangedHandler = nil
            mouse.mouseInput?.leftButton.pressedChangedHandler = nil
            mouse.mouseInput?.rightButton?.pressedChangedHandler = nil
        }
    }

    private func configureMouse(_ mouse: GCMouse) {
        guard let mouseInput = mouse.mouseInput else { return }

        mouseInput.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
            DispatchQueue.main.async {
                self?.delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: CGFloat(deltaX) * 1.15, y: CGFloat(-deltaY) * 1.15))
            }
        }

        mouseInput.scroll.valueChangedHandler = { [weak self] _, xValue, yValue in
            DispatchQueue.main.async {
                self?.delegate?.inputControllerDidScroll(delta: CGPoint(x: CGFloat(-xValue) * 18.0, y: CGFloat(-yValue) * 18.0))
            }
        }

        mouseInput.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            if !pressed {
                DispatchQueue.main.async {
                    self?.delegate?.inputControllerDidClick()
                }
            }
        }

        mouseInput.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            if !pressed {
                DispatchQueue.main.async {
                    self?.delegate?.inputControllerDidPressBack()
                }
            }
        }
    }

    func handlePressesBegan(_ presses: Set<UIPress>, allowToolbarToggle: Bool) -> Bool {
        var handled = false
        let immediateStep: CGFloat = 22.0
        let webInputActive = delegate?.inputControllerIsWebInputFocused() ?? false

        for press in presses {
            // 1. Hardware Bluetooth keyboard key events
            if let key = press.key {
                let mods = key.modifierFlags
                if mods.contains(.command) || mods.contains(.control) {
                    continue
                }

                if webInputActive {
                    switch key.keyCode {
                    case .keyboardReturnOrEnter, .keypadEnter:
                        delegate?.inputControllerDidSendKeyboardAction(.enter)
                        return true
                    case .keyboardDeleteOrBackspace:
                        delegate?.inputControllerDidSendKeyboardAction(.backspace)
                        return true
                    case .keyboardTab:
                        delegate?.inputControllerDidSendKeyboardAction(.tab(shift: mods.contains(.shift)))
                        return true
                    case .keyboardEscape:
                        delegate?.inputControllerDidSendKeyboardAction(.escape)
                        return true
                    case .keyboardUpArrow:
                        delegate?.inputControllerDidSendKeyboardAction(.arrowUp)
                        return true
                    case .keyboardDownArrow:
                        delegate?.inputControllerDidSendKeyboardAction(.arrowDown)
                        return true
                    case .keyboardLeftArrow:
                        delegate?.inputControllerDidSendKeyboardAction(.arrowLeft)
                        return true
                    case .keyboardRightArrow:
                        delegate?.inputControllerDidSendKeyboardAction(.arrowRight)
                        return true
                    default:
                        let chars = key.characters
                        if !chars.isEmpty, let scalar = chars.unicodeScalars.first, scalar.value >= 32 {
                            delegate?.inputControllerDidTypeText(chars)
                            return true
                        }
                    }
                } else {
                    switch key.keyCode {
                    case .keyboardSpacebar:
                        let delta: CGFloat = mods.contains(.shift) ? -480 : 480
                        delegate?.inputControllerDidScroll(delta: CGPoint(x: 0, y: delta))
                        return true
                    case .keyboardPageDown:
                        delegate?.inputControllerDidScroll(delta: CGPoint(x: 0, y: 760))
                        return true
                    case .keyboardPageUp:
                        delegate?.inputControllerDidScroll(delta: CGPoint(x: 0, y: -760))
                        return true
                    case .keyboardEscape:
                        delegate?.inputControllerDidPressBack()
                        return true
                    case .keyboardReturnOrEnter, .keypadEnter:
                        delegate?.inputControllerDidClick()
                        return true
                    default:
                        break
                    }
                }
            }

            // 2. Siri Remote & D-Pad press types
            switch press.type {
            case .upArrow:
                cancelScrollInertia()
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: 0, y: -immediateStep))
                handled = true
            case .downArrow:
                cancelScrollInertia()
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: 0, y: immediateStep))
                handled = true
            case .leftArrow:
                cancelScrollInertia()
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: -immediateStep, y: 0))
                handled = true
            case .rightArrow:
                cancelScrollInertia()
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: immediateStep, y: 0))
                handled = true
            case .select:
                selectPressActive = true
                selectPannedSignificantly = false
                handled = true
            case .playPause:
                playPauseLongFired = false
                playPauseLongTimer?.invalidate()
                if allowToolbarToggle {
                    playPauseLongTimer = Timer.scheduledTimer(withTimeInterval: longPressThreshold, repeats: false) { [weak self] _ in
                        guard let self = self else { return }
                        self.playPauseLongFired = true
                        self.delegate?.inputControllerDidToggleToolbar()
                    }
                }
                handled = true
            case .menu:
                menuLongFired = false
                menuLongTimer?.invalidate()
                menuLongTimer = Timer.scheduledTimer(withTimeInterval: longPressThreshold, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.menuLongFired = true
                    self.delegate?.inputControllerDidToggleToolbar()
                }
                handled = true
            default:
                break
            }
        }
        return handled
    }

    func handlePressesEnded(_ presses: Set<UIPress>) -> Bool {
        var handled = false
        for press in presses {
            switch press.type {
            case .upArrow, .downArrow, .leftArrow, .rightArrow:
                activeDirections.remove(press.type)
                if activeDirections.isEmpty {
                    dpadHoldDuration = 0
                }
                handled = true
            case .select:
                let shouldClick = selectPressActive && !selectPannedSignificantly
                selectPressActive = false
                selectPannedSignificantly = false
                if shouldClick {
                    delegate?.inputControllerDidClick()
                }
                handled = true
            case .playPause:
                playPauseLongTimer?.invalidate()
                playPauseLongTimer = nil
                if !playPauseLongFired {
                    delegate?.inputControllerDidToggleMode()
                }
                playPauseLongFired = false
                handled = true
            case .menu:
                menuLongTimer?.invalidate()
                menuLongTimer = nil
                if !menuLongFired {
                    delegate?.inputControllerDidPressBack()
                }
                menuLongFired = false
                handled = true
            default:
                break
            }
        }
        return handled
    }

    func handlePressesCancelled(_ presses: Set<UIPress>) {
        for press in presses {
            switch press.type {
            case .upArrow, .downArrow, .leftArrow, .rightArrow:
                activeDirections.remove(press.type)
                if activeDirections.isEmpty { dpadHoldDuration = 0 }
            case .select:
                selectPressActive = false
                selectPannedSignificantly = false
            case .playPause:
                playPauseLongTimer?.invalidate()
                playPauseLongTimer = nil
                playPauseLongFired = false
            case .menu:
                menuLongTimer?.invalidate()
                menuLongTimer = nil
                menuLongFired = false
            default:
                break
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? (1.0 / 60.0) : min(link.timestamp - lastTimestamp, 0.05)
        lastTimestamp = link.timestamp

        // 1. D-Pad / Arrow keys movement with smooth acceleration
        if !activeDirections.isEmpty {
            dpadHoldDuration += dt
            let speed: CGFloat = min(20.0, 7.5 + CGFloat(dpadHoldDuration) * 15.0)
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            if activeDirections.contains(.leftArrow) { dx -= speed }
            if activeDirections.contains(.rightArrow) { dx += speed }
            if activeDirections.contains(.upArrow) { dy -= speed }
            if activeDirections.contains(.downArrow) { dy += speed }
            if dx != 0 || dy != 0 {
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: dx, y: dy))
            }
        }

        // 2. Smooth scroll inertia after touchpad release
        if abs(scrollVelocity.x) > 12 || abs(scrollVelocity.y) > 12 {
            let dx = scrollVelocity.x * CGFloat(dt)
            let dy = scrollVelocity.y * CGFloat(dt)
            delegate?.inputControllerDidScroll(delta: CGPoint(x: dx, y: dy))
            let decay = pow(0.05, dt)
            scrollVelocity.x *= decay
            scrollVelocity.y *= decay
        } else if scrollVelocity != .zero {
            scrollVelocity = .zero
        }

        // 3. Extended Gamepad (Xbox / PlayStation / MFi / Bluetooth)
        for controller in GCController.controllers() {
            guard let gp = controller.extendedGamepad else { continue }

            let lx = CGFloat(gp.leftThumbstick.xAxis.value)
            let ly = CGFloat(gp.leftThumbstick.yAxis.value)
            if abs(lx) > 0.14 || abs(ly) > 0.14 {
                let speed: CGFloat = 17.0
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: lx * speed, y: -ly * speed))
            }

            let rx = CGFloat(gp.rightThumbstick.xAxis.value)
            let ry = CGFloat(gp.rightThumbstick.yAxis.value)
            if abs(rx) > 0.14 || abs(ry) > 0.14 {
                let scrollSpeed: CGFloat = 24.0
                delegate?.inputControllerDidScroll(delta: CGPoint(x: rx * scrollSpeed, y: -ry * scrollSpeed))
            }

            let aPressed = gp.buttonA.isPressed
            if aPressed && !lastButtonA { delegate?.inputControllerDidClick() }
            lastButtonA = aPressed

            let bPressed = gp.buttonB.isPressed
            if bPressed && !lastButtonB { delegate?.inputControllerDidPressBack() }
            lastButtonB = bPressed

            let xPressed = gp.buttonX.isPressed
            if xPressed && !lastButtonX { delegate?.inputControllerDidToggleToolbar() }
            lastButtonX = xPressed

            let yPressed = gp.buttonY.isPressed
            if yPressed && !lastButtonY { delegate?.inputControllerDidToggleMode() }
            lastButtonY = yPressed

            let lPressed = gp.leftShoulder.isPressed
            if lPressed && !lastLeftShoulder { delegate?.inputControllerDidPressBack() }
            lastLeftShoulder = lPressed

            let rPressed = gp.rightShoulder.isPressed
            if rPressed && !lastRightShoulder { delegate?.inputControllerDidPressForward() }
            lastRightShoulder = rPressed
        }
    }
}
