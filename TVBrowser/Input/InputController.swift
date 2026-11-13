import UIKit
import GameController

protocol InputControllerDelegate: AnyObject {
    func inputControllerDidMoveCursor(delta: CGPoint)
    func inputControllerDidScroll(delta: CGPoint)
    func inputControllerDidClick()
    func inputControllerDidToggleMode()
    func inputControllerDidPressBack()
    func inputControllerDidPressForward()
    func inputControllerDidToggleToolbar()
}

final class InputController {
    weak var delegate: InputControllerDelegate?

    private var displayLink: CADisplayLink?
    private var activeDirections: Set<UIPress.PressType> = []
    private var dpadHoldDuration: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval = 0

    // Debounce flags for gamepad buttons
    private var lastButtonA = false
    private var lastButtonB = false
    private var lastButtonX = false
    private var lastButtonY = false
    private var lastLeftShoulder = false
    private var lastRightShoulder = false

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        GCController.startWirelessControllerDiscovery(completionHandler: nil)

        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        GCController.stopWirelessControllerDiscovery()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func controllerDidConnect(_ note: Notification) {
        // Controllers are polled cleanly on the display link
    }

    @objc private func controllerDidDisconnect(_ note: Notification) {
        lastButtonA = false
        lastButtonB = false
        lastButtonX = false
        lastButtonY = false
        lastLeftShoulder = false
        lastRightShoulder = false
    }

    func handlePressesBegan(_ presses: Set<UIPress>) -> Bool {
        var handled = false
        let immediateStep: CGFloat = 22.0
        for press in presses {
            switch press.type {
            case .upArrow:
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: 0, y: -immediateStep))
                handled = true
            case .downArrow:
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: 0, y: immediateStep))
                handled = true
            case .leftArrow:
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: -immediateStep, y: 0))
                handled = true
            case .rightArrow:
                activeDirections.insert(press.type)
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: immediateStep, y: 0))
                handled = true
            case .select:
                delegate?.inputControllerDidClick()
                handled = true
            case .playPause:
                delegate?.inputControllerDidToggleMode()
                handled = true
            case .menu:
                delegate?.inputControllerDidPressBack()
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
            default:
                break
            }
        }
        return handled
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTimestamp == 0 ? (1.0 / 60.0) : min(link.timestamp - lastTimestamp, 0.05)
        lastTimestamp = link.timestamp

        // 1. D-Pad / Arrow keys movement with smooth acceleration
        if !activeDirections.isEmpty {
            dpadHoldDuration += dt
            let speed: CGFloat = min(18.0, 7.0 + CGFloat(dpadHoldDuration) * 14.0)
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

        // 2. Extended Gamepad (Xbox / PlayStation / MFi / Bluetooth)
        for controller in GCController.controllers() {
            guard let gp = controller.extendedGamepad else { continue }

            let lx = CGFloat(gp.leftThumbstick.xAxis.value)
            let ly = CGFloat(gp.leftThumbstick.yAxis.value)
            if abs(lx) > 0.14 || abs(ly) > 0.14 {
                let speed: CGFloat = 16.0
                delegate?.inputControllerDidMoveCursor(delta: CGPoint(x: lx * speed, y: -ly * speed))
            }

            let rx = CGFloat(gp.rightThumbstick.xAxis.value)
            let ry = CGFloat(gp.rightThumbstick.yAxis.value)
            if abs(rx) > 0.14 || abs(ry) > 0.14 {
                let scrollSpeed: CGFloat = 22.0
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
