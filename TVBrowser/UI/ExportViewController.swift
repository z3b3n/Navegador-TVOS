import UIKit
import CoreImage

final class ExportViewController: UIViewController {
    var server: LocalExportServer!
    var serverURLString: String?
    var connectedClientsCount: Int = 0
    var onStopServerRequested: (() -> Void)?

    private let titleLabel = UILabel()
    private let infoLabel = UILabel()
    private let urlLabel = UILabel()
    private let clientsLabel = UILabel()
    private let qrImageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [closeButton]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.08, alpha: 1.0)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        titleLabel.text = "Control Remoto · Ratón, Teclado y Marcadores"
        titleLabel.font = .systemFont(ofSize: 36, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        infoLabel.text = "Escanea el QR con tu iPhone o abre esta dirección en el navegador de tu PC/Mac.\nEl control remoto seguirá activo en segundo plano al cerrar esta ventana."
        infoLabel.font = .systemFont(ofSize: 24, weight: .regular)
        infoLabel.textColor = .lightGray
        infoLabel.numberOfLines = 0
        infoLabel.textAlignment = .center

        urlLabel.text = serverURLString ?? "Iniciando servidor local..."
        urlLabel.font = .monospacedSystemFont(ofSize: 34, weight: .semibold)
        urlLabel.textColor = .systemTeal
        urlLabel.textAlignment = .center
        urlLabel.numberOfLines = 0

        clientsLabel.text = "Dispositivos conectados ahora: \(connectedClientsCount)"
        clientsLabel.font = .systemFont(ofSize: 22, weight: .medium)
        clientsLabel.textColor = connectedClientsCount > 0 ? .systemGreen : UIColor.white.withAlphaComponent(0.65)

        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.backgroundColor = .white
        qrImageView.layer.cornerRadius = 16
        qrImageView.clipsToBounds = true
        qrImageView.widthAnchor.constraint(equalToConstant: 300).isActive = true
        qrImageView.heightAnchor.constraint(equalToConstant: 300).isActive = true

        if let urlStr = serverURLString {
            qrImageView.image = generateQRCode(from: urlStr)
        }

        let btnRow = UIStackView()
        btnRow.axis = .horizontal
        btnRow.spacing = 24

        styleButton(closeButton, title: "Seguir navegando (dejar activo)", bg: .systemBlue, action: #selector(closeTapped))
        styleButton(stopButton, title: "Apagar servidor remoto", bg: UIColor.white.withAlphaComponent(0.16), action: #selector(stopTapped))
        btnRow.addArrangedSubview(closeButton)
        btnRow.addArrangedSubview(stopButton)

        [titleLabel, infoLabel, urlLabel, clientsLabel, qrImageView, btnRow].forEach { stack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 100),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -100)
        ])
    }

    func updateStatus(urlString: String?, clientsCount: Int) {
        self.serverURLString = urlString
        self.connectedClientsCount = clientsCount
        guard isViewLoaded else { return }
        if let urlString = urlString {
            urlLabel.text = urlString
            qrImageView.image = generateQRCode(from: urlString)
        } else {
            urlLabel.text = "No se pudo obtener la IP local (verifica Wi-Fi/Ethernet)"
            qrImageView.image = nil
        }
        clientsLabel.text = "Dispositivos conectados ahora: \(clientsCount)"
        clientsLabel.textColor = clientsCount > 0 ? .systemGreen : UIColor.white.withAlphaComponent(0.65)
    }

    private func styleButton(_ button: UIButton, title: String, bg: UIColor, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 25, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 28, bottom: 14, right: 28)
        button.layer.cornerRadius = 14
        button.backgroundColor = bg
        button.setTitleColor(.white, for: .normal)
        button.addTarget(self, action: action, for: .primaryActionTriggered)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations({
            for btn in [self.closeButton, self.stopButton] {
                if context.nextFocusedView === btn {
                    btn.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
                    btn.backgroundColor = .white
                    btn.setTitleColor(.black, for: .normal)
                } else if context.previouslyFocusedView === btn {
                    btn.transform = .identity
                    btn.backgroundColor = (btn === self.closeButton) ? .systemBlue : UIColor.white.withAlphaComponent(0.16)
                    btn.setTitleColor(.white, for: .normal)
                }
            }
        }, completion: nil)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func stopTapped() {
        onStopServerRequested?()
        dismiss(animated: true)
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: .ascii)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return UIImage(ciImage: scaled)
    }
}
