import UIKit

enum CursorMode {
    case pointer
    case scroll
}

enum CursorVisualHint: Equatable {
    case normal
    case clickable
    case textInput
}

final class VirtualCursorView: UIView {
    var mode: CursorMode = .pointer {
        didSet {
            guard oldValue != mode else { return }
            updateAppearance()
        }
    }

    var visualHint: CursorVisualHint = .normal {
        didSet {
            guard oldValue != visualHint else { return }
            updateAppearance()
        }
    }

    private let outerRing = CAShapeLayer()
    private let innerDot = CAShapeLayer()
    private let textBeam = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 38, height: 38))
        isUserInteractionEnabled = false
        backgroundColor = .clear
        setupLayers()
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayers() {
        let ringRect = bounds.insetBy(dx: 3, dy: 3)
        outerRing.path = UIBezierPath(ovalIn: ringRect).cgPath
        outerRing.lineWidth = 3.0
        outerRing.shadowColor = UIColor.black.cgColor
        outerRing.shadowOpacity = 0.7
        outerRing.shadowRadius = 4.0
        outerRing.shadowOffset = CGSize(width: 0, height: 2)
        layer.addSublayer(outerRing)

        let dotRect = bounds.insetBy(dx: 13, dy: 13)
        innerDot.path = UIBezierPath(ovalIn: dotRect).cgPath
        layer.addSublayer(innerDot)

        let beamPath = UIBezierPath()
        beamPath.move(to: CGPoint(x: bounds.midX, y: 7))
        beamPath.addLine(to: CGPoint(x: bounds.midX, y: bounds.height - 7))
        beamPath.move(to: CGPoint(x: bounds.midX - 5, y: 7))
        beamPath.addLine(to: CGPoint(x: bounds.midX + 5, y: 7))
        beamPath.move(to: CGPoint(x: bounds.midX - 5, y: bounds.height - 7))
        beamPath.addLine(to: CGPoint(x: bounds.midX + 5, y: bounds.height - 7))
        textBeam.path = beamPath.cgPath
        textBeam.lineWidth = 2.6
        textBeam.lineCap = .round
        textBeam.strokeColor = UIColor.white.cgColor
        textBeam.fillColor = UIColor.clear.cgColor
        textBeam.shadowColor = UIColor.black.cgColor
        textBeam.shadowOpacity = 0.8
        textBeam.shadowRadius = 2.0
        textBeam.isHidden = true
        layer.addSublayer(textBeam)
    }

    private func updateAppearance() {
        if mode == .scroll {
            outerRing.isHidden = false
            innerDot.isHidden = false
            textBeam.isHidden = true
            outerRing.fillColor = UIColor.systemGreen.withAlphaComponent(0.26).cgColor
            outerRing.strokeColor = UIColor.systemGreen.cgColor
            innerDot.fillColor = UIColor.white.cgColor
            UIView.animate(withDuration: 0.12) { self.transform = .identity }
            return
        }

        switch visualHint {
        case .normal:
            outerRing.isHidden = false
            innerDot.isHidden = false
            textBeam.isHidden = true
            outerRing.fillColor = UIColor.white.withAlphaComponent(0.26).cgColor
            outerRing.strokeColor = UIColor.white.cgColor
            innerDot.fillColor = UIColor.systemBlue.cgColor
            UIView.animate(withDuration: 0.12) { self.transform = .identity }
        case .clickable:
            outerRing.isHidden = false
            innerDot.isHidden = false
            textBeam.isHidden = true
            outerRing.fillColor = UIColor.systemBlue.withAlphaComponent(0.32).cgColor
            outerRing.strokeColor = UIColor.white.cgColor
            innerDot.fillColor = UIColor.white.cgColor
            UIView.animate(withDuration: 0.12) {
                self.transform = CGAffineTransform(scaleX: 1.18, y: 1.18)
            }
        case .textInput:
            outerRing.isHidden = true
            innerDot.isHidden = true
            textBeam.isHidden = false
            UIView.animate(withDuration: 0.12) { self.transform = .identity }
        }
    }

    func animateClick() {
        let baseScale: CGFloat = (mode == .pointer && visualHint == .clickable) ? 1.18 : 1.0
        UIView.animate(withDuration: 0.08, animations: {
            self.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
        }) { _ in
            UIView.animate(withDuration: 0.12) {
                self.transform = CGAffineTransform(scaleX: baseScale, y: baseScale)
            }
        }
    }
}
