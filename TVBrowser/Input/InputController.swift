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

    // Scroll inertia velocity (points / second) for touchpad flicks only
    private var scrollVelocity: CGPoint = .zero

    // Press tracking for short vs long press & click-on-release
    private var playPauseLongTimer: Timer?
    private var playPauseLongFired = false
    private var selectLongTimer: Timer?
    private var selectLongFired = false
    private var selectPressActive = false
    private var selectPannedSignificantly = false

    // Debounce flags for gamepad buttons
    private var lastButtonA = false
    private var lastButtonB = false
    private var lastButtonX = false
    private var lastButtonY = false
    private var lastLeftShoulder = false
    private var lastRightShoulder = false

    private let playPauseLongThreshold: TimeInterval = 0.45
    private let selectLongPressThreshold: TimeInterval = 0.50
    private let dpadHoldDelayBeforeGlide: TimeInterval = 0.09

    var isSelectPressed: Bool { selectPressActive }

    func markSelectPanMoved() {
        if selectPressActive {
            selectPannedSignificantly = true
            selectLongTimer?.invalidate()
            selectLongTimer = nil
        }
    }

    func applyScrollImpulse(velocity: CGPoint) {
        // Gentle bounded inertia for touchpad flicks so pages settle quickly without running away
        let maxV: CGFloat = 1500
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
        selectLongTimer?.invalidate()
        selectLongTimer = nil
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
                self?.delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: CGFloat(deltaX) * 1.1, y: CGFloat(-deltaY) * 1.1))
            }
        }

        mouseInput.scroll.valueChangedHandler = { [weak self] _, xValue, yValue in
            DispatchQueue.main.async {
                self?.delegate?.inputControllerDidScroll(delta: CGPoint(x: CGFloat(-xValue) * 15.0, y: CGFloat(-yValue) * 15.0))
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

    func handlePressesBegan(_ presses: Set<UIPress>, allowToolbarToggle: Bool, interceptMenu: Bool = true) -> Bool {
        var handled = false
        // Predictable discrete step per tap — stops cleanly with zero runaway
        let tapStep: CGFloat = 9.0
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
                        if interceptMenu {
                            delegate?.inputControllerDidPressBack()
                            return true
                        }
                        continue
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
                if activeDirections.isEmpty { dpadHoldDuration = 0 }
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: 0, y: -tapStep))
                handled = true
            case .downArrow:
                cancelScrollInertia()
                if activeDirections.isEmpty { dpadHoldDuration = 0 }
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: 0, y: tapStep))
                handled = true
            case .leftArrow:
                cancelScrollInertia()
                if activeDirections.isEmpty { dpadHoldDuration = 0 }
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: -tapStep, y: 0))
                handled = true
            case .rightArrow:
                cancelScrollInertia()
                if activeDirections.isEmpty { dpadHoldDuration = 0 }
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: tapStep, y: 0))
                handled = true
            case .select:
                selectPressActive = true
                selectPannedSignificantly = false
                selectLongFired = false
                selectLongTimer?.invalidate()
                if allowToolbarToggle {
                    selectLongTimer = Timer.scheduledTimer(withTimeInterval: selectLongPressThreshold, repeats: false) { [weak self] _ in
                        guard let self = self, self.selectPressActive, !self.selectPannedSignificantly else { return }
                        self.selectLongFired = true
                        self.delegate?.inputControllerDidToggleToolbar()
                    }
                }
                handled = true
            case .playPause:
                playPauseLongFired = false
                playPauseLongTimer?.invalidate()
                playPauseLongTimer = Timer.scheduledTimer(withTimeInterval: playPauseLongThreshold, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.playPauseLongFired = true
                    self.delegate?.inputControllerDidToggleMode()
                }
                handled = true
            case .menu:
                if interceptMenu {
                    handled = true
                }
            default:
                break
            }
        }
        return handled
    }

    func handlePressesEnded(_ presses: Set<UIPress>, interceptMenu: Bool = true) -> Bool {
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
                selectLongTimer?.invalidate()
                selectLongTimer = nil
                let shouldClick = selectPressActive && !selectPannedSignificantly && !selectLongFired
                selectPressActive = false
                selectPannedSignificantly = false
                selectLongFired = false
                if shouldClick {
                    delegate?.inputControllerDidClick()
                }
                handled = true
            case .playPause:
                playPauseLongTimer?.invalidate()
                playPauseLongTimer = nil
                if !playPauseLongFired {
                    // Short Play/Pause opens/closes the top Safari HUD directly from anywhere
                    delegate?.inputControllerDidToggleToolbar()
                }
                playPauseLongFired = false
                handled = true
            case .menu:
                guard interceptMenu else { break }
                delegate?.inputControllerDidPressBack()
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
                selectLongTimer?.invalidate()
                selectLongTimer = nil
                selectPressActive = false
                selectPannedSignificantly = false
                selectLongFired = false
            case .playPause:
                playPauseLongTimer?.invalidate()
                playPauseLongTimer = nil
                playPauseLongFired = false
            default:
                break
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? (1.0 / 60.0) : min(link.timestamp - lastTimestamp, 0.05)
        lastTimestamp = link.timestamp

        // 1. D-Pad hold glide: brief tap deadband, then predictable capped cruise speed
        //    so cursor never runs away and stops the exact instant you release the button.
        if !activeDirections.isEmpty {
            dpadHoldDuration += dt
            if dpadHoldDuration > dpadHoldDelayBeforeGlide {
                let elapsed = dpadHoldDuration - dpadHoldDelayBeforeGlide
                let t = min(1.0, CGFloat(elapsed) / 0.35)
                let smooth = 1.0 - pow(1.0 - t, 2.0) // calm ease-out ramp
                let speedPtsPerSec: CGFloat = 260.0 + 380.0 * smooth // max 640 pt/s (~10.5 pt/frame)
                let step = speedPtsPerSec * CGFloat(dt)

                var dx: CGFloat = 0
                var dy: CGFloat = 0
                if activeDirections.contains(.leftArrow) { dx -= step }
                if activeDirections.contains(.rightArrow) { dx += step }
                if activeDirections.contains(.upArrow) { dy -= step }
                if activeDirections.contains(.downArrow) { dy += step }
                if dx != 0 && dy != 0 {
                    dx *= 0.78
                    dy *= 0.78
                }
                if dx != 0 || dy != 0 {
                    delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: dx, y: dy))
                }
            }
        }

        // 2. Crisp short-tail inertia for touchpad flicks in Scroll mode
        if abs(scrollVelocity.x) > 18 || abs(scrollVelocity.y) > 18 {
            let dx = scrollVelocity.x * CGFloat(dt)
            let dy = scrollVelocity.y * CGFloat(dt)
            delegate?.inputControllerDidScroll(delta: CGPoint(x: dx, y: dy))
            let decay = pow(0.002, dt)
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
            let mag = hypot(lx, ly)
            if mag > 0.14 {
                let norm = min(1.0, (mag - 0.14) / 0.86)
                let curveSpeed = (220.0 + 460.0 * norm) * CGFloat(dt)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: (lx / mag) * curveSpeed, y: (-ly / mag) * curveSpeed))
            }

            let rx = CGFloat(gp.rightThumbstick.xAxis.value)
            let ry = CGFloat(gp.rightThumbstick.yAxis.value)
            if abs(rx) > 0.14 || abs(ry) > 0.14 {
                let scrollSpeed = 900.0 * CGFloat(dt)
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
