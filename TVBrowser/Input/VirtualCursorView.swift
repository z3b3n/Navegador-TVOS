import UIKit

enum CursorMode {
    case pointer
    case scroll
}

final class VirtualCursorView: UIView {
    var mode: CursorMode = .pointer {
        didSet {
            updateAppearance()
        }
    }

    private let outerRing = CAShapeLayer()
    private let innerDot = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
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
        outerRing.shadowOpacity = 0.65
        outerRing.shadowRadius = 4.0
        outerRing.shadowOffset = CGSize(width: 0, height: 2)
        layer.addSublayer(outerRing)

        let dotRect = bounds.insetBy(dx: 12, dy: 12)
        innerDot.path = UIBezierPath(ovalIn: dotRect).cgPath
        layer.addSublayer(innerDot)
    }

    private func updateAppearance() {
        switch mode {
        case .pointer:
            outerRing.fillColor = UIColor.white.withAlphaComponent(0.28).cgColor
            outerRing.strokeColor = UIColor.white.cgColor
            innerDot.fillColor = UIColor.systemBlue.cgColor
        case .scroll:
            outerRing.fillColor = UIColor.systemGreen.withAlphaComponent(0.25).cgColor
            outerRing.strokeColor = UIColor.systemGreen.cgColor
            innerDot.fillColor = UIColor.white.cgColor
        }
    }

    func animateClick() {
        UIView.animate(withDuration: 0.08, animations: {
            self.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
        }) { _ in
            UIView.animate(withDuration: 0.12) {
                self.transform = .identity
            }
        }
    }
}
