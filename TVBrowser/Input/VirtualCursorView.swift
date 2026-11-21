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

    private let outerContrastHalo = CAShapeLayer()
    private let outerRing = CAShapeLayer()
    private let innerDotHalo = CAShapeLayer()
    private let innerDot = CAShapeLayer()
    private let textBeamHalo = CAShapeLayer()
    private let textBeam = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
        isUserInteractionEnabled = false
        backgroundColor = .clear
        setupLayers()
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayers() {
        let ringRect = bounds.insetBy(dx: 5, dy: 5)
        let ringPath = UIBezierPath(ovalIn: ringRect).cgPath

        // Thick dark halo ensures visibility on solid white pages like Google
        outerContrastHalo.path = ringPath
        outerContrastHalo.lineWidth = 6.5
        outerContrastHalo.strokeColor = UIColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 0.90).cgColor
        outerContrastHalo.fillColor = UIColor.clear.cgColor
        outerContrastHalo.shadowColor = UIColor.black.cgColor
        outerContrastHalo.shadowOpacity = 0.65
        outerContrastHalo.shadowRadius = 6.0
        outerContrastHalo.shadowOffset = CGSize(width: 0, height: 2)
        layer.addSublayer(outerContrastHalo)

        outerRing.path = ringPath
        outerRing.lineWidth = 3.0
        layer.addSublayer(outerRing)

        let dotHaloRect = bounds.insetBy(dx: 16, dy: 16)
        innerDotHalo.path = UIBezierPath(ovalIn: dotHaloRect).cgPath
        innerDotHalo.fillColor = UIColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 0.92).cgColor
        layer.addSublayer(innerDotHalo)

        let dotRect = bounds.insetBy(dx: 18, dy: 18)
        innerDot.path = UIBezierPath(ovalIn: dotRect).cgPath
        layer.addSublayer(innerDot)

        let beamPath = UIBezierPath()
        beamPath.move(to: CGPoint(x: bounds.midX, y: 11))
        beamPath.addLine(to: CGPoint(x: bounds.midX, y: bounds.height - 11))
        beamPath.move(to: CGPoint(x: bounds.midX - 6, y: 11))
        beamPath.addLine(to: CGPoint(x: bounds.midX + 6, y: 11))
        beamPath.move(to: CGPoint(x: bounds.midX - 6, y: bounds.height - 11))
        beamPath.addLine(to: CGPoint(x: bounds.midX + 6, y: bounds.height - 11))

        textBeamHalo.path = beamPath.cgPath
        textBeamHalo.lineWidth = 5.5
        textBeamHalo.lineCap = .round
        textBeamHalo.strokeColor = UIColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 0.95).cgColor
        textBeamHalo.fillColor = UIColor.clear.cgColor
        textBeamHalo.isHidden = true
        layer.addSublayer(textBeamHalo)

        textBeam.path = beamPath.cgPath
        textBeam.lineWidth = 2.6
        textBeam.lineCap = .round
        textBeam.strokeColor = UIColor.white.cgColor
        textBeam.fillColor = UIColor.clear.cgColor
        textBeam.isHidden = true
        layer.addSublayer(textBeam)
    }

    private func updateAppearance() {
        if mode == .scroll {
            outerContrastHalo.isHidden = false
            outerRing.isHidden = false
            innerDotHalo.isHidden = false
            innerDot.isHidden = false
            textBeamHalo.isHidden = true
            textBeam.isHidden = true
            outerRing.fillColor = UIColor.systemGreen.withAlphaComponent(0.32).cgColor
            outerRing.strokeColor = UIColor.systemGreen.cgColor
            innerDot.fillColor = UIColor.white.cgColor
            UIView.animate(withDuration: 0.12) { self.transform = .identity }
            return
        }

        switch visualHint {
        case .normal:
            outerContrastHalo.isHidden = false
            outerRing.isHidden = false
            innerDotHalo.isHidden = false
            innerDot.isHidden = false
            textBeamHalo.isHidden = true
            textBeam.isHidden = true
            outerRing.fillColor = UIColor(red: 0.10, green: 0.45, blue: 0.98, alpha: 0.24).cgColor
            outerRing.strokeColor = UIColor.white.cgColor
            innerDot.fillColor = UIColor(red: 0.15, green: 0.62, blue: 1.0, alpha: 1.0).cgColor
            UIView.animate(withDuration: 0.12) { self.transform = .identity }

        case .clickable:
            outerContrastHalo.isHidden = false
            outerRing.isHidden = false
            innerDotHalo.isHidden = false
            innerDot.isHidden = false
            textBeamHalo.isHidden = true
            textBeam.isHidden = true
            outerRing.fillColor = UIColor.systemBlue.withAlphaComponent(0.42).cgColor
            outerRing.strokeColor = UIColor(red: 0.35, green: 0.82, blue: 1.0, alpha: 1.0).cgColor
            innerDot.fillColor = UIColor.white.cgColor
            UIView.animate(withDuration: 0.12) {
                self.transform = CGAffineTransform(scaleX: 1.16, y: 1.16)
            }

        case .textInput:
            // Keep outer ring visible so the cursor never vanishes inside white text inputs
            outerContrastHalo.isHidden = false
            outerRing.isHidden = false
            innerDotHalo.isHidden = true
            innerDot.isHidden = true
            textBeamHalo.isHidden = false
            textBeam.isHidden = false
            outerRing.fillColor = UIColor(red: 0.08, green: 0.12, blue: 0.22, alpha: 0.22).cgColor
            outerRing.strokeColor = UIColor(red: 0.35, green: 0.82, blue: 1.0, alpha: 1.0).cgColor
            UIView.animate(withDuration: 0.12) { self.transform = .identity }
        }
    }

    func animateClick() {
        let baseScale: CGFloat = (mode == .pointer && visualHint == .clickable) ? 1.16 : 1.0
        UIView.animate(withDuration: 0.08, animations: {
            self.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
        }) { _ in
            UIView.animate(withDuration: 0.12) {
                self.transform = CGAffineTransform(scaleX: baseScale, y: baseScale)
            }
        }
    }
}
